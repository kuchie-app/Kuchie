"""Shared helpers for the Kuchie 2.0 sync spikes (PR 0).

Two clients:
- `Server`: Suwayomi GraphQL (`tool/qa/server.py`, port 14567).
- `Runtime`: the Mac-side Mihon extension runtime the Simulator build uses
  (`tool/qa/ensure_simulator_runtime.sh`, port 14569). It is the same bridge
  `LocalMihonRuntime` (lib/src/features/local_collection/data/
  local_mihon_runtime.dart) talks to, so locators come back exactly as the
  Simulator app receives them before Dart parses them.

`stable_locator` and `mihon_locator_id` mirror the Dart code byte for byte.
"""

import base64
import hashlib
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.request

SERVER = os.environ.get("KUCHIE_SPIKE_SERVER", "http://127.0.0.1:14567")
# What WKWebView sends on an iPhone; the app passes its WebView user agent to
# the runtime (`_webViewHeaders`), and some sites refuse the JVM default.
IOS_USER_AGENT = os.environ.get(
    "KUCHIE_SPIKE_USER_AGENT",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 26_5 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Mobile/15E148",
)
RUNTIME_DATA = Path(
    os.environ.get(
        "KUCHIE_QA_EXTENSION_RUNTIME_DATA",
        Path.home() / "development" / "kuchie-qa-extension-runtime",
    )
)


class GraphQLError(RuntimeError):
    pass


class Server:
    def __init__(self, base=SERVER, headers=None):
        self.base = base.rstrip("/")
        self.headers = dict(headers or {})

    def gql(self, query, variables=None, *, timeout=600, raw=False):
        body = json.dumps({"query": query, "variables": variables or {}}).encode()
        request = urllib.request.Request(
            f"{self.base}/api/graphql",
            data=body,
            headers={"Content-Type": "application/json", **self.headers},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            payload = {"errors": [{"message": f"HTTP {error.code}: {error.read()[:300]!r}"}]}
        if raw:
            return payload
        if payload.get("errors"):
            raise GraphQLError(json.dumps(payload["errors"])[:2000])
        return payload["data"]


class Runtime:
    """Calls `/dalvik` like `LocalMihonRuntime._invoke`."""

    def __init__(self, apk_path):
        self.apk = Path(apk_path).read_bytes()
        self.key = hashlib.sha256(self.apk).hexdigest()
        self.port = int((RUNTIME_DATA / "runtime.port").read_text().strip() or 14569)
        self.token = (RUNTIME_DATA / "runtime.token").read_text().strip()

    def call(self, method, source_id=None, **arguments):
        body = {"method": method, **({"sourceId": source_id} if source_id else {}), **arguments}
        try:
            return self._send({**body, "extensionId": self.key})
        except urllib.error.HTTPError as error:
            if error.code != 409:
                raise RuntimeError(f"runtime {method}: HTTP {error.code} {error.read()[:300]!r}")
            return self._send({**body, "data": base64.b64encode(self.apk).decode()})

    def _send(self, body):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/dalvik",
            data=json.dumps(body).encode("utf-8"),
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "Accept": "application/json",
                "X-Kuchie-Runtime-Token": self.token,
                "User-Agent": IOS_USER_AGENT,
            },
        )
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.loads(response.read().decode("utf-8") or "null")

    # The four calls Kuchie's Local library uses.
    def info(self):
        return self.call("extensionInfo")

    def popular(self, source_id, page):
        return self.call("getPopularManga", source_id, page=page)

    def latest(self, source_id, page):
        return self.call("getLatestManga", source_id, page=page)

    def search(self, source_id, query, page=1):
        return self.call("getSearchManga", source_id, page=page, search=query)

    def chapters(self, source_id, manga):
        return self.call(
            "getChapterList", source_id,
            mangaData={"url": manga["url"], "title": manga.get("title") or ""},
        )


# --- Mirrors of local_mihon_runtime.dart / local_sources.dart -------------

_CHAPTER_MARKER = "|kuchie-chapter|"
_MEMO_MARKER = "|mangayomi-memo|"


def chapter_locator(url, chapter):
    """`_chapterLocator`: URL plus the SChapter fields getPageList needs."""
    fields = {}
    for key in ("name", "scanlator", "chapter_number", "date_upload"):
        value = chapter.get(key)
        if isinstance(value, bool) or value is None:
            continue
        if isinstance(value, (int, float)) or (isinstance(value, str) and value):
            fields[key] = value[:1024] if isinstance(value, str) else value
    if not fields:
        return url
    encoded = base64.urlsafe_b64encode(
        json.dumps(fields, separators=(",", ":"), ensure_ascii=False).encode()
    ).decode()
    return f"{url}{_CHAPTER_MARKER}{encoded}"


def stable_locator(locator):
    """`_stableLocator`: drop Kuchie's chapter suffix and Mangayomi's memo."""
    index = locator.rfind(_CHAPTER_MARKER)
    url = locator if index < 0 else locator[:index]
    memo = url.rfind(_MEMO_MARKER)
    return url[:memo] if memo > 0 else url


def mihon_locator_id(stable):
    """`_mihonLocatorId`: series and chapter IDs in catalog.sqlite."""
    return hashlib.sha256(stable.encode("utf-8")).hexdigest()


def timed(fn, *args, **kwargs):
    start = time.perf_counter()
    result = fn(*args, **kwargs)
    return result, time.perf_counter() - start


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
