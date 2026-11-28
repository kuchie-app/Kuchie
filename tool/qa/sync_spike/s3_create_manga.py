#!/usr/bin/env python3
"""S3: the most reliable way to create a server manga row for a Kuchie series.

Takes series the server does not have yet (from the extension's Latest list
through the Simulator runtime), then:
  (a) `fetchSourceManga(SEARCH, title)` and look the URL up;
  (b) `restoreBackup` with a minimal Mihon backup (source, url, title).
Also checks whether a backup carries progress the plain mutation drops (S2):
`lastPageRead` on a chapter whose pages the server never fetched, and an old
history timestamp as `lastReadAt`.

Usage: s3_create_manga.py --apk <extension.apk> --source <id> --name <source name> [--per-method 25]
"""

import argparse
from pathlib import Path
import time

import backup
from common import Runtime, Server, chapter_locator, stable_locator, write_json

FIND = """query($s: LongString!, $u: String!) {
  mangas(condition: {sourceId: $s, url: $u}) { nodes { id url title inLibrary initialized
    chapters { totalCount } } }
}"""
SEARCH = """mutation($s: LongString!, $q: String!) {
  fetchSourceManga(input: {source: $s, page: 1, type: SEARCH, query: $q}) { mangas { id url title } }
}"""


def candidates(runtime, server, source, count):
    found, seen, page = [], set(), 1
    while len(found) < count and page <= 40:
        result = runtime.latest(source, page)
        for manga in result["mangas"]:
            stable = stable_locator(manga["url"])
            if stable in seen:
                continue
            seen.add(stable)
            if not server.gql(FIND, {"s": source, "u": stable})["mangas"]["nodes"]:
                found.append(manga)
        if not result.get("hasNextPage"):
            break
        page += 1
    return found[:count]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--source", required=True)
    parser.add_argument("--name", required=True, help="source name for BackupSource")
    parser.add_argument("--per-method", type=int, default=25)
    args = parser.parse_args()
    runtime, server = Runtime(args.apk), Server()

    pool = candidates(runtime, server, args.source, args.per_method * 2)
    via_search, via_backup = pool[:args.per_method], pool[args.per_method:]
    report = {"source": args.source, "search": [], "backup": [], "restoreProgress": None}

    for manga in via_search:
        stable = stable_locator(manga["url"])
        start = time.perf_counter()
        results = server.gql(SEARCH, {"s": args.source, "q": manga["title"]})["fetchSourceManga"]["mangas"]
        nodes = server.gql(FIND, {"s": args.source, "u": stable})["mangas"]["nodes"]
        report["search"].append({"title": manga["title"], "url": stable, "created": bool(nodes),
                                 "results": len(results), "seconds": round(time.perf_counter() - start, 2)})
        print(f"search {'OK ' if nodes else 'MISS'} {manga['title'][:60]!r} ({len(results)} results)", flush=True)

    if via_backup:
        data = backup.backup(
            [backup.manga(int(args.source), stable_locator(m["url"]), m["title"]) for m in via_backup],
            [backup.source(args.name, int(args.source))],
        )
        start = time.perf_counter()
        status = backup.restore(server, data)
        seconds = round(time.perf_counter() - start, 2)
        print("restore", status, f"{seconds}s", flush=True)
        for manga in via_backup:
            stable = stable_locator(manga["url"])
            nodes = server.gql(FIND, {"s": args.source, "u": stable})["mangas"]["nodes"]
            report["backup"].append({"title": manga["title"], "url": stable, "created": bool(nodes),
                                     "row": nodes[0] if nodes else None})
            print(f"backup {'OK ' if nodes else 'MISS'} {manga['title'][:60]!r} "
                  f"{nodes[0] if nodes else ''}", flush=True)
        report["restore"] = {"status": status, "seconds": seconds}

        # Progress through a backup, on a series whose chapters the server has
        # listed but never opened (pageCount -1).
        target = next((m for m in via_backup if (n := server.gql(FIND, {"s": args.source, "u": stable_locator(m["url"])})
                       ["mangas"]["nodes"]) and n[0]["chapters"]["totalCount"] >= 2), None)
        if target is None and via_backup:
            target = via_backup[0]
        if target:
            stable = stable_locator(target["url"])
            row = server.gql(FIND, {"s": args.source, "u": stable})["mangas"]["nodes"][0]
            if row["chapters"]["totalCount"] < 2:
                server.gql("mutation($id: Int!) { fetchMangaAndChapters(input: {id: $id, fetchManga: false,"
                           " fetchChapters: true}) { manga { id } } }", {"id": row["id"]})
            listed = [stable_locator(chapter_locator(c["url"], c)) for c in runtime.chapters(args.source, target)]
            old_ms = 1_700_000_000_000  # 2023-11-14
            data = backup.backup(
                [backup.manga(int(args.source), stable, target["title"],
                              chapters=[backup.chapter(listed[0], "c0", read=False, last_page_read=5),
                                        backup.chapter(listed[1], "c1", read=True, last_page_read=0)],
                              histories=[backup.history(listed[0], old_ms)])],
                [backup.source(args.name, int(args.source))],
            )
            status = backup.restore(server, data)
            rows = server.gql("query($m: Int!) { chapters(condition: {mangaId: $m}) { nodes { url isRead"
                              " lastPageRead lastReadAt pageCount } } }", {"m": row["id"]})["chapters"]["nodes"]
            by_url = {r["url"]: r for r in rows}
            report["restoreProgress"] = {"status": status, "historyLastReadMs": old_ms,
                                         "chapter0": by_url.get(listed[0]), "chapter1": by_url.get(listed[1])}
            print("restoreProgress", report["restoreProgress"], flush=True)

    ok = lambda rows: sum(r["created"] for r in rows)
    report["summary"] = {"search": f"{ok(report['search'])}/{len(report['search'])}",
                         "backup": f"{ok(report['backup'])}/{len(report['backup'])}"}
    print(report["summary"])
    write_json(Path(__file__).parent / "results" / f"s3-{args.source}.json", report)


if __name__ == "__main__":
    main()
