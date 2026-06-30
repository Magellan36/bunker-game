extends GridMap
## BunkerLayout.gd
##
## Provides the MeshLibrary reference for BuildModeController.
## Layout is fully procedural (BunkerPregen.gd) — any tiles placed in the
## editor are wiped at runtime in _ready() so they never appear in-game.
##
## MeshLibrary tile IDs (must match the assigned MeshLibrary asset):
##   0 = Floor
##   1 = Wall
##   2 = Pillar

# ─── Tile ID constants ────────────────────────────────────────────────────────
const FLOOR:    int = 0
const WALL:     int = 1
const PILLAR:   int = 2
const SHELVING: int = 3

# ─── Orientation shortcuts ────────────────────────────────────────────────────
const ROT_Z: int = 0
const ROT_X: int = 22

# ─── Bunker footprint ─────────────────────────────────────────────────────────
## RockSurround.gd reads these to know what area to leave open.
@export var bunker_width: int = 8
@export var bunker_depth: int = 16

# ─── Self-clear ───────────────────────────────────────────────────────────────
## Wipes every tile placed in the editor the moment the scene loads.
## This is the definitive fix for the "mini bunker" — even if tiles exist
## in the .tscn, they are removed before the first rendered frame.
func _ready() -> void:
	var cells: Array[Vector3i] = get_used_cells()
	for cell: Vector3i in cells:
		set_cell_item(cell, INVALID_CELL_ITEM)
	if cells.size() > 0:
		print("[BunkerLayout] Cleared %d editor-placed tile(s) at startup." % cells.size())
