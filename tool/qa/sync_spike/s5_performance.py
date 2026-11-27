#!/usr/bin/env python3
"""S5: pull cost for a 500-series / 50,000-chapter library.

Seeds the library with restoreBackup (fake URLs under a real source id, so
nothing hits the site), then times:
- full pull: library series + every library chapter, unpaged and paged;
- incremental pull: a per-series fingerprint plus chapters whose lastReadAt
  moved, after a handful of changes.

Usage: s5_performance.py [--series 500] [--chapters 100] [--skip-seed]
"""

import argparse
import json
from pathlib import Path
import random
import time
import urllib.request

import backup
from common import Server, timed, write_json

SOURCE = 2499283573021220255  # MangaDex (en); URLs below are fake
PREFIX = "/manga/spike-seed-"

SERIES = """query { mangas(condition: {inLibrary: true}) { totalCount nodes {
  id sourceId url title inLibraryAt categories { nodes { id } } } } }"""
CHAPTER_FIELDS = "id mangaId url isRead isBookmarked lastPageRead lastReadAt isDownloaded"
ALL_CHAPTERS = "query { chapters(filter: {inLibrary: {equalTo: true}}) { totalCount nodes { %s } } }" % CHAPTER_FIELDS
# No orderBy: with the inLibrary filter, orderBy (ID or any other) plus
# first/offset throws an H2 NullPointerException on v2.4.2366. The default
# order is ID, so cursors still walk the table in order.
PAGE = """query($first: Int!, $after: Cursor) { chapters(filter: {inLibrary: {equalTo: true}}, first: $first,
  after: $after) { pageInfo { hasNextPage endCursor } nodes { %s } } }""" % CHAPTER_FIELDS
FINGERPRINT = """query { mangas(condition: {inLibrary: true}) { nodes { id unreadCount bookmarkCount
  downloadCount lastReadChapter { id lastReadAt } } } }"""
SINCE = """query($t: LongString!) { chapters(filter: {lastReadAt: {greaterThan: $t}}) { nodes { %s } } }""" % CHAPTER_FIELDS
BY_MANGA = """query($ids: [Int!]!) { chapters(filter: {mangaId: {in: $ids}}) { nodes { %s } } }""" % CHAPTER_FIELDS


def size(data):
    return len(json.dumps(data))


def gzip_bytes(server, query):
    """Bytes on the wire with Accept-Encoding: gzip, as dart:io asks for."""
    request = urllib.request.Request(f"{server.base}/api/graphql", data=json.dumps({"query": query}).encode(),
                                     headers={"Content-Type": "application/json", "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(request, timeout=600) as response:
        return len(response.read()), response.headers.get("Content-Encoding")


def seed(server, series, chapters):
    rng = random.Random(7)
    batch = 100
    for start in range(0, series, batch):
        mangas = []
        for i in range(start, min(start + batch, series)):
            read_upto = rng.randint(0, chapters)
            chaps = [backup.chapter(f"/chapter/spike-seed-{i}-{j}", f"Chapter {j + 1}", number=float(j + 1),
                                    source_order=j, read=j < read_upto,
                                    last_page_read=rng.randint(0, 20) if j == read_upto else 0)
                     for j in range(chapters)]
            hist = [backup.history(f"/chapter/spike-seed-{i}-{read_upto - 1}",
                                   1_750_000_000_000 + i * 1000)] if read_upto else []
            mangas.append(backup.manga(SOURCE, f"{PREFIX}{i}", f"Spike seed {i:03}", chapters=chaps,
                                       histories=hist))
        (status, seconds) = timed(backup.restore, server, backup.backup(mangas, [backup.source("MangaDex", SOURCE)]))
        print(f"seeded {min(start + batch, series)}/{series} in {seconds:.1f}s {status['state']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--series", type=int, default=500)
    parser.add_argument("--chapters", type=int, default=100)
    parser.add_argument("--skip-seed", action="store_true")
    args = parser.parse_args()
    server = Server()
    report = {}

    if not args.skip_seed:
        _, report["seedSeconds"] = timed(seed, server, args.series, args.chapters)

    runs = []
    for _ in range(3):
        series, s_series = timed(server.gql, SERIES)
        chapters, s_chapters = timed(server.gql, ALL_CHAPTERS)
        runs.append({"seriesSeconds": round(s_series, 2), "chaptersSeconds": round(s_chapters, 2),
                     "series": series["mangas"]["totalCount"], "chapters": chapters["chapters"]["totalCount"],
                     "seriesBytes": size(series), "chaptersBytes": size(chapters)})
        print("full", runs[-1], flush=True)
    report["fullUnpaged"] = runs
    report["fullChaptersGzip"] = gzip_bytes(server, ALL_CHAPTERS)
    print("gzip", report["fullChaptersGzip"], flush=True)

    for page_size in (2000, 5000, 10000):
        start, after, pages, total_bytes = time.perf_counter(), None, 0, 0
        while True:
            data = server.gql(PAGE, {"first": page_size, "after": after})["chapters"]
            pages, total_bytes = pages + 1, total_bytes + size(data)
            if not data["pageInfo"]["hasNextPage"]:
                break
            after = data["pageInfo"]["endCursor"]
        report[f"fullPaged{page_size}"] = {"seconds": round(time.perf_counter() - start, 2), "pages": pages,
                                           "bytes": total_bytes}
        print(f"paged {page_size}", report[f"fullPaged{page_size}"], flush=True)

    # Incremental: fingerprint, change a few series another way, pull again.
    before, s_fp = timed(server.gql, FINGERPRINT)
    cursor = str(int(time.time()) - 1)
    ids = [n["id"] for n in server.gql(f'{{ mangas(filter: {{url: {{startsWith: "{PREFIX}"}}}}, first: 5)'
                                         " { nodes { id } } }")
           ["mangas"]["nodes"]]
    chapter_ids = server.gql("query($m: [Int!]!) { chapters(filter: {mangaId: {in: $m}}, first: 10) { nodes { id } } }",
                             {"m": ids})["chapters"]["nodes"]
    server.gql("mutation($i: [Int!]!) { updateChapters(input: {ids: $i, patch: {lastPageRead: 4}}) { clientMutationId } }",
               {"i": [c["id"] for c in chapter_ids[:3]]})
    server.gql("mutation($i: [Int!]!) { updateChapters(input: {ids: $i, patch: {isRead: true}}) { clientMutationId } }",
               {"i": [c["id"] for c in chapter_ids[3:6]]})
    start = time.perf_counter()
    after_fp = server.gql(FINGERPRINT)
    old = {n["id"]: n for n in before["mangas"]["nodes"]}
    changed = [n["id"] for n in after_fp["mangas"]["nodes"] if old.get(n["id"]) != n]
    since = server.gql(SINCE, {"t": cursor})["chapters"]["nodes"]
    refetched = server.gql(BY_MANGA, {"ids": changed})["chapters"]["nodes"] if changed else []
    report["incremental"] = {"seconds": round(time.perf_counter() - start, 2), "fingerprintSeconds": round(s_fp, 2),
                             "fingerprintBytes": size(after_fp), "changedSeries": len(changed),
                             "chaptersSinceCursor": len(since), "chaptersRefetched": len(refetched)}
    print("incremental", report["incremental"], flush=True)
    write_json(Path(__file__).parent / "results" / "s5-performance.json", report)


if __name__ == "__main__":
    main()
