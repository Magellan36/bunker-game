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
var _viewports: Array[SubViewport] = []
var _vp_textures: Array[ViewportTexture] = []
var _charge_watched: Array[Node] = []
var _charge_callbacks: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	custom_minimum_size = Vector2(BAR_WIDTH, SLOT_SIZE + DRAWER_HEIGHT + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font()
	_build_viewports()
	set_process(true)


func _build_viewports() -> void:
	for _i: int in SLOT_COUNT:
		## Render above display resolution for clean small silhouettes, while
		## keeping UPDATE_ONCE and the prebuilt four-viewport lifecycle.
		var viewport: SubViewport = ItemPreviewKit.build_viewport(self, 96, 1.14)
		PreviewPresentation.configure(viewport)
		_viewports.append(viewport)
		_vp_textures.append(viewport.get_texture())


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
	if slot_index < 0 or slot_index >= _viewports.size():
		return
	if not is_instance_valid(item):
		PreviewPresentation.set_item(_viewports[slot_index], null)
	else:
		PreviewPresentation.set_item(_viewports[slot_index], item)


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
	var lift: float = _ease_out(_slot_lift[index]) * 3.0
	var position: Vector2 = Vector2(float(index) * (SLOT_SIZE + SLOT_GAP), SLOT_Y - lift)
	var rect: Rect2 = Rect2(position, Vector2(SLOT_SIZE, SLOT_SIZE))
	var selected: bool = index == _selected_slot

	if selected:
		var glow: Color = BLUE
		glow.a = 0.14 * _slot_lift[index]
		UIKit.draw_rounded_rect(self, rect.grow(3.0), Color.TRANSPARENT, glow, 3.0, SLOT_RADIUS + 2.0)

	UIKit.draw_rounded_rect(self, rect, BG, BLUE if selected else BORDER, 2.0 if selected else 1.0, SLOT_RADIUS)
	var inner_rect: Rect2 = rect.grow(-4.0)
	UIKit.draw_rounded_rect(self, inner_rect, SURFACE, Color(BRASS.r, BRASS.g, BRASS.b, 0.20), 1.0, SLOT_RADIUS - 2.0)

	if is_instance_valid(item) and index < _vp_textures.size() and _vp_textures[index] != null:
		var preview_rect: Rect2 = Rect2(rect.position + Vector2(6.0, 7.0), Vector2(60.0, 60.0))
		draw_texture_rect(_vp_textures[index], preview_rect, false)
	else:
		_draw_empty_slot(rect)

	_draw_slot_number(rect, index + 1, selected)
	if is_instance_valid(item):
		_draw_item_meter(rect, item)


func _draw_slot_number(rect: Rect2, number: int, selected: bool) -> void:
	var key_rect: Rect2 = Rect2(rect.position + Vector2(5.0, 5.0), Vector2(15.0, 15.0))
	var key_bg: Color = Color("101514e8")
	UIKit.draw_rounded_rect(self, key_rect, key_bg, BLUE.darkened(0.28) if selected else BORDER, 1.0, 4.0)
	var value: String = str(number)
	var width: float = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(_font, Vector2(key_rect.get_center().x - width * 0.5, key_rect.position.y + 11.0),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, BLUE if selected else MUTED)


func _draw_empty_slot(rect: Rect2) -> void:
	var center: Vector2 = rect.get_center() + Vector2(0.0, 2.0)
	for i: int in 12:
		var start_angle: float = -PI * 0.5 + TAU * float(i) / 12.0
		var end_angle: float = start_angle + TAU / 24.0
		draw_arc(center, 13.0, start_angle, end_angle, 3, Color(BRASS.r, BRASS.g, BRASS.b, 0.28), 1.0, true)
	draw_circle(center, 1.5, Color(BRASS.r, BRASS.g, BRASS.b, 0.30))


func _draw_item_meter(rect: Rect2, item: Node) -> void:
	var state: Dictionary = _item_hud_state(item)
	match String(state.get("kind", "none")):
		"liquid":
			_draw_liquid_gauge(rect, state)
		"battery":
			_draw_battery_meter(rect, state)
		"charges":
			_draw_charge_pips(rect, state)


func _draw_liquid_gauge(rect: Rect2, state: Dictionary) -> void:
	var center: Vector2 = rect.position + Vector2(SLOT_SIZE - 17.0, 17.0)
	var fraction: float = clampf(float(state.get("fraction", 0.0)), 0.0, 1.0)
	var quality: float = clampf(float(state.get("quality", 0.0)), 0.0, 100.0)
	draw_circle(center, 12.0, Color("101514ed"))
	draw_arc(center, 9.0, -PI * 0.5, PI * 1.5, 32, EMPTY, 2.5, true)
	if fraction > 0.0:
		draw_arc(center, 9.0, -PI * 0.5, -PI * 0.5 + TAU * fraction,
			maxi(4, int(32.0 * fraction)), WATER_BLUE, 2.5, true)
	_draw_drop(center, _quality_color(quality) if fraction > 0.0 else EMPTY)


func _draw_drop(center: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -5.0), center + Vector2(4.0, 1.0),
		center + Vector2(3.0, 4.0), center + Vector2(0.0, 5.0),
		center + Vector2(-3.0, 4.0), center + Vector2(-4.0, 1.0),
	])
	draw_colored_polygon(points, color)


func _draw_battery_meter(rect: Rect2, state: Dictionary) -> void:
	var fraction: float = clampf(float(state.get("fraction", 0.0)), 0.0, 1.0)
	var lit_bars: int = ceili(fraction * 4.0) if fraction > 0.0 else 0
	var origin: Vector2 = rect.position + Vector2(SLOT_SIZE - 33.0, 10.0)
	var shell: Rect2 = Rect2(origin, Vector2(24.0, 12.0))
	UIKit.draw_rounded_rect(self, shell, Color("101514ed"), BORDER, 1.0, 3.0)
	draw_rect(Rect2(origin + Vector2(24.0, 3.0), Vector2(2.0, 6.0)), BORDER, true)
	for i: int in 4:
		var bar: Rect2 = Rect2(origin + Vector2(3.0 + float(i) * 5.0, 3.0), Vector2(3.0, 6.0))
		var color: Color = EMPTY
		if i < lit_bars:
			if lit_bars == 1:
				var pulse: float = 0.72 + sin(_low_battery_phase) * 0.20
				color = Color(RED.r, RED.g, RED.b, pulse)
			elif lit_bars == 2:
				color = AMBER
			else:
				color = GREEN
		draw_rect(bar, color, true)


func _draw_charge_pips(rect: Rect2, state: Dictionary) -> void:
	var current: int = maxi(0, int(state.get("current", 0)))
	var maximum: int = maxi(1, int(state.get("maximum", 1)))
	var visible_pips: int = mini(maximum, 4)
	var start_x: float = rect.end.x - 10.0 - float(visible_pips - 1) * 9.0
	for i: int in visible_pips:
		var center: Vector2 = Vector2(start_x + float(i) * 9.0, rect.position.y + 14.0)
		draw_circle(center, 3.2, GREEN if i < current else EMPTY)
		draw_arc(center, 3.2, 0.0, TAU, 16, Color("0b100f"), 1.0, true)


func _draw_identity_drawer(slot: int, item: Node) -> void:
	var alpha: float = _drawer_alpha()
	if alpha <= 0.0:
		return
	var slide: float = (1.0 - alpha) * -5.0
	var slot_center_x: float = float(slot) * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE * 0.5
	var x: float = float(slot) * (SLOT_SIZE + SLOT_GAP)
	var y: float = SLOT_Y + SLOT_SIZE - 1.0 + slide
	var drawer_rect: Rect2 = Rect2(Vector2(x, y), Vector2(DRAWER_WIDTH, DRAWER_HEIGHT))
	var bg: Color = Color(BG.r, BG.g, BG.b, BG.a * alpha)
	var edge: Color = Color(BORDER.r, BORDER.g, BORDER.b, alpha)
	UIKit.draw_rounded_rect(self, drawer_rect, bg, edge, 1.0, 7.0)
	var notch: PackedVector2Array = PackedVector2Array([
		Vector2(slot_center_x - 6.0, y), Vector2(slot_center_x, y + 5.0),
		Vector2(slot_center_x + 6.0, y),
	])
	draw_colored_polygon(notch, Color(BLUE.r, BLUE.g, BLUE.b, alpha))

	var name: String = _item_display_name(item).to_upper()
	var name_color: Color = Color(IVORY.r, IVORY.g, IVORY.b, alpha)
	var font_size: int = _drawer_font_size(name)
	var name_width: float = _font.get_string_size(
		name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_height: float = _font.get_height(font_size)
	var baseline_y: float = y + (DRAWER_HEIGHT - text_height) * 0.5 \
		+ _font.get_ascent(font_size)
	draw_string(_font,
		Vector2(drawer_rect.get_center().x - name_width * 0.5, baseline_y),
		name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, name_color)


func _drawer_font_size(text: String) -> int:
	var font_size: int = 11
	var available_width: float = DRAWER_WIDTH - 8.0
	while font_size > 8 and _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available_width:
		font_size -= 1
	return font_size


# ─── Item presentation contract ───────────────────────────────────────────────
func _item_hud_state(item: Node) -> Dictionary:
	if not is_instance_valid(item):
		return {"kind": "none"}
	if item.has_method("get_inventory_hud_state"):
		var result: Variant = item.call("get_inventory_hud_state")
		if result is Dictionary:
			return result as Dictionary
	if item.has_method("get_bottle_badge_info"):
		var bottle: Dictionary = item.call("get_bottle_badge_info") as Dictionary
		return {
			"kind": "liquid",
			"fraction": float(bottle.get("fill_pct", 0.0)),
			"quality": float(bottle.get("quality", 0.0)),
		}
	var charges: Array = _get_charge_info(item)
	if charges.size() == 2:
		return {"kind": "charges", "current": int(charges[0]), "maximum": int(charges[1])}
	return {"kind": "none"}


func _get_charge_info(item: Node) -> Array:
	if item.has_method("get_charge_info"):
		return item.call("get_charge_info") as Array
	if "_bites_left" in item and "TOTAL_BITES" in item:
		return [int(item.get("_bites_left")), int(item.get("TOTAL_BITES"))]
	if "_charges" in item and "_max_charges" in item:
		return [int(item.get("_charges")), int(item.get("_max_charges"))]
	if "_charges_left" in item and "TOTAL_CHARGES" in item:
		return [int(item.get("_charges_left")), int(item.get("TOTAL_CHARGES"))]
	return []


func _item_display_name(item: Node) -> String:
	if item.has_method("get_display_name"):
		return String(item.call("get_display_name"))
	return _prettify_name(item.name)


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


func _prettify_name(raw: String) -> String:
	var source: String = raw.strip_edges()
	while source.length() > 0 and source[-1].is_valid_int():
		source = source.substr(0, source.length() - 1)
	var result: String = ""
	for i: int in source.length():
		if i > 0 and source[i] == source[i].to_upper() and source[i] != " ":
			result += " "
		result += source[i]
	return result.strip_edges()
