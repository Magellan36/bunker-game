extends SceneTree
## Wall-height tiers (Q / E, LT / RT), the cursor tier indicator, the catalog
## without Half/Quarter entries, and pillar connection-dot picking. Run with:
## godot --headless --path . --script res://tools/tests/build_wall_tier_smoke.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	## Load after autoload registration (BuildModeController references
	## GraphicsSettings, which a command-line SceneTree compiles too early).
	var fixture: GDScript = load("res://tools/tests/fixtures/build_wall_tier_fixture.gd")
	if fixture == null or not fixture.can_instantiate():
		quit(1)
		return
	root.add_child(fixture.new())
