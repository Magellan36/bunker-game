#!/usr/bin/env python3
"""Main-menu backdrop asset gate (Sep 2026).

Development (default): reports which BackdropAssetSlot nodes still show a
greybox and which referenced assets lack provenance. Always exits 0 unless the
files are malformed.

Release (--release): fails while
  * any BackdropAssetSlot in the backdrop scene has no asset_scene, or
  * any non-code resource referenced by the main-menu scenes (models,
    textures, audio, skies...) has no complete, human-authored provenance
    entry in assets/menu_backdrop/provenance.json.

This complements tools/tests/check_ui_placeholders.py, which covers the
tracked AI-authored UI icon placeholders.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SCENES = [
    ROOT / "scenes/world/menu_backdrop/MenuBackdrop.tscn",
    ROOT / "scenes/ui/main_menu/MainMenu.tscn",
    ROOT / "scenes/world/menu_backdrop/MenuTerrain.tscn",
    ROOT / "scenes/world/menu_backdrop/MenuClutter.tscn",
    ROOT / "scenes/world/menu_backdrop/entrance_cart.tscn",
    *sorted((ROOT / "scenes/world/menu_backdrop/ruins").glob("*.tscn")),
]
BACKDROP = SCENES[0]
MANIFEST = ROOT / "assets/menu_backdrop/provenance.json"
SLOT_SCRIPT = "res://scripts/world/menu_backdrop/BackdropAssetSlot.gd"
CODE_TYPES = {"Script", "Shader", "GDScript"}
INCOMPLETE = re.compile(r"(CONFIRM|TODO|TBD|\?\?)", re.IGNORECASE)

EXT_RE = re.compile(r'^\[ext_resource type="([^"]+)"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"')
NODE_RE = re.compile(r'^\[node name="([^"]+)"')


def parse_ext(text: str) -> dict[str, tuple[str, str]]:
    found: dict[str, tuple[str, str]] = {}
    for line in text.splitlines():
        m = EXT_RE.match(line)
        if m:
            found[m.group(3)] = (m.group(1), m.group(2))
    return found


def slot_report(text: str, ext: dict[str, tuple[str, str]]) -> tuple[list[str], list[str]]:
    slot_ids = {rid for rid, (_, path) in ext.items() if path == SLOT_SCRIPT}
    filled: list[str] = []
    empty: list[str] = []
    name = None
    is_slot = False
    has_asset = False

    def close() -> None:
        if name is not None and is_slot:
            (filled if has_asset else empty).append(name)

    for line in text.splitlines():
        m = NODE_RE.match(line)
        if m:
            close()
            name, is_slot, has_asset = m.group(1), False, False
            continue
        if line.startswith("["):
            close()
            name = None
            continue
        if name is None:
            continue
        s = re.match(r'^script = ExtResource\("([^"]+)"\)', line)
        if s and s.group(1) in slot_ids:
            is_slot = True
        if line.startswith("asset_scene = "):
            has_asset = True
    close()
    return filled, empty


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    entries = {entry["path"]: entry for entry in manifest.get("assets", [])}
    errors: list[str] = []
    notes: list[str] = []

    backdrop_text = BACKDROP.read_text(encoding="utf-8")
    filled, empty = slot_report(backdrop_text, parse_ext(backdrop_text))
    notes.append(f"backdrop slots: {len(filled)} filled, {len(empty)} greybox")
    for name in empty:
        (errors if args.release else notes).append(f"slot still greybox: {name}")

    for scene in SCENES:
        for kind, path in parse_ext(scene.read_text(encoding="utf-8")).values():
            if kind in CODE_TYPES or path.endswith((".gd", ".gdshader")):
                continue
            entry = entries.get(path)
            problem = None
            if entry is None:
                problem = "no provenance entry"
            elif entry.get("ai_generated") is not False:
                problem = "ai_generated must be false"
            elif any(INCOMPLETE.search(str(entry.get(k, ""))) or not entry.get(k)
                     for k in ("author", "source", "license")):
                problem = "author/source/license incomplete"
            if problem:
                message = f"{scene.name}: {path}: {problem}"
                (errors if args.release else notes).append(message)

    for note in notes:
        print(note)
    if errors:
        print("Main-menu backdrop release gate failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Main-menu backdrop check passed." if args.release
          else "Main-menu backdrop development check complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
