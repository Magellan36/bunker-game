extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: GDScript = load("res://tools/tests/fixtures/bunker_door_fixture.gd")
	if fixture == null or not fixture.can_instantiate():
		quit(1)
		return
	root.add_child(fixture.new())
