extends Control
## MainMenuScreen.gd (Sep 2026)
## Presentation and navigation for the main menu: a minimal, text-only column
## in the left third over the live surface backdrop. Emits `action_requested`
## for anything that leaves this screen; MainMenu.gd performs the hand-off.
##
## Views (Home / Load / Credits) swap inside the same column with a short
## slide-and-fade, and one FocusRail glides between whatever is
## focused. Mouse hover moves focus, so keyboard, mouse and controller always
## agree on the current item. Every animation honours UIMotion.reduced().
##
## No artwork: type, rules and gradients are all engine-drawn. The wordmark
## is plain text in the project font; swap in a licensed logo when one exists.

signal action_requested(action: StringName, slot: int)

enum View { HOME, LOAD, CREDITS }

const ITEM_SCRIPT: GDScript = preload("res://scripts/ui/main_menu/MainMenuItem.gd")
const SELECTOR_SCRIPT: GDScript = preload("res://scripts/ui/common/FocusRail.gd")
const CREDITS_SCRIPT: GDScript = preload("res://scripts/ui/main_menu/MainMenuCredits.gd")
const FEED_SHADER: Shader = preload("res://assets/shaders/surface_feed_grain.gdshader")
const FONT_BOLD: FontFile = preload("res://assets/fonts/IosevkaCharon-Bold.ttf")
const FONT_MEDIUM: FontFile = preload("res://assets/fonts/IosevkaCharon-Medium.ttf")
const FONT_REGULAR: FontFile = preload("res://assets/fonts/IosevkaCharon-Regular.ttf")
const QUIT_CONFIRM_SECONDS: float = 3.0
const SCRIM_COLOR: Color = Color(0.043, 0.055, 0.055)
## Wordmark letter-spacing as a fraction of its font size (final state).
const WORDMARK_TRACKING: float = 0.15
## The intro starts this many times wider and settles to 1.
const WORDMARK_INTRO_TRACKING: float = 2.6

@export_group("Layout")
## Left edge of the menu column, as a fraction of screen width.
@export_range(0.0, 0.5, 0.005) var column_left_fraction: float = 0.085
## Column width at 1080p (scales with resolution).
@export var column_width: float = 600.0
## Largest wordmark size at 1080p; it shrinks to fit the column width.
@export var wordmark_max_size: float = 108.0
## Top of the wordmark, as a fraction of screen height.
@export_range(0.0, 0.6, 0.01) var title_top_fraction: float = 0.2
@export_group("Brand")
@export var wordmark: String = "BUNKER GAME"
## Optional line under the wordmark. Deliberately empty: brand copy should be
## written by a person, not generated.
@export var tagline: String = ""
@export_group("Surface feed")
@export var show_feed_readout: bool = true
@export var feed_label: String = "SURFACE FEED  ·  CAM 02"
@export var film_grain: float = 0.05
@export_group("Sound")
@export var move_sound: AudioStream
@export var confirm_sound: AudioStream
@export var back_sound: AudioStream
@export var ui_bus: StringName = &"Master"

var _s: float = 1.0
var _view: int = View.HOME
var _views: Dictionary = {}
var _view_focus: Dictionary = {}
var _busy: bool = false
var _intro_running: bool = false
var _intro_tween: Tween
var _view_tween: Tween
var _dim_tween: Tween
var _quiet_focus: bool = false
var _quit_armed_until: float = -1.0
var _clock: float = 0.0
var _feed_timer: float = 0.0
var _gust: float = 0.0
var _flash: float = 0.0
var _continue_slot: int = 0

var _feed_fx: ColorRect
var _scrim: TextureRect
var _bottom_scrim: TextureRect
var _selector: Control
var _column: VBoxContainer
var _wordmark_label: Label
var _wordmark_font: FontVariation
var _wordmark_holder: Control
var _wordmark_size: int = 108
var _rule_holder: Control
var _rule: ColorRect
var _tagline_label: Label
var _brand_gap: Control
var _view_host: Control
var _footer: VBoxContainer
var _version_label: Label
var _feed_box: VBoxContainer
var _feed_title: Label
var _feed_line: Label
var _rec_dot: Label
var _audio: AudioStreamPlayer

var _continue_item: Button
var _new_game_item: Button
var _load_item: Button
var _settings_item: Button
var _credits_item: Button
var _quit_item: Button
var _slot_items: Array[Button] = []
var _load_back: Button
var _credits_back: Button
var _credits: ScrollContainer
var _home_list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	refresh_saves()
	get_viewport().size_changed.connect(_layout)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_layout()
	_hide_for_intro()


# ── Public API (MainMenu.gd) ─────────────────────────────────────────────────

func play_intro() -> void:
	_hide_for_intro()
	_intro_running = true
	if UIMotion.reduced():
		_finish_intro()
		return
	var t := create_tween().set_parallel(true)
	_intro_tween = t
	t.tween_property(_wordmark_label, "modulate:a", 1.0, 1.4).set_delay(0.15)
	t.tween_method(_set_tracking, WORDMARK_INTRO_TRACKING, 1.0, 2.0).set_delay(0.15) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_rule, "size:x", 56.0 * _s, 0.8).set_delay(1.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_tagline_label, "modulate:a", 1.0, 0.8).set_delay(1.3)
	var items := _visible_items(_home_list)
	for i: int in range(items.size()):
		var item: Control = items[i]
		var at := 1.25 + float(i) * 0.07
		t.tween_property(item, "modulate:a", 1.0, 0.45).set_delay(at)
		t.tween_property(item, "position:x", 0.0, 0.65).from(-22.0 * _s).set_delay(at) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_footer, "modulate:a", 1.0, 0.7).set_delay(1.9)
	t.tween_property(_feed_box, "modulate:a", 1.0, 0.7).set_delay(2.1)
	t.tween_callback(_focus_default).set_delay(1.25)
	t.chain().tween_callback(_finish_intro)


func skip_intro() -> void:
	if not _intro_running:
		return
	if is_instance_valid(_intro_tween):
		_intro_tween.custom_step(60.0)
	_finish_intro()


func is_intro_running() -> bool:
	return _intro_running


## Leaving the menu: lock input and let the column fall away.
func play_outro(seconds: float) -> void:
	_busy = true
	_set_items_enabled(false)
	var t := create_tween().set_parallel(true)
	var items := _visible_items(_views[_view] as Control)
	for i: int in range(items.size()):
		var item: Control = items[i]
		t.tween_property(item, "modulate:a", 0.0, UIMotion.duration(seconds * 0.45)) \
			.set_delay(UIMotion.duration(float(i) * 0.035))
	t.tween_property(_column, "modulate:a", 0.0, UIMotion.duration(seconds * 0.7)) \
		.set_delay(UIMotion.duration(seconds * 0.15))
	t.tween_property(_footer, "modulate:a", 0.0, UIMotion.duration(seconds * 0.4))
	t.tween_property(_feed_box, "modulate:a", 0.0, UIMotion.duration(seconds * 0.4))


## An overlay (Settings) opened or closed above the menu.
func set_overlay_active(active: bool) -> void:
	if is_instance_valid(_dim_tween):
		_dim_tween.kill()
	_dim_tween = create_tween().set_parallel(true)
	var alpha := 0.0 if active else 1.0
	_dim_tween.tween_property(_column, "modulate:a", alpha, UIMotion.duration(0.18))
	_dim_tween.tween_property(_footer, "modulate:a", alpha, UIMotion.duration(0.18))
	_set_items_enabled(not active)
	if not active:
		_quiet_focus = true
		_settings_item.grab_focus()
		_quiet_focus = false


## Lightning brightness from the backdrop, 0..1+.
func set_flash(amount: float) -> void:
	_flash = amount


## Wind gust from the backdrop, 0..1.
func set_gust(amount: float) -> void:
	_gust = amount


func refresh_saves() -> void:
	var newest := ""
	_continue_slot = 0
	for i: int in range(_slot_items.size()):
		var slot := i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		var item: Button = _slot_items[i]
		if info.get("exists", false):
			item.call("set_caption", _describe_slot(info))
			item.disabled = false
			var stamp := str(info.get("timestamp", ""))
			if _continue_slot == 0 or stamp > newest:
				newest = stamp
				_continue_slot = slot
		else:
			item.call("set_caption", "Empty")
			item.disabled = true
	_continue_item.visible = _continue_slot > 0
	if _continue_slot > 0:
		var latest: Dictionary = SaveManager.get_slot_info(_continue_slot)
		_continue_item.call("set_caption", "Slot %d  ·  %s" % [_continue_slot, _describe_slot(latest)])
	_load_item.disabled = _continue_slot == 0
	_link_focus(_home_list)
	_link_focus(_views[View.LOAD] as Control)


# ── Build ────────────────────────────────────────────────────────────────────

func _build() -> void:
	_feed_fx = ColorRect.new()
	_feed_fx.name = "SurfaceFeedFx"
	_feed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fx := ShaderMaterial.new()
	fx.shader = FEED_SHADER
	fx.set_shader_parameter("grain_amount", film_grain)
	fx.set_shader_parameter("animate", not UIMotion.reduced())
	_feed_fx.material = fx
	add_child(_feed_fx)
	_feed_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_scrim = _gradient_rect("LeftScrim", PackedFloat32Array([0.0, 0.3, 0.64]),
		[Color(SCRIM_COLOR, 0.9), Color(SCRIM_COLOR, 0.64), Color(SCRIM_COLOR, 0.0)], false)
	_bottom_scrim = _gradient_rect("BottomScrim", PackedFloat32Array([0.0, 1.0]),
		[Color(SCRIM_COLOR, 0.0), Color(SCRIM_COLOR, 0.6)], true)

	_selector = SELECTOR_SCRIPT.new()
	_selector.name = "Selector"
	add_child(_selector)
	_selector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_wordmark_font = FontVariation.new()
	_wordmark_font.base_font = FONT_BOLD
	_wordmark_label = _label(wordmark, _wordmark_font, BunkerDesign.IVORY)
	_wordmark_label.name = "Wordmark"
	# A plain holder keeps the wide intro tracking from resizing the column.
	_wordmark_holder = Control.new()
	_wordmark_holder.name = "WordmarkHolder"
	_wordmark_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_wordmark_holder)
	_wordmark_holder.add_child(_wordmark_label)

	_rule_holder = Control.new()
	_rule_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_rule_holder)
	_rule = ColorRect.new()
	_rule.color = BunkerDesign.BRASS
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule_holder.add_child(_rule)

	_tagline_label = _label(tagline, FONT_REGULAR, BunkerDesign.MUTED)
	_tagline_label.visible = not tagline.is_empty()
	_column.add_child(_tagline_label)

	_brand_gap = Control.new()
	_brand_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_brand_gap)

	_view_host = Control.new()
	_view_host.name = "Views"
	_view_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_view_host)

	_build_home()
	_build_load()
	_build_credits()
	for key: int in _views:
		(_views[key] as Control).visible = key == View.HOME

	_build_footer()
	_build_feed()

	_audio = AudioStreamPlayer.new()
	_audio.bus = ui_bus
	_audio.max_polyphony = 4
	add_child(_audio)


func _build_home() -> void:
	_home_list = _new_view(View.HOME, "")
	_continue_item = _item(_home_list, "Continue", func() -> void:
		_emit(&"continue", _continue_slot))
	_new_game_item = _item(_home_list, "New Game", func() -> void: _emit(&"new_game"))
	_load_item = _item(_home_list, "Load Game", func() -> void: _show_view(View.LOAD))
	_settings_item = _item(_home_list, "Settings", func() -> void: _emit(&"settings", 0, false))
	_credits_item = _item(_home_list, "Credits", func() -> void: _show_view(View.CREDITS))
	_quit_item = _item(_home_list, "Quit", _on_quit_pressed)


func _build_load() -> void:
	var view := _new_view(View.LOAD, "LOAD GAME")
	for slot: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var item := _item(view, "Slot %d" % slot, func() -> void: _emit(&"load_slot", slot))
		_slot_items.append(item)
	view.add_child(_spacer(10.0))
	_load_back = _item(view, "Back", _go_home)


func _build_credits() -> void:
	var view := _new_view(View.CREDITS, "CREDITS")
	_credits = CREDITS_SCRIPT.new()
	_credits.name = "CreditsScroll"
	_credits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(_credits)
	view.add_child(_spacer(10.0))
	_credits_back = _item(view, "Back", _go_home)


func _build_footer() -> void:
	_footer = VBoxContainer.new()
	_footer.name = "Footer"
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_theme_constant_override("separation", 10)
	add_child(_footer)
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", 24)
	_footer.add_child(hints)
	BunkerUIComponents.key_hint(hints, "ENTER", "Select", "ENTER", "A")
	BunkerUIComponents.key_hint(hints, "ESC", "Back", "ESC", "B")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	_version_label = _label("v%s" % version if not version.is_empty() else "Development build",
		FONT_REGULAR, BunkerDesign.MUTED)
	_version_label.modulate.a = 0.6
	_footer.add_child(_version_label)


func _build_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.name = "SurfaceFeedReadout"
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.alignment = BoxContainer.ALIGNMENT_END
	_feed_box.visible = show_feed_readout
	add_child(_feed_box)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.add_child(top)
	_rec_dot = _label("●", FONT_REGULAR, BunkerDesign.RED)
	top.add_child(_rec_dot)
	_feed_title = _label(feed_label, FONT_MEDIUM, BunkerDesign.MUTED)
	top.add_child(_feed_title)
	_feed_line = _label("", FONT_REGULAR, BunkerDesign.MUTED)
	_feed_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed_line.modulate.a = 0.75
	_feed_box.add_child(_feed_line)


func _new_view(key: int, eyebrow: String) -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "View%d" % key
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_theme_constant_override("separation", 0)
	_view_host.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not eyebrow.is_empty():
		var label := _label(eyebrow, FONT_MEDIUM, BunkerDesign.BRASS.lightened(0.3))
		label.name = "Eyebrow"
		view.add_child(label)
		view.add_child(_spacer(12.0))
	_views[key] = view
	return view


func _item(parent: Container, title: String, callback: Callable) -> Button:
	var item: Button = ITEM_SCRIPT.new()
	item.call("setup", title)
	item.pressed.connect(func() -> void:
		if not _busy and not _intro_running:
			callback.call())
	parent.add_child(item)
	return item


func _label(text: String, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.y = height
	spacer.set_meta(&"base_height", height)
	return spacer


func _gradient_rect(node_name: String, offsets: PackedFloat32Array, colors: Array,
		vertical: bool) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1 if vertical else 512
	texture.height = 256 if vertical else 1
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0.0, 1.0) if vertical else Vector2(1.0, 0.0)
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


# ── Layout ───────────────────────────────────────────────────────────────────

func _layout() -> void:
	var viewport := get_viewport_rect().size
	_s = clampf(minf(viewport.y / 1080.0, viewport.x / 1920.0 * 1.15), 0.66, 1.4)
	var left := clampf(viewport.x * column_left_fraction, 48.0 * _s, 420.0 * _s)
	var width := column_width * _s
	var top := viewport.y * title_top_fraction

	_scrim.position = Vector2.ZERO
	_scrim.size = Vector2(maxf(left + width * 2.2, viewport.x * 0.55), viewport.y)
	_bottom_scrim.size = Vector2(viewport.x, viewport.y * 0.24)
	_bottom_scrim.position = Vector2(0.0, viewport.y - _bottom_scrim.size.y)

	_column.position = Vector2(left, top)
	_column.size = Vector2(width, viewport.y - top - 132.0 * _s)
	_fit_wordmark(width)
	if not _intro_running:
		_set_tracking(1.0)
	_rule_holder.custom_minimum_size.y = 2.0 * _s + 18.0 * _s
	_rule.position = Vector2(4.0 * _s, 6.0 * _s)
	_rule.size = Vector2(_rule.size.x if _intro_running else 56.0 * _s, 2.0 * _s)
	_tagline_label.add_theme_font_size_override("font_size", roundi(19.0 * _s))
	_brand_gap.custom_minimum_size.y = 68.0 * _s

	for view: Control in _views.values():
		_scale_tree(view)
	_credits.set("ui_scale", _s)
	_credits.call("rebuild")
	_selector.set("ui_scale", _s)
	_selector.call("snap")

	_footer.position = Vector2(left, viewport.y - 84.0 * _s)
	_version_label.add_theme_font_size_override("font_size", maxi(11, roundi(12.0 * _s)))
	var margin := 40.0 * _s
	_feed_title.add_theme_font_size_override("font_size", maxi(11, roundi(12.0 * _s)))
	_rec_dot.add_theme_font_size_override("font_size", maxi(9, roundi(10.0 * _s)))
	_feed_line.add_theme_font_size_override("font_size", maxi(11, roundi(12.0 * _s)))
	_feed_box.reset_size()
	var feed_size := _feed_box.get_combined_minimum_size()
	_feed_box.size = Vector2(maxf(feed_size.x, 320.0 * _s), feed_size.y)
	_feed_box.position = Vector2(viewport.x - margin - _feed_box.size.x,
		viewport.y - margin - _feed_box.size.y)


func _scale_tree(node: Node) -> void:
	for child: Node in node.get_children():
		if child.has_method("apply_ui_scale"):
			child.call("apply_ui_scale", _s)
		elif child.has_meta(&"base_height"):
			(child as Control).custom_minimum_size.y = float(child.get_meta(&"base_height")) * _s
		elif child is Label:
			(child as Label).add_theme_font_size_override("font_size", maxi(12, roundi(13.0 * _s)))
			_set_label_tracking(child as Label, 3.0 * _s)


## `amount` is a multiple of the final tracking (1 = settled).
func _set_tracking(amount: float) -> void:
	if _wordmark_font != null:
		_wordmark_font.spacing_glyph = roundi(_wordmark_size * WORDMARK_TRACKING * amount)


## Largest size (up to wordmark_max_size) whose settled width fits the column,
## so any title length works at any resolution.
func _fit_wordmark(max_width: float) -> void:
	var font_size := roundi(wordmark_max_size * _s)
	var floor_size := roundi(36.0 * _s)
	while font_size > floor_size:
		_wordmark_font.spacing_glyph = roundi(font_size * WORDMARK_TRACKING)
		var width := _wordmark_font.get_string_size(wordmark, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x
		if width <= max_width:
			break
		font_size -= 2
	_wordmark_size = font_size
	_wordmark_label.add_theme_font_size_override("font_size", font_size)
	_wordmark_holder.custom_minimum_size.y = _wordmark_font.get_height(font_size)


func _set_label_tracking(label: Label, spacing: float) -> void:
	var font := label.get_theme_font("font")
	var variation := font as FontVariation
	if variation == null:
		variation = FontVariation.new()
		variation.base_font = font
		label.add_theme_font_override("font", variation)
	variation.spacing_glyph = roundi(spacing)


# ── Intro helpers ────────────────────────────────────────────────────────────

func _hide_for_intro() -> void:
	_wordmark_label.modulate.a = 0.0
	_rule.size.x = 0.0
	_tagline_label.modulate.a = 0.0
	for item: Control in _visible_items(_home_list):
		item.modulate.a = 0.0
	_footer.modulate.a = 0.0
	_feed_box.modulate.a = 0.0


func _finish_intro() -> void:
	_intro_running = false
	_wordmark_label.modulate.a = 1.0
	_set_tracking(1.0)
	_rule.size.x = 56.0 * _s
	_tagline_label.modulate.a = 1.0
	for item: Control in _visible_items(_home_list):
		item.modulate.a = 1.0
		item.position.x = 0.0
	_footer.modulate.a = 1.0
	_feed_box.modulate.a = 1.0
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _home_list.is_ancestor_of(focused):
		_focus_default()


func _focus_default() -> void:
	_quiet_focus = true
	var target: Button = _continue_item if _continue_item.visible else _new_game_item
	target.grab_focus()
	_selector.call("snap")
	_quiet_focus = false


# ── Navigation ───────────────────────────────────────────────────────────────

func _show_view(next: int, forward: bool = true) -> void:
	if next == _view or _busy:
		return
	_disarm_quit()
	var old: Control = _views[_view]
	var incoming: Control = _views[next]
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and old.is_ancestor_of(focused):
		_view_focus[_view] = focused
	_view = next
	_play(confirm_sound if forward else back_sound)
	if next == View.CREDITS:
		_credits.call("reset")
	if is_instance_valid(_view_tween):
		_view_tween.kill()
	var shift := 26.0 * _s * (1.0 if forward else -1.0)
	for view: Control in _views.values():
		if view != old and view != incoming:
			view.visible = false
	incoming.visible = true
	incoming.modulate.a = 0.0
	_focus_in(next)
	if UIMotion.reduced():
		old.visible = false
		old.position.x = 0.0
		incoming.modulate.a = 1.0
		incoming.position.x = 0.0
		return
	_view_tween = create_tween().set_parallel(true)
	_view_tween.tween_property(old, "modulate:a", 0.0, 0.12)
	_view_tween.tween_property(old, "position:x", -shift, 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_view_tween.tween_property(incoming, "modulate:a", 1.0, 0.24).set_delay(0.1)
	_view_tween.tween_property(incoming, "position:x", 0.0, 0.34).from(shift).set_delay(0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_view_tween.chain().tween_callback(func() -> void:
		old.visible = false
		old.position.x = 0.0)


func _focus_in(view_key: int) -> void:
	_quiet_focus = true
	var remembered: Variant = _view_focus.get(view_key)
	if remembered is Button and is_instance_valid(remembered) and not (remembered as Button).disabled:
		(remembered as Button).grab_focus()
	elif view_key == View.LOAD:
		var target: Button = _load_back
		for item: Button in _slot_items:
			if not item.disabled:
				target = item
				break
		target.grab_focus()
	elif view_key == View.CREDITS:
		_credits_back.grab_focus()
	else:
		_load_item.grab_focus()
	_quiet_focus = false


func _go_home() -> void:
	_show_view(View.HOME, false)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _intro_running:
		return
	if event.is_action_pressed("ui_cancel"):
		if _view != View.HOME:
			_go_home()
		elif get_viewport().gui_get_focus_owner() != _quit_item:
			_quit_item.grab_focus()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Credits: up/down scroll the text (Back is the only focusable item there).
	# Handled here because GUI focus navigation runs before _unhandled_input.
	if not _intro_running and not _busy and _view == View.CREDITS \
			and (event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true)):
		_credits.call("nudge", 90.0 * _s * (-1.0 if event.is_action("ui_up") else 1.0))
		get_viewport().set_input_as_handled()
		return
	# Any deliberate input during the opening skips straight to the menu.
	if not _intro_running:
		return
	var deliberate: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if deliberate:
		skip_intro()
		get_viewport().set_input_as_handled()


func _on_focus_changed(control: Control) -> void:
	if control == null or not is_ancestor_of(control):
		return
	_selector.call("set_target", control)
	if control != _quit_item:
		_disarm_quit()
	if not _quiet_focus and not _intro_running and not _busy:
		_play(move_sound)


func _on_quit_pressed() -> void:
	if _clock <= _quit_armed_until:
		_emit(&"quit")
		return
	_quit_armed_until = _clock + QUIT_CONFIRM_SECONDS
	_quit_item.call("set_title", "Press again to quit")
	_quit_item.set("accent", BunkerDesign.RED)
	_quit_item.call("set_title_color", BunkerDesign.RED.lightened(0.25))
	_play(confirm_sound)


func _disarm_quit() -> void:
	if _quit_armed_until < 0.0:
		return
	_quit_armed_until = -1.0
	_quit_item.call("set_title", "Quit")
	_quit_item.set("accent", BunkerDesign.BLUE)
	_quit_item.call("set_title_color", BunkerDesign.IVORY)


func _emit(action: StringName, slot: int = 0, locks: bool = true) -> void:
	if _busy:
		return
	_play(confirm_sound)
	if locks:
		_busy = true
	action_requested.emit(action, slot)


## Unlocks after an action that did not leave the menu (e.g. a failed load).
func release() -> void:
	_busy = false
	_set_items_enabled(true)
	_column.modulate.a = 1.0
	_footer.modulate.a = 1.0
	_feed_box.modulate.a = 1.0
	for view: Control in _views.values():
		for item: Control in _visible_items(view):
			item.modulate.a = 1.0
	_focus_in(_view)


# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_clock += delta
	if _quit_armed_until >= 0.0 and _clock > _quit_armed_until:
		_disarm_quit()
	# The wordmark catches a little of each lightning flash.
	var f := clampf(_flash, 0.0, 1.0)
	_wordmark_label.self_modulate = Color(1.0 + f * 0.18, 1.0 + f * 0.22, 1.0 + f * 0.3)
	_rec_dot.modulate.a = 1.0 if UIMotion.reduced() else (1.0 if fmod(_clock, 1.6) < 0.9 else 0.2)
	_feed_timer -= delta
	if _feed_timer <= 0.0 and _feed_box.visible:
		_feed_timer = 0.25
		var wind_kmh := roundi(22.0 + _gust * 41.0)
		_feed_line.text = "WIND %d KM/H   ·   %s" % [wind_kmh,
			Time.get_time_string_from_system()]


# ── Helpers ──────────────────────────────────────────────────────────────────

func _visible_items(root: Control) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in root.get_children():
		if child is Button and (child as Button).visible:
			found.append(child as Control)
	return found


func _link_focus(root: Control) -> void:
	var focusable: Array[Button] = []
	for child: Node in root.get_children():
		if child is Button:
			var button := child as Button
			button.focus_mode = Control.FOCUS_NONE if button.disabled or not button.visible \
				else Control.FOCUS_ALL
			if button.focus_mode == Control.FOCUS_ALL:
				focusable.append(button)
	for i: int in range(focusable.size()):
		var button := focusable[i]
		var up := focusable[(i - 1 + focusable.size()) % focusable.size()]
		var down := focusable[(i + 1) % focusable.size()]
		button.focus_neighbor_top = button.get_path_to(up)
		button.focus_neighbor_bottom = button.get_path_to(down)
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


func _set_items_enabled(enabled: bool) -> void:
	for view: Control in _views.values():
		for child: Node in view.get_children():
			if child is Button:
				(child as Button).mouse_filter = Control.MOUSE_FILTER_STOP if enabled \
					else Control.MOUSE_FILTER_IGNORE
	if enabled:
		_link_focus(_home_list)
		_link_focus(_views[View.LOAD] as Control)
		_link_focus(_views[View.CREDITS] as Control)
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()
		for view: Control in _views.values():
			for child: Node in view.get_children():
				if child is Button:
					(child as Button).focus_mode = Control.FOCUS_NONE


func _play(stream: AudioStream) -> void:
	if stream == null or _audio == null:
		return
	_audio.stream = stream
	_audio.play()


static func _describe_slot(info: Dictionary) -> String:
	var day: Variant = info.get("day", "?")
	var parts: PackedStringArray = ["Day %s" % (str(int(day)) if day is float or day is int else str(day))]
	var time_display := str(info.get("time_display", ""))
	if not time_display.is_empty() and time_display != "?":
		parts.append(time_display)
	var ago := _relative_time(str(info.get("timestamp", "")))
	if not ago.is_empty():
		parts.append(ago)
	return "  ·  ".join(parts)


## Save timestamps are local wall-clock strings; compare against local now.
static func _relative_time(stamp: String) -> String:
	if stamp.length() < 19:
		return ""
	var then := Time.get_unix_time_from_datetime_string(stamp.replace(" ", "T"))
	var now := Time.get_unix_time_from_datetime_string(
		Time.get_datetime_string_from_system(false, false))
	var seconds := int(now - then)
	if seconds < 0:
		return ""
	if seconds < 90:
		return "just now"
	if seconds < 3600:
		return "%d minutes ago" % (seconds / 60)
	if seconds < 7200:
		return "1 hour ago"
	if seconds < 86400:
		return "%d hours ago" % (seconds / 3600)
	if seconds < 172800:
		return "yesterday"
	if seconds < 86400 * 14:
		return "%d days ago" % (seconds / 86400)
	return stamp.substr(0, 10)
