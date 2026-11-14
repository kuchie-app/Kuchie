# Kiri motion

Flutter loads the nine final WebP animations and static PNG poses from
`assets/kuchie/character/`. The source rig and keyframes are here so the
illustrations can be edited and regenerated. Only the chapter loading scene
loops. The app swaps in the corresponding final pose when Reduce Motion is on.

From this directory, run these commands with Node.js, Sharp and Python Pillow
(with WebP support):

```sh
node source/render.cjs /tmp/kuchie-kiri-frames
python3 source/export.py /tmp/kuchie-kiri-frames
cp character/*.webp character/*.png ../../assets/kuchie/character/
```

Use a fresh temporary frame directory when changing a scene's duration to avoid
reusing frames from an earlier render.
