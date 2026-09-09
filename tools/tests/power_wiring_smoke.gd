extends SceneTree
## Load graph/build fixtures after autoloads exist, matching game startup order.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: GDScript = load("res://tools/tests/fixtures/power_wiring_fixture.gd")
	if fixture == null or not fixture.can_instantiate():
		quit(1)
		return
	root.add_child(fixture.new())
