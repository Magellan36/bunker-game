extends SceneTree
## Headless presentation-resource smoke for the loading screen. Run with:
## godot --headless --path . --script res://tools/tests/loading_screen_ui_smoke.gd

const LOADING_SCRIPT: GDScript = preload("res://scripts/ui/loading/LoadingScreen.gd")
const BACKDROP_SCRIPT: GDScript = preload("res://scripts/ui/loading/LoadingBackdropArt.gd")
const INDICATOR_SCRIPT: GDScript = preload("res://scripts/ui/loading/LoadingIndicator.gd")
const SYMBOL_SCRIPT: GDScript = preload("res://scripts/ui/common/BunkerSymbolTexture.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(LOADING_SCRIPT.can_instantiate(), "loading lifecycle script instantiates")
	_check(BACKDROP_SCRIPT.can_instantiate(), "procedural backdrop script instantiates")
	_check(INDICATOR_SCRIPT.can_instantiate(), "indeterminate indicator script instantiates")

	var backdrop: Control = BACKDROP_SCRIPT.new() as Control
	var indicator: Control = INDICATOR_SCRIPT.new() as Control
	root.add_child(backdrop)
	root.add_child(indicator)
	await process_frame
	_check(indicator.custom_minimum_size.x >= 650.0,
		"indicator preserves the approved long, slender proportion")
	_check(indicator.has_method("set_failed"), "indicator supports a visible failure state")

	for symbol_name: String in ["shelter", "tip"]:
		var symbol: Texture2D = SYMBOL_SCRIPT.new() as Texture2D
		symbol.set("symbol", symbol_name)
		_check(symbol.get_width() == 32 and symbol.get_height() == 32,
			"%s symbol is available to the shared UI icon system" % symbol_name)

	backdrop.free()
	indicator.free()
	if _failures == 0:
		print("LOADING_SCREEN_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("LOADING_SCREEN_UI_SMOKE_FAIL: %s" % message)
