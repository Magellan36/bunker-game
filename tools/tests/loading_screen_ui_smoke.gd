extends SceneTree
## Headless presentation-resource smoke for the loading screen. Run with:
## godot --headless --path . --script res://tools/tests/loading_screen_ui_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	var loading_script: GDScript = load("res://scripts/ui/loading/LoadingScreen.gd") as GDScript
	var backdrop_script: GDScript = load("res://scripts/ui/loading/LoadingBackdropArt.gd") as GDScript
	var indicator_script: GDScript = load("res://scripts/ui/loading/LoadingIndicator.gd") as GDScript
	var symbol_script: GDScript = load("res://scripts/ui/common/BunkerSymbolTexture.gd") as GDScript
	_check(loading_script.can_instantiate(), "loading lifecycle script instantiates")
	_check(backdrop_script.can_instantiate(), "procedural backdrop script instantiates")
	_check(indicator_script.can_instantiate(), "indeterminate indicator script instantiates")

	var backdrop: Control = backdrop_script.new() as Control
	var indicator: Control = indicator_script.new() as Control
	root.add_child(backdrop)
	root.add_child(indicator)
	await process_frame
	_check(indicator.custom_minimum_size.x >= 650.0,
		"indicator preserves the approved long, slender proportion")
	_check(indicator.has_method("set_failed"), "indicator supports a visible failure state")

	for symbol_name: String in ["shelter", "tip"]:
		var symbol: Texture2D = symbol_script.new() as Texture2D
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
