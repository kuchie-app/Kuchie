#!/usr/bin/env python3
"""S3b: how restoreBackup merges into chapters that already have progress.

Restores the chapters S3 wrote (chapter0: page 5, history 2023-11-14;
chapter1: read) again with lower/older and then newer values.

Usage: s3b_restore_merge.py --source <id> --name <source name>
"""

import argparse
import json
from pathlib import Path

import backup
from common import Server, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    server = Server()
    s3 = json.loads((Path(__file__).parent / "results" / f"s3-{args.source}.json").read_text())
    c0, c1 = s3["restoreProgress"]["chapter0"]["url"], s3["restoreProgress"]["chapter1"]["url"]
    manga_url = next(b["url"] for b in s3["backup"]
                     if server.gql("query($u: String!) { chapters(filter: {url: {equalTo: $u}}) { nodes { manga { url } } } }",
                                   {"u": c0})["chapters"]["nodes"][0]["manga"]["url"] == b["url"])
    title = next(b["title"] for b in s3["backup"] if b["url"] == manga_url)

    def state():
        rows = server.gql("query($a: String!, $b: String!) { chapters(filter: {url: {in: [$a, $b]}}) { nodes"
                          " { url isRead lastPageRead lastReadAt isBookmarked } } }", {"a": c0, "b": c1})
        return {r["url"]: r for r in rows["chapters"]["nodes"]}

    def run(label, chapters, histories):
        data = backup.backup([backup.manga(int(args.source), manga_url, title, chapters=chapters,
                                           histories=histories)],
                             [backup.source(args.name, int(args.source))])
        backup.restore(server, data)
        result = state()
        print(f"{label:<48} c0={result[c0]} c1={result[c1]}", flush=True)
        return {"step": label, "c0": result[c0], "c1": result[c1]}

    steps = [{"step": "before", **{k: v for k, v in zip(("c0", "c1"), (state()[c0], state()[c1]))}}]
    steps.append(run("lower page (2), unread c1, older history (2020)",
                     [backup.chapter(c0, "c0", last_page_read=2), backup.chapter(c1, "c1", read=False)],
                     [backup.history(c0, 1_580_000_000_000)]))
    steps.append(run("higher page (9), bookmark, newer history (2025)",
                     [backup.chapter(c0, "c0", last_page_read=9, bookmark=True), backup.chapter(c1, "c1")],
                     [backup.history(c0, 1_750_000_000_000), backup.history(c1, 1_750_000_000_000)]))
    write_json(Path(__file__).parent / "results" / f"s3b-merge-{args.source}.json", steps)


if __name__ == "__main__":
    main()
