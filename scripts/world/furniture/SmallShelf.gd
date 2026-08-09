extends Shelving
class_name SmallShelf
## SmallShelf.gd — shelf-family variant: 6 slots as 3 tiers × 2 columns
## (vs. Medium's 5×2=10). Same procedural mesh style, stack limits, NPC
## behavior, and StorageUI contract inherited — only tier layout differs.

func _init() -> void:
	display_name = "Small Shelf"
	## Aug 2026 — same 0.60 spacing/lowered-floor fix as Medium so TestCrate
	## (H=0.48) fits here too; unit_h proportioned the same way (3 tiers).
	shelf_y       = [0.12, 0.72, 1.32]   ## was [0.225, 0.675, 1.125]
	unit_h        = 2.35                  ## was 1.6
