extends Shelving
class_name SmallShelf
## SmallShelf.gd — shelf-family variant: 6 slots as 3 tiers × 2 columns
## (vs. Medium's 5×2=10). Same procedural mesh style, stack limits, NPC
## behavior, and StorageUI contract inherited — only tier layout differs.

func _init() -> void:
	display_name = "Small Shelf"
	shelf_y       = [0.225, 0.675, 1.125]
	unit_h        = 1.6   ## proportional to 3 tiers vs Medium's 5-tier 2.5
