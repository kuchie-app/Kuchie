#!/usr/bin/env python3
"""S4b: on a server with several users (preview v2.4.2512+), which state is
per user and which is shared?

Only for the disposable QA server (`tool/qa/server.py`): it switches on
UI_LOGIN with throwaway random credentials, adds a second user, and switches
auth back to NONE at the end. Uses the server's local source (the three QA
series `server.py` seeds), so no extension or network is needed.

Checks, as user A then as user B:
  library   user.inLibrary after A adds a series
  progress  user.lastPageRead / isRead / isBookmarked / lastReadAt after A reads
  history   chapters(filter: {lastReadAt > 0}) per user
  restore   restoreBackup by B (history + read state): who gets it
  downloads user.isDownloaded after A downloads a chapter
  identity  the JWT's claims, for telling accounts apart

Usage: s4b_multi_user.py
"""

import base64
import json
import secrets
import time
from pathlib import Path

import backup
from common import GraphQLError, Server, write_json

SETTINGS = """mutation($s: PartialSettingsTypeInput!) {
  setSettings(input: {settings: $s}) { settings { authMode } } }"""
LOGIN = """mutation($u: String!, $p: String!) {
  login(input: {username: $u, password: $p}) { accessToken refreshToken } }"""
CODE = "mutation { createRegistrationCode(input: {}) { code expiresAt } }"
REGISTER = """mutation($u: String!, $p: String!) {
  register(input: {username: $u, password: $p}) { clientMutationId } }"""
REDEEM = """mutation($c: String!, $u: String!, $p: String!) {
  redeemRegistrationCode(input: {code: $c, username: $u, password: $p}) { clientMutationId } }"""
ME = "{ user { id username roles permissions } }"
SOURCE = """mutation { fetchSourceManga(input: {source: "0", type: POPULAR, page: 1}) {
  mangas { id title url } } }"""
FETCH = """mutation($id: Int!) { fetchMangaAndChapters(input: {id: $id, fetchManga: true, fetchChapters: true}) {
  chapters { id name url sourceOrder } } }"""
PAGES = "mutation($id: Int!) { fetchChapterPages(input: {chapterId: $id}) { pages } }"
ADD = """mutation($ids: [Int!]!) { updateMangas(input: {ids: $ids, patch: {inLibrary: true}}) {
  mangas { id } } }"""
READ = """mutation($ids: [Int!]!, $patch: UpdateChapterPatchInput!) {
  updateChapters(input: {ids: $ids, patch: $patch}) { chapters { id } } }"""
STATE = """query($m: Int!) {
  manga(id: $m) { id user { inLibrary inLibraryAt } }
  mangas(condition: {inLibrary: true}) { totalCount }
  read: chapters(filter: {lastReadAt: {greaterThan: "0"}}) { totalCount }
  chapters(condition: {mangaId: $m}, order: [{by: SOURCE_ORDER, byType: ASC}]) {
    nodes { id sourceOrder pageCount user { isRead isBookmarked lastPageRead lastReadAt isDownloaded } } }
}"""
ENQUEUE = "mutation($ids: [Int!]!) { enqueueChapterDownloads(input: {ids: $ids}) { clientMutationId } }"
START = "mutation { startDownloader(input: {}) { clientMutationId } }"


def claims(token):
    payload = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def as_user(server, username, password):
    tokens = server.gql(LOGIN, {"u": username, "p": password})["login"]
    return Server(server.base, {"Authorization": f"Bearer {tokens['accessToken']}"}), tokens


def state(client, manga_id):
    data = client.gql(STATE, {"m": manga_id})
    return {
        "inLibrary": data["manga"]["user"]["inLibrary"],
        "inLibraryAt": data["manga"]["user"]["inLibraryAt"],
        "libraryCount": data["mangas"]["totalCount"],
        "readCount": data["read"]["totalCount"],
        "chapters": [
            {"sourceOrder": c["sourceOrder"], "pageCount": c["pageCount"], **c["user"]}
            for c in data["chapters"]["nodes"]
        ],
    }


def main():
    anonymous = Server()
    seeded = anonymous.gql(SOURCE)["fetchSourceManga"]["mangas"]
    manga = seeded[0]
    chapters = anonymous.gql(FETCH, {"id": manga["id"]})["fetchMangaAndChapters"]["chapters"]
    chapters.sort(key=lambda c: c["sourceOrder"])
    for chapter in chapters:
        anonymous.gql(PAGES, {"id": chapter["id"]})
    c0, c1, c2 = (c["id"] for c in chapters[:3])

    # Without auth every request is user 1 ("admin"), so set it up first.
    admin_name, admin_pass = "admin", secrets.token_urlsafe(16)
    reader_name, reader_pass = "qa-reader", secrets.token_urlsafe(16)
    results = {"server": anonymous.gql("{ aboutServer { version } }")["aboutServer"]["version"],
               "manga": manga, "chapters": chapters,
               "anonymousIs": anonymous.gql(ME)["user"]}
    # The built-in admin's password is managed by the auth settings; set it
    # while auth is still off, since setPassword refuses for that user.
    anonymous.gql(SETTINGS, {"s": {"authUsername": admin_name, "authPassword": admin_pass}})
    try:
        anonymous.gql(REGISTER, {"u": reader_name, "p": reader_pass})
        results["createdWith"] = "register (as user 1 without auth)"
    except GraphQLError as error:
        results["registerError"] = str(error)[:300]
        code = anonymous.gql(CODE)["createRegistrationCode"]["code"]
        anonymous.gql(REDEEM, {"c": code, "u": reader_name, "p": reader_pass})
        results["createdWith"] = "createRegistrationCode + redeemRegistrationCode"
    anonymous.gql(SETTINGS, {"s": {"authMode": "UI_LOGIN"}})
    admin = None
    try:
        admin, admin_tokens = as_user(anonymous, admin_name, admin_pass)
        results["adminClaims"] = claims(admin_tokens["accessToken"])
        results["adminMe"] = admin.gql(ME)["user"]
        reader, reader_tokens = as_user(anonymous, reader_name, reader_pass)
        results["readerClaims"] = claims(reader_tokens["accessToken"])
        results["readerMe"] = reader.gql(ME)["user"]
        results["before"] = {"admin": state(admin, manga["id"]), "reader": state(reader, manga["id"])}

        # Admin adds the series and reads chapter 0; reader reads chapter 1.
        admin.gql(ADD, {"ids": [manga["id"]]})
        admin.gql(READ, {"ids": [c0], "patch": {"lastPageRead": 5, "isBookmarked": True}})
        reader.gql(READ, {"ids": [c1], "patch": {"lastPageRead": 3, "isRead": True}})
        results["afterProgress"] = {"admin": state(admin, manga["id"]), "reader": state(reader, manga["id"])}

        # Reader restores history for chapter 2.
        data = backup.backup(
            [backup.manga(0, manga["url"], manga["title"], chapters=[
                backup.chapter(chapters[2]["url"], chapters[2]["name"], read=True, last_page_read=7,
                               source_order=chapters[2]["sourceOrder"]),
            ], histories=[backup.history(chapters[2]["url"], 1700000000000)])],
            [backup.source("Local source", 0)],
        )
        results["restore"] = backup.restore(reader, data)
        results["afterRestore"] = {"admin": state(admin, manga["id"]), "reader": state(reader, manga["id"])}

        # Admin downloads chapter 0.
        admin.gql(ENQUEUE, {"ids": [c0]})
        try:
            admin.gql(START)
        except GraphQLError as error:
            # Enqueueing usually starts it already; the call can time out.
            results["startDownloaderError"] = str(error)[:200]
        deadline = time.time() + 60
        while time.time() < deadline:
            if state(admin, manga["id"])["chapters"][0]["isDownloaded"]:
                break
            time.sleep(1)
        results["afterDownload"] = {"admin": state(admin, manga["id"]), "reader": state(reader, manga["id"])}
    finally:
        try:
            (admin or anonymous).gql(SETTINGS, {"s": {"authMode": "NONE"}})
        except Exception as error:  # noqa: BLE001
            results["resetError"] = str(error)[:300]
        results["authAfter"] = Server().gql("{ settings { authMode } }", raw=True)
    write_json(Path(__file__).parent / "results" / "s4b-multi-user.json", results)
    print(json.dumps({k: results[k] for k in ("createdWith", "afterProgress", "afterRestore", "afterDownload", "authAfter")
                      if k in results}, indent=1)[:6000])


if __name__ == "__main__":
    main()
