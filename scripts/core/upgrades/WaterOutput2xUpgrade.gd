extends UpgradeDef
class_name WaterOutput2xUpgrade
## WaterOutput2xUpgrade.gd
## First tiered upgrade. Tier count is COMPUTED from WaterHookup's own
## TIER_DAILY_ML array (3 real completions: index 0→1, 1→2, 2→3 — NOT the
## illustrative "4" from the reference sketch, which was showing the UI
## pattern generically, not water output's real number). apply_effect()
## direct-sets hookup.tier rather than replaying the old "+1" debug logic —
## see the redesign plan's note on why direct-set is more correct once
## progress is tracked by the station rather than the button itself.

func get_max_tier() -> int:
	return WaterHookup.TIER_DAILY_ML.size() - 1

func apply_effect(tier_reached: int) -> void:
	var wm: WaterManager = get_tree_ref().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	var hookup: WaterHookup = wm.get_the_hookup()
	if hookup == null:
		return
	hookup.tier = clampi(tier_reached, 0, WaterHookup.TIER_DAILY_ML.size() - 1)

## Resources have no SceneTree of their own — this needs the running tree,
## injected by whatever calls apply_effect() (ResearchStation, Part 3).
var _tree_ref: SceneTree = null
func set_tree_ref(t: SceneTree) -> void:
	_tree_ref = t
func get_tree_ref() -> SceneTree:
	return _tree_ref