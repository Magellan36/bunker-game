#!/usr/bin/env python3
"""Packs the main-menu ground sets (ambientCG, CC0) for the menu terrain shader.

Source: /mnt/storage/Bunker Game/models/NEW MODELS/MAIN MENU GROUND/*.zip
Output: assets/menu_backdrop/ground/<layer>/
    albedo.jpg   colour (sRGB)
    normal.png   OpenGL-convention normal map (Godot's convention)
    ord.png      R = ambient occlusion, G = roughness, B = height (displacement)

Pure repacking of the human-made source maps: nothing is generated.
Usage: python3 tools/menu_terrain/pack_ground_textures.py [--size 2048]
"""
import argparse, io, zipfile
from pathlib import Path
from PIL import Image

SRC = Path("/mnt/storage/Bunker Game/models/NEW MODELS/MAIN MENU GROUND")
OUT = Path(__file__).resolve().parents[2] / "assets/menu_backdrop/ground"
LAYERS = {  # layer name -> ambientCG set
    "earth": "Ground067",
    "gravel": "Ground062S",
    "debris": "Ground073",
    "brick": "Ground111",
}

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=2048)
    size = ap.parse_args().size
    for layer, set_id in LAYERS.items():
        z = zipfile.ZipFile(SRC / f"{set_id}_2K-PNG.zip")
        def img(suffix: str) -> Image.Image:
            im = Image.open(io.BytesIO(z.read(f"{set_id}_2K-PNG_{suffix}.png")))
            return im.resize((size, size), Image.LANCZOS) if im.size[0] != size else im
        out = OUT / layer
        out.mkdir(parents=True, exist_ok=True)
        img("Color").convert("RGB").save(out / "albedo.jpg", quality=92, optimize=True)
        img("NormalGL").convert("RGB").save(out / "normal.png", optimize=True)
        ao, rough, height = (img(s).convert("L") for s in ("AmbientOcclusion", "Roughness", "Displacement"))
        Image.merge("RGB", (ao, rough, height)).save(out / "ord.png", optimize=True)
        print(layer, set_id, "->", out)

if __name__ == "__main__":
    main()
