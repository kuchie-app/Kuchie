import argparse
import json
import shutil
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("frames", type=Path)
args = parser.parse_args()
base = Path(__file__).resolve().parent
out = base.parent / "character"
out.mkdir(exist_ok=True)
scenes = json.loads((base / "scenes.json").read_text())
for phase, info in scenes.items():
    paths = sorted((args.frames / phase).glob("*.png"))
    if len(paths) < 10:
        raise ValueError(f"{phase} needs a full render")
    frames = [Image.open(p).convert("RGBA") for p in paths]
    assert all(f.size == (480, 360) for f in frames), phase
    interval = round(info["duration"] / len(frames))
    durations = [interval] * len(frames)
    durations[-1] += info["duration"] - interval * len(frames)
    frames[0].save(
        out / f"{phase}.webp", save_all=True, append_images=frames[1:],
        duration=durations, loop=0 if phase == "loading" else 1,
        quality=84, alpha_quality=95, method=5,
    )
    frames[-1].save(out / f"{phase}.png", optimize=True)
    shutil.copyfile(args.frames / phase / "final.svg", out / f"{phase}.svg")
    for frame in frames:
        frame.close()
    with Image.open(out / f"{phase}.webp") as image:
        assert image.n_frames >= 10, phase
        assert image.info.get("loop") == (0 if phase == "loading" else 1), phase
        assert image.getbbox() and image.getpixel((0, 0))[3] == 0, phase
    print(f"{phase} — {len(paths)} frames, {(out / f'{phase}.webp').stat().st_size // 1024} KB")
