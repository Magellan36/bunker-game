extends SceneTree
var failures: int = 0


class ChargeItem:
	extends Node
	var _charges: int = 2
	var _max_charges: int = 4

	func get_display_name() -> String:
		return "  Field Dressing  "

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	# Keep this contract deterministic even if the developer previously enabled
	# the persisted accessibility preference in the same Godot user directory.
	var previous_reduced: bool = UIMotion.reduced()
	UIMotion.set_reduced(false)
	check(UIFormat.integer(1234567) == "1,234,567", "integer grouping is shared")
	check(UIFormat.money(-1234) == "-$1,234", "signed currency is shared")
	check(UIFormat.percent(82.6) == "83%", "percentage rounding is shared")
	check(UIFormat.allocation_tier(1) == "CRITICAL"
		and UIFormat.allocation_tier(3) == "STANDARD"
		and UIFormat.allocation_tier(5) == "LUXURY",
		"allocation tiers are shared and uppercase")
	check(UIFormat.water_quality(82.6) == "Water quality 83%",
		"water-quality wording is shared")
	check(UIFormat.battery(46.2) == "46% battery remaining",
		"battery wording is shared")
	check(UIFormat.uses(2, 4) == "2 / 4 uses remaining",
		"charge wording is shared")
	check(BunkerDesign.CONTROL_HEIGHT == 34.0
		and BunkerDesign.CONTROL_VERTICAL_PADDING == 4.0,
		"desktop control density is shared without changing typography")
	var item: ChargeItem = ChargeItem.new()
	check(ItemPresentation.title(item) == "Field Dressing",
		"item names use the shared precedence and trimming")
	check(ItemPresentation.detail(item) == "2 / 4 uses remaining",
		"item details use shared charge formatting")
	var fallback_item: Node = Node.new()
	fallback_item.name = "WaterBottleItem12"
	check(ItemPresentation.title(fallback_item) == "Water Bottle",
		"fallback item names split words and remove technical suffixes")
	check(ItemPresentation.record_detail({
		"current_fill_mL": 240.0, "stored_water_quality": 82.0,
	}) == "240 mL  •  82% quality", "serialized water details use shared formatting")
	item.free()
	fallback_item.free()
	var surface: Control = Control.new()
	root.add_child(surface)
	var bar: BunkerSmoothProgressBar = BunkerSmoothProgressBar.new()
	surface.add_child(bar)
	bar.set_target_value(10.25)
	bar.set_target_value(10.55)
	for i: int in 120:
		bar._process(1.0 / 60.0)
	check(is_equal_approx(bar.value, 10.55), "fractional meter must converge")
	surface.hide()
	bar.set_target_value(85.5)
	surface.show()
	UIFade.fade_in(surface)
	check(is_equal_approx(bar.value, 85.5), "new host snapshot must snap")
	var callback_state: Array[bool] = [false]
	UIFade.fade_out(surface, 0.05, func() -> void: callback_state[0] = true)
	UIFade.fade_in(surface, 0.01)
	await create_timer(0.10).timeout
	check(not callback_state[0] and is_equal_approx(surface.modulate.a, 1.0), "reopen cancels stale close")
	var owner: CanvasLayer = CanvasLayer.new()
	root.add_child(owner)
	var lifecycle_surface: Control = Control.new()
	owner.add_child(lifecycle_surface)
	var lifecycle_button: Button = Button.new()
	lifecycle_surface.add_child(lifecycle_button)
	var hidden_callback: Array[bool] = [false]
	UIPanelLifecycle.dismiss(
		owner, lifecycle_surface, func() -> void: hidden_callback[0] = true)
	check(owner.get_meta(UIPanelLifecycle.EXITING, false) == true,
		"dismiss marks presentation exiting immediately")
	check(lifecycle_button.focus_mode == Control.FOCUS_NONE,
		"dismiss removes interaction immediately")
	UIPanelLifecycle.prepare_open(owner)
	await create_timer(UIMotion.EXIT + 0.04).timeout
	check(not hidden_callback[0] and owner.visible,
		"lifecycle reopen cancels stale completion")
	check(lifecycle_button.focus_mode == Control.FOCUS_ALL,
		"lifecycle reopen restores interaction")
	UIPanelLifecycle.dismiss(
		owner, lifecycle_surface, func() -> void: hidden_callback[0] = true)
	await create_timer(UIMotion.EXIT + 0.04).timeout
	check(hidden_callback[0] and not owner.visible,
		"lifecycle completion hides after logical close")
	var preview: TextureRect = TextureRect.new()
	surface.add_child(preview)
	var texture: GradientTexture1D = GradientTexture1D.new()
	UIPreviewMotion.swap(preview, null, texture)
	var tween: Variant = preview.get_meta(UIPreviewMotion.TWEEN_META)
	UIPreviewMotion.swap(preview, null, texture)
	check(preview.get_meta(UIPreviewMotion.TWEEN_META) == tween, "no-op preview refresh retains tween")
	var second: GradientTexture1D = GradientTexture1D.new()
	UIPreviewMotion.swap(preview, null, second)
	check(preview.texture == second, "preview reflects latest selection immediately")
	var panel: PanelContainer = PanelContainer.new()
	root.add_child(panel)
	for viewport: Vector2 in [Vector2(1920,1080), Vector2(1280,720), Vector2(2560,1440)]:
		UIPanelLayout.fit(panel, viewport, Vector2(440,760), Vector2(24,24), 1.0)
		check(panel.position.y >= 24 and panel.get_rect().end.y <= viewport.y - 24, "panel vertical bounds")
		check(is_equal_approx(panel.get_rect().end.x, viewport.x - 24), "panel right edge")
	UIMotion.set_reduced(true)
	UIFade.fade_in(surface)
	check(is_equal_approx(surface.modulate.a, 1.0), "reduced motion is immediate")
	bar.set_target_value(40.4)
	bar._process(0.016)
	check(is_equal_approx(bar.value, 40.4), "reduced motion snaps meter")
	UIMotion.set_reduced(previous_reduced)
	print("UI_CONSISTENCY_FOUNDATIONS: %d failures" % failures)
	quit(failures)
