#!/usr/bin/env python3
"""Writes the main-menu ruin compositions (scenes/world/menu_backdrop/ruins/).

Each ruin is a hand-placed arrangement of human-made pieces (Destroyed City
columns/debris/rocks/road slabs, Majadroid towers, floor slabs, wreckage
mounds and fire stairs). The layouts are authored below as data so they are
easy to tweak: (piece, position, rotation degrees (x, y, z), scale). A
negative x scale mirrors a tower so reused pieces read as new silhouettes.

Usage: python3 tools/menu_backdrop/make_ruin_scenes.py
"""
from math import cos, sin, radians
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "scenes/world/menu_backdrop/ruins"
M = "res://assets/models/menu_backdrop/"
PIECES = {
    "column_1": M + "destroyed/column_1/column_1.gltf",
    "column_2": M + "destroyed/column_2/column_2.gltf",
    "column_3": M + "destroyed/column_3/column_3.gltf",
    "debris": M + "destroyed/debris/debris.gltf",
    "rocks": M + "destroyed/rocks/rocks.gltf",
    "road_slab": M + "destroyed/road_slab/road_slab.gltf",
    "floor_slab": M + "destroyed/floor_slab/floor_slab.gltf",
    "wreckage_1": M + "destroyed/wreckage_1/wreckage_1.gltf",
    "wreckage_2": M + "destroyed/wreckage_2/wreckage_2.gltf",
    "wreckage_3": M + "destroyed/wreckage_3/wreckage_3.gltf",
    "fire_stairs": M + "destroyed/fire_stairs/fire_stairs.gltf",
    "tower_01": M + "tower_majadroid_01.glb",
    "tower_02": M + "tower_majadroid_02.glb",
    "tower_03": M + "tower_majadroid_03.glb",
    "tower_05": M + "tower_majadroid_05.glb",
    "tower_06": M + "tower_majadroid_06.glb",
    "tyre": M + "clutter/tyre/tyre.gltf",
    "jerrycan": M + "clutter/jerrycan/jerrycan.gltf",
}

RUINS = {
    # Mid-ground, right flank: a collapsed frame. Pillars scaled to ~9 m,
    # one fallen, a floor slab leaning on them, stairs thrown down.
    "ruin_collapse_right": [
        ("wreckage_3", (0, -0.4, 0), (0, 20, 0), (0.62, 0.7, 0.62)),
        ("column_1", (-3.2, 0, -2.0), (0, 15, 0), (1.8, 1.8, 1.8)),
        ("column_2", (2.6, 0, 1.4), (0, -30, 14), (1.6, 1.6, 1.6)),
        ("column_3", (1.5, 1.1, -4.8), (84, 60, 0), (1.5, 1.5, 1.5)),
        ("floor_slab", (-0.5, 2.6, -0.8), (13, 25, -9), (0.26, 0.4, 0.26)),
        ("fire_stairs", (5.2, 0.9, -1.5), (0, 70, 68), (1, 1, 1)),
        ("debris", (-5.5, 0, 2.6), (0, 110, 0), (1.4, 1.2, 1.4)),
        ("debris", (4.8, 0, 4.4), (0, -40, 6), (1.1, 1, 1.1)),
        ("rocks", (0.8, 0, 5.5), (0, 200, 0), (1.3, 1.3, 1.3)),
        ("road_slab", (-4.0, 0.4, 5.6), (0, 35, -12), (1.2, 1, 1.2)),
        ("road_slab", (6.5, 0.3, -5.0), (8, -65, 0), (1, 1, 1)),
    ],
    # Mid-ground, left (behind the menu): kept low and quiet.
    "ruin_collapse_left": [
        ("wreckage_2", (0, -0.6, 0), (0, 70, 0), (0.5, 0.55, 0.5)),
        ("column_3", (-1.6, 0, 0.8), (0, 40, 0), (1.1, 0.8, 1.1)),
        ("column_2", (2.8, 0.9, -1.5), (86, -20, 0), (1.2, 1.2, 1.2)),
        ("debris", (0.5, 0, 3.2), (0, 15, 0), (1.3, 1, 1.3)),
        ("rocks", (-3.8, 0, -2.4), (0, 90, 0), (1.2, 1, 1.2)),
        ("road_slab", (3.6, 0.2, 2.9), (0, -20, 9), (1, 1, 1)),
    ],
    # Foreground rubble slots (were greybox).
    "rubble_left": [
        ("debris", (0, 0, 0), (0, 30, 0), (1.25, 1.0, 1.25)),
        ("rocks", (1.9, 0, 0.8), (0, 160, 0), (0.9, 0.9, 0.9)),
        ("road_slab", (-1.6, 0.18, 1.2), (0, -25, 11), (0.8, 1, 0.8)),
        ("tyre", (1.2, 0.08, -1.1), (90, 20, 0), (1, 1, 1)),
    ],
    "rubble_right": [
        ("rocks", (0, 0, 0), (0, -30, 0), (1.0, 0.8, 1.0)),
        ("debris", (-1.1, 0, -0.6), (0, 200, 0), (0.7, 0.6, 0.7)),
        ("jerrycan", (0.9, 0.12, 0.7), (0, 40, 90), (1, 1, 1)),
    ],
    # Replaces the plain intact block that read as a grey box: tower 03
    # mirrored, leaning and sunk into its own rubble.
    "ruin_leaning_03": [
        ("tower_03", (0, -7, 0), (0, 150, 5), (-1, 1, 1)),
        ("wreckage_1", (4, -0.5, 6), (0, 30, 0), (2.4, 2.2, 2.4)),
        ("wreckage_3", (-20, -0.3, -8), (0, 0, 0), (1.6, 1.8, 1.6)),
    ],
    # Far band (470-560 m): new silhouettes from mirrored, turned, leaning or
    # half-buried towers, and one pancaked block.
    "far_pancake": [
        ("wreckage_2", (0, -0.8, 0), (0, 10, 0), (2.8, 3.0, 2.8)),
        ("floor_slab", (0, 1.5, 0), (4, 0, -3), (1, 1, 1)),
        ("floor_slab", (3, 5.0, -2), (-6, 12, 5), (0.95, 1, 0.95)),
        ("floor_slab", (-2, 8.2, 3), (8, -9, -7), (0.9, 1, 0.9)),
        ("floor_slab", (5, 11.0, 1), (-3, 25, 12), (0.8, 1, 0.8)),
        ("column_1", (-18, 0, -14), (0, 0, 8), (4, 5, 4)),
        ("column_2", (17, 0, 12), (0, 40, -6), (4, 4.5, 4)),
        ("column_3", (-14, 0, 18), (0, 80, 0), (4, 3.5, 4)),
    ],
    "far_tower_05": [
        ("tower_05", (0, -18, 0), (0, 40, 0), (-1, 1, 1)),
        ("wreckage_3", (0, -0.5, 0), (0, 15, 0), (3.2, 3.4, 3.2)),
    ],
    "far_tower_06": [
        ("tower_06", (0, -8, 0), (-5, 92, 0), (-1, 1, 1)),
        ("wreckage_1", (10, -0.5, 8), (0, 60, 0), (3.0, 2.6, 3.0)),
    ],
    "far_tower_01": [
        ("tower_01", (0, -10, 0), (0, -52, -7), (-1, 1, 1)),
        ("wreckage_2", (-6, -0.5, 5), (0, 0, 0), (2.6, 2.4, 2.6)),
    ],
    "far_tower_02": [
        ("tower_02", (0, -34, 0), (0, 126, 0), (-1, 1, 1)),
        ("wreckage_1", (0, -0.5, 0), (0, 45, 0), (3.4, 3.2, 3.4)),
    ],
}


def basis(rot_deg, scale):
    """Godot Basis.from_euler (YXZ order) with per-axis scale, as the 9 numbers Transform3D serialises."""
    x, y, z = (radians(a) for a in rot_deg)
    cx, sx, cy, sy, cz, sz = cos(x), sin(x), cos(y), sin(y), cos(z), sin(z)
    # R = Ry * Rx * Rz
    r = [
        [cy * cz + sy * sx * sz, -cy * sz + sy * sx * cz, sy * cx],
        [cx * sz, cx * cz, -sx],
        [-sy * cz + cy * sx * sz, sy * sz + cy * sx * cz, cy * cx],
    ]
    # Transform3D text lists the basis row by row; column c is scaled by scale[c].
    return [r[row][col] * scale[col] for row in range(3) for col in range(3)]


def write(name, parts):
    used = sorted({p[0] for p in parts})
    ids = {piece: str(i + 1) for i, piece in enumerate(used)}
    lines = ["[gd_scene format=3]", ""]
    for piece in used:
        lines.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (PIECES[piece], ids[piece]))
    lines += ["", '[node name="%s" type="Node3D"]' % name, ""]
    for i, (piece, pos, rot, scale) in enumerate(parts):
        b = basis(rot, scale)
        lines.append('[node name="%s_%d" parent="." instance=ExtResource("%s")]' % (piece, i, ids[piece]))
        lines.append("transform = Transform3D(%s, %g, %g, %g)" % (", ".join("%.5f" % v for v in b), *pos))
        lines.append("")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / (name + ".tscn")).write_text("\n".join(lines))
    print("wrote", name, len(parts), "pieces")


if __name__ == "__main__":
    for ruin, parts in RUINS.items():
        write(ruin, parts)
