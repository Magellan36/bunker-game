extends SceneTree
## tools/ui_capture/capture_scene.gd — render any scene to PNGs for UI review.
##
##   godot --path . --windowed --script res://tools/ui_capture/capture_scene.gd -- \
##       <res://scene.tscn> <out_prefix> <t1,t2,...> [action@index,...]
##
## Captures at each time (seconds). Actions run just before the capture with
## that index (see _do(): strike, down, load/credits/home, settings, and
## settings-panel probes). Env CAPTURE_VIEWPORT=WxH renders inside a
## SubViewport of that size: use it for 720p/1440p/21:9 checks, because the
## GraphicsSettings autoload forces the saved window mode and ignores
## --resolution. Keep this a dev tool: tools/ is excluded from exports.

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var out_prefix: String = args[1]
	var times: PackedStringArray = args[2].split(",")
	if OS.has_environment("CAPTURE_SIZE"):
		var parts := OS.get_environment("CAPTURE_SIZE").split("x")
		root.mode = Window.MODE_WINDOWED
		root.borderless = false
		root.size = Vector2i(int(parts[0]), int(parts[1]))
		await process_frame
		await process_frame
	var packed := load(scene_path) as PackedScene
	var inst := packed.instantiate()
	var target: Viewport = root
	if OS.has_environment("CAPTURE_VIEWPORT"):
		var parts := OS.get_environment("CAPTURE_VIEWPORT").split("x")
		var sub := SubViewport.new()
		sub.size = Vector2i(int(parts[0]), int(parts[1]))
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sub)
		sub.add_child(inst)
		target = sub
	else:
		root.add_child(inst)
		current_scene = inst
	var elapsed := 0.0
	var index := 0
	for t_text: String in times:
		var t := float(t_text)
		if t > elapsed:
			await create_timer(t - elapsed).timeout
			elapsed = t
		if args.size() > 3:
			for action: String in args[3].split(","):
				var parts := action.split("@")
				if parts.size() == 2 and int(parts[1]) == index:
					await _do(inst, parts[0])
		await process_frame
		await process_frame
		var img := target.get_texture().get_image()
		img.save_png("%s_%02d.png" % [out_prefix, index])
		print("captured ", t, " -> ", "%s_%02d.png" % [out_prefix, index])
		index += 1
	quit()


func _do(inst: Node, action: String) -> void:
	match action:
		"strike":
			var storm := inst.find_child("Storm", true, false)
			if storm != null:
				storm.call("trigger", 1.0)
		"down":
			var ev := InputEventAction.new()
			ev.action = "ui_down"
			ev.pressed = true
			Input.parse_input_event(ev)
		"load", "credits", "home":
			var screen := inst.get_node("Interface/Screen")
			screen.call("_show_view", {"home": 0, "load": 1, "credits": 2}[action], action != "home")
		"confirm", "confirm_safe":
			var dialog: CanvasLayer = (load("res://scripts/ui/common/ConfirmDialogUI.gd") as GDScript).new()
			root.add_child(dialog)
			await process_frame
			if action == "confirm":
				dialog.call("open", "Exit to desktop?", "Any progress since your last save will be lost.",
					"Exit game", "Stay here", "danger")
			else:
				dialog.call("open", "Restart required", "Switch the rendering driver and restart now?",
					"Restart now", "Not now", "warning")
		"toasts":
			var nm: Node = root.get_node("NotificationManager")
			nm.call("notify", 1, 0, "Generator S started")
			nm.call("notify", 1, 1, "Generator S fuel reserve low", -1.0, true, "18% remaining")
			nm.call("notify", 1, 2, "Power grid tripped", -1.0, true, "Reduce load, then restart generators")
		"settings":
			inst.call("_open_settings")
		"focusrow", "jump", "toggle", "cycle", "popup", "preset", "close":
			var panel: Node = inst.find_child("GraphicsSettingsPanel", true, false)
			match action:
				"focusrow": (panel.get("_aa_option") as Control).grab_focus()
				"jump":
					panel.call("_jump_to_section", "effects")
					(panel.get("_vol_fog_check") as Control).grab_focus()
				"toggle":
					var t: CheckButton = panel.get("_vol_fog_check")
					t.button_pressed = not t.button_pressed
				"popup": (panel.get("_aa_option") as OptionButton).show_popup()
				"preset": (panel.get("_preset_buttons")[2] as Button).pressed.emit()
				"close": panel.call("close")
				"cycle":
					var o: OptionButton = panel.get("_aa_option")
					(o.get_meta(&"ui_cycle") as Callable).call(1)
		"female", "randomise":
			var button: Button = inst.get("female_button" if action == "female" else "randomise_button")
			button.grab_focus()
			button.pressed.emit()
		"leave":
			inst.call("_leave", "res://scenes/ui/character_creation/CharacterCreation.tscn")
		_:
			if inst.has_method(action):
				inst.call(action)
