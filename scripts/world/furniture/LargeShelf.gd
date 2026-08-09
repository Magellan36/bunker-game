extends Shelving
class_name LargeShelf
## LargeShelf.gd — shelf-family variant: 15 slots as 5 tiers × 3 columns
## (vs. Medium's 5×2=10). Same tier heights and unit height as Medium;
## wider unit to fit 3 columns. Same stack limits, NPC behavior, and
## StorageUI contract inherited.

func _init() -> void:
	display_name   = "Large Shelf"
	slots_per_tier = 3
	## Aug 2026 — 0.62 = TestCrate width (0.54, the widest item) + 0.08
	## clearance, so 3 crates sit snug side-by-side with no overlap (columns
	## at ±0.62/0, crate edges at ±0.89, 0.08 gap between neighbours).
	multi_col_spacing = 0.62
	## Aug 2026 — widened from 1.70 so 3 crates at 0.62 spacing sit inside the
	## frame: unit_w/2 = 1.00, outermost crate edge at 0.89 → 0.11 margin.
	unit_w            = 2.00
