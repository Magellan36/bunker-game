extends SceneTree
## Deterministic pressure tests; no GPU allocations or user settings writes.

class TestSettings extends "res://scripts/core/GraphicsSettings.gd":
	var memory_for_test: int = 512 * 1024 * 1024
	var apply_count: int = 0
	var save_count: int = 0

	func _available_graphics_memory() -> int:
		return memory_for_test

	func _apply_all() -> void:
		apply_count += 1

	func _save() -> void:
		save_count += 1

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var settings := TestSettings.new()
	var rejections: Array[String] = []
	settings.graphics_change_rejected.connect(func(reason: String) -> void: rejections.append(reason))
	_check(not settings.apply_preset(settings.Preset.HIGH), "High must be rejected under memory pressure")
	_check(settings.current_preset == settings.Preset.MEDIUM and not settings.sdfgi_enabled,
		"Rejected preset must not mutate graphics state")
	_check(settings.apply_count == 0 and settings.save_count == 0,
		"Rejected preset must not allocate graphics or persist settings")
	_check(rejections.size() == 1 and rejections[0].contains("system memory"),
		"Rejection must provide a user-visible reason")
	settings.set_setting("sdfgi_enabled", true)
	settings.set_setting("shadow_quality", 4096)
	_check(not settings.sdfgi_enabled and settings.shadow_quality == 2048,
		"Individual expensive settings must also be guarded")
	_check(settings.apply_count == 0 and settings.save_count == 0,
		"Rejected individual settings must not allocate or save")
	_check(settings.apply_preset(settings.Preset.LOW), "Lowering quality must remain available")
	_check(settings.set_setting_live("render_scale", 0.75), "Lowering render scale must remain available")
	_check(settings.set_setting_live("camera_fov", 55.0), "Camera comfort settings must remain available")
	settings.memory_for_test = settings.GRAPHICS_MEMORY_HEADROOM
	_check(settings.apply_preset(settings.Preset.HIGH), "Sufficient headroom must allow High")
	_check(settings.sdfgi_enabled and settings.current_preset == settings.Preset.HIGH,
		"Accepted presets must still apply their requested settings")
	settings.memory_for_test = 0
	_check(settings.apply_preset(settings.Preset.HIGH), "Reapplying unchanged settings must remain available")
	_check(settings.apply_preset(settings.Preset.MEDIUM), "High to Medium must work under pressure")
	settings.memory_for_test = -1
	_check(settings.apply_preset(settings.Preset.ULTRA), "Unknown memory must not lock out presets")
	settings.free()
	# Exercise the real panel's rejection signal without enabling GPU effects.
	var live_settings: Node = root.get_node("GraphicsSettings")
	var panel: CanvasLayer = load("res://scripts/ui/menus/GraphicsSettingsPanel.gd").new()
	root.add_child(panel)
	await process_frame
	var preset_option: OptionButton = panel.get("_preset_option")
	preset_option.select(2)
	live_settings.graphics_change_rejected.emit("Memory guard UI test")
	await process_frame
	_check(preset_option.selected == live_settings.current_preset,
		"Rejected dropdown selection must return to the actual preset")
	var history: Array = root.get_node("NotificationManager").get_history()
	_check(not history.is_empty() and history.back().get("text", "") == "Memory guard UI test",
		"Rejection must appear in the notification system")
	panel.queue_free()
	await process_frame
	if failures == 0:
		print("GRAPHICS_MEMORY_GUARD_SMOKE_OK")
	quit(0 if failures == 0 else 1)
