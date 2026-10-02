extends CanvasLayer
## SurvivorSelectScreen.gd (Oct 2026)
## New Game only: after the loading screen, the world stays hidden behind
## black while the player picks up to three of six survivors to bring in.
##
## Archetype D (full-screen moment, docs/ui/QUIET_DESIGN_SYSTEM.md): black,
## left-weighted type (NEW GAME eyebrow, title, brass rule, one line), a
## 3×2 grid of Q.tile cards — live 3D portrait, name, age, ONE revealed trait
## and the rest as blank greyed chips — the food/water estimate beneath, and
## Confirm as the one primary action. At three picks the other cards grey out.
##
## Confirm: the chosen survivors are spawned beside the player. In a New Game
## they arrive during preparation to help set the bunker up (Brannon, Oct
## 2026: the NPC system favours tidying purchases until the seal). The column
## fades, "Your chosen survivors will assist you in setting up the bunker."
## fades in quickly
## and out a little slower, then the black lifts to reveal the bunker. The
## world is paused for the whole screen so day one starts on reveal.
##
## Data/arithmetic: SurvivorDraft.gd. Portraits: SurvivorPortrait.gd.

signal finished

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const DRAFT: GDScript = preload("res://scripts/ui/new_game/SurvivorDraft.gd")
const PORTRAIT: GDScript = preload("res://scripts/ui/new_game/SurvivorPortrait.gd")
const NPC_SCENE: String = "res://scenes/npc/NPC.tscn"

const LAYER: int = 1001
const MESSAGE: String = "Your chosen survivors will assist you in setting up the bunker."
## Motion (seconds). The message fades in quickly and out a little slower.
const BLACK_IN: float = 0.35
const MESSAGE_IN: float = 0.45
const MESSAGE_HOLD: float = 1.7
const MESSAGE_OUT: float = 0.6
const REVEAL: float = 1.1

## Set by the creator (LoadingScreen) before add_child.
var world: Node = null

var _s: float = 1.0
var _candidates: Array[Dictionary] = []
var _picked: Array[int] = []
var _not_mandatory: bool = false
var _leaving: bool = false
var _intro_done: bool = false

var _black: ColorRect
var _content: Control
var _column: VBoxContainer
var _title: Label
var _rule: ColorRect
var _counter: Label
var _grid: GridContainer
var _cards: Array[Button] = []
var _estimate: Label
var _confirm: Button
var _footer: HBoxContainer
var _message: Label


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true   ## day one starts when the bunker is revealed
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_candidates = DRAFT.roll()
	_not_mandatory = randf() < DRAFT.NOT_MANDATORY_CHANCE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	_play_intro()


## Freed without Confirm (quitting, tests): never leave the game paused.
func _exit_tree() -> void:
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


# ── Build ────────────────────────────────────────────────────────────────────

func _build() -> void:
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   ## nothing reaches the world
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	C.apply_theme(_content)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 0)
	_content.add_child(_column)
	_column.add_child(Q.eyebrow("New game"))
	_title = Q.label("Choose survivors", 40, Q.TEXT)
	_column.add_child(_title)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 22.0
	_column.add_child(rule_holder)
	_rule = ColorRect.new()
	_rule.color = Color(Q.HEADING, 0.85)
	_rule.position = Vector2(2.0, 10.0)
	_rule.size = Vector2(56.0, 1.0)
	rule_holder.add_child(_rule)
	_column.add_child(Q.label("Select up to three.", 15, Q.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 30.0
	_column.add_child(gap)
	_counter = Q.label("", 14, Q.MUTED)
	_counter.name = "Counter"
	_column.add_child(_counter)

	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.columns = 3
	_content.add_child(_grid)
	for i: int in _candidates.size():
		_cards.append(_make_card(i, _candidates[i]))

	_estimate = Q.label("", 15, Q.MUTED)
	_estimate.name = "Estimate"
	_estimate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_estimate)

	_confirm = Button.new()
	_confirm.name = "Confirm"
	_confirm.text = "Confirm"
	Q.primary_action(_confirm)
	_confirm.pressed.connect(_on_confirm)
	_content.add_child(_confirm)

	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.add_theme_constant_override("separation", 22)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_footer)
	C.key_hint(_footer, "ENTER", "Select", "ENTER", "A")

	_message = Q.label(MESSAGE, 22, Q.TEXT)
	_message.name = "Message"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.modulate.a = 0.0
	C.apply_theme(_message)   ## Iosevka, like the rest of the screen
	add_child(_message)
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var nav: Node = NAV_SCRIPT.new()
	nav.set("ui_root", _content)
	nav.set("close_on_cancel", false)
	add_child(nav)


func _make_card(index: int, candidate: Dictionary) -> Button:
	var card := Button.new()
	card.name = "Survivor%d" % index
	card.toggle_mode = true
	card.clip_contents = true   ## a rare third chip row never spills out
	Q.tile(card)
	_grid.add_child(card)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var portrait: SubViewportContainer = PORTRAIT.new()
	portrait.name = "Portrait"
	portrait.call("setup", String(candidate["gender"]))
	box.add_child(portrait)

	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	box.add_child(name_row)
	var name_label: Label = Q.label(String(candidate["name"]), 20, Q.MUTED)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var picked_label: Label = Q.label("Selected", 12, Q.ACCENT)
	picked_label.name = "Picked"
	picked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	picked_label.modulate.a = 0.0   ## reserves its space so nothing shifts
	name_row.add_child(picked_label)

	var age: Label = Q.label("Age %d" % int(candidate["age"]), 13, Q.MUTED)
	age.name = "Age"
	box.add_child(age)

	var traits := HFlowContainer.new()
	traits.name = "Traits"
	traits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	traits.add_theme_constant_override("h_separation", 6)
	traits.add_theme_constant_override("v_separation", 6)
	box.add_child(traits)
	var words: Array = candidate["words"]
	for w: int in words.size():
		traits.add_child(_trait_chip(String(words[w]) if w == int(candidate["revealed"]) else "", w))

	for child: Node in card.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.toggled.connect(_on_card_toggled.bind(index))
	card.focus_entered.connect(_refresh)
	card.focus_exited.connect(_refresh)
	card.mouse_entered.connect(func() -> void:
		if not _controller_active() and not card.disabled and not _leaving:
			card.grab_focus())
	return card


## Revealed trait: the word on a faint chip. Hidden trait: the same chip,
## greyed and blank — present, but not known yet.
func _trait_chip(word: String, salt: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Trait" if word != "" else "HiddenTrait"
	chip.set_meta("hidden", word == "")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Q.TEXT, 0.07 if word != "" else 0.035)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 3.0
	chip.add_theme_stylebox_override("panel", style)
	if word != "":
		chip.add_child(Q.label(word, 13, Q.MUTED))
	else:
		var blank := Control.new()
		blank.name = "Blank"
		blank.set_meta("width", 38.0 + float((salt * 13) % 30))
		chip.add_child(blank)
	return chip


# ── Layout ───────────────────────────────────────────────────────────────────

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_s = clampf(minf(vp.y / 1080.0, vp.x / 1920.0 * 1.15), 0.66, 1.4)
	var s: float = _s
	var left: float = vp.x * 0.085
	var card_size := Vector2(262.0, 344.0) * s
	var gap: float = 18.0 * s
	_grid.add_theme_constant_override("h_separation", int(gap))
	_grid.add_theme_constant_override("v_separation", int(gap))
	for card: Button in _cards:
		card.custom_minimum_size = card_size
		var box := card.get_node("Box") as VBoxContainer
		box.offset_left = 10.0 * s
		box.offset_top = 10.0 * s
		box.offset_right = -12.0 * s
		box.offset_bottom = -12.0 * s
		## The text block keeps its 12 px floors at small sizes, so the
		## portrait takes whatever height is left after it (name, age, and
		## two rows of trait chips).
		var name_px: float = maxf(12.0, 20.0 * s)
		var small_px: float = maxf(12.0, 13.0 * s)
		var chip_row: float = small_px * 1.3 + 5.0 + 6.0
		var text_block: float = name_px * 1.35 + small_px * 1.35 + chip_row * 2.0 + 4.0 * 3.0
		(card.get_node("Box/Portrait") as Control).custom_minimum_size.y = \
			maxf(60.0, card_size.y - 22.0 * s - text_block)
		_font(card.get_node("Box/NameRow/Name"), 20)
		_font(card.get_node("Box/NameRow/Picked"), 12)
		_font(card.get_node("Box/Age"), 13)
		for chip: Node in card.get_node("Box/Traits").get_children():
			var inner: Node = chip.get_child(0) if chip.get_child_count() > 0 else null
			if inner is Label:
				_font(inner, 13)
			elif inner is Control:
				(inner as Control).custom_minimum_size = Vector2(float(inner.get_meta("width", 48.0)) * s,
					maxf(12.0, 13.0 * s) * 1.3)   ## same height as a revealed chip
	var grid_size := Vector2(card_size.x * 3.0 + gap * 2.0, card_size.y * 2.0 + gap)
	var below: float = 24.0 * s + 46.0 * s + 18.0 * s + 40.0 * s
	## Centre the grid in the space right of the text column.
	var column_right: float = left + 380.0 * s
	var grid_x: float = maxf(column_right + 40.0 * s,
		column_right + (vp.x - column_right - grid_size.x) * 0.5)
	var grid_y: float = maxf(24.0 * s, (vp.y - grid_size.y - below) * 0.5)
	_grid.position = Vector2(grid_x, grid_y)
	_grid.size = grid_size

	_font(_title, 40)
	_column.position = Vector2(left, grid_y + 4.0 * s)
	_column.size = Vector2(minf(360.0 * s, grid_x - left - 30.0 * s), 0.0)
	for label: Node in _column.get_children():
		if label is Label and label != _title:
			_font(label, 15 if label != _counter else 14)
	(_column.get_child(0) as Label).add_theme_font_size_override("font_size", maxi(12, int(12.0 * s)))
	if not UIMotion.reduced() and _rule.size.x > 0.0:
		_rule.size.x = 56.0 * s

	_font(_estimate, 15)
	_estimate.position = Vector2(grid_x, grid_y + grid_size.y + 24.0 * s)
	_estimate.size = Vector2(grid_size.x, 46.0 * s)
	_confirm.add_theme_font_size_override("font_size", maxi(12, int(16.0 * s)))
	_confirm.custom_minimum_size = Vector2(170.0 * s, 40.0 * s)
	_confirm.size = _confirm.custom_minimum_size
	_confirm.position = Vector2(grid_x + grid_size.x - _confirm.size.x,
		_estimate.position.y + 46.0 * s + 18.0 * s)
	_footer.position = Vector2(left, vp.y - 72.0 * s)
	_font(_message, 22)


func _font(node: Node, size: int) -> void:
	(node as Control).add_theme_font_size_override("font_size", maxi(12, int(round(size * _s))))


# ── State ────────────────────────────────────────────────────────────────────

func _on_card_toggled(pressed: bool, index: int) -> void:
	if _leaving:
		_cards[index].set_pressed_no_signal(_picked.has(index))
		return
	if pressed and not _picked.has(index):
		if _picked.size() >= DRAFT.MAX_PICKS:
			_cards[index].set_pressed_no_signal(false)
			return
		_picked.append(index)
	elif not pressed:
		_picked.erase(index)
	_refresh()


func _refresh() -> void:
	var full: bool = _picked.size() >= DRAFT.MAX_PICKS
	for i: int in _cards.size():
		var card: Button = _cards[i]
		var picked: bool = _picked.has(i)
		card.set_pressed_no_signal(picked)
		card.disabled = full and not picked
		var focused: bool = card.has_focus()
		(card.get_node("Box/NameRow/Name") as Label).add_theme_color_override("font_color",
			Q.TEXT if picked or focused else Q.MUTED)
		_fade(card.get_node("Box/NameRow/Picked") as CanvasItem, 1.0 if picked else 0.0, 0.16)
		if _intro_done:
			_fade(card, 0.32 if card.disabled else 1.0, 0.22)
		card.get_node("Box/Portrait").call("set_live", picked or (focused and not card.disabled))
	_counter.text = "%d of %d selected" % [_picked.size(), DRAFT.MAX_PICKS]
	_estimate.text = DRAFT.estimate_text(_picked.size() + 1, _not_mandatory)


func _fade(item: CanvasItem, alpha: float, seconds: float) -> void:
	if is_equal_approx(item.modulate.a, alpha):
		return
	var t := item.create_tween()
	t.tween_property(item, "modulate:a", alpha, UIMotion.duration(seconds))


# ── Motion ───────────────────────────────────────────────────────────────────

func _play_intro() -> void:
	var first: Button = _cards[0] if not _cards.is_empty() else _confirm
	if UIMotion.reduced():
		_black.modulate.a = 1.0
		_rule.size.x = 56.0 * _s
		_intro_done = true
		first.grab_focus()
		return
	_black.modulate.a = 0.0
	_content.modulate.a = 1.0
	_column.modulate.a = 0.0
	_rule.size.x = 0.0
	for card: Button in _cards:
		card.modulate.a = 0.0
	_estimate.modulate.a = 0.0
	_confirm.modulate.a = 0.0
	_footer.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_black, "modulate:a", 1.0, BLACK_IN)
	t.tween_property(_column, "modulate:a", 1.0, 0.6).set_delay(0.2)
	t.tween_property(_rule, "size:x", 56.0 * _s, 0.7).set_delay(0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in _cards.size():
		t.tween_property(_cards[i], "modulate:a", 1.0, 0.45).set_delay(0.3 + 0.06 * i)
	t.tween_property(_estimate, "modulate:a", 1.0, 0.5).set_delay(0.75)
	t.tween_property(_confirm, "modulate:a", 1.0, 0.5).set_delay(0.8)
	t.tween_property(_footer, "modulate:a", 1.0, 0.5).set_delay(0.85)
	t.chain().tween_callback(func() -> void:
		_intro_done = true
		_refresh())
	first.grab_focus()


func _on_confirm() -> void:
	if _leaving:
		return
	_leaving = true
	for card: Button in _cards:
		card.focus_mode = Control.FOCUS_NONE
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.release_focus()
	spawn_selected()
	var reduced: bool = UIMotion.reduced()
	var t := create_tween()
	t.tween_property(_content, "modulate:a", 0.0, 0.0 if reduced else 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(_message, "modulate:a", 1.0, 0.0 if reduced else MESSAGE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(MESSAGE_HOLD)   ## readable even with reduced motion
	t.tween_property(_message, "modulate:a", 0.0, 0.0 if reduced else MESSAGE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: get_tree().paused = false)
	t.tween_property(_black, "modulate:a", 0.0, 0.0 if reduced else REVEAL) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())


## Spawns the chosen survivors on the navmesh a couple of metres in front of
## the player, side by side, facing them. Public for the smoke test.
func spawn_selected() -> Array[Node]:
	var spawned: Array[Node] = []
	var scene := load(NPC_SCENE) as PackedScene
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if scene == null or player == null or world == null or not is_instance_valid(world):
		return spawned
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var map: RID = player.get_world_3d().navigation_map
	var count: int = _picked.size()
	for k: int in count:
		var spot: Vector3 = player.global_position + forward * 2.3 \
			+ right * ((float(k) - float(count - 1) * 0.5) * 1.3)
		if map.is_valid():
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, spot)
			if snapped != Vector3.ZERO and snapped.distance_to(spot) < 3.0:
				spot = Vector3(snapped.x, spot.y, snapped.z)
		spot.y = player.global_position.y + 0.3
		var to_player: Vector3 = player.global_position - spot
		var yaw: float = atan2(-to_player.x, -to_player.z)
		var npc: Node3D = scene.instantiate()
		npc.call("apply_save_dict", DRAFT.to_save_dict(_candidates[_picked[k]], spot, yaw))
		world.add_child(npc)
		spawned.append(npc)
	return spawned


func _controller_active() -> bool:
	var input_mode: Node = get_node_or_null(^"/root/InputMode")
	return input_mode != null and bool(input_mode.call("is_controller"))


## Test hooks.
func get_candidates() -> Array[Dictionary]:
	return _candidates


func get_cards() -> Array[Button]:
	return _cards
