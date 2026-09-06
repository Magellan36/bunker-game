extends SceneTree
## Headless HUD status presentation smoke. Run with:
## godot --headless --path . --script res://tools/tests/hud_status_icons_smoke.gd

const BADGE_SCRIPT: GDScript = preload("res://scripts/ui/hud/StatusEffectIcon.gd")
const CONTAINER_SCRIPT: GDScript = preload("res://scripts/ui/hud/StatusEffectsContainer.gd")
const SYMBOL_SCRIPT: GDScript = preload("res://scripts/ui/common/BunkerSymbolTexture.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var container: StatusEffectsContainer = CONTAINER_SCRIPT.new() as StatusEffectsContainer
	root.add_child(container)
	container.add_medical_effect("open_wound_2", null, Color("c84940"), true)
	container.update_medical_effect("open_wound_2", 1.0, 0.4, "Open wound")
	container.update_medical_outer_ring("open_wound_2", true, 0.25, Color("c39b38"))
	await process_frame

	var badges: Dictionary = container.get("_badges") as Dictionary
	var medical: StatusEffectIcon = badges.get("open_wound_2") as StatusEffectIcon
	_check(medical != null, "medical badge is created")
	if medical != null:
		_check(medical.custom_minimum_size == Vector2(50.0, 50.0),
			"approved compact badge footprint is preserved")
		_check(str(medical.call("_symbol_for_effect")) == "infection",
			"infected wounds receive the infection fallback icon")
		_check(is_equal_approx(float(medical.get("_severity_frac")), 1.0),
			"medical severity remains externally driven")
		_check(is_equal_approx(float(medical.get("_heal_frac")), 0.4),
			"healing overlay fraction remains externally driven")
		medical.update_medical(0.3, 0.8, "Open wound")
		medical.call("_process", 0.05)
		var eased_heal: float = float(medical.get("_display_heal_frac"))
		_check(eased_heal > 0.4 and eased_heal < 0.8,
			"medical healing ring eases between live values")
		_check(medical.get("_has_outer_ring") == true,
			"infection-style outer ring remains independent")

	container.add_effect("cold", null, 10.0, Color("db9130"))
	await process_frame
	var timed: StatusEffectIcon = badges.get("cold") as StatusEffectIcon
	_check(timed != null and str(timed.call("_symbol_for_effect")) == "temperature",
		"ordinary timed effects receive semantic fallback icons")

	for symbol_name: String in ["bleeding", "infection", "fracture", "burn", "temperature"]:
		var symbol: Texture2D = SYMBOL_SCRIPT.new() as Texture2D
		symbol.set("symbol", symbol_name)
		_check(symbol.get_width() == 32 and symbol.get_height() == 32,
			"%s is available to the shared icon system" % symbol_name)

	container.free()
	if _failures == 0:
		print("HUD_STATUS_ICONS_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("HUD_STATUS_ICONS_SMOKE_FAIL: %s" % message)
