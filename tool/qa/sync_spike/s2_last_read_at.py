#!/usr/bin/env python3
"""S2: what do Suwayomi mutations do to `lastReadAt` (and `inLibraryAt`)?

Runs a fixed sequence of mutations on one chapter of a manga that already
exists on the server (S1 creates them) and records every field after each.

Usage: s2_last_read_at.py [--manga-id N]
"""

import argparse
from pathlib import Path
import time

from common import Server, write_json

CHAPTER = "query($id: Int!) { chapter(id: $id) { id lastReadAt lastPageRead isRead isBookmarked pageCount } }"
MANGA = """query($id: Int!) { manga(id: $id) { id inLibrary inLibraryAt
  lastReadChapter { id lastReadAt } latestReadChapter { id } } }"""
UPDATE = """mutation($ids: [Int!]!, $patch: UpdateChapterPatchInput!) {
  updateChapters(input: {ids: $ids, patch: $patch}) { chapters { id } } }"""
UPDATE_MANGA = """mutation($id: Int!, $patch: UpdateMangaPatchInput!) {
  updateManga(input: {id: $id, patch: $patch}) { manga { id } } }"""
SINCE = """query($t: LongString!) { chapters(filter: {lastReadAt: {greaterThan: $t}}) { totalCount } }"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manga-id", type=int)
    parser.add_argument("--fetch-pages", action="store_true",
                        help="fetchChapterPages first, as reading through the server does")
    args = parser.parse_args()
    server = Server()

    manga_id = args.manga_id or server.gql(
        "{ chapters(first: 1, orderBy: ID) { nodes { mangaId } } }")["chapters"]["nodes"][0]["mangaId"]
    chapters = server.gql("query($m: Int!) { chapters(condition: {mangaId: $m}, orderBy: SOURCE_ORDER)"
                          " { nodes { id } } }", {"m": manga_id})["chapters"]["nodes"]
    chapter, other = chapters[0]["id"], chapters[-1]["id"]
    steps = []

    def record(label, patch=None, ids=None, manga_patch=None):
        before_ms = int(time.time() * 1000)
        before_s = int(time.time())
        if patch is not None:
            server.gql(UPDATE, {"ids": ids or [chapter], "patch": patch})
        if manga_patch is not None:
            server.gql(UPDATE_MANGA, {"id": manga_id, "patch": manga_patch})
        state = server.gql(CHAPTER, {"id": chapter})["chapter"]
        manga = server.gql(MANGA, {"id": manga_id})["manga"]
        since = server.gql(SINCE, {"t": str(before_s - 1)})["chapters"]["totalCount"]
        steps.append({"step": label, "sentAtMs": before_ms, "chapter": state, "manga": manga,
                      "chaptersWithLastReadAtSinceStep": since})
        print(f"{label:<44} lastReadAt={state['lastReadAt']:<14} page={state['lastPageRead']:<3} "
              f"read={state['isRead']!s:<5} inLibraryAt={manga['inLibraryAt']} since={since}", flush=True)
        time.sleep(1.2)

    record("start")
    if args.fetch_pages:
        pages = server.gql("mutation($id: Int!) { fetchChapterPages(input: {chapterId: $id}) { pages } }",
                           {"id": chapter})["fetchChapterPages"]["pages"]
        print(f"fetchChapterPages: {len(pages)} pages")
        record("after fetchChapterPages")
    record("lastPageRead=3", {"lastPageRead": 3})
    record("lastPageRead=3 again (no change)", {"lastPageRead": 3})
    record("lastPageRead=1 (backwards)", {"lastPageRead": 1})
    record("isBookmarked=true", {"isBookmarked": True})
    record("isRead=true", {"isRead": True})
    record("isRead=false", {"isRead": False})
    record("isRead=true on another chapter", {"isRead": True}, ids=[other])
    record("lastPageRead=0", {"lastPageRead": 0})
    record("inLibrary=true", manga_patch={"inLibrary": True})
    record("inLibrary=true again", manga_patch={"inLibrary": True})
    record("inLibrary=false", manga_patch={"inLibrary": False})
    record("inLibrary=true after removal", manga_patch={"inLibrary": True})
    write_json(Path(__file__).parent / "results" / f"s2-last-read-at{'-pages' if args.fetch_pages else ''}.json",
               {"mangaId": manga_id, "chapterId": chapter, "otherChapterId": other, "steps": steps})


if __name__ == "__main__":
    main()
