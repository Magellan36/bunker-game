extends Shelving
class_name LargeShelf
## LargeShelf.gd — shelf-family variant: 15 slots as 5 tiers × 3 columns
## (vs. Medium's 5×2=10). Same tier heights and unit height as Medium;
## wider unit to fit 3 columns. Same stack limits, NPC behavior, and
## StorageUI contract inherited.

func _init() -> void:
	display_name   = "Large Shelf"
	slots_per_tier = 3
	unit_w         = 1.70   ## widened from Medium's 1.25 to fit 3 columns
