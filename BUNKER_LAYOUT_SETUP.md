# Bunker Layout — Implementation Guide

## What you're building
A GridMap-based bunker: 24x18 grid, 4 defined zones, doorway gaps between them.

```
┌────────────┬────────────┐
│  Quarters  │  Storage   │
│            │            │
├──────┐     ├────────────┤
│ Cmd  │     │  Workshop  │
│      │     │            │
└────────────┴────────────┘
```

---

## Step 1 — Create the MeshLibrary

A MeshLibrary is a collection of 3D meshes GridMap uses as its tiles.
You need 3 tiles: Floor, Wall, Pillar.

1. **Scene > New Scene** → root node: `Node3D` → name it `TileSet`
2. Add 3 children, each a `MeshInstance3D`:
   - **Floor** — PlaneMesh, size `(1, 1)` OR a thin BoxMesh `(1, 0.1, 1)`
   - **Wall** — BoxMesh, size `(1, 2, 1)` (tall block)
   - **Pillar** — BoxMesh, size `(1, 1, 1)` (shorter/thicker)
3. For each MeshInstance3D, give it a material:
   - Create a **StandardMaterial3D**
   - Set **Albedo Color** to a dark grey (e.g. `#4a4a4a`) for concrete feel
   - Roughness: `0.9`, Metallic: `0.0`
4. **Do NOT add CollisionShape3D** — GridMap handles collision automatically

### Export as MeshLibrary:
5. With the `TileSet` scene open, go to **Scene > Export As... > MeshLibrary**
6. Save as `assets/bunker_tiles.meshlib` in your project

---

## Step 2 — Add GridMap to MainWorld.tscn

1. Open `MainWorld.tscn`
2. **Delete** your old flat floor `MeshInstance3D`/`StaticBody3D` (GridMap replaces it)
3. Add a child node: **GridMap** → rename it `BunkerLayout`
4. In the **Inspector**:
   - **Mesh Library** → click the field → Load → select `assets/bunker_tiles.meshlib`
   - **Cell Size** → set to `(2, 2, 2)` (2 units per tile — gives good scale for your player)
5. Attach script: `scripts/world/BunkerLayout.gd`

---

## Step 3 — Reposition the Player

The bunker starts at grid cell (0,0,0). In world space with cell size 2, the center of the bunker is around `(24, 0.1, 18)` — roughly `(24, 0, 18)`.

1. Click your `Player` node in MainWorld.tscn
2. In Inspector → **Transform > Position** → set to `(14, 1, 10)`
   (this puts you in the middle of the bunker, on the floor)

---

## Step 4 — Verify Tile IDs

The script uses:
- ID `0` = Floor
- ID `1` = Wall  
- ID `2` = Pillar

These IDs are assigned **in the order you added the MeshInstance3D children** when building the TileSet scene. Floor must be first child, Wall second, Pillar third. If tiles look wrong, check the order.

To verify: click the GridMap node → Inspector → **Mesh Library** → expand it. You'll see tiles listed 0, 1, 2. Confirm names match.

---

## Step 5 — Hit F5

You should see:
- A concrete floor filling the bunker footprint
- Outer perimeter walls
- Interior divider walls with doorway gaps
- 4 distinct room zones

### Tweaks available in Inspector (on BunkerLayout node):
| Property | Default | Effect |
|---|---|---|
| `bunker_width` | 24 | Makes bunker wider |
| `bunker_depth` | 18 | Makes bunker deeper |

---

## Troubleshooting

**All tiles are the same mesh / wrong tile showing:**
→ Tile ID order is wrong. Rebuild TileSet with Floor as first child.

**Player falls through floor:**
→ GridMap collision is auto-generated but needs **Generate Collision** enabled.
→ Click GridMap → Inspector → enable **Generate Collision** (it's a checkbox).

**Bunker is tiny / too big:**
→ Adjust Cell Size on the GridMap. `(2,2,2)` is recommended. Changing this requires repositioning your player too.

**Walls are floating / below floor:**
→ Wall tiles are stamped at `y=1` (one cell above floor). With cell size 2, that puts them at y=2 world units. This is correct — they sit on top of the floor tiles.
