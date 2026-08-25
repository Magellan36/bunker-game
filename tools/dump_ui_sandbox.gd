extends SceneTree
## dump_ui_sandbox.gd
## Reads a UI sandbox scene and prints every Control's layout data as
## structured, greppable lines (prefix "[UI]") so an agent can translate
## it into the real scene/script without opening the editor.
##
## Usage:
##   Godot --headless --path <project> --script tools/dump_ui_sandbox.gd -- <scene_path>
## (scene_path defaults to the Character Creation sandbox if omitted.)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://scenes/ui/character_creation/UISandbox_CharacterCreation.tscn"
	if args.size() > 0:
		path = args[0]
	var ps: PackedScene = load(path)
	if ps == null:
		print("[UI] FAILED load ", path)
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	_dump(inst, "")
	inst.free()
	quit()

func _dump(node: Node, indent: String) -> void:
	var line := "[UI] %s%s <%s>" % [indent, node.name, node.get_class()]
	if node is Control:
		var c := node as Control
		line += " a=%s off=(%s,%s,%s,%s) size=%s min=%s ratio=%s" % [
			c.anchors_preset,
			c.offset_left, c.offset_top, c.offset_right, c.offset_bottom,
			c.size, c.custom_minimum_size, c.size_flags_stretch_ratio]
		if not c.visible:
			line += " [hidden]"
		if c is Button:
			line += " text=\"%s\"" % (c as Button).text
		elif c is Label:
			line += " text=\"%s\"" % (c as Label).text
		elif c is ColorRect:
			line += " color=%s" % (c as ColorRect).color
	print(line)
	for child: Node in node.get_children():
		_dump(child, indent + "  ")