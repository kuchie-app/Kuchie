#!/usr/bin/env python3
"""Serve synthetic extension and manga files for Kuchie's Local mode QA."""

import argparse
from functools import lru_cache
from hashlib import sha256
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import time
from urllib.parse import urlsplit
import zipfile

from server import test_page


PORT = 14568
PAGE_COUNT = 18
SOURCE_ID = "qa.lantern"
SOURCE_NAME = "QA Lantern Source"
REPO_NAME = "QA Local Repository"
SERIES = {
    "lantern-station": ("QA Lantern Station", (36, 89, 133)),
    "night-ferry": ("QA Night Ferry", (66, 111, 76)),
    "paper-signal": ("QA Paper Signal", (159, 73, 46)),
    "reader-benchmark": ("QA Reader Benchmark", (87, 60, 111)),
}
CHAPTERS = ("chapter-01", "chapter-02")
PAGE_PATH = re.compile(r"/series/([^/]+)/([^/]+)/page-(\d{2})\.png")


def encode(payload):
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()


def package(port):
    return encode({
        "format": "kuchie.extension.v1",
        "id": SOURCE_ID,
        "name": SOURCE_NAME,
        "version": "1.0.0",
        "language": "en",
        "catalog": f"http://127.0.0.1:{port}/catalog.json",
    })


def feeds(port):
    package_bytes = package(port)
    paths = {
        "/index.json": encode({
            "format": "kuchie.repository.v1",
            "name": REPO_NAME,
            "extensions": [{
                "id": SOURCE_ID,
                "name": SOURCE_NAME,
                "version": "1.0.0",
                "language": "en",
                "url": "extension.json",
                "sha256": sha256(package_bytes).hexdigest(),
            }],
        }),
        "/extension.json": package_bytes,
        "/catalog.json": encode({
            "manga": [
                {
                    "id": key,
                    "title": title,
                    "description": "Synthetic manga for testing Kuchie Local.",
                    "cover": f"/series/{key}/chapter-01/page-01.png",
                    "chapters": f"/series/{key}/chapters.json",
                }
                for key, (title, _) in SERIES.items()
            ],
        }),
    }
    for series in SERIES:
        paths[f"/series/{series}/chapters.json"] = encode({
            "chapters": [
                {"id": chapter, "title": f"Chapter {number:02}", "pages": f"{chapter}/pages.json"}
                for number, chapter in enumerate(CHAPTERS, 1)
            ],
        })
        for chapter in CHAPTERS:
            paths[f"/series/{series}/{chapter}/pages.json"] = encode({
                "pages": [f"page-{number:02}.png" for number in range(1, PAGE_COUNT + 1)],
            })
    return paths


@lru_cache(maxsize=len(SERIES) * len(CHAPTERS) * PAGE_COUNT)
def page_png(series, chapter, page):
    return test_page(CHAPTERS.index(chapter) + 1, page, SERIES[series][1])


def export_cbz(destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w") as archive:
        for page in range(1, PAGE_COUNT + 1):
            archive.writestr(f"page-{page:02}.png", page_png("lantern-station", "chapter-01", page))


def start_server(port, delay):
    documents = feeds(port)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            content = documents.get(path)
            content_type = "application/json"
            if content is None and (match := PAGE_PATH.fullmatch(path)):
                series, chapter, page = match.groups()
                if series in SERIES and chapter in CHAPTERS and 1 <= int(page) <= PAGE_COUNT:
                    if delay:
                        time.sleep(delay)
                    content = page_png(series, chapter, int(page))
                    content_type = "image/png"
            if content is None:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            try:
                self.wfile.write(content)
            except (BrokenPipeError, ConnectionResetError):
                pass

    with ThreadingHTTPServer(("127.0.0.1", port), Handler) as httpd:
        print(f"Extension repository: http://127.0.0.1:{port}/index.json", flush=True)
        print(f"Extension package:    http://127.0.0.1:{port}/extension.json", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--delay", type=float, default=0, help="Seconds to delay every image response.")
    parser.add_argument("--export-cbz", type=Path, help="Export a sample CBZ archive.")
    parser.add_argument("--export-extension", type=Path, help="Export a package for the same port.")
    parser.add_argument("--export-only", action="store_true", help="Export files and exit.")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    if not 0 <= args.delay <= 30:
        parser.error("delay must be between 0 and 30 seconds")
    if args.export_only and not (args.export_cbz or args.export_extension):
        parser.error("--export-only needs an export path")
    if args.export_cbz:
        export_cbz(args.export_cbz)
        print(f"Sample CBZ: {args.export_cbz}", flush=True)
    if args.export_extension:
        args.export_extension.parent.mkdir(parents=True, exist_ok=True)
        args.export_extension.write_bytes(package(args.port))
        print(f"Sample extension: {args.export_extension}", flush=True)
    if not args.export_only:
        start_server(args.port, args.delay)


if __name__ == "__main__":
    main()
