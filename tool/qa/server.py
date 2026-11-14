#!/usr/bin/env python3
"""Run a disposable Suwayomi QA catalog without using a personal server."""

import argparse
import binascii
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib


def png_chunk(kind, data):
    chunk = kind + data
    return struct.pack(">I", len(data)) + chunk + struct.pack(">I", binascii.crc32(chunk))


def test_page(chapter, page, tint):
    """Draw deterministic panels, with varying geometry to expose wrong pages."""
    width, height = 640, 960
    ink, paper = bytes((23, 28, 39)), bytes((244, 238, 223))
    accent = bytes(tint)
    bands = (chapter * 3 + page) % 7 + 2
    rows = []
    for y in range(height):
        inset = 32
        panel = (y - 35) // 295
        band_y = (y - 35) % 295
        if 0 <= panel < 3 and 0 <= band_y < 268:
            block_width = 60 + (page * 91 + chapter * 17 + y // 3) % 480
            fill = accent if panel == 1 else ink
            row = paper * inset + fill * block_width
        elif 883 <= y < 915:
            row = paper * inset + (ink * 17 + paper * 9) * bands
        else:
            row = b""
        rows.append(b"\0" + row + paper * (width - len(row) // 3))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(b"".join(rows)))
        + png_chunk(b"IEND", b"")
    )


def seed(root):
    catalog = (
        ("QA - Lantern Station", (36, 89, 133)),
        ("QA - Paper Signal", (159, 73, 46)),
        ("QA - Night Ferry", (66, 111, 76)),
    )
    for title, tint in catalog:
        series = root / "local" / title
        series.mkdir(parents=True)
        (series / "details.json").write_text(
            json.dumps(
                {
                    "title": title,
                    "author": "Kuchie QA",
                    "description": "Synthetic panels for testing chapter navigation and offline saving.",
                    "genre": ["QA"],
                    "status": "0",
                }
            ),
            encoding="utf-8",
        )
        for chapter in range(1, 4):
            folder = series / f"Chapter {chapter:02}"
            folder.mkdir()
            for page in range(1, 19):
                (folder / f"page-{page:02}.png").write_bytes(test_page(chapter, page, tint))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", required=True, type=Path, help="Official Suwayomi Server JAR")
    parser.add_argument("--java", default="java", help="Java executable compatible with the JAR")
    parser.add_argument("--port", type=int, default=14567)
    parser.add_argument("--bind", default="127.0.0.1", choices=("127.0.0.1", "0.0.0.0"),
                        help="Use loopback for Simulator; LAN only for a device on a trusted network")
    args = parser.parse_args()
    if not args.jar.is_file():
        parser.error("the Suwayomi Server JAR does not exist")
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    with tempfile.TemporaryDirectory(prefix="kuchie-qa-catalog-") as directory:
        root = Path(directory)
        seed(root)
        config = {
            "rootDir": root,
            "ip": args.bind,
            "port": args.port,
            "initialOpenInBrowserEnabled": "false",
            "systemTrayEnabled": "false",
            "kcefEnabled": "false",
            "webUIEnabled": "false",
            "globalUpdateInterval": 0,
        }
        print(f"QA catalog: {root}", flush=True)
        print(f"Open http://127.0.0.1:{args.port}; stop with Ctrl-C.", flush=True)
        command = [
            args.java,
            "-Xmx512m",
            f"-Djava.io.tmpdir={root}",
            *[f"-Dsuwayomi.tachidesk.config.server.{key}={value}" for key, value in config.items()],
            "-jar",
            str(args.jar.resolve()),
        ]
        with subprocess.Popen(command, cwd=root) as server:
            try:
                return server.wait()
            except KeyboardInterrupt:
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.terminate()
                    try:
                        server.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        server.kill()
                return 0


if __name__ == "__main__":
    raise SystemExit(main())
