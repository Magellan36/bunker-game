extends CanvasLayer
## Shared storage inspector for every shelving/container family.  World
## objects keep ownership of slots and transfers; this file only presents
## their existing contract, so physical-slot mappings remain authoritative.


const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

const DEFAULTS := {
	"title": "Storage", "slot_count": 6, "grid_cols": 2, "grid_rows": 3,
	"display_order": [], "supports_stacking": false,
	"primary_button_tooltip": "Carry item", "primary_requires_empty_hands": false,
	"closes_on_action": true,
}

var interaction_system: Node
var inventory: Node
var inventory_hud: Node
var is_open := false

var _target: Node3D
var _config := {}
var _root: Control
var _panel: PanelContainer
var _title: Label
var _scroll_viewport: Control
var _scroll: ScrollContainer
var _grid: GridContainer
var _selection_name: Label
var _selection_detail: Label
var _selection_panel: PanelContainer
var _selection_eyebrow: Label
var _state_row: HBoxContainer
var _state_meter: ItemStateMeter
var _footer_hint: Label
var _carry: Button
var _inventory: Button
var _move: Button
var _close: Button
var _cards: Array[Button] = []
var _signatures: Array[String] = []
var _shown_ids: Array[int] = []
var _selected_visual := -1
var _proximity: Node
var _controller_nav: ControllerUINavigation
var _refresh_elapsed := 0.0
var _key_hints: HBoxContainer
var _pad_hints: HBoxContainer
## Move mode (Oct 2026, shelves only): the visual slot whose stack is being
## moved, or -1. _arriving is the card the glide lands on (kept faded until
## the preview gets there).
var _moving_from := -1
var _arriving := -1
var _ghost: TextureRect

func _ready() -> void:
	layer = 60
	_build()
	visible = false
	set_process(false)
	_controller_nav = ControllerUINavigation.new()
	_controller_nav.ui_root = self
	add_child(_controller_nav)
	_proximity = (load("res://scripts/ui/common/UIProximityClose.gd") as GDScript).new()
	_proximity.ui = self
	add_child(_proximity)

## Sep 2026 quiet pass (QUIET_DESIGN_SYSTEM archetype B, storage = 440 px):
## quiet shell, inspector header with a text Close, flat preview tiles, a
## one-line selection readout, one primary action (Add to inventory) beside a
## quiet text action (Carry), input-aware key hints.
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	Q.avoid_toasts(_panel, false)  # never covered by toasts
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	BunkerUIComponents.apply_theme(_panel)
	_panel.add_theme_stylebox_override("panel", Q.shell_box(12))
	_root.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_panel.add_child(BunkerUIComponents.inset(body, 24, 22, 24, 16))
	var header: HBoxContainer = Q.inspector_header("Storage", "", close, 26)
	body.add_child(header)
	_title = header.find_child("Title", true, false) as Label
	_close = header.get_node("Close") as Button
	body.add_child(_rule())
	body.add_child(Q.eyebrow("Contents", 12))
	_scroll_viewport = Control.new()
	_scroll_viewport.name = "StorageViewport"
	_scroll_viewport.custom_minimum_size.y = 144
	_scroll_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_viewport.clip_contents = true
	body.add_child(_scroll_viewport)
	_scroll = ScrollContainer.new()
	_scroll.name = "StorageScroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll_viewport.add_child(_scroll)
	Q.scrollbar(_scroll.get_v_scroll_bar())
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	BunkerUIComponents.scroll_content(_scroll, _grid)
	body.add_child(_rule())
	## Selection readout: plain text, no card. The PanelContainer stays as the
	## stable holder other code/tests address.
	_selection_panel = PanelContainer.new()
	_selection_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(_selection_panel)
	var selected_body := VBoxContainer.new()
	selected_body.add_theme_constant_override("separation", 4)
	_selection_panel.add_child(selected_body)
	_selection_eyebrow = Q.eyebrow("Selected", 12)
	selected_body.add_child(_selection_eyebrow)
	_selection_name = Q.label("", 20, Q.TEXT)
	_selection_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selected_body.add_child(_selection_name)
	_selection_detail = Q.label("", 14, Q.MUTED)
	_selection_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_body.add_child(_selection_detail)
	_state_row = HBoxContainer.new()
	_state_row.add_theme_constant_override("separation", 9)
	selected_body.add_child(_state_row)
	_state_meter = ItemStateMeter.new()
	_state_row.add_child(_state_meter)
	_state_row.hide()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	_carry = Button.new()
	_carry.text = "Carry item"
	Q.nav_button(_carry, 15, 40.0)
	_carry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_carry.pressed.connect(_take_for_carry)
	actions.add_child(_carry)
	## Move: only for targets with slot geometry (Shelving.move_slot).
	_move = Button.new()
	_move.text = "Move"
	Q.nav_button(_move, 15, 40.0)
	_move.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move.custom_minimum_size.x = 84.0
	_move.pressed.connect(_toggle_move)
	actions.add_child(_move)
	_inventory = Button.new()
	_inventory.text = "Add to inventory"
	Q.primary_action(_inventory, 15, 40.0)
	_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory.pressed.connect(_take_for_inventory)
	actions.add_child(_inventory)
	## Footer: input-aware hints. The controller acts on the focused tile
	## directly (A carry, Y inventory), so its hints differ from keyboard.
	_footer_hint = Label.new()   ## retained handle; hidden (hints replace it)
	_footer_hint.visible = false
	body.add_child(_footer_hint)
	_key_hints = HBoxContainer.new()
	_key_hints.alignment = BoxContainer.ALIGNMENT_END
	_key_hints.add_theme_constant_override("separation", 16)
	body.add_child(_key_hints)
	_pad_hints = HBoxContainer.new()
	_pad_hints.alignment = BoxContainer.ALIGNMENT_END
	_pad_hints.add_theme_constant_override("separation", 16)
	body.add_child(_pad_hints)
	_build_hints()

	get_viewport().size_changed.connect(_layout)

## Hints follow the mode: browsing (select/carry/close) or moving
## (place/cancel).
func _build_hints() -> void:
	for row: HBoxContainer in [_key_hints, _pad_hints]:
		for child: Node in row.get_children():
			row.remove_child(child)
			child.queue_free()
	if _moving_from >= 0:
		BunkerUIComponents.key_hint(_key_hints, "ENTER", "Place", "ENTER", "ENTER")
		BunkerUIComponents.key_hint(_key_hints, "ESC", "Cancel", "ESC", "ESC")
		BunkerUIComponents.key_hint(_pad_hints, "A", "Place", "A", "A")
		BunkerUIComponents.key_hint(_pad_hints, "B", "Cancel", "B", "B")
		return
	BunkerUIComponents.key_hint(_key_hints, "ENTER", "Select", "ENTER", "ENTER")
	BunkerUIComponents.key_hint(_key_hints, "ESC", "Close", "ESC", "ESC")
	BunkerUIComponents.key_hint(_pad_hints, "A", "Carry", "A", "A")
	if _move != null and _move.visible:
		BunkerUIComponents.key_hint(_pad_hints, "X", "Move", "X", "X")
	BunkerUIComponents.key_hint(_pad_hints, "Y", "Inventory", "Y", "Y")
	BunkerUIComponents.key_hint(_pad_hints, "B", "Close", "B", "B")

func _rule() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", Q.hairline())
	line.add_theme_constant_override("separation", 2)
	return line

func _layout() -> void:
	if _panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	var rows := ceili(float(int(_config.get("slot_count", 6))) \
		/ maxf(float(int(_config.get("grid_cols", 2))), 1.0))
	var desired := minf(760.0, 340.0 + float(rows) * 152.0)
	## In-world inspector rail: preserve the bunker view and keep the panel at
	## comfortable eye level rather than pinning it to a screen corner.
	UIPanelLayout.fit(_panel, viewport, Vector2(440.0, desired),
		Vector2(24.0, 24.0), 1.0, 0.5)

func _ensure_pool(needed: int) -> void:
	while _cards.size() < needed:
		var index := _cards.size()
		_signatures.append("")
		_shown_ids.append(0)
		var card := BunkerItemCard.new()
		card.pressed.connect(_card_pressed.bind(index))
		card.focus_entered.connect(_card_focused.bind(index))
		_grid.add_child(card)
		_cards.append(card)

func open(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	for required in [&"get_ui_config", &"get_slot_display", &"take_for_carry", &"take_for_inventory"]:
		if not target.has_method(required):
			push_warning("StorageUI: target is missing %s" % required)
			return
	_target = target
	UIPanelLifecycle.prepare_open(self)
	_config = DEFAULTS.duplicate(true)
	_config.merge(target.get_ui_config(), true)
	var slots := maxi(1, int(_config["slot_count"]))
	_ensure_pool(slots)
	_grid.columns = maxi(1, int(_config["grid_cols"]))
	_title.text = str(_config["title"]).replace("_", " ").capitalize()
	var primary_word := str(_config.get("primary_button_tooltip", "Carry"))
	_carry.text = primary_word if "item" in primary_word.to_lower() else primary_word + " item"
	_selected_visual = -1
	_move.visible = target.has_method("move_slot") and target.has_method("can_move_slot")
	_end_move()
	visible = true
	is_open = true
	set_process(true)
	if _proximity != null:
		_proximity.bind(target)
	_refresh(true)
	_layout()
	_layout.call_deferred()
	_scroll.set_deferred("scroll_vertical", 0)
	if InputMode.is_controller():
		_focus_initial_item.call_deferred()
	else:
		_close.call_deferred("grab_focus")
	UIFade.fade_in(_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not is_open:
		return
	is_open = false
	set_process(false)
	if _proximity != null:
		_proximity.unbind()
	_end_move()
	if _ghost != null:
		_end_glide(_ghost)
	_target = null
	_selected_visual = -1
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UIPanelLifecycle.dismiss(self, _panel)

func _process(delta: float) -> void:
	var pad: bool = InputMode.is_controller()
	if _pad_hints.visible != pad:
		_pad_hints.visible = pad
		_key_hints.visible = not pad

	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.1:
		_refresh_elapsed = 0.0
		_refresh(false)

func _data_index(visual: int) -> int:
	var order: Array = _config.get("display_order", [])
	return int(order[visual]) if visual >= 0 and visual < order.size() else visual

func _slot(visual: int) -> Array:
	if _target == null or not is_instance_valid(_target):
		return [null, 0]
	var value: Array = _target.get_slot_display(_data_index(visual))
	return value if value.size() >= 2 else [null, 0]

func _refresh(force: bool) -> void:
	if _target == null or not is_instance_valid(_target):
		close()
		return
	var slots := int(_config["slot_count"])
	for i in _cards.size():
		var card: Button = _cards[i]
		card.visible = i < slots
		if i >= slots:
			continue
		var shown := _slot(i)
		var item: Node = shown[0]
		var count := int(shown[1])
		var sig := ItemPresentation.signature(item, count)
		if force or sig != _signatures[i]:
			var new_id := item.get_instance_id() if item != null and is_instance_valid(item) else 0
			if i == _selected_visual and _shown_ids[i] != 0 and new_id != _shown_ids[i]:
				_selected_visual = -1
			if i == _moving_from and new_id != _shown_ids[i]:
				_end_move()   ## the stack left (a resident took it): nothing to move
			_signatures[i] = sig
			_shown_ids[i] = new_id
			if item != null and is_instance_valid(item):
				## PreviewStudio: cached render, shared spinner on hover/focus.
				card.display(ItemPresentation.title(item), null, count, 1)
				PreviewStudio.bind_card(card, PreviewStudio.request_item(item), card.set_preview)
				card.focus_mode = Control.FOCUS_ALL
			else:
				card.display("Empty", null, 0, 0)
				PreviewStudio.bind_card(card, "", card.set_preview)
				card.focus_mode = Control.FOCUS_NONE
		if i == _selected_visual:
			card.button_pressed = true
		_apply_move_state(i, card)
	_configure_focus_neighbors()
	_refresh_selection()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and focus in _cards and focus.focus_mode == Control.FOCUS_NONE:
		_focus_nearest_occupied.call_deferred()

func _select(index: int) -> void:
	_selected_visual = index
	for i in _cards.size():
		_cards[i].button_pressed = i == index
	_refresh_selection()

func _selection_valid() -> bool:
	if _selected_visual < 0:
		return false
	var shown := _slot(_selected_visual)
	var item: Node = shown[0]
	return item != null and is_instance_valid(item) \
		and item.get_instance_id() == _shown_ids[_selected_visual]

func _refresh_selection() -> void:
	if _moving_from >= 0 and _selection_valid():
		_selection_eyebrow.text = "MOVING"
		_selection_eyebrow.visible = true
		_selection_name.text = ItemPresentation.title(_slot(_moving_from)[0])
		_selection_detail.text = "Choose a slot."
		_state_row.hide()
		_carry.disabled = true
		_inventory.disabled = true
		_move.text = "Cancel"
		_move.disabled = false
		return
	_selection_eyebrow.text = "SELECTED"
	_move.text = "Move"
	if not _selection_valid():
		_move.disabled = true
		_selection_eyebrow.visible = false
		_selection_name.text = ""
		_selection_name.visible = false
		_selection_detail.text = "Select an item to see its actions." if _has_items() else "Nothing stored here yet."
		_state_row.hide()
		_carry.disabled = true
		_inventory.disabled = true
		return
	_selection_eyebrow.visible = true
	_selection_name.visible = true
	var shown := _slot(_selected_visual)
	var item: Node = shown[0]
	_selection_name.text = ItemPresentation.title(item)
	_selection_detail.text = ItemPresentation.detail(item, int(shown[1]))
	_refresh_item_state(item)
	var hands_blocked: bool = bool(_config.get("primary_requires_empty_hands", false)) \
		and interaction_system != null and "held_item" in interaction_system \
		and interaction_system.get("held_item") != null
	_carry.disabled = hands_blocked
	_inventory.disabled = inventory == null \
		or (inventory.has_method("is_full") and inventory.is_full())
	_move.disabled = not _can_move_from(_selected_visual)

func _has_items() -> bool:
	for i: int in mini(int(_config.get("slot_count", 0)), _cards.size()):
		if _cards[i].focus_mode != Control.FOCUS_NONE:
			return true
	return false

func _refresh_item_state(item: Node) -> void:
	_state_meter.state = ItemPresentation.hud_state(item)
	_state_row.visible = String(_state_meter.state.get("kind", "none")) != "none"
	_state_meter.queue_redraw()

func _take_for_carry() -> void:
	if not _selection_valid() or _carry.disabled:
		return
	if _target.take_for_carry(_data_index(_selected_visual), interaction_system):
		if bool(_config.get("closes_on_action", true)):
			close()
		else:
			_refresh(true)

func _take_for_inventory() -> void:
	if not _selection_valid() or _inventory.disabled:
		return
	if _target.take_for_inventory(_data_index(_selected_visual), inventory):
		## Deliberately remain open: players can move several items per session.
		_refresh(true)
		_focus_nearest_occupied()
		if inventory_hud != null and inventory_hud.has_method("refresh_previews"):
			inventory_hud.refresh_previews()

func _focus_nearest_occupied() -> void:
	for offset in range(_cards.size()):
		var i := (_selected_visual + offset) % _cards.size()
		if i < int(_config["slot_count"]) and _cards[i].focus_mode != Control.FOCUS_NONE:
			_select(i)
			_cards[i].grab_focus()
			return
	_selected_visual = -1
	_close.grab_focus()


func _focus_initial_item() -> void:
	for i in int(_config.get("slot_count", 0)):
		if i < _cards.size() and _cards[i].focus_mode != Control.FOCUS_NONE:
			_select(i)
			_cards[i].grab_focus()
			return
	_close.grab_focus()


func _configure_focus_neighbors() -> void:
	## The slot grid can contain non-focusable empty cells. Explicit geometry
	## keeps horizontal D-pad motion in its row instead of letting a nearby
	## lower card win the generic spatial search.
	var count := mini(int(_config.get("slot_count", 0)), _cards.size())
	var columns := maxi(1, int(_config.get("grid_cols", 2)))
	var active: Array[int] = []
	for index in count:
		if _cards[index].visible and _cards[index].focus_mode != Control.FOCUS_NONE:
			active.append(index)
	for index in active:
		var card: Button = _cards[index]
		var row := floori(float(index) / float(columns))
		var column := index % columns
		var left := _find_focus_slot(active, row, column, columns, Vector2i.LEFT)
		var right := _find_focus_slot(active, row, column, columns, Vector2i.RIGHT)
		var up := _find_focus_slot(active, row, column, columns, Vector2i.UP)
		var down := _find_focus_slot(active, row, column, columns, Vector2i.DOWN)
		card.focus_neighbor_left = card.get_path_to(_cards[left]) if left >= 0 else NodePath(".")
		card.focus_neighbor_right = card.get_path_to(_cards[right]) if right >= 0 else (card.get_path_to(_scroll.get_v_scroll_bar()) if _scroll.get_v_scroll_bar().visible else NodePath("."))
		card.focus_neighbor_top = card.get_path_to(_cards[up]) if up >= 0 else card.get_path_to(_close)
		var lower_action: Button = _carry if column < ceili(float(columns) * 0.5) else _inventory
		card.focus_neighbor_bottom = card.get_path_to(_cards[down]) if down >= 0 \
			else card.get_path_to(lower_action)
	var first := active[0] if not active.is_empty() else -1
	var last_left := _last_focus_slot(active, columns, 0)
	var last_right := _last_focus_slot(active, columns, mini(1, columns - 1))
	_close.focus_neighbor_bottom = _close.get_path_to(_cards[first]) if first >= 0 else _close.get_path_to(_carry)
	_carry.focus_neighbor_left = NodePath(".")
	_carry.focus_neighbor_right = _carry.get_path_to(_inventory)
	_carry.focus_neighbor_top = _carry.get_path_to(_cards[last_left]) if last_left >= 0 else _carry.get_path_to(_close)
	_carry.focus_neighbor_bottom = NodePath(".")
	_inventory.focus_neighbor_left = _inventory.get_path_to(_carry)
	_inventory.focus_neighbor_right = NodePath(".")
	_inventory.focus_neighbor_top = _inventory.get_path_to(_cards[last_right]) if last_right >= 0 else _inventory.get_path_to(_close)
	_inventory.focus_neighbor_bottom = NodePath(".")


func _find_focus_slot(active: Array[int], row: int, column: int, columns: int,
		direction: Vector2i) -> int:
	var best := -1
	var best_distance := 1_000_000
	for candidate in active:
		var candidate_row := floori(float(candidate) / float(columns))
		var candidate_column := candidate % columns
		var matches := (direction.x < 0 and candidate_row == row and candidate_column < column) \
			or (direction.x > 0 and candidate_row == row and candidate_column > column) \
			or (direction.y < 0 and candidate_column == column and candidate_row < row) \
			or (direction.y > 0 and candidate_column == column and candidate_row > row)
		if not matches:
			continue
		var distance := absi(candidate_column - column) + absi(candidate_row - row)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _last_focus_slot(active: Array[int], columns: int, preferred_column: int) -> int:
	var best := -1
	for candidate in active:
		if candidate % columns == preferred_column and candidate > best:
			best = candidate
	return best if best >= 0 else (active[-1] if not active.is_empty() else -1)

func _input(event: InputEvent) -> void:
	if not is_open or not event.is_pressed() or event.is_echo():
		return
	## Move mode: the nav's close-on-cancel is off, so Esc/E/B land here and
	## cancel the move instead of closing the panel.
	if _moving_from >= 0 and ((event is InputEventKey and event.keycode in [KEY_ESCAPE, KEY_E]) \
			or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B)):
		_cancel_move()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventJoypadButton):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus in _cards:
		return
	if _moving_from >= 0:
		if event.button_index == JOY_BUTTON_A:
			_card_pressed(_cards.find(focus))
			get_viewport().set_input_as_handled()
		return
	if event.button_index == JOY_BUTTON_X and _move.visible:
		_select(_cards.find(focus))
		_toggle_move()
		get_viewport().set_input_as_handled()
	elif event.button_index == JOY_BUTTON_A:
		_take_for_carry()
		get_viewport().set_input_as_handled()
	elif event.button_index == JOY_BUTTON_Y:
		_take_for_inventory()
		get_viewport().set_input_as_handled()


# ── Move between slots (shelves) ──────────────────────────────────────────

func _card_pressed(index: int) -> void:
	if _moving_from < 0:
		_select(index)
	elif index == _moving_from:
		_cancel_move()
	elif _can_move_to(index):
		_complete_move(index)
	else:
		_cards[index].button_pressed = false

func _card_focused(index: int) -> void:
	if _moving_from < 0:
		_select(index)

func _can_move_to(visual: int) -> bool:
	return _moving_from >= 0 and visual != _moving_from and _target != null \
		and is_instance_valid(_target) and _target.has_method("can_move_slot") \
		and bool(_target.can_move_slot(_data_index(_moving_from), _data_index(visual)))

## True when the stack at `visual` has at least one slot it may go to
## (claimed by a resident, or nowhere free → false).
func _can_move_from(visual: int) -> bool:
	if not _move.visible or visual < 0 or _target == null or not is_instance_valid(_target):
		return false
	for i: int in int(_config.get("slot_count", 0)):
		if i != visual and bool(_target.can_move_slot(_data_index(visual), _data_index(i))):
			return true
	return false

## Browsing: occupied cards focusable, all at full strength. Moving: the
## source and valid targets stay lit and focusable; everything else fades.
func _apply_move_state(i: int, card: Button) -> void:
	if i == _arriving:
		return
	if _moving_from < 0:
		card.modulate.a = 1.0
		card.focus_mode = Control.FOCUS_ALL if _shown_ids[i] != 0 else Control.FOCUS_NONE
		return
	var valid: bool = i == _moving_from or _can_move_to(i)
	card.modulate.a = 1.0 if valid else 0.35
	card.focus_mode = Control.FOCUS_ALL if valid else Control.FOCUS_NONE

func _toggle_move() -> void:
	if _moving_from >= 0:
		_cancel_move()
		return
	if not _selection_valid() or _move.disabled:
		return
	_moving_from = _selected_visual
	_controller_nav.close_on_cancel = false
	_build_hints()
	_refresh(false)
	## Land on the nearest valid slot so Enter/A places straight away.
	for offset: int in range(1, _cards.size()):
		var i: int = (_moving_from + offset) % _cards.size()
		if i < int(_config["slot_count"]) and _can_move_to(i):
			_cards[i].grab_focus()
			return

func _cancel_move() -> void:
	var from := _moving_from
	_end_move()
	if from >= 0 and is_open:
		_refresh(false)
		_select(from)
		_cards[from].grab_focus()

func _end_move() -> void:
	_moving_from = -1
	if _controller_nav != null:
		_controller_nav.close_on_cancel = true
	if _key_hints != null:
		_build_hints()

func _complete_move(to: int) -> void:
	var from := _moving_from
	var texture: Texture2D = (_cards[from] as BunkerItemCard).preview.texture
	var start: Rect2 = (_cards[from] as BunkerItemCard).preview.get_global_rect()
	var end: Rect2 = (_cards[to] as BunkerItemCard).preview.get_global_rect()
	var viewer := get_tree().get_first_node_in_group("player") as Node3D
	_end_move()
	if not bool(_target.move_slot(_data_index(from), _data_index(to), viewer)):
		_refresh(true)
		return
	_selected_visual = to
	_refresh(true)
	_select(to)
	_cards[to].grab_focus()
	_glide(texture, start, end, to)

## The preview lifts off the old card and settles on the new one, which
## fades in under it as it lands.
func _glide(texture: Texture2D, start: Rect2, end: Rect2, to: int) -> void:
	if UIMotion.reduced() or texture == null:
		return
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	if _arriving >= 0 and _arriving < _cards.size():
		_cards[_arriving].modulate.a = 1.0
	_ghost = TextureRect.new()
	_ghost.texture = texture
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.position = start.position
	_ghost.size = start.size
	_root.add_child(_ghost)
	_arriving = to
	var card: Button = _cards[to]
	card.modulate.a = 0.0
	var time: float = UIMotion.duration(0.26)
	var tween := _ghost.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_ghost, "position", end.position, time)
	tween.parallel().tween_property(_ghost, "size", end.size, time)
	tween.tween_property(card, "modulate:a", 1.0, UIMotion.duration(0.12))
	tween.parallel().tween_property(_ghost, "modulate:a", 0.0, UIMotion.duration(0.12))
	tween.tween_callback(_end_glide.bind(_ghost))

func _end_glide(ghost: TextureRect) -> void:
	if is_instance_valid(ghost):
		ghost.queue_free()
	if ghost == _ghost:
		if _arriving >= 0 and _arriving < _cards.size():
			_cards[_arriving].modulate.a = 1.0
		_ghost = null
		_arriving = -1
