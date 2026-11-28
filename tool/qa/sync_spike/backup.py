"""A minimal Mihon backup (`.tachibk`: gzipped protobuf) for `restoreBackup`.

Field numbers follow Mihon's `eu.kanade.tachiyomi.data.backup.models`
(Backup, BackupManga, BackupChapter, BackupHistory, BackupSource,
BackupCategory), which Suwayomi reads.
"""

import gzip
import json
import struct
import time
import uuid
import urllib.error
import urllib.request


def _varint(value):
    value &= (1 << 64) - 1
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _key(field, wire):
    return _varint(field << 3 | wire)


def _int(field, value):
    return _key(field, 0) + _varint(int(value))


def _bool(field, value):
    return _int(field, 1 if value else 0)


def _bytes(field, data):
    return _key(field, 2) + _varint(len(data)) + data


def _str(field, text):
    return _bytes(field, text.encode("utf-8"))


def _float(field, value):
    return _key(field, 5) + struct.pack("<f", value)


def chapter(url, name, *, read=False, bookmark=False, last_page_read=0, number=-1.0,
            source_order=0, last_modified_at=0):
    return b"".join([
        _str(1, url), _str(2, name), _bool(4, read), _bool(5, bookmark),
        _int(6, last_page_read), _float(9, number), _int(10, source_order),
        _int(11, last_modified_at),
    ])


def history(url, last_read_ms, read_duration=0):
    return _str(1, url) + _int(2, last_read_ms) + _int(3, read_duration)


def manga(source_id, url, title, *, favorite=True, chapters=(), histories=(), categories=(),
          date_added_ms=0):
    parts = [_int(1, source_id), _str(2, url), _str(3, title), _int(13, date_added_ms)]
    parts += [_bytes(16, c) for c in chapters]
    parts += [_int(17, c) for c in categories]
    parts += [_bool(100, favorite)]
    parts += [_bytes(104, h) for h in histories]
    return b"".join(parts)


def category(name, order, cid=None):
    return _str(1, name) + _int(2, order) + (_int(3, cid) if cid is not None else b"")


def source(name, source_id):
    return _str(1, name) + _int(2, source_id)


def backup(mangas, sources, categories=()):
    body = b"".join([_bytes(1, m) for m in mangas] + [_bytes(2, c) for c in categories]
                    + [_bytes(101, s) for s in sources])
    return gzip.compress(body)


RESTORE = """mutation($backup: Upload!, $flags: PartialBackupFlagsInput) {
  restoreBackup(input: {backup: $backup, flags: $flags}) { id status { state totalManga mangaProgress } }
}"""
STATUS = "query($id: String!) { restoreStatus(id: $id) { state totalManga mangaProgress } }"


def restore(server, data, flags=None, timeout=900):
    """GraphQL multipart upload, then poll `restoreStatus` until it settles."""
    boundary = uuid.uuid4().hex
    operations = json.dumps({"query": RESTORE, "variables": {"backup": None, "flags": flags}})
    parts = [
        ("operations", None, operations.encode()),
        ("map", None, json.dumps({"0": ["variables.backup"]}).encode()),
        ("0", "kuchie-spike.tachibk", data),
    ]
    body = bytearray()
    for name, filename, content in parts:
        body += f"--{boundary}\r\n".encode()
        disposition = f'form-data; name="{name}"' + (f'; filename="{filename}"' if filename else "")
        body += f"Content-Disposition: {disposition}\r\n".encode()
        if filename:
            body += b"Content-Type: application/octet-stream\r\n"
        body += b"\r\n" + content + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    request = urllib.request.Request(
        f"{server.base}/api/graphql", data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}", **server.headers},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"restoreBackup HTTP {error.code}: {error.read()[:500]!r}")
    if payload.get("errors"):
        raise RuntimeError(json.dumps(payload["errors"])[:1000])
    rid = payload["data"]["restoreBackup"]["id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = server.gql(STATUS, {"id": rid})["restoreStatus"]
        if status and status["state"] in ("SUCCESS", "FAILURE"):
            return status
        time.sleep(0.5)
    raise TimeoutError("restore did not finish")
