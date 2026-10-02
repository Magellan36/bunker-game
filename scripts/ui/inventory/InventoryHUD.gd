extends Control
## Compact four-slot light-item inventory HUD.
## Gameplay ownership remains in InventoryManager/InteractionSystem; this file
## is presentation only. Heavy objects never enter these slots.

const SLOT_COUNT: int = 4
const SLOT_SIZE: float = 72.0
const SLOT_GAP: float = 8.0
const SLOT_Y: float = 4.0
const SLOT_RADIUS: float = 8.0
const BAR_WIDTH: float = SLOT_SIZE * SLOT_COUNT + SLOT_GAP * (SLOT_COUNT - 1)
const DRAWER_WIDTH: float = SLOT_SIZE
const DRAWER_HEIGHT: float = 24.0
const DRAWER_IN: float = 0.14
const DRAWER_HOLD: float = 1.0
const DRAWER_OUT: float = 0.16
const DRAWER_TOTAL: float = DRAWER_IN + DRAWER_HOLD + DRAWER_OUT

## Sep 2026 quiet pass (plan Pass 3A): flat scrim slots, brass slot number,
## selection = lift + faint wash + ACCENT underline, name revealed as plain
## shadowed text under the slot. No borders, no keycaps, no blue glow.
const SCRIM: Color = Color(0.027, 0.035, 0.035, 0.56)
const WASH: Color = Color(0.949, 0.91, 0.812, 0.07)
const ACCENT: Color = Color("86a9bf")
const HEADING: Color = Color("a8946c")
const SHADOW: Color = Color(0, 0, 0, 0.7)
const BG: Color = Color("111716ed")
const SURFACE: Color = Color("1d2423f2")
const BORDER: Color = Color("66583f")
const IVORY: Color = Color("f2e8cf")
const MUTED: Color = Color("aaa799")
const BRASS: Color = Color("88734e")
const BLUE: Color = Color("66bfff")
const WATER_BLUE: Color = Color("54b9ed")
const GREEN: Color = Color("75d48a")
const AMBER: Color = Color("dda42e")
const RED: Color = Color("df5a52")
const EMPTY: Color = Color("48504d")

## Set by MainWorld after ready.
var inventory: Node = null

var _selected_slot: int = -1
var _slot_lift: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _slot_ids: Array[int] = [-1, -1, -1, -1]
var _snapshot_ready: bool = false
var _drawer_slot: int = -1
var _drawer_age: float = DRAWER_TOTAL
var _low_battery_phase: float = 0.0
## Sep 2026: slot previews are PreviewStudio renders (cached static textures);
## the four per-slot SubViewports are gone.
var _slot_keys: Array[String] = ["", "", "", ""]
var _vp_textures: Array[Texture2D] = [null, null, null, null]
var _charge_watched: Array[Node] = []
var _charge_callbacks: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	custom_minimum_size = Vector2(BAR_WIDTH, SLOT_SIZE + DRAWER_HEIGHT + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   ## 256 px renders drawn at 60 px
	PreviewStudio.preview_ready.connect(_on_preview_ready)
	set_process(true)


func _on_preview_ready(key: String, tex: Texture2D) -> void:
	var hit: bool = false
	for i: int in SLOT_COUNT:
		if _slot_keys[i] == key:
			_vp_textures[i] = tex
			hit = true
	if hit:
		queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw: bool = false
	for i: int in SLOT_COUNT:
		var target: float = 1.0 if i == _selected_slot else 0.0
		var before: float = _slot_lift[i]
		_slot_lift[i] = move_toward(before, target, delta * 9.0)
		needs_redraw = needs_redraw or not is_equal_approx(before, _slot_lift[i])

	if _drawer_slot >= 0:
		_drawer_age += delta
		if _drawer_age >= DRAWER_TOTAL:
			_drawer_slot = -1
		needs_redraw = true

	if _has_low_flashlight():
		_low_battery_phase = fmod(_low_battery_phase + delta * 3.4, TAU)
		needs_redraw = true
	else:
		_low_battery_phase = 0.0

	if needs_redraw:
		queue_redraw()


# ─── Public API ───────────────────────────────────────────────────────────────
func set_selected(slot: int) -> void:
	var next_slot: int = clampi(slot, -1, SLOT_COUNT - 1)
	var changed: bool = next_slot != _selected_slot
	_selected_slot = next_slot
	if changed and _slot_has_item(next_slot):
		_reveal_item(next_slot)
	queue_redraw()


## Rebuilds only the four already-created preview worlds. Newly stored items
## reveal their identity drawer even when the player used G and now holds none.
func refresh_previews() -> void:
	var slots: Array = _slots()
	_disconnect_state_watches()
	for i: int in SLOT_COUNT:
		var item: Node = slots[i] as Node if i < slots.size() and slots[i] is Node else null
		_set_preview(i, item)
		var next_id: int = item.get_instance_id() if is_instance_valid(item) else -1
		if _snapshot_ready and next_id != -1 and next_id != _slot_ids[i]:
			_reveal_item(i)
		_slot_ids[i] = next_id
		_watch_item_state(item)
	_snapshot_ready = true
	queue_redraw()


func _set_preview(slot_index: int, item: Node) -> void:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	var key: String = PreviewStudio.request_item(item) if is_instance_valid(item) else ""
	_slot_keys[slot_index] = key
	_vp_textures[slot_index] = PreviewStudio.texture(key) if not key.is_empty() else null
	queue_redraw()


func _watch_item_state(item: Node) -> void:
	if not is_instance_valid(item) or not item.has_signal("charge_changed"):
		return
	var callback: Callable = _on_item_state_changed.bind(item)
	item.charge_changed.connect(callback)
	_charge_watched.append(item)
	_charge_callbacks[item.get_instance_id()] = callback


func _disconnect_state_watches() -> void:
	for item: Node in _charge_watched:
		if not is_instance_valid(item) or not item.has_signal("charge_changed"):
			continue
		var callback_variant: Variant = _charge_callbacks.get(item.get_instance_id(), Callable())
		var callback: Callable = callback_variant as Callable
		if callback.is_valid() and item.charge_changed.is_connected(callback):
			item.charge_changed.disconnect(callback)
	_charge_watched.clear()
	_charge_callbacks.clear()


func _on_item_state_changed(item: Node) -> void:
	## Food cans and antibiotics swap their mesh after emitting the signal, so
	## wait for that mutation before recapturing the static preview.
	_refresh_item_visual.call_deferred(item)
	queue_redraw()


func _refresh_item_visual(item: Node) -> void:
	if not is_instance_valid(item):
		return
	var slots: Array = _slots()
	for i: int in mini(SLOT_COUNT, slots.size()):
		if slots[i] == item:
			_set_preview(i, item)
			break
	queue_redraw()


func _reveal_item(slot: int) -> void:
	if not _slot_has_item(slot):
		return
	_drawer_slot = slot
	_drawer_age = 0.0
	queue_redraw()


# ─── Drawing ──────────────────────────────────────────────────────────────────
func _draw() -> void:
	var slots: Array = _slots()
	if _drawer_slot >= 0 and _drawer_slot < slots.size() and is_instance_valid(slots[_drawer_slot]):
		_draw_identity_drawer(_drawer_slot, slots[_drawer_slot] as Node)

	for i: int in SLOT_COUNT:
		var item: Node = slots[i] as Node if i < slots.size() and slots[i] is Node else null
		_draw_slot(i, item)


func _draw_slot(index: int, item: Node) -> void:
	var lift_t: float = _ease_out(_slot_lift[index])
	var lift: float = lift_t * 3.0
	var position: Vector2 = Vector2(float(index) * (SLOT_SIZE + SLOT_GAP), SLOT_Y - lift)
	var rect: Rect2 = Rect2(position, Vector2(SLOT_SIZE, SLOT_SIZE))
	var selected: bool = index == _selected_slot

	UIKit.draw_rounded_rect(self, rect, SCRIM, Color.TRANSPARENT, 0.0, SLOT_RADIUS)
	if lift_t > 0.001:
		UIKit.draw_rounded_rect(self, rect, Color(WASH, WASH.a * lift_t), Color.TRANSPARENT, 0.0, SLOT_RADIUS)
		var underline_w: float = (SLOT_SIZE - 20.0) * lift_t
		draw_rect(Rect2(Vector2(rect.get_center().x - underline_w * 0.5, rect.end.y - 3.0),
			Vector2(underline_w, 2.0)), Color(ACCENT, lift_t), true)

	if is_instance_valid(item) and index < _vp_textures.size() and _vp_textures[index] != null:
		var preview_rect: Rect2 = Rect2(rect.position + Vector2(6.0, 6.0), Vector2(60.0, 60.0))
		draw_texture_rect(_vp_textures[index], preview_rect, false)   ## mipmapped studio render
	elif not is_instance_valid(item):
		_draw_empty_slot(rect)   ## the dashed ring marks an EMPTY slot only

	_draw_slot_number(rect, index + 1, selected)
	if is_instance_valid(item):
		_draw_item_meter(rect, item)


func _draw_slot_number(rect: Rect2, number: int, selected: bool) -> void:
	var value: String = str(number)
	var at: Vector2 = rect.position + Vector2(8.0, 16.0)
	draw_string(_font, at + Vector2(0.0, 1.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SHADOW)
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, IVORY if selected else HEADING)


func _draw_empty_slot(rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	for i: int in 12:
		var start_angle: float = -PI * 0.5 + TAU * float(i) / 12.0
		var end_angle: float = start_angle + TAU / 36.0
		draw_arc(center, 12.0, start_angle, end_angle, 3, Color(HEADING, 0.3), 1.2, true)


func _draw_item_meter(rect: Rect2, item: Node) -> void:
	var state: Dictionary = _item_hud_state(item)
	match String(state.get("kind", "none")):
		"liquid":
			ItemStateMeter._draw_liquid_gauge(self, rect, state)
		"battery":
			ItemStateMeter._draw_battery_meter(self, rect, state, _low_battery_phase)
		"charges":
			ItemStateMeter._draw_charge_pips(self, rect, state)


## Name reveal: plain shadowed text centred under the slot, allowed to run
## wider than the slot (it is transient), clamped inside the bar.
func _draw_identity_drawer(slot: int, item: Node) -> void:
	var alpha: float = _drawer_alpha()
	if alpha <= 0.0:
		return
	var slide: float = (1.0 - alpha) * -4.0
	var name: String = _item_display_name(item)
	var font_size: int = 14
	var width: float = _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var slot_center_x: float = float(slot) * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE * 0.5
	var x: float = clampf(slot_center_x - width * 0.5, 0.0, maxf(0.0, BAR_WIDTH - width))
	var baseline_y: float = SLOT_Y + SLOT_SIZE + 6.0 + slide + _font.get_ascent(font_size)
	draw_string(_font, Vector2(x, baseline_y + 1.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, Color(SHADOW, SHADOW.a * alpha))
	draw_string(_font, Vector2(x, baseline_y), name, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, Color(IVORY, alpha))


# ─── Item presentation contract ───────────────────────────────────────────────
func _item_hud_state(item: Node) -> Dictionary:
	return ItemPresentation.hud_state(item)

func _get_charge_info(item: Node) -> Array:
	return ItemPresentation.charge_info(item)


func _item_display_name(item: Node) -> String:
	return ItemPresentation.title(item)


func _quality_color(quality: float) -> Color:
	if quality <= 50.0:
		return RED
	if quality <= 75.0:
		return AMBER
	return GREEN


func _drawer_alpha() -> float:
	if _drawer_age < DRAWER_IN:
		return _ease_out(_drawer_age / DRAWER_IN)
	if _drawer_age < DRAWER_IN + DRAWER_HOLD:
		return 1.0
	return 1.0 - _ease_in((_drawer_age - DRAWER_IN - DRAWER_HOLD) / DRAWER_OUT)


func _ease_out(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped, 3.0)


func _ease_in(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return clamped * clamped


func _slots() -> Array:
	if inventory != null and "slots" in inventory:
		return inventory.get("slots") as Array
	return [null, null, null, null]


func _slot_has_item(slot: int) -> bool:
	if slot < 0:
		return false
	var slots: Array = _slots()
	return slot < slots.size() and is_instance_valid(slots[slot])


func _has_low_flashlight() -> bool:
	for item_variant: Variant in _slots():
		if not item_variant is Node or not is_instance_valid(item_variant):
			continue
		var state: Dictionary = _item_hud_state(item_variant as Node)
		if String(state.get("kind", "")) == "battery":
			var fraction: float = float(state.get("fraction", 0.0))
			if fraction > 0.0 and fraction <= 0.25:
				return true
	return false
