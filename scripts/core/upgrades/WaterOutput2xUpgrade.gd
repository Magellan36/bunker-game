extends UpgradeDef
class_name WaterOutput2xUpgrade
## WaterOutput2xUpgrade.gd
## First real (non-placeholder) upgrade. Effect copied VERBATIM from
## AdminMenu._on_hookup_output_double_pressed() — "2x water output" == tier
## + 1, since WaterHookup.TIER_DAILY_ML's four tiers are each exactly double
## the last. Same clamp-at-max-tier behavior, same reasoning, per direction
## to copy the existing working debug function exactly.

func apply_effect() -> void:
	var wm: WaterManager = get_tree_ref().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	var hookup: WaterHookup = wm.get_the_hookup()
	if hookup == null:
		return
	var max_tier: int = WaterHookup.TIER_DAILY_ML.size() - 1
	if hookup.tier >= max_tier:
		push_warning("WaterOutput2xUpgrade: hookup already at max tier — no effect")
		return
	hookup.tier += 1

## Resources have no SceneTree of their own — this needs the running tree,
## injected by whatever calls apply_effect() (ResearchStation, Part 3).
var _tree_ref: SceneTree = null
func set_tree_ref(t: SceneTree) -> void:
	_tree_ref = t
func get_tree_ref() -> SceneTree:
	return _tree_ref