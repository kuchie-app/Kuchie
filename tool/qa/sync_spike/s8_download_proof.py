#!/usr/bin/env python3
"""S8: is `isDownloaded` + `pageCount` after `enqueueChapterDownloads` proof
that a chapter is whole on the server, and how do failures look?

Scenarios (each enqueues and watches downloadStatus until the chapter settles):
  ok       a real chapter the server never opened (Weeb Central from S1)
  removed  a chapter whose URL the source no longer has (S5 seed, fake URL)
  tamper   after `ok`, delete one page file on disk and query again
  full     with --downloads-path on a tiny volume (disk full)

Usage: s8_download_proof.py [--scenario ok,removed,tamper] [--downloads-path DIR]
"""

import argparse
from pathlib import Path
import time
import urllib.error
import urllib.request

from common import GraphQLError, Server, write_json

WEEB_CENTRAL = "2131019126180322627"
STATUS = """{ downloadStatus { state queue { state progress tries chapter { id } } } }"""
CHAPTER = """query($id: Int!) { chapter(id: $id) { id name isDownloaded pageCount sourceOrder
  manga { id title } } }"""


def watch(server, chapter_id, timeout=300):
    """Enqueue one chapter and record each distinct downloader state for it."""
    server.gql("mutation($i: [Int!]!) { enqueueChapterDownloads(input: {ids: $i}) { clientMutationId } }",
               {"i": [chapter_id]})
    try:
        # Enqueueing starts the downloader; startDownloader waits for a state
        # change and times out (30 s) when it is already running.
        server.gql("mutation { startDownloader(input: {}) { clientMutationId } }", timeout=5)
    except Exception:
        pass
    trail, start, last = [], time.time(), None
    while time.time() - start < timeout:
        status = server.gql(STATUS)["downloadStatus"]
        item = next((q for q in status["queue"] if q["chapter"]["id"] == chapter_id), None)
        seen = (item["state"], item["tries"]) if item else ("NOT_IN_QUEUE", None)
        if seen != last:
            trail.append({"t": round(time.time() - start, 1), "state": seen[0], "tries": seen[1],
                          "progress": item and item["progress"], "downloader": status["state"]})
            last = seen
        if item is None and len(trail) > 1:
            break
        if item and item["state"] == "ERROR" and status["state"] == "STOPPED":
            break
        if item and item["state"] == "ERROR" and time.time() - start > 60:
            break
        time.sleep(0.5)
    return {"trail": trail, "chapter": server.gql(CHAPTER, {"id": chapter_id})["chapter"],
            "seconds": round(time.time() - start, 1)}


def page_status(server, manga_id, source_order, page):
    """What a client reading through the server gets for one page."""
    url = f"{server.base}/api/v1/manga/{manga_id}/chapter/{source_order}/page/{page}"
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.status, len(response.read())
    except urllib.error.HTTPError as error:
        return error.code, 0


def pick_real(server, used=()):
    """A Weeb Central chapter the server listed but never opened (pageCount -1)."""
    mangas = server.gql("""query($s: LongString!) { mangas(condition: {sourceId: $s}) { nodes { id } } }""",
                        {"s": WEEB_CENTRAL})["mangas"]["nodes"]
    for manga in mangas:
        nodes = server.gql("""query($m: Int!) { chapters(condition: {mangaId: $m}, filter: {pageCount:
          {lessThan: 0}, isDownloaded: {equalTo: false}}) { nodes { id } } }""", {"m": manga["id"]})
        for node in nodes["chapters"]["nodes"]:
            if node["id"] not in used:
                return node["id"]
    raise LookupError("no unopened Weeb Central chapter; run s1_urls.py first")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", default="ok,removed,tamper")
    parser.add_argument("--downloads-path", type=Path)
    parser.add_argument("--server-root", type=Path,
                        help="the server's rootDir (server.py prints it as 'QA catalog'); "
                             "downloads live in <root>/downloads when downloadsPath is empty")
    args = parser.parse_args()
    server, report = Server(), {}
    scenarios = args.scenario.split(",")
    original_path = server.gql("{ settings { downloadsPath downloadAsCbz } }")["settings"]
    report["settings"] = original_path

    if "ok" in scenarios or "tamper" in scenarios:
        real = pick_real(server)
        report["ok"] = watch(server, real)
        print("ok", report["ok"], flush=True)

    if "tamper" in scenarios:
        chapter = report["ok"]["chapter"]
        root = Path(original_path["downloadsPath"] or (args.server_root / "downloads"))
        pages = sorted(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in
                       (".jpg", ".jpeg", ".png", ".webp", ".gif") and chapter["name"] in str(p.parent))
        report["tamper"] = {"filesOnDisk": len(pages)}
        if pages:
            pages[0].unlink()
            again = server.gql(CHAPTER, {"id": chapter["id"]})["chapter"]
            report["tamper"].update(
                deleted=pages[0].name, afterDelete=again,
                page0=page_status(server, chapter["manga"]["id"], chapter["sourceOrder"], 0),
                page1=page_status(server, chapter["manga"]["id"], chapter["sourceOrder"], 1))
        print("tamper", report["tamper"], flush=True)

    if "removed" in scenarios:
        queued = {q["chapter"]["id"] for q in server.gql(STATUS)["downloadStatus"]["queue"]}
        fake = next(n["id"] for n in server.gql("""{ chapters(filter: {url: {startsWith: "/chapter/spike-seed-"}},
          first: 50) { nodes { id } } }""")["chapters"]["nodes"] if n["id"] not in queued)
        report["removed"] = watch(server, fake, timeout=240)
        print("removed", report["removed"], flush=True)

    if "full" in scenarios and args.downloads_path:
        server.gql("mutation($p: String!) { setSettings(input: {settings: {downloadsPath: $p}}) { clientMutationId } }",
                   {"p": str(args.downloads_path)})
        try:
            report["full"] = watch(server, pick_real(server, used={report.get("ok", {}).get("chapter", {}).get("id")}), timeout=240)
            report["full"]["filesOnDisk"] = sum(1 for p in args.downloads_path.rglob("*") if p.is_file())
        finally:
            server.gql("mutation($p: String!) { setSettings(input: {settings: {downloadsPath: $p}}) { clientMutationId } }",
                       {"p": original_path["downloadsPath"]})
        print("full", report["full"], flush=True)

    name = "-".join(scenarios)
    write_json(Path(__file__).parent / "results" / f"s8-{name}.json", report)


if __name__ == "__main__":
    main()
