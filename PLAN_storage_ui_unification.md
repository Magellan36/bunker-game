# Plan: Storage UI Unification (Shelf + Basket → Shared `StorageUI`)

**Owner of this plan:** UI Claude instance (HUD/menus/Build Mode/Furniture)
**Scope:** New file `scripts/ui/inventory/StorageUI.gd`; edits to
`scripts/world/furniture/Shelving.gd`, `scripts/world/items/Basket.gd`,
`scripts/world/core/MainWorld.gd`; deletion of `ShelfUI.gd`/`BasketUI.gd`;
documentation updates.

**Confirmed design (per your answers):**
1. One single generic, config-driven `StorageUI.gd` — NOT a base class with
   per-type subclasses. A future storage type needs zero new UI files.
2. Every storage object implements the same 3-method contract:
   `get_slot_display()`, `take_for_carry()`, `take_for_inventory()`.
3. Designed with room for lockable storage, freezers/fridges, lockers, and
   larger shelving units — see §5 for exactly how each of those fits
   without changing `StorageUI.gd` itself.

**One naming note, not a question — just documenting the call I made:**
Basket's primary button was never actually "carry" (it drops the item on
the ground, doesn't hand it to the player). I kept your approved method
name `take_for_carry()` for the contract (renaming what you already signed
off on felt like more friction than it was worth), but its concrete
meaning is now "this storage type's primary retrieval action, whatever
that is" — Shelving's implementation hands the item to the player's hold
point, Basket's drops it on the ground. Documented clearly in the
contract's own header comment so this doesn't confuse anyone later.

**Scope note:** this pass is about code-sharing and future extensibility,
not visual re-theming — `StorageUI.gd` keeps the existing look Shelf/Basket
already agreed on (14px corner radius, its own dark palette), rather than
pulling it onto the `UIKit` domain-stripe system Power/Water/Farming/Pause
use. That's a separate, deferrable decision if you want it later, not
bundled in here.

---

## 1. What's actually being eliminated

`ShelfUI.gd` (477 lines) and `BasketUI.gd` (470 lines) share 17 of 18
functions almost verbatim. The only REAL differences between them were:
grid shape (3×2 vs 4×3), a reversed slot-to-visual-position mapping for
shelves (bottom-to-top data order, top-to-bottom display), row labels
("Top/Middle/Bottom shelf" vs generic "Row N"), stacking (shown via a
count badge) vs not, and which 2 buttons appear (Carry+Inv vs Drop+Inv).
Every one of those is now just a value in a config dictionary the storage
object itself provides — nothing about a specific type is hardcoded in the
UI anymore.

## 2. The contract (add to any future storage object's own script)

```gdscript
func get_ui_config() -> Dictionary
func get_slot_display(slot_idx: int) -> Array   # [item_or_null, count]
func take_for_carry(slot_idx: int, isys: Node) -> bool
func take_for_inventory(slot_idx: int, inv: Node) -> bool
```

`get_ui_config()` keys (every one optional — `StorageUI.gd` falls back to
a sensible default for anything you don't specify):

| Key | Meaning | Shelving | Basket |
|---|---|---|---|
| `title` | Panel header text | `"SHELF CONTENTS"` | `"BASKET CONTENTS"` |
| `slot_count` | Total slots | `6` | `12` |
| `grid_cols` / `grid_rows` | Grid shape | `2` / `3` | `3` / `4` |
| `display_order` | visual position → data slot index (`[]` = identity) | `[4,5,2,3,0,1]` | `[]` |
| `row_labels` | Per-row label text (`[]` = auto "Row N") | `["Top shelf","Middle shelf","Bottom shelf"]` | `[]` |
| `supports_stacking` | Show a `×N` badge when count > 1 | `true` | `false` |
| `primary_button_icon` / `_tooltip` / `_color` | The main action button | `"↑"` / `"Carry"` / green | `"↓"` / `"Drop"` / red |
| `primary_requires_empty_hands` | Block the primary action if the player's hands are full | `true` | `false` |
| `closes_on_action` | Close the menu after a successful action, vs stay open and refresh just that slot | `true` | `false` |

## 3. How the pool handles different capacities

`StorageUI.gd` keeps ONE dynamic pool of slot visuals (viewport, camera,
light, buttons, labels) that only ever GROWS, never shrinks or rebuilds —
if you open a 6-slot shelf then a 12-slot basket, the pool grows to 12;
opening the shelf again afterward just hides slots 6-11, nothing gets
destroyed or recreated. A future 24-slot "larger shelving unit" simply
grows the same pool further the first time it's opened. This is what makes
adding a new storage type free on the UI side — there's no fixed slot
count anywhere in this file.

## 4. `MainWorld.gd`/`InteractionSystem.gd` integration — kept minimal

`InteractionSystem.gd` is Player-thread-owned (not this thread's scope per
the project's ownership split), so this plan deliberately makes **zero
changes to it**. Both of its existing properties, `shelf_ui` and
`basket_ui`, get assigned the SAME new `StorageUI` instance in
`MainWorld.gd`. Every existing call in `InteractionSystem.gd`
(`shelf_ui.is_open`, `basket_ui.is_open`, `basket_ui.open(held_item)`,
etc.) keeps working exactly as-is, because both property names now just
point at the same object. This is the one cross-file touch this plan
needs, and it's a pure "point two names at one thing" change — nothing
about how `InteractionSystem.gd` behaves changes.

## 5. Room for what you mentioned — without touching this file again

- **Lockable storage:** doesn't need any change to `StorageUI.gd` at all —
  a locked object simply shouldn't call `.open()` in the first place (its
  own `on_e_interact()`-equivalent checks a lock state first, same as any
  other gated interaction in this project). If you later want a "locked"
  message shown INSIDE this UI for some reason, that's one new optional
  config key (`locked_message: String`) and a short-circuit at the top of
  `open()` — small, additive, not needed today.
- **Freezers/fridges:** if these need a freshness/temperature indicator
  per item later, the badge system is already generic text (`badge.text`),
  not hardcoded to stack counts — a future pass could add a
  `badge_text_source` config option without restructuring anything.
- **Lockers, larger shelving units:** purely a matter of `slot_count`/
  `grid_cols`/`grid_rows`/`display_order`/`row_labels` values in that
  type's own `get_ui_config()` — the pool growth in §3 already covers
  arbitrary capacity.

---

## 6. Create `scripts/ui/inventory/StorageUI.gd` (new file)

Create this file with EXACTLY this content:

```gdscript
extends CanvasLayer
## StorageUI.gd
## Generic storage-container overlay menu (Aug 2026 "Storage UI
## Unification" pass) — ONE shared UI for any storage object (Shelving,
## Basket, and any future type: lockers, freezers, larger shelving units,
## etc.), replacing the former separate ShelfUI.gd/BasketUI.gd (476/470
## lines, 17 of 18 functions identical).
##
## THE CONTRACT — any storage object opened with this UI must implement:
##   get_ui_config() -> Dictionary        (see _DEFAULT_CONFIG below for every key)
##   get_slot_display(slot_idx: int) -> Array     -> [item_or_null, count]
##   take_for_carry(slot_idx: int, isys: Node) -> bool
##       Primary button. Concrete behavior is TYPE-SPECIFIC — Shelving hands
##       the item to the player's hold point ("Carry"), Basket drops it on
##       the ground ("Drop"). The method name is the historical/approved
##       one; treat it as "this storage type's primary retrieval action,"
##       not literally "carry" — see each type's own get_ui_config()
##       primary_button_icon/_tooltip for what it actually does.
##   take_for_inventory(slot_idx: int, inv: Node) -> bool
##       Secondary "⊕" button — always means "pop into the player's
##       inventory pocket," identical meaning for every storage type.
## That's the whole contract. Grid shape, row labels, capacity, stacking,
## and the primary button's icon/label/color/hands-empty-requirement are
## ALL read from get_ui_config() at open() time — nothing type-specific is
## hardcoded in this file. Adding a new storage type needs ZERO changes
## here, just a world-object script implementing the contract above.

# ─── Dependencies (injected by MainWorld) ─────────────────────────────────────
var interaction_system: Node   = null
var inventory: Node            = null
var inventory_hud: Node        = null

# ─── State ────────────────────────────────────────────────────────────────────
var _target: Node3D    = null
var is_open: bool      = false
var _config: Dictionary = {}

## Every key get_ui_config() may provide, with a safe fallback — read via
## _cfg(key) so a storage object's config dict only needs to specify keys
## that differ from these defaults.
const _DEFAULT_CONFIG: Dictionary = {
	"title": "STORAGE CONTENTS",
	"slot_count": 6,
	"grid_cols": 2,
	"grid_rows": 3,
	"display_order": [],                 ## [] = identity (visual pos i -> data slot i)
	"row_labels": [],                    ## [] = auto "Row N" labels
	"supports_stacking": false,
	"primary_button_icon": "↑",
	"primary_button_tooltip": "Take",
	"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
	"primary_requires_empty_hands": false,
	"closes_on_action": true,
}

func _cfg(key: String):
	return _config.get(key, _DEFAULT_CONFIG.get(key))

# ─── Layout constants (unchanged from the old ShelfUI.gd/BasketUI.gd) ────────
const PREVIEW_SIZE:  int   = 96
const SLOT_GAP:      int   = 18
const BTN_SIZE:      float = 36.0
const BTN_GAP:       float = 8.0
const PANEL_PAD:     int   = 28
const PANEL_RADIUS:  float = 14.0
const ROW_GAP:        int   = 22
const ROW_LABEL_H:   int   = 18

const C_BG:          Color = Color(0.08, 0.08, 0.08, 0.92)
const C_SLOT_BG:     Color = Color(0.13, 0.13, 0.13, 1.00)
const C_SLOT_BORDER: Color = Color(0.28, 0.28, 0.28, 1.00)
const C_BTN_INV:     Color = Color(0.22, 0.33, 0.50, 1.00)
const C_BTN_TEXT:    Color = Color(0.90, 0.88, 0.84, 1.00)
const C_TITLE:       Color = Color(0.80, 0.78, 0.72, 1.00)
const C_EMPTY_TEXT:  Color = Color(0.35, 0.35, 0.35, 1.00)
const C_ROW_LABEL:   Color = Color(0.45, 0.43, 0.40, 1.00)
const C_BADGE_TEXT:  Color = Color(0.80, 1.00, 0.85, 1.00)

# ─── Nodes — a dynamic pool, sized to the LARGEST slot_count opened so far.
## Extras beyond the current config's slot_count are hidden, never freed, so
## reopening a same-or-smaller storage type never rebuilds anything. ────────
var _root: Control       = null
var _panel: Panel        = null
var _pool_size: int      = 0
var _viewports: Array    = []
var _vp_rects: Array     = []
var _slot_bgs: Array     = []
var _empty_labels: Array = []
var _badge_labels: Array = []
var _primary_btns: Array = []
var _inv_btns: Array     = []

func _ready() -> void:
	layer = 10
	_build_root()
	visible = false

func _build_root() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.50)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	_root.add_child(backdrop)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color = C_BG
	ss.set_corner_radius_all(int(PANEL_RADIUS))
	ss.set_border_width_all(1)
	ss.border_color = Color(0.30, 0.30, 0.30, 0.80)
	_panel.add_theme_stylebox_override("panel", ss)
	_root.add_child(_panel)

	var title: Label = Label.new()
	title.name = "Title"
	title.add_theme_color_override("font_color", C_TITLE)
	title.add_theme_font_size_override("font_size", 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(title)

# ─── Pool management ──────────────────────────────────────────────────────────
func _ensure_pool_size(needed: int) -> void:
	while _pool_size < needed:
		_add_pool_slot()
		_pool_size += 1

func _add_pool_slot() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.transparent_bg = true
	vp.own_world_3d    = true
	vp.disable_3d      = false
	_root.add_child(vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.2
	vp.add_child(cam)
	cam.position = Vector3(0.8, 0.8, 0.8)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var light := OmniLight3D.new()
	light.position = Vector3(1.0, 1.5, 1.0)
	light.light_energy = 2.5
	light.omni_range = 8.0
	vp.add_child(light)

	var slot_bg: Panel = Panel.new()
	var slot_ss: StyleBoxFlat = StyleBoxFlat.new()
	slot_ss.bg_color = C_SLOT_BG
	slot_ss.set_corner_radius_all(6)
	slot_ss.set_border_width_all(1)
	slot_ss.border_color = C_SLOT_BORDER
	slot_bg.add_theme_stylebox_override("panel", slot_ss)
	slot_bg.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_panel.add_child(slot_bg)

	var tr: TextureRect = TextureRect.new()
	tr.texture = vp.get_texture()
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_panel.add_child(tr)

	var empty_lbl: Label = Label.new()
	empty_lbl.text = "—"
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_color_override("font_color", C_EMPTY_TEXT)
	empty_lbl.add_theme_font_size_override("font_size", 20)
	empty_lbl.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_panel.add_child(empty_lbl)

	var badge: Label = Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	badge.add_theme_color_override("font_color", C_BADGE_TEXT)
	badge.add_theme_font_size_override("font_size", 11)
	badge.size = Vector2(PREVIEW_SIZE - 4, 20)
	badge.visible = false
	_panel.add_child(badge)

	var slot_idx: int = _pool_size
	var primary_btn: Button = _make_icon_button(slot_idx, true)
	_panel.add_child(primary_btn)

	var inv_btn: Button = _make_icon_button(slot_idx, false)
	_panel.add_child(inv_btn)

	_viewports.append(vp)
	_vp_rects.append(tr)
	_slot_bgs.append(slot_bg)
	_empty_labels.append(empty_lbl)
	_badge_labels.append(badge)
	_primary_btns.append(primary_btn)
	_inv_btns.append(inv_btn)

## Icon/tooltip/color for the primary button are applied generically here
## and then OVERWRITTEN per the active config in _apply_primary_button_style()
## every time open() runs — a pool slot might have been built while a
## different storage type's config was active, so its style can't be baked
## in once at creation time the way the old separate files did.
func _make_icon_button(slot_idx: int, is_primary: bool) -> Button:
	var btn: Button = Button.new()
	btn.size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.add_theme_color_override("font_color", C_BTN_TEXT)
	btn.add_theme_font_size_override("font_size", 16)

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.set_corner_radius_all(int(BTN_SIZE * 0.25))
	btn.add_theme_stylebox_override("normal", ss)
	btn.add_theme_stylebox_override("hover", ss.duplicate())
	btn.add_theme_stylebox_override("pressed", ss.duplicate())

	if is_primary:
		btn.pressed.connect(func() -> void: _on_primary_pressed(slot_idx))
	else:
		btn.text = "⊕"
		btn.tooltip_text = "Add to inventory"
		var inv_ss: StyleBoxFlat = ss.duplicate()
		inv_ss.bg_color = C_BTN_INV
		btn.add_theme_stylebox_override("normal", inv_ss)
		var inv_hover: StyleBoxFlat = inv_ss.duplicate()
		inv_hover.bg_color = C_BTN_INV.lightened(0.2)
		btn.add_theme_stylebox_override("hover", inv_hover)
		var inv_pressed: StyleBoxFlat = inv_ss.duplicate()
		inv_pressed.bg_color = C_BTN_INV.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", inv_pressed)
		btn.pressed.connect(func() -> void: _on_inv_pressed(slot_idx))

	return btn

func _apply_primary_button_style() -> void:
	var icon: String = String(_cfg("primary_button_icon"))
	var tip: String  = String(_cfg("primary_button_tooltip"))
	var color: Color  = _cfg("primary_button_color")

	for btn: Button in _primary_btns:
		btn.text = icon
		btn.tooltip_text = tip
		var ss: StyleBoxFlat = StyleBoxFlat.new()
		ss.bg_color = color
		ss.set_corner_radius_all(int(BTN_SIZE * 0.25))
		btn.add_theme_stylebox_override("normal", ss)
		var hover: StyleBoxFlat = ss.duplicate()
		hover.bg_color = color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover)
		var pressed: StyleBoxFlat = ss.duplicate()
		pressed.bg_color = color.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", pressed)

# ─── Open / Close ─────────────────────────────────────────────────────────────
func open(target: Node3D) -> void:
	if target == null:
		return
	if not (target.has_method("get_ui_config") and target.has_method("get_slot_display")
			and target.has_method("take_for_carry") and target.has_method("take_for_inventory")):
		push_warning("StorageUI: target missing required contract method(s) — %s" % str(target))
		return

	_target = target
	_config = target.get_ui_config()
	is_open = true
	visible = true

	var title: Label = _panel.get_node("Title")
	title.text = String(_cfg("title"))

	_ensure_pool_size(int(_cfg("slot_count")))
	_apply_primary_button_style()
	_layout_panel()
	_populate_slots()

	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_root)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	_target = null
	visible = false
	_clear_all_viewports()
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─── Layout panel ─────────────────────────────────────────────────────────────
func _layout_panel() -> void:
	var cols: int = int(_cfg("grid_cols"))
	var rows: int = int(_cfg("grid_rows"))
	var col_w: int = PREVIEW_SIZE
	var row_h: int = PREVIEW_SIZE + int(BTN_SIZE) + 10
	var title_h: int = 32

	var panel_w: int = PANEL_PAD * 2 + cols * col_w + (cols - 1) * SLOT_GAP
	var panel_h: int = PANEL_PAD * 2 + title_h + rows * row_h + (rows - 1) * (ROW_GAP + ROW_LABEL_H)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.size     = Vector2(panel_w, panel_h)
	_panel.position = (vp_size - _panel.size) * 0.5

	var title: Label = _panel.get_node("Title")
	title.position = Vector2(0, PANEL_PAD * 0.5)
	title.size = Vector2(panel_w, title_h)

	for child in _panel.get_children():
		if child.name.begins_with("RowLabel_"):
			child.queue_free()

	var row_labels: Array = _cfg("row_labels")
	var slot_count: int = int(_cfg("slot_count"))

	## Hide every pool slot beyond this config's slot_count — _populate_slots()
	## (called right after this) sets correct visibility for every in-use
	## slot, so only the unused tail of the pool needs handling here.
	for i: int in _pool_size:
		if i >= slot_count:
			_vp_rects[i].visible     = false
			_slot_bgs[i].visible     = false
			_empty_labels[i].visible = false
			_primary_btns[i].visible = false
			_inv_btns[i].visible     = false
			_badge_labels[i].visible = false

	for row: int in rows:
		var row_y_base: int = PANEL_PAD + title_h + row * (row_h + ROW_GAP + ROW_LABEL_H)

		var label_text: String = row_labels[row] if row < row_labels.size() else "Row %d" % (row + 1)
		var row_lbl: Label = Label.new()
		row_lbl.name = "RowLabel_%d" % row
		row_lbl.text = label_text
		row_lbl.add_theme_color_override("font_color", C_ROW_LABEL)
		row_lbl.add_theme_font_size_override("font_size", 10)
		row_lbl.position = Vector2(PANEL_PAD, row_y_base)
		row_lbl.size     = Vector2(panel_w - PANEL_PAD * 2, ROW_LABEL_H)
		_panel.add_child(row_lbl)

		for col: int in cols:
			var visual_idx: int = row * cols + col
			if visual_idx >= slot_count:
				continue
			var sx: float = PANEL_PAD + col * (col_w + SLOT_GAP)
			var sy: float = row_y_base + ROW_LABEL_H + 4
			_position_slot_visuals(visual_idx, sx, sy)

func _data_slot_for(visual_idx: int) -> int:
	var display_order: Array = _cfg("display_order")
	if visual_idx < display_order.size():
		return int(display_order[visual_idx])
	return visual_idx

func _position_slot_visuals(visual_idx: int, sx: float, sy: float) -> void:
	var tr: TextureRect   = _vp_rects[visual_idx]
	var slot_bg: Panel    = _slot_bgs[visual_idx]
	var empty_lbl: Label  = _empty_labels[visual_idx]
	var badge: Label       = _badge_labels[visual_idx]
	var primary: Button    = _primary_btns[visual_idx]
	var inv_b: Button      = _inv_btns[visual_idx]

	slot_bg.position    = Vector2(sx, sy)
	tr.position          = Vector2(sx, sy)
	empty_lbl.position   = Vector2(sx, sy)
	badge.position        = Vector2(sx + 4, sy + 4)

	var btn_y: float = sy + PREVIEW_SIZE + 6.0
	primary.size = Vector2(BTN_SIZE, BTN_SIZE)
	inv_b.size    = Vector2(BTN_SIZE, BTN_SIZE)

	var both_w: float   = BTN_SIZE * 2.0 + BTN_GAP
	var center_x: float = sx + PREVIEW_SIZE * 0.5

	primary.position = Vector2(center_x - both_w * 0.5, btn_y)
	inv_b.position     = Vector2(center_x - both_w * 0.5 + BTN_SIZE + BTN_GAP, btn_y)

	primary.set_meta("center_x", center_x)
	primary.set_meta("btn_y", btn_y)

# ─── Populate slots ────────────────────────────────────────────────────────────
func _populate_slots() -> void:
	if _target == null:
		return
	_clear_all_viewports()
	var slot_count: int = int(_cfg("slot_count"))
	for i: int in slot_count:
		_refresh_slot(i)

func _refresh_slot(visual_idx: int) -> void:
	if _target == null:
		return
	var data_idx: int = _data_slot_for(visual_idx)
	var display: Array = _target.get_slot_display(data_idx)
	var item = display[0] if display.size() > 0 else null
	var count: int = int(display[1]) if display.size() > 1 else 0
	_set_slot(visual_idx, item, count)

func _set_slot(visual_idx: int, item, count: int) -> void:
	var empty_lbl: Label = _empty_labels[visual_idx]
	var badge: Label       = _badge_labels[visual_idx]
	var tr: TextureRect    = _vp_rects[visual_idx]
	var primary: Button    = _primary_btns[visual_idx]
	var inv_b: Button       = _inv_btns[visual_idx]

	var has_item: bool = (item != null and count > 0)

	empty_lbl.visible = not has_item
	tr.visible          = has_item
	primary.visible      = has_item

	var show_inv: bool = has_item and item != null and item.is_in_group("inventory_item")
	inv_b.visible = show_inv

	if primary.has_meta("center_x"):
		var center_x: float = primary.get_meta("center_x")
		var btn_y: float    = primary.get_meta("btn_y")
		if show_inv:
			var both_w: float = BTN_SIZE * 2.0 + BTN_GAP
			primary.position = Vector2(center_x - both_w * 0.5, btn_y)
			inv_b.position     = Vector2(center_x - both_w * 0.5 + BTN_SIZE + BTN_GAP, btn_y)
		else:
			primary.position = Vector2(center_x - BTN_SIZE * 0.5, btn_y)

	if bool(_cfg("supports_stacking")) and has_item and count > 1:
		badge.text    = "×%d" % count
		badge.visible = true
	else:
		badge.visible = false

	if not has_item:
		_clear_viewport(visual_idx)
		return

	_populate_viewport(visual_idx, item)

func _populate_viewport(visual_idx: int, item: Node) -> void:
	var vp: SubViewport = _viewports[visual_idx]

	var to_free: Array = []
	for child in vp.get_children():
		if child is MeshInstance3D:
			to_free.append(child)
	for c in to_free:
		c.queue_free()

	var mesh_inst: MeshInstance3D = null
	if item.has_method("get_inventory_mesh"):
		var m: Mesh = item.get_inventory_mesh()
		if m != null:
			mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = m
	if mesh_inst == null:
		for child in item.get_children():
			if child is MeshInstance3D:
				mesh_inst = child.duplicate() as MeshInstance3D
				break
	if mesh_inst == null:
		return

	mesh_inst.rotation_degrees = Vector3(-20.0, 45.0, 0.0)
	mesh_inst.position = Vector3.ZERO
	vp.add_child(mesh_inst)

	if mesh_inst.mesh != null:
		var local_aabb: AABB    = mesh_inst.mesh.get_aabb()
		var basis: Basis        = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center

func _clear_viewport(visual_idx: int) -> void:
	var vp: SubViewport = _viewports[visual_idx]
	for child in vp.get_children():
		if child is MeshInstance3D:
			child.queue_free()

func _clear_all_viewports() -> void:
	for i: int in _pool_size:
		_clear_viewport(i)

# ─── Button callbacks ─────────────────────────────────────────────────────────
func _on_primary_pressed(visual_idx: int) -> void:
	if _target == null or interaction_system == null:
		return
	if bool(_cfg("primary_requires_empty_hands")) and interaction_system.held_item != null:
		_show_error("Hands full")
		return
	var data_idx: int = _data_slot_for(visual_idx)
	var ok: bool = _target.take_for_carry(data_idx, interaction_system)
	if not ok:
		return
	if bool(_cfg("closes_on_action")):
		close()
	else:
		_refresh_slot(visual_idx)

func _on_inv_pressed(visual_idx: int) -> void:
	if _target == null or inventory == null:
		return
	if inventory.is_full():
		_show_error("Inventory full")
		return
	var data_idx: int = _data_slot_for(visual_idx)
	var ok: bool = _target.take_for_inventory(data_idx, inventory)
	if not ok:
		return
	if bool(_cfg("closes_on_action")):
		close()
	else:
		_refresh_slot(visual_idx)

# ─── Error message ────────────────────────────────────────────────────────────
func _show_error(text: String) -> void:
	if inventory_hud != null and inventory_hud.has_method("show_error_message"):
		inventory_hud.show_error_message(text)

# ─── Backdrop click to close ──────────────────────────────────────────────────
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# ─── Block game input while open ─────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") \
			or event.is_action_pressed("store_item"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
```

---

## 7. Edit `scripts/world/furniture/Shelving.gd`

### Step 7.1 — Rename the injected UI reference for clarity

Find this exact line:

```gdscript
var _shelf_ui: Node           = null   ## Injected by MainWorld after spawn
```

Replace it with exactly this:

```gdscript
var _storage_ui: Node         = null   ## Injected by MainWorld after spawn (Aug 2026 — the shared StorageUI, was _shelf_ui)
```

### Step 7.2 — Update the one call site

Find this exact block:

```gdscript
## E pressed — open the shelf UI overlay
func on_e_interact() -> void:
	if _shelf_ui == null:
		push_warning("Shelving: _shelf_ui not injected")
		return
	_shelf_ui.open(self)
```

Replace it with exactly this:

```gdscript
## E pressed — open the shelf UI overlay
func on_e_interact() -> void:
	if _storage_ui == null:
		push_warning("Shelving: _storage_ui not injected")
		return
	_storage_ui.open(self)
```

### Step 7.3 — Make `retrieve_to_carry()` report success/failure

Find this exact block:

```gdscript
# ─── Retrieve to carry (from ShelfUI "Carry" button) ─────────────────────────
## Pops the top item from the slot's stack and gives it to the player's hand.
func retrieve_to_carry(slot_idx: int, isys: Node) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return
	if isys.held_item != null:
		return   ## Hands full — UI should have blocked this already

	## Pop from top of stack
	var item: RigidBody3D = stack.pop_back()

	## Remove shelved guard so pickup is allowed again
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")

	item.freeze           = false
	item.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.collision_layer  = 2
	item.collision_mask   = 1
	item.gravity_scale    = 1.0
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	if item.has_signal("knocked_out") and \
			not item.knocked_out.is_connected(isys._on_item_knocked_out):
		item.knocked_out.connect(isys._on_item_knocked_out)

	if "from_inventory" in item:
		item.from_inventory = false

	if item.has_method("pickup"):
		item.pickup(isys.hold_point)

	isys.held_item       = item
	isys._held_from_slot = -1
	item_retrieved.emit(slot_idx, item)
```

Replace it with exactly this (adds `-> bool` and `return false`/`return
true`, everything else in the function body is byte-for-byte unchanged):

```gdscript
# ─── Retrieve to carry (from StorageUI's primary "Carry" button) ─────────────
## Pops the top item from the slot's stack and gives it to the player's hand.
## Returns true on success — Aug 2026, part of the StorageUI contract
## (get_slot_display/take_for_carry/take_for_inventory), see §7.4 below.
func retrieve_to_carry(slot_idx: int, isys: Node) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return false
	if isys.held_item != null:
		return false   ## Hands full — UI should have blocked this already

	## Pop from top of stack
	var item: RigidBody3D = stack.pop_back()

	## Remove shelved guard so pickup is allowed again
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")

	item.freeze           = false
	item.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.collision_layer  = 2
	item.collision_mask   = 1
	item.gravity_scale    = 1.0
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	if item.has_signal("knocked_out") and \
			not item.knocked_out.is_connected(isys._on_item_knocked_out):
		item.knocked_out.connect(isys._on_item_knocked_out)

	if "from_inventory" in item:
		item.from_inventory = false

	if item.has_method("pickup"):
		item.pickup(isys.hold_point)

	isys.held_item       = item
	isys._held_from_slot = -1
	item_retrieved.emit(slot_idx, item)
	return true
```

### Step 7.4 — Make `retrieve_to_inventory()` report success/failure

Find this exact block:

```gdscript
# ─── Retrieve to inventory (from ShelfUI "Inv." button) ──────────────────────
func retrieve_to_inventory(slot_idx: int, inv: Node) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return

	var item: RigidBody3D = stack.pop_back()

	## Remove shelved guard before handing to inventory
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")

	item.freeze          = false
	item.visible         = true
	item.collision_layer = 1
	item.collision_mask  = 1
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	inv.add_item(item)
	item_retrieved.emit(slot_idx, item)
```

Replace it with exactly this:

```gdscript
# ─── Retrieve to inventory (from StorageUI's secondary "⊕" button) ───────────
## Returns true on success — Aug 2026, part of the StorageUI contract.
func retrieve_to_inventory(slot_idx: int, inv: Node) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return false

	var item: RigidBody3D = stack.pop_back()

	## Remove shelved guard before handing to inventory
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")

	item.freeze          = false
	item.visible         = true
	item.collision_layer = 1
	item.collision_mask  = 1
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	inv.add_item(item)
	item_retrieved.emit(slot_idx, item)
	return true
```

### Step 7.5 — Add the StorageUI contract methods

Find this exact block (the last 2 functions in the file):

```gdscript
func slot_is_empty(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return true
	return slots[slot_idx].is_empty()

func _first_empty_slot() -> int:
	for i: int in slots.size():
		if slots[i].is_empty(): return i
	return -1
```

Replace it with exactly this (keeps both functions, appends the 4 new
contract methods below them):

```gdscript
func slot_is_empty(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return true
	return slots[slot_idx].is_empty()

func _first_empty_slot() -> int:
	for i: int in slots.size():
		if slots[i].is_empty(): return i
	return -1

# ─── StorageUI contract (Aug 2026 — Storage UI Unification pass) ────────────
## Thin wrappers over this file's own pre-existing slot_top_item()/
## slot_count()/retrieve_to_carry()/retrieve_to_inventory() — none of that
## existing logic changed beyond the bool-return additions in §7.3/§7.4
## above, including NPC-facing npc_retrieve() and the item_placed/
## item_retrieved signals other systems already depend on.
func get_slot_display(slot_idx: int) -> Array:
	return [slot_top_item(slot_idx), slot_count(slot_idx)]

func take_for_carry(slot_idx: int, isys: Node) -> bool:
	return retrieve_to_carry(slot_idx, isys)

func take_for_inventory(slot_idx: int, inv: Node) -> bool:
	return retrieve_to_inventory(slot_idx, inv)

func get_ui_config() -> Dictionary:
	return {
		"title": "SHELF CONTENTS",
		"slot_count": 6,
		"grid_cols": 2,
		"grid_rows": 3,
		"display_order": [4, 5, 2, 3, 0, 1],   ## visual position -> data slot (top row shows data slots 4/5, etc.)
		"row_labels": ["Top shelf", "Middle shelf", "Bottom shelf"],
		"supports_stacking": true,
		"primary_button_icon": "↑",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}
```

Also update the remaining reference to the old variable name inside
`_resolve_interaction_system()`'s neighboring injection comment — find this
exact line in `MainWorld.gd`'s shelf injection loop (covered in §9 below,
not here — flagging so it isn't missed).

---

## 8. Edit `scripts/world/items/Basket.gd`

Find this exact block (the end of the file):

```gdscript
	## Real collision shape on the RigidBody3D itself, matching
	## SeedItem.gd/FarmProduceItem.gd's documented reasoning (a nested
	## MeshInstance3D.create_trimesh_collision() would leave this body with
	## no collider and it would fall through the floor).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.28
	cyl_shape.height = 0.45
	shape.shape = cyl_shape
	shape.position = _mesh.position
	add_child(shape)
```

Replace it with exactly this (keeps everything above unchanged, appends
the contract methods after it):

```gdscript
	## Real collision shape on the RigidBody3D itself, matching
	## SeedItem.gd/FarmProduceItem.gd's documented reasoning (a nested
	## MeshInstance3D.create_trimesh_collision() would leave this body with
	## no collider and it would fall through the floor).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.28
	cyl_shape.height = 0.45
	shape.shape = cyl_shape
	shape.position = _mesh.position
	add_child(shape)

# ─── StorageUI contract (Aug 2026 — Storage UI Unification pass) ────────────
## Baskets never stack (1 item per slot, count is always 0 or 1) and have
## no "carry" concept — the primary button drops the item on the ground
## near the basket (see get_ui_config()'s primary_button_tooltip below;
## the contract method is still named take_for_carry(), see StorageUI.gd's
## own header comment for why that name is kept generic across storage
## types with different primary actions).
func get_slot_display(slot_idx: int) -> Array:
	if slot_idx < 0 or slot_idx >= CAPACITY:
		return [null, 0]
	var item: RigidBody3D = slots[slot_idx]
	return [item, 1 if item != null else 0]

func take_for_carry(slot_idx: int, _isys: Node) -> bool:
	var item: RigidBody3D = remove_item(slot_idx)
	return item != null

func take_for_inventory(slot_idx: int, inv: Node) -> bool:
	var item: RigidBody3D = remove_item(slot_idx)
	if item == null:
		return false
	## Match Shelving.retrieve_to_inventory's post-remove physics reset —
	## remove_item() above already re-enables physics/visibility/layers,
	## so this is just the inventory hand-off.
	inv.add_item(item)
	return true

func get_ui_config() -> Dictionary:
	return {
		"title": "BASKET CONTENTS",
		"slot_count": CAPACITY,
		"grid_cols": 3,
		"grid_rows": 4,
		"display_order": [],    ## [] = identity (visual position i -> data slot i)
		"row_labels": [],       ## [] = auto "Row N" labels
		"supports_stacking": false,
		"primary_button_icon": "↓",
		"primary_button_tooltip": "Drop",
		"primary_button_color": Color(0.55, 0.20, 0.20, 1.00),
		"primary_requires_empty_hands": false,
		"closes_on_action": false,
	}
```

---

## 9. Edit `scripts/world/core/MainWorld.gd`

### Step 9.1 — Collapse the two var declarations into one

Find this exact block:

```gdscript
# ─── Shelf UI ─────────────────────────────────────────────────────────────────
var _shelf_ui: Node = null

# ─── Basket UI ────────────────────────────────────────────────────────────────
var _basket_ui: Node = null
```

Replace it with exactly this:

```gdscript
# ─── Storage UI (Aug 2026 — shared by Shelving and Basket, was two separate
# ShelfUI/BasketUI instances) ──────────────────────────────────────────────────
var _storage_ui: Node = null
```

### Step 9.2 — Update the setup call

Find this exact block:

```gdscript
	## ShelfUI must come after inventory_manager exists and connect_world_objects
	## has registered shelf group members, so injection covers pre-placed shelves.
	_setup_shelf_ui()
	_setup_basket_ui()
```

Replace it with exactly this:

```gdscript
	## StorageUI must come after inventory_manager exists and connect_world_objects
	## has registered shelf group members, so injection covers pre-placed shelves.
	_setup_storage_ui()
```

### Step 9.3 — Collapse the two setup functions into one

Find this exact block:

```gdscript
func _setup_shelf_ui() -> void:
	var shelf_ui_script: Script = load("res://scripts/ui/inventory/ShelfUI.gd")
	_shelf_ui = CanvasLayer.new()
	_shelf_ui.set_script(shelf_ui_script)
	_shelf_ui.name = "ShelfUI"
	add_child(_shelf_ui)

	## Inject shared refs
	_shelf_ui.interaction_system = interaction_system
	_shelf_ui.inventory          = inventory_manager
	var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
	_shelf_ui.inventory_hud = inv_hud

	## Give InteractionSystem a ref so it can block input while open
	interaction_system.shelf_ui = _shelf_ui

	## Inject into any shelves already in the scene (pre-placed before build mode)
	var shelves: Array = get_tree().get_nodes_in_group("shelving")
	for shelf in shelves:
		if "_shelf_ui" in shelf:
			shelf.set("_shelf_ui", _shelf_ui)
		if "_interaction_system" in shelf:
			shelf.set("_interaction_system", interaction_system)

func _setup_basket_ui() -> void:
	var basket_ui_script: Script = load("res://scripts/ui/inventory/BasketUI.gd")
	_basket_ui = CanvasLayer.new()
	_basket_ui.set_script(basket_ui_script)
	_basket_ui.name = "BasketUI"
	add_child(_basket_ui)

	## Inject shared refs
	_basket_ui.interaction_system = interaction_system
	_basket_ui.inventory          = inventory_manager
	var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
	_basket_ui.inventory_hud = inv_hud

	interaction_system.basket_ui = _basket_ui
```

Replace it with exactly this:

```gdscript
## Aug 2026 — replaces the former separate _setup_shelf_ui()/
## _setup_basket_ui() (each built its own ShelfUI/BasketUI CanvasLayer).
## One shared StorageUI instance now serves both. InteractionSystem.gd
## (Player-thread-owned, not touched by this change) keeps its own two
## separate properties, shelf_ui and basket_ui — both are simply pointed at
## this SAME instance below, so every existing call in that file
## (shelf_ui.is_open, basket_ui.open(...), etc.) keeps working unchanged.
func _setup_storage_ui() -> void:
	var storage_ui_script: Script = load("res://scripts/ui/inventory/StorageUI.gd")
	_storage_ui = CanvasLayer.new()
	_storage_ui.set_script(storage_ui_script)
	_storage_ui.name = "StorageUI"
	add_child(_storage_ui)

	## Inject shared refs
	_storage_ui.interaction_system = interaction_system
	_storage_ui.inventory          = inventory_manager
	var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
	_storage_ui.inventory_hud = inv_hud

	## Give InteractionSystem a ref so it can block input while open —
	## both properties point at the same instance, see comment above.
	interaction_system.shelf_ui  = _storage_ui
	interaction_system.basket_ui = _storage_ui

	## Inject into any shelves already in the scene (pre-placed before build mode)
	var shelves: Array = get_tree().get_nodes_in_group("shelving")
	for shelf in shelves:
		if "_storage_ui" in shelf:
			shelf.set("_storage_ui", _storage_ui)
		if "_interaction_system" in shelf:
			shelf.set("_interaction_system", interaction_system)
```

---

## 10. Delete the old files

Delete these 4 files entirely (fully replaced by `StorageUI.gd` above;
confirmed via repo-wide search that nothing besides `MainWorld.gd` — just
edited in §9 — references either script):

- `scripts/ui/inventory/ShelfUI.gd`
- `scripts/ui/inventory/ShelfUI.gd.uid`
- `scripts/ui/inventory/BasketUI.gd`
- `scripts/ui/inventory/BasketUI.gd.uid`

---

## 11. Documentation updates

### Step 11.1 — `docs/systems/ui/README.md`

Find this exact line in the "Files by subfolder" table:

```
| `inventory/` | `InventoryHUD.gd` (~445 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback), `InventoryManager.gd` (~155, see Non-responsibilities), `ShelfUI.gd` (~475), `BasketUI.gd` (~470) | Slot HUD, inventory state, shelf storage panel, basket contents panel |
```

Replace it with exactly this:

```
| `inventory/` | `InventoryHUD.gd` (~445 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback), `InventoryManager.gd` (~155, see Non-responsibilities), `StorageUI.gd` (~380 — Aug 2026, generic shared storage overlay, replaces the former `ShelfUI.gd`/`BasketUI.gd`, see "Storage UI Unification" below) | Slot HUD, inventory state, shared storage-container panel |
```

Find this exact line (start of the `BasketUI Panel (Jul 2026)` section):

```
## BasketUI Panel (Jul 2026)
```

Replace the entire section that follows it (everything from that heading
down to the next `## ` heading) with this new section — same insertion
point, same "read `BasketUI Panel`'s old content and supersede it" intent:

```
## Storage UI Unification (Aug 2026)
Replaces the former separate `ShelfUI.gd`/`BasketUI.gd` (476/470 lines, 17
of 18 functions duplicated between them) with one generic, config-driven
`StorageUI.gd`. Any storage object — `Shelving.gd`, `Basket.gd`, and any
future type — implements a 4-method contract:

- `get_ui_config() -> Dictionary` — grid shape, slot count, row labels,
  stacking, primary-button icon/label/color, close-vs-refresh-on-action.
  Every key optional, `StorageUI.gd`'s `_DEFAULT_CONFIG` fills in the rest.
- `get_slot_display(slot_idx) -> Array` — `[item_or_null, count]`.
- `take_for_carry(slot_idx, isys) -> bool` — the primary button. Concrete
  meaning is type-specific: `Shelving` hands the item to the player's hold
  point ("Carry"), `Basket` drops it on the ground ("Drop") — the method
  name is historical, not literal; treat it as "this type's primary
  retrieval action."
- `take_for_inventory(slot_idx, inv) -> bool` — secondary "⊕" button,
  always means "into the player's inventory pocket," same for every type.

`StorageUI.gd` keeps ONE dynamic slot-visual pool that only grows (never
rebuilds) — opening a 12-slot basket after a 6-slot shelf grows the pool
to 12; reopening the shelf afterward just hides the extra 6, nothing gets
destroyed. This is what makes adding a future storage type (lockable
storage, freezers/fridges, lockers, larger shelving units, all mentioned
as planned) free on the UI side — no fixed slot count anywhere in the
file, no new UI code needed, just a world-object script implementing the
4-method contract above.

`MainWorld.gd`'s former `_setup_shelf_ui()`/`_setup_basket_ui()` collapsed
into one `_setup_storage_ui()`, which points BOTH of
`InteractionSystem.gd`'s existing `shelf_ui`/`basket_ui` properties at the
same `StorageUI` instance — `InteractionSystem.gd` itself (Player-thread-
owned) needed zero changes, every existing call there
(`shelf_ui.is_open`, `basket_ui.open(...)`, etc.) keeps working since both
names now just reference the same object.

Visual style deliberately NOT changed in this pass — `StorageUI.gd` kept
the existing look (14px corner radius, its own dark palette) rather than
moving onto the `UIKit` domain-stripe system Power/Water/Farming/Pause
use. That's a separate, not-yet-requested decision.
```

### Step 11.2 — `docs/systems/furniture-items/README.md`

Find any existing reference to `_shelf_ui` in this file (search for it —
if present, e.g. describing `Shelving.gd`'s injected UI reference) and
update it to `_storage_ui` to match Step 7.1 above. If no such reference
exists, no change needed here — just confirm before skipping.

### Step 11.3 — `HANDOVER.md`

Same convention as the last several passes — insert a new top section
above whatever is currently there (do not delete existing content, this
file is shared across parallel Claude threads). Find the first line of the
file (whatever it currently is) and insert this immediately before it:

```markdown
# Handover — Storage UI Unification: ShelfUI + BasketUI → StorageUI (Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode/Furniture).

## What changed
- New `scripts/ui/inventory/StorageUI.gd` — one generic, config-driven
  storage overlay replacing `ShelfUI.gd`/`BasketUI.gd` (476/470 lines, 17
  of 18 duplicated). Any storage object implements a 4-method contract
  (`get_ui_config`, `get_slot_display`, `take_for_carry`,
  `take_for_inventory`) and needs zero new UI code.
- `Shelving.gd`/`Basket.gd` (furniture-items scope) implement that
  contract as thin wrappers over their existing retrieval logic —
  `retrieve_to_carry()`/`retrieve_to_inventory()` gained bool return
  values, nothing else about their behavior changed (NPC-facing
  `npc_retrieve()` and existing signals untouched).
- `MainWorld.gd`'s `_setup_shelf_ui()`/`_setup_basket_ui()` collapsed into
  one `_setup_storage_ui()`. `InteractionSystem.gd` (Player-thread-owned)
  needed ZERO changes — its `shelf_ui`/`basket_ui` properties both now
  point at the same shared instance.
- Deliberately built with room for planned future storage types (lockable
  storage, freezers/fridges, lockers, larger shelving units) — see
  `docs/systems/ui/README.md`'s "Storage UI Unification" section for how
  each fits without touching `StorageUI.gd` again.

## Files Created
`scripts/ui/inventory/StorageUI.gd`

## Files Deleted
`scripts/ui/inventory/ShelfUI.gd` + `.uid`,
`scripts/ui/inventory/BasketUI.gd` + `.uid`

## Files Modified
`scripts/world/furniture/Shelving.gd`, `scripts/world/items/Basket.gd`,
`scripts/world/core/MainWorld.gd`

## Next Up
- Visual styling (`UIKit` domain-stripe system) not applied to
  `StorageUI.gd` in this pass — flagged as a deliberate, deferrable
  choice, not an oversight.
- First planned future storage type (lockable storage / freezer / locker
  / larger shelving) will be the real test of the contract — implement it
  by adding the 4 contract methods to that object's own script, nothing
  else.

---

```

---

## 12. Verification checklist

1. Open a Shelf (E) — 6 slots in a 3-row × 2-col grid, "Top shelf"/"Middle
   shelf"/"Bottom shelf" labels, "Carry" (↑, green) + "⊕" buttons, stack
   count badges on slots with more than 1 item. Confirm the display order
   still matches what it did before (top shelf = the physically highest
   shelf tier).
2. Open a Basket (G while holding one) — 12 slots in a 4-row × 3-col grid,
   generic "Row 1-4" labels, "Drop" (↓, red) + "⊕" buttons, no stack
   badges ever. Confirm dropping/adding-to-inventory keeps the menu open
   and just refreshes that one slot (unlike Shelf, which closes).
3. Open a Shelf, then immediately open a Basket, then reopen the Shelf —
   confirm no visual glitches or leftover slot content from the previous
   storage object (pool reuse working correctly).
4. Confirm "Hands full" still blocks Shelf's Carry button but does NOT
   block Basket's Drop button (per `primary_requires_empty_hands`).
5. Confirm "Inventory full" still blocks the "⊕" button on both.
6. Confirm no console errors referencing `StorageUI`, `Shelving`,
   `Basket`, or `MainWorld`.
7. Confirm NPCs can still retrieve items from shelves (`npc_retrieve()` —
   untouched by this pass, but worth a smoke test since this file was
   heavily edited).
