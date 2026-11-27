#!/usr/bin/env python3
"""S1: does Kuchie's stableLocator equal Suwayomi's manga/chapter `url`?

Lists popular series through the Simulator's extension runtime (what the
Local library stores), lists the same pages through the server, then looks
each Kuchie locator up with `mangas(condition: {sourceId, url})` and compares
chapter URLs after `fetchMangaAndChapters`.

Usage: s1_urls.py --apk <extension.apk> --source <mihon source id> [--series 20]
"""

import argparse
from pathlib import Path

from common import GraphQLError, Runtime, Server, mihon_locator_id, stable_locator, chapter_locator, write_json

FIND = """query($s: LongString!, $u: String!) {
  mangas(condition: {sourceId: $s, url: $u}) { nodes { id url title } }
}"""
FETCH_SOURCE = """mutation($s: LongString!, $p: Int!, $t: FetchSourceMangaType!, $q: String) {
  fetchSourceManga(input: {source: $s, page: $p, type: $t, query: $q}) {
    hasNextPage mangas { id url title }
  }
}"""
FETCH_CHAPTERS = """mutation($id: Int!) {
  fetchMangaAndChapters(input: {id: $id, fetchManga: true, fetchChapters: true}) {
    chapters { url name }
  }
}"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--source", required=True)
    parser.add_argument("--series", type=int, default=20)
    parser.add_argument("--min-chapters", type=int, default=200,
                        help="keep adding series until this many chapters are compared")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    runtime, server = Runtime(args.apk), Server()

    def listed():
        page = 1
        while True:
            result = runtime.popular(args.source, page)
            # The server lists the same page, which creates its manga rows.
            server.gql(FETCH_SOURCE, {"s": args.source, "p": page, "t": "POPULAR", "q": None})
            yield from result["mangas"]
            if not result.get("hasNextPage") or page >= 50:
                return
            page += 1

    report = {"source": args.source, "apk": args.apk.name, "series": [], "summary": {}}
    series_exact = chapters_total = chapters_exact = 0
    local = []
    for manga in listed():
        if len(local) >= args.series and chapters_total >= args.min_chapters:
            break
        local.append(manga)
        stable = stable_locator(manga["url"])
        nodes = server.gql(FIND, {"s": args.source, "u": stable})["mangas"]["nodes"]
        entry = {"title": manga["title"], "kuchie": stable, "kuchieId": mihon_locator_id(stable)}
        if not nodes:
            # Not listed by the server this time, or a different URL: search by title.
            found = server.gql(FETCH_SOURCE, {"s": args.source, "p": 1, "t": "SEARCH",
                                              "q": manga["title"]})["fetchSourceManga"]["mangas"]
            same_title = [m for m in found if m["title"].strip().lower() == manga["title"].strip().lower()]
            entry["serverSameTitle"] = [m["url"] for m in same_title]
            nodes = server.gql(FIND, {"s": args.source, "u": stable})["mangas"]["nodes"]
        entry["match"] = bool(nodes)
        if nodes:
            series_exact += 1
            try:
                server_chapters = server.gql(FETCH_CHAPTERS, {"id": nodes[0]["id"]})[
                    "fetchMangaAndChapters"]["chapters"]
            except GraphQLError as error:
                if "No chapters found" not in str(error):
                    raise
                server_chapters = []
            server_urls = {c["url"] for c in server_chapters}
            kuchie_urls = [stable_locator(chapter_locator(c["url"], c))
                           for c in runtime.chapters(args.source, manga)]
            matched = sum(1 for u in kuchie_urls if u in server_urls)
            entry.update(chapters=len(kuchie_urls), serverChapters=len(server_urls),
                         chaptersMatched=matched,
                         chapterMisses=[u for u in kuchie_urls if u not in server_urls][:5])
            chapters_total += len(kuchie_urls)
            chapters_exact += matched
        report["series"].append(entry)
        print(f"{'OK ' if entry['match'] else 'MISS'} {manga['title'][:50]!r} "
              f"chapters {entry.get('chaptersMatched', 0)}/{entry.get('chapters', 0)}", flush=True)

    report["summary"] = {
        "series": len(local), "seriesExact": series_exact,
        "chapters": chapters_total, "chaptersExact": chapters_exact,
        "seriesRate": round(series_exact / max(len(local), 1), 4),
        "chapterRate": round(chapters_exact / max(chapters_total, 1), 4),
    }
    print(report["summary"])
    write_json(args.out or Path(__file__).parent / "results" / f"s1-{args.source}.json", report)


if __name__ == "__main__":
    main()
