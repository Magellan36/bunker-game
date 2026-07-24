extends CanvasLayer
## BuildModeHUD.gd
## Full build-mode overlay:
##   - Pulsing kiwi-green screen border
##   - "BUILD MODE" banner + red cancel X button (top-left)
##   - Bottom toolbar: Construct / Deconstruct / Duplicate / Move / Undo
##   - Construct submenu: vertical panel above toolbar with 3D previews, names, prices
##   - Hammer cursor following the mouse
##   - Rock dig confirm dialog (Yes / No)

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tool_selected(tool_id: int)
signal construct_item_chosen(tile_id: int)   ## Emitted when player picks from submenu
## Farming System plan §8.1 — a genuinely different toolbar tool (buy → spawn
## near player, not ghost-preview placement). Emitted when the player picks a
## Soil/Seeds item from the Farming shop submenu (see FARMING_SHOP_ITEMS).
signal farming_item_chosen(item_id: int)
signal cancel_requested()                     ## Red X or RMB — cancel active ghost
signal undo_requested()                       ## Undo button clicked — instant action
signal dig_confirmed()                        ## Player confirmed a rock dig
signal dig_cancelled()                        ## Player declined a rock dig

# ─── Tool IDs ─────────────────────────────────────────────────────────────────
const TOOL_CONSTRUCT:   int = 0
const TOOL_DECONSTRUCT: int = 1
const TOOL_DUPLICATE:   int = 2
const TOOL_MOVE:        int = 3
const TOOL_UNDO:        int = 4
const TOOL_WIRE:        int = 5   ## Wire draw — click A → click B to place wire
const TOOL_WATER_PIPE:  int = 6   ## Water pipe draw (July 2026 groundwork pass) — click A → click B, auto-elbow at corners
const TOOL_FARMING:     int = 7   ## Farming shop (Jul 2026) — buy → spawn near player, no ghost preview

# ─── Construct-able items — organised by category ─────────────────────────────
## Two-level menu: pick category → pick item.
## tile_id must match BuildModeController constants.
const CATEGORIES: Dictionary = {
	"Structure": [
		{ "tile_id": 1, "name": "Wall",    "price": 50  },
		{ "tile_id": 2, "name": "Pillar",  "price": 25  },
	],
	"Furniture": [
		{ "tile_id": 3, "name": "Shelving","price": 75  },
		{ "tile_id": 4, "name": "Bed",     "price": 150 },
	],
	"Lighting": [
		{ "tile_id": 5, "name": "Light",   "price": 50  },
		## Grow lights (Jul 2026, Farming System) — structurally just another
		## light fixture to the build system, per plan §5.1. Prices are
		## placeholders, unreviewed — flagged for a future balance pass, same
		## convention this project already applies to new device pricing.
		{ "tile_id": 23, "name": "Grow Light",       "price": 180 },
		{ "tile_id": 24, "name": "Grow Light (Pro)", "price": 350 },
	],
	"Power": [
		{ "tile_id": 6,  "name": "Gen S",     "price": 1200  },
		{ "tile_id": 7,  "name": "Gen M",     "price": 3500  },
		{ "tile_id": 8,  "name": "Gen L",     "price": 12000 },
		{ "tile_id": 10, "name": "Terminal",  "price": 2500  },
		{ "tile_id": 11, "name": "Load Test", "price": 0     },
		{ "tile_id": 12, "name": "Breaker",   "price": 80    },
		{ "tile_id": 16, "name": "Breaker (Smart)", "price": 240 },
		{ "tile_id": 13, "name": "Battery S", "price": 150   },
		{ "tile_id": 14, "name": "Battery M", "price": 350   },
		{ "tile_id": 15, "name": "Battery L", "price": 600   },
	],
	"Water": [
		## July 2026 groundwork pass. Test Sink price is a placeholder (plan
		## does not specify economics for this pass — flagged for a future
		## balance pass). Hookup (tile_id 17) intentionally NOT listed here —
		## exactly one hookup exists per game (auto-placed at start by
		## MainWorld._spawn_initial_water_hookup(), see docs/systems/water/
		## README.md) and is relocatable only via the Move tool, never
		## re-purchasable from this menu (Step 2 plan, July 2026).
		{ "tile_id": 18, "name": "Test Sink", "price": 0   },
		## Water Dispenser (Jul 2026, demand/priority pass) — the first real
		## water-consuming device. Price is a placeholder (plan does not
		## specify economics for this pass, same caveat as Test Sink above) —
		## flagged for a future balance pass.
		{ "tile_id": 19, "name": "Dispenser", "price": 250 },
		## Purifier (Jul 2026) — attaches directly onto an existing pipe run,
		## no floor/wall snap (see WaterPurifierAttach.gd / GhostPreview.gd's
		## TILE_WATER_PURIFIER branch). $240 fixed price, refunded on delete.
		{ "tile_id": 20, "name": "Purifier",  "price": 240 },
	],
	"Farming": [
		## Farming System (Jul 2026) — the two tray tiles only. Grow lights
		## live in "Lighting" above (plan §5.1); Soil/Seeds are sold through
		## the separate Farming toolbar tool's shop (FARMING_SHOP_ITEMS below),
		## NOT this menu — see plan §0.2's "naming collision" note.
		{ "tile_id": 21, "name": "Tray (1x1)", "price": 150 },
		{ "tile_id": 22, "name": "Tray (2x1)", "price": 275 },
	],
}

## Farming toolbar tool's shop (Jul 2026, plan §8.2) — a SEPARATE dict from
## CATEGORIES since these aren't placeable/ghost-preview tiles at all, just
## carryable items bought and spawned near the player (see
## FarmingShopHelper.gd). Deliberately shares the same "category → item list"
## shape as CATEGORIES so the existing two-level submenu machinery can be
## reused for both (see _current_categories()) — items still key off
## "tile_id" purely for code-reuse simplicity, even though for this dict the
## value is really an item_id (see FarmingShopHelper.SHOP_ITEM_INFO, which
## must be kept in sync).
const FARMING_SHOP_ITEMS: Dictionary = {
	"Soil": [
		{ "tile_id": 1, "name": "Bag of Soil",       "price": 100 },
	],
	"Seeds": [
		{ "tile_id": 2, "name": "Tomato Seeds (x4)", "price": 25 },
		{ "tile_id": 3, "name": "Onion Seeds (x4)",  "price": 25 },
	],
}

## Flat list used only for legacy compat (3D preview viewports, etc.)
## Generated from CATEGORIES at runtime — do NOT edit directly.
var CONSTRUCT_ITEMS: Array = []

## Helper: look up price for a tile_id across all categories.
func get_item_price(tile_id: int) -> int:
	for cat_items: Array in CATEGORIES.values():
		for item: Dictionary in cat_items:
			if item["tile_id"] == tile_id:
				return item["price"]
	return 0

# ─── Visual constants ──────────────────────────────────────────────────────────
const KIWI:         Color = Color(0.42, 0.87, 0.15, 1.0)
const BORDER_W:     float = 4.0
const BORDER_INSET: float = 6.0

const BANNER_BG:    Color = Color(0.06, 0.14, 0.04, 0.88)
const BANNER_TEXT:  Color = Color(0.52, 0.97, 0.20, 1.0)

## Toolbar
const SLOT_W:       float = 100.0
const SLOT_H:       float = 56.0
const SLOT_GAP:     float = 8.0
const SLOT_CORNER:  float = 8.0
const COLOR_BG:     Color = Color(0.10, 0.10, 0.10, 0.82)
const COLOR_BORDER: Color = Color(0.25, 0.25, 0.25, 0.90)
const COLOR_SEL:    Color = Color(0.42, 0.87, 0.15, 1.0)
const COLOR_TEXT:   Color = Color(0.80, 0.78, 0.72, 0.95)
const TOOL_LABELS:  Array = ["Construct", "Deconstruct", "Duplicate", "Move", "Undo", "Wire", "Pipe", "Farming"]
const TOOL_ICONS:   Array = ["🧱", "🔨", "📋", "✥", "↩", "🔌", "🚰", "🌱"]

## Submenu
const SUB_W:        float = 160.0
const SUB_ITEM_H:   float = 72.0   ## Height per row in submenu
const SUB_VP_SIZE:  int   = 52     ## SubViewport px for 3D preview
const SUB_GAP:      float = 6.0
const SUB_PAD:      float = 10.0
const SUB_BG:       Color = Color(0.08, 0.10, 0.07, 0.94)
const SUB_BORDER:   Color = Color(0.42, 0.87, 0.15, 0.60)
const PRICE_COLOR:  Color = Color(0.35, 0.95, 0.30, 1.0)

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:       Control        = null   ## Full-screen draw surface
var _cursor:       Label          = null   ## Hammer emoji cursor
var _banner:       PanelContainer = null
var _banner_label: Label          = null
var _cancel_btn:   Control        = null   ## Red X button

## Submenu nodes (built once, shown/hidden)
var _submenu_root:    Control   = null
var _sub_viewports:   Array     = []   ## SubViewport per item
var _sub_vp_textures: Array     = []   ## ViewportTexture handles

# ─── External refs ────────────────────────────────────────────────────────────
## Set by BuildModeController after _ready — used to read tile meshes
var gridmap: GridMap  = null
## Camera ref — injected by MainWorld so we can project 3D→2D for the overlay
var camera: Camera3D  = null
## Set each frame by BuildModeController when deconstruct tool is active.
## Sentinel value (-9999 …) means nothing is hovered.
var hovered_deconstruct_cell: Vector3    = Vector3(-9999.0, -9999.0, -9999.0)
## Set each frame when Duplicate or Rotate tool is active and cursor is over a placed object.
var hovered_dupe_rotate_pos: Vector3     = Vector3(-9999.0, -9999.0, -9999.0)
## Set each frame when Deconstruct tool is active and cursor is over a rock chunk.
var hovered_rock_chunk_world_pos: Vector3 = Vector3(-9999.0, -9999.0, -9999.0)

# ─── State ────────────────────────────────────────────────────────────────────
var active_tool:      int   = TOOL_CONSTRUCT
var _submenu_open:    bool  = false
## Two-level menu state: "root" = category list, "items" = item list for _active_category
var _submenu_level:    String = "root"
var _active_category:  String = ""
## Which data source the submenu is currently browsing — "construct"
## (CATEGORIES, tile ghost-preview placement) or "farming" (FARMING_SHOP_ITEMS,
## buy → spawn near player). See _current_categories()/_open_submenu().
var _submenu_source:   String = "construct"
var _pulse_t:         float = 0.0
var _mouse_pos:       Vector2 = Vector2.ZERO
var _cancel_hovered:  bool  = false
## Brief flash when Undo is clicked (counts down from UNDO_FLASH_TIME to 0)
var _undo_flash_t:    float = 0.0
const UNDO_FLASH_TIME: float = 0.25

## Rock dig confirm dialog state
var dig_confirm_open: bool  = false
var _dig_confirm_yes_rect: Rect2 = Rect2()
var _dig_confirm_no_rect:  Rect2 = Rect2()

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer   = 10
	visible = false

	# Build flat CONSTRUCT_ITEMS from CATEGORIES (used for 3D preview viewports)
	for cat_items: Array in CATEGORIES.values():
		for item: Dictionary in cat_items:
			CONSTRUCT_ITEMS.append(item)

	# Full-screen canvas for border + toolbar
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.name = "BuildCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_canvas_draw)

	# Banner
	var style: StyleBoxFlat = _make_stylebox(BANNER_BG, Color.TRANSPARENT,
		Vector4i(0, 6, 6, 0))
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_banner.offset_left = 0.0
	_banner.offset_top  = 12.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", style)
	add_child(_banner)

	_banner_label = Label.new()
	_banner_label.text = "⚒  BUILD MODE"
	_banner_label.add_theme_color_override("font_color", BANNER_TEXT)
	_banner_label.add_theme_font_size_override("font_size", 15)
	_banner.add_child(_banner_label)

	# Cancel (X) button — built after banner so we can position after it resizes
	_cancel_btn = _build_cancel_button()
	add_child(_cancel_btn)
	_cancel_btn.visible = false

	# Submenu panel
	_submenu_root = _build_submenu()
	add_child(_submenu_root)
	_submenu_root.visible = false

	# Hammer cursor
	_cursor = Label.new()
	_cursor.text = "🔨"
	_cursor.add_theme_font_size_override("font_size", 28)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.z_index = 100
	add_child(_cursor)

# ─── Process ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_t  += delta * 2.2
	_mouse_pos = get_viewport().get_mouse_position()
	_cursor.set_position(_mouse_pos + Vector2(4.0, -28.0))
	# Undo flash timer
	if _undo_flash_t > 0.0:
		_undo_flash_t = maxf(0.0, _undo_flash_t - delta)
	# Keep cancel X flush-right of the banner every frame
	_reposition_cancel_btn()
	_canvas.queue_redraw()

# ─── Public API ───────────────────────────────────────────────────────────────
func show_hud() -> void:
	visible = true
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	# Rebuild submenu viewports now that gridmap should be set
	_refresh_submenu_previews()

func hide_hud() -> void:
	visible = false
	_submenu_open = false
	_submenu_root.visible = false
	_cancel_btn.visible   = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func set_active_tool(tool_id: int) -> void:
	active_tool = tool_id
	_canvas.queue_redraw()

## Called by BuildModeController when a ghost is active — show cancel X
func set_ghost_active(active: bool) -> void:
	_cancel_btn.visible = active
	# Close submenu when ghost goes active
	if active and _submenu_open:
		_close_submenu()

## Open / close the construct submenu externally
func open_construct_menu() -> void:
	if not _submenu_open:
		_open_submenu()

func close_construct_menu() -> void:
	if _submenu_open:
		_close_submenu()

## Open the rock dig confirmation dialog
func open_dig_confirm() -> void:
	dig_confirm_open = true
	_canvas.queue_redraw()

## Close the rock dig confirmation dialog without emitting signals
func close_dig_confirm() -> void:
	dig_confirm_open = false
	_canvas.queue_redraw()

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# ── Rock dig confirm dialog — intercept ALL input while open ──────────────
	if dig_confirm_open:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = event.position
			if _dig_confirm_yes_rect.has_point(pos):
				dig_confirm_open = false
				_canvas.queue_redraw()
				dig_confirmed.emit()
				get_viewport().set_input_as_handled()
				return
			elif _dig_confirm_no_rect.has_point(pos):
				dig_confirm_open = false
				_canvas.queue_redraw()
				dig_cancelled.emit()
				get_viewport().set_input_as_handled()
				return
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			dig_confirm_open = false
			_canvas.queue_redraw()
			dig_cancelled.emit()
			get_viewport().set_input_as_handled()
			return
		# Eat all other input
		get_viewport().set_input_as_handled()
		return

	# Escape: close submenu if open, else cancel ghost
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _submenu_open:
			_close_submenu()
			get_viewport().set_input_as_handled()
			return
		else:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position

		if event.button_index == MOUSE_BUTTON_LEFT:
			# Cancel X button
			if _cancel_btn.visible and _cancel_btn.get_rect().has_point(pos):
				cancel_requested.emit()
				get_viewport().set_input_as_handled()
				return

			# Toolbar slot
			var slot: int = _get_toolbar_slot_at(pos)
			if slot != -1:
				_on_toolbar_click(slot)
				get_viewport().set_input_as_handled()
				return

			# Submenu item
			if _submenu_open:
				var item: int = _get_submenu_item_at(pos)
				if item != -1:
					_on_submenu_item_selected(item)
					get_viewport().set_input_as_handled()
					return
				# Click outside submenu while open → close it
				_close_submenu()
				get_viewport().set_input_as_handled()
				return

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# RMB always cancels ghost / submenu
			if _submenu_open:
				_close_submenu()
			else:
				cancel_requested.emit()
			get_viewport().set_input_as_handled()
			return

	# Track hover for cancel button redraw
	if event is InputEventMouseMotion:
		if _cancel_btn.visible:
			var was: bool = _cancel_hovered
			_cancel_hovered = _cancel_btn.get_rect().has_point(event.position)
			if was != _cancel_hovered:
				_canvas.queue_redraw()

# ─── Toolbar click handler ────────────────────────────────────────────────────
func _on_toolbar_click(slot: int) -> void:
	if slot == TOOL_CONSTRUCT:
		if _submenu_open:
			_close_submenu()
		else:
			# Clicking construct while ghost active: cancel ghost, open menu
			cancel_requested.emit()
			_open_submenu()
	elif slot == TOOL_UNDO:
		## Undo is an instant action — no mode switch, just fire the signal.
		_close_submenu()
		cancel_requested.emit()
		undo_requested.emit()
		_undo_flash_t = UNDO_FLASH_TIME
	elif slot == TOOL_WIRE:
		## Wire draw tool — toggle on/off (clicking again deselects)
		_close_submenu()
		cancel_requested.emit()
		if active_tool == TOOL_WIRE:
			active_tool = TOOL_CONSTRUCT
			tool_selected.emit(TOOL_CONSTRUCT)
		else:
			active_tool = TOOL_WIRE
			tool_selected.emit(TOOL_WIRE)
	elif slot == TOOL_WATER_PIPE:
		## Water pipe draw tool (July 2026) — same toggle-on/off shape as Wire above.
		_close_submenu()
		cancel_requested.emit()
		if active_tool == TOOL_WATER_PIPE:
			active_tool = TOOL_CONSTRUCT
			tool_selected.emit(TOOL_CONSTRUCT)
		else:
			active_tool = TOOL_WATER_PIPE
			tool_selected.emit(TOOL_WATER_PIPE)
	elif slot == TOOL_FARMING:
		## Farming shop (Jul 2026, plan §8.1) — same open/close-submenu shape
		## as TOOL_CONSTRUCT, but browsing FARMING_SHOP_ITEMS instead of
		## CATEGORIES, and picking an item spawns it immediately (no ghost).
		if _submenu_open and _submenu_source == "farming":
			_close_submenu()
		else:
			cancel_requested.emit()
			active_tool = TOOL_FARMING
			tool_selected.emit(TOOL_FARMING)
			_open_submenu("farming")
	else:
		# Any other tool: close submenu, cancel ghost, switch tool
		_close_submenu()
		cancel_requested.emit()
		active_tool = slot
		tool_selected.emit(slot)
	_canvas.queue_redraw()

# ─── Submenu ──────────────────────────────────────────────────────────────────
## Returns whichever data source the submenu is currently browsing —
## CATEGORIES (tile ghost-preview placement) or FARMING_SHOP_ITEMS
## (buy → spawn near player). See _submenu_source.
func _current_categories() -> Dictionary:
	return FARMING_SHOP_ITEMS if _submenu_source == "farming" else CATEGORIES

func _open_submenu(source: String = "construct") -> void:
	_submenu_source = source
	if source == "construct":
		active_tool = TOOL_CONSTRUCT
	_submenu_open  = true
	_submenu_level = "root"
	_active_category = ""
	_submenu_root.visible = true
	_position_submenu()
	_canvas.queue_redraw()

func _close_submenu() -> void:
	_submenu_open    = false
	_submenu_level   = "root"
	_active_category = ""
	_submenu_root.visible = false
	_canvas.queue_redraw()

func _submenu_current_rows() -> int:
	## How many rows does the current submenu level show?
	var cats: Dictionary = _current_categories()
	if _submenu_level == "root":
		return cats.size()
	else:
		return cats.get(_active_category, []).size() + 1  ## +1 for Back row

func _position_submenu() -> void:
	## Position directly above whichever toolbar slot opened this submenu —
	## Construct (slot 0) normally, or Farming (slot TOOL_FARMING) when
	## _submenu_source == "farming".
	var anchor_slot: int  = TOOL_FARMING if _submenu_source == "farming" else TOOL_CONSTRUCT
	var vp_size: Vector2  = get_viewport().get_visible_rect().size
	var count: int        = TOOL_LABELS.size()
	var total_w: float    = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float    = (vp_size.x - total_w) * 0.5 + anchor_slot * (SLOT_W + SLOT_GAP)
	var toolbar_y: float  = vp_size.y - SLOT_H - 20.0
	var rows: int         = _submenu_current_rows()
	var sub_h: float      = SUB_ITEM_H * rows + SUB_PAD * 2.0

	_submenu_root.set_position(Vector2(start_x, toolbar_y - sub_h - 8.0))
	_submenu_root.custom_minimum_size = Vector2(SUB_W, sub_h)
	_submenu_root.size = Vector2(SUB_W, sub_h)

func _build_submenu() -> Control:
	var root: Control = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.name = "ConstructSubmenu"

	for i in CONSTRUCT_ITEMS.size():
		var item: Dictionary = CONSTRUCT_ITEMS[i]

		# SubViewport for 3D preview
		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(SUB_VP_SIZE, SUB_VP_SIZE)
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.transparent_bg  = true
		vp.disable_3d      = false
		vp.own_world_3d    = true
		root.add_child(vp)

		var cam: Camera3D = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.6
		vp.add_child(cam)
		cam.position = Vector3(1.0, 1.2, 1.0)
		# look_at requires the node to be in the tree — defer until next frame
		cam.call_deferred("look_at", Vector3.ZERO, Vector3.UP)

		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(1.0, 2.0, 1.0)
		light.light_energy = 3.0
		light.omni_range = 8.0
		vp.add_child(light)

		_sub_viewports.append(vp)
		_sub_vp_textures.append(vp.get_texture())

	# Draw surface for the submenu panel
	var draw_ctrl: Control = Control.new()
	draw_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_ctrl.name = "SubDraw"
	root.add_child(draw_ctrl)
	draw_ctrl.draw.connect(_on_submenu_draw.bind(draw_ctrl))

	return root

func _on_submenu_draw(ctrl: Control) -> void:
	var font: Font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	var rows: int  = _submenu_current_rows()
	var sub_h: float = SUB_ITEM_H * rows + SUB_PAD * 2.0
	var rect: Rect2  = Rect2(Vector2.ZERO, Vector2(SUB_W, sub_h))
	var mouse_local: Vector2 = _mouse_pos - _submenu_root.position

	# Panel background + border
	ctrl.draw_rect(rect, SUB_BG, true)
	ctrl.draw_rect(rect, SUB_BORDER, false, 1.5)

	var cats: Dictionary = _current_categories()

	# ── Root level: show category names ───────────────────────────────────────
	if _submenu_level == "root":
		var cat_keys: Array = cats.keys()
		for i: int in cat_keys.size():
			var cat_name: String = cat_keys[i]
			var row_y: float     = SUB_PAD + i * SUB_ITEM_H
			var row_rect: Rect2  = Rect2(0, row_y, SUB_W, SUB_ITEM_H)

			# Hover highlight
			if row_rect.has_point(mouse_local):
				ctrl.draw_rect(row_rect, Color(0.42, 0.87, 0.15, 0.15), true)

			# Separator
			if i < cat_keys.size() - 1:
				ctrl.draw_line(
					Vector2(SUB_PAD, row_y + SUB_ITEM_H),
					Vector2(SUB_W - SUB_PAD, row_y + SUB_ITEM_H),
					Color(0.3, 0.3, 0.3, 0.6), 1.0)

			# Category icon prefix
			const CAT_ICONS: Dictionary = {
				"Structure": "🧱",
				"Furniture": "🛏",
				"Lighting":  "💡",
				"Power":     "⚡",
				"Water":     "🚰",
				"Farming":   "🌱",
				"Soil":      "🟫",
				"Seeds":     "🌱",
			}
			var icon: String = CAT_ICONS.get(cat_name, "•")
			ctrl.draw_string(font, Vector2(SUB_PAD, row_y + 30.0),
				icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT)

			# Category name
			ctrl.draw_string(font, Vector2(SUB_PAD + 28.0, row_y + 29.0),
				cat_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)

			# Item count badge
			var n: int = cats[cat_name].size()
			var badge: String = "%d item%s" % [n, "s" if n != 1 else ""]
			ctrl.draw_string(font, Vector2(SUB_PAD + 28.0, row_y + 47.0),
				badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.55, 0.55, 0.9))

			# Chevron → right edge
			ctrl.draw_string(font, Vector2(SUB_W - 18.0, row_y + 32.0),
				"›", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PRICE_COLOR)

	# ── Items level: show Back row + items in active category ─────────────────
	else:
		var cat_items: Array = cats.get(_active_category, [])

		# Row 0: Back button
		var back_rect: Rect2 = Rect2(0, SUB_PAD, SUB_W, SUB_ITEM_H)
		if back_rect.has_point(mouse_local):
			ctrl.draw_rect(back_rect, Color(0.42, 0.87, 0.15, 0.12), true)
		ctrl.draw_string(font, Vector2(SUB_PAD, SUB_PAD + 32.0),
			"‹ Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.75, 0.45, 1.0))
		ctrl.draw_string(font, Vector2(SUB_PAD, SUB_PAD + 48.0),
			_active_category, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.65, 0.38, 0.85))
		# Separator under back
		ctrl.draw_line(
			Vector2(SUB_PAD, SUB_PAD + SUB_ITEM_H),
			Vector2(SUB_W - SUB_PAD, SUB_PAD + SUB_ITEM_H),
			Color(0.42, 0.87, 0.15, 0.35), 1.0)

		# Items
		for i: int in cat_items.size():
			var item: Dictionary = cat_items[i]
			var row_y: float    = SUB_PAD + (i + 1) * SUB_ITEM_H   ## +1 for Back row
			var row_rect: Rect2 = Rect2(0, row_y, SUB_W, SUB_ITEM_H)

			# Hover highlight
			if row_rect.has_point(mouse_local):
				ctrl.draw_rect(row_rect, Color(0.42, 0.87, 0.15, 0.15), true)

			# Separator (not after last)
			if i < cat_items.size() - 1:
				ctrl.draw_line(
					Vector2(SUB_PAD, row_y + SUB_ITEM_H),
					Vector2(SUB_W - SUB_PAD, row_y + SUB_ITEM_H),
					Color(0.3, 0.3, 0.3, 0.6), 1.0)

			# 3D preview viewport — find flat index in CONSTRUCT_ITEMS.
			# Farming-shop items (_submenu_source == "farming") are deliberately
			# excluded from this lookup: FARMING_SHOP_ITEMS' "tile_id" values are
			# really item_ids (1/2/3) that collide numerically with real
			# CONSTRUCT_ITEMS tile_ids (Wall/Pillar/Shelving) — without this guard
			# a farming shop row would incorrectly show a wall/pillar preview mesh.
			var flat_idx: int = -1
			if _submenu_source == "construct":
				for fi: int in CONSTRUCT_ITEMS.size():
					if CONSTRUCT_ITEMS[fi]["tile_id"] == item["tile_id"]:
						flat_idx = fi
						break
			if flat_idx >= 0 and flat_idx < _sub_vp_textures.size() \
					and _sub_vp_textures[flat_idx] != null:
				var vp_rect: Rect2 = Rect2(SUB_PAD,
					row_y + (SUB_ITEM_H - SUB_VP_SIZE) * 0.5,
					SUB_VP_SIZE, SUB_VP_SIZE)
				ctrl.draw_texture_rect(_sub_vp_textures[flat_idx], vp_rect, false)

			# Name + price
			var name_x: float = SUB_PAD + SUB_VP_SIZE + SUB_GAP
			ctrl.draw_string(font, Vector2(name_x, row_y + 26.0),
				item["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)
			ctrl.draw_string(font, Vector2(name_x, row_y + 44.0),
				"$%d" % item["price"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, PRICE_COLOR)

func _refresh_submenu_previews() -> void:
	## Load meshes from MeshLibrary into the SubViewports
	if gridmap == null:
		return
	var lib: MeshLibrary = gridmap.mesh_library
	if lib == null:
		return

	for i in CONSTRUCT_ITEMS.size():
		if i >= _sub_viewports.size():
			break
		var tile_id: int  = CONSTRUCT_ITEMS[i]["tile_id"]
		## Guard: only fetch mesh if this tile_id actually exists in the MeshLibrary.
		## Procedural tiles (Shelving, Bed, Generators, etc.) have no MeshLibrary entry.
		if not lib.get_item_list().has(tile_id):
			continue
		var mesh: Mesh    = lib.get_item_mesh(tile_id)
		if mesh == null:
			## Procedural tile (e.g. Shelving) — no MeshLibrary entry; skip 3D preview,
			## the submenu row still draws with name + price as text.
			continue

		var vp: SubViewport = _sub_viewports[i]
		# Remove any old mesh
		for child in vp.get_children():
			if child is MeshInstance3D:
				child.queue_free()

		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.rotation_degrees = Vector3(0.0, 35.0, 0.0)
		vp.add_child(mi)

		# Center mesh in viewport
		if mi.mesh != null:
			var aabb: AABB = mi.mesh.get_aabb()
			mi.position = -aabb.get_center()

## Returns the row index (0-based) within the current submenu level, or -1.
func _get_submenu_item_at(pos: Vector2) -> int:
	if not _submenu_open or not _submenu_root.visible:
		return -1
	var local: Vector2 = pos - _submenu_root.position
	var rows: int      = _submenu_current_rows()
	var sub_h: float   = SUB_ITEM_H * rows + SUB_PAD * 2.0
	if local.x < 0 or local.x > SUB_W or local.y < 0 or local.y > sub_h:
		return -1
	var row: int = int((local.y - SUB_PAD) / SUB_ITEM_H)
	if row >= 0 and row < rows:
		return row
	return -1

func _on_submenu_item_selected(row: int) -> void:
	var cats: Dictionary = _current_categories()

	# ── Root level: user clicked a category ───────────────────────────────────
	if _submenu_level == "root":
		var cat_keys: Array = cats.keys()
		if row >= 0 and row < cat_keys.size():
			_active_category = cat_keys[row]
			_submenu_level   = "items"
			_position_submenu()
			_canvas.queue_redraw()
		return

	# ── Items level ────────────────────────────────────────────────────────────
	if row == 0:
		# Back button — return to root
		_submenu_level   = "root"
		_active_category = ""
		_position_submenu()
		_canvas.queue_redraw()
		return

	# row 1+ → item at index (row - 1)
	var cat_items: Array = cats.get(_active_category, [])
	var item_idx: int    = row - 1
	if item_idx < 0 or item_idx >= cat_items.size():
		return

	var id_val: int = cat_items[item_idx]["tile_id"]
	_close_submenu()
	if _submenu_source == "farming":
		## Buy → spawn near player — no ghost, no tool switch (plan §8.1/§8.3).
		farming_item_chosen.emit(id_val)
	else:
		active_tool = TOOL_CONSTRUCT
		construct_item_chosen.emit(id_val)
	_canvas.queue_redraw()

# ─── Cancel button ────────────────────────────────────────────────────────────
func _build_cancel_button() -> Control:
	## Red box with X — lives at the same top-left as the banner.
	## Repositioned every frame in _process so it's always flush-right of the banner.
	var btn: Control = Control.new()
	btn.custom_minimum_size = Vector2(36.0, 36.0)
	btn.size = Vector2(36.0, 36.0)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.name = "CancelBtn"
	btn.draw.connect(_on_cancel_draw.bind(btn))
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_top  = 12.0
	btn.offset_left = 0.0
	return btn

func _reposition_cancel_btn() -> void:
	## Called every process tick — keeps X flush-right of the banner, vertically centred.
	if _banner == null or _cancel_btn == null:
		return
	var bx: float = _banner.offset_left + _banner.size.x + 4.0
	var by: float = _banner.offset_top  + (_banner.size.y - _cancel_btn.size.y) * 0.5
	_cancel_btn.offset_left = bx
	_cancel_btn.offset_top  = by

func _on_cancel_draw(btn: Control) -> void:
	var r: Rect2  = Rect2(Vector2.ZERO, btn.size)
	var cr: float = 5.0
	var bg: Color = Color(0.55, 0.08, 0.08, 0.88) if not _cancel_hovered \
		else Color(0.80, 0.12, 0.12, 0.95)
	var border: Color = Color(0.90, 0.25, 0.25, 0.80)

	# Rounded bg
	_draw_rounded_on(btn, r, cr, bg)
	# Border
	btn.draw_rect(r, border, false, 1.5)

	# X mark
	var pad: float = 9.0
	var xc: Color  = Color(1.0, 0.85, 0.85, 1.0)
	btn.draw_line(Vector2(pad, pad), Vector2(r.size.x - pad, r.size.y - pad), xc, 2.5)
	btn.draw_line(Vector2(r.size.x - pad, pad), Vector2(pad, r.size.y - pad), xc, 2.5)

# ─── Main canvas draw (border + toolbar) ──────────────────────────────────────
func _on_canvas_draw() -> void:
	_draw_border()
	_draw_deconstruct_overlay()
	_draw_dupe_rotate_overlay()
	_draw_rock_chunk_overlay()
	_draw_toolbar()
	if dig_confirm_open:
		_draw_dig_confirm()
	# Trigger submenu redraw
	if _submenu_open and _submenu_root.visible:
		var draw_ctrl: Control = _submenu_root.get_node_or_null("SubDraw")
		if draw_ctrl != null:
			draw_ctrl.queue_redraw()
	# Trigger cancel btn redraw
	if _cancel_btn != null and _cancel_btn.visible:
		_cancel_btn.queue_redraw()

## Draws a red semi-transparent tile overlay when the Deconstruct tool is active
## and the cursor is hovering over a tile. Uses camera projection to find the
## screen-space corners of the 1×1 grid cell.
func _draw_deconstruct_overlay() -> void:
	if active_tool != TOOL_DECONSTRUCT:
		return
	if camera == null:
		return
	# Sentinel check
	if hovered_deconstruct_cell.x < -999.0:
		return

	# The grid cell is 1 unit wide. Sample 4 ground-level corners.
	# We offset slightly above ground (y + 0.05) so the rect isn't z-fighting.
	var half: float  = 0.5
	var y_off: float = 0.05
	var base: Vector3 = hovered_deconstruct_cell + Vector3(0.0, y_off, 0.0)
	var corners_3d: Array[Vector3] = [
		base + Vector3(-half, 0.0, -half),
		base + Vector3( half, 0.0, -half),
		base + Vector3( half, 0.0,  half),
		base + Vector3(-half, 0.0,  half),
	]

	# Project to screen
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector3 in corners_3d:
		pts.append(camera.unproject_position(c))

	# Fill — red, semi-transparent
	_canvas.draw_colored_polygon(pts, Color(0.85, 0.12, 0.08, 0.35))
	# Border — brighter red outline
	var border_col: Color = Color(1.0, 0.25, 0.18, 0.90)
	for i: int in pts.size():
		_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], border_col, 2.0)

## Draws a light-blue semi-transparent tile overlay when Duplicate or Move tool
## is active (phase 0 hover) and the cursor is hovering over a placed object.
func _draw_dupe_rotate_overlay() -> void:
	if active_tool != TOOL_DUPLICATE and active_tool != TOOL_MOVE:
		return
	if camera == null:
		return
	if hovered_dupe_rotate_pos.x < -999.0:
		return

	var half: float  = 0.5
	var y_off: float = 0.05
	var base: Vector3 = hovered_dupe_rotate_pos + Vector3(0.0, y_off, 0.0)
	var corners_3d: Array[Vector3] = [
		base + Vector3(-half, 0.0, -half),
		base + Vector3( half, 0.0, -half),
		base + Vector3( half, 0.0,  half),
		base + Vector3(-half, 0.0,  half),
	]

	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector3 in corners_3d:
		pts.append(camera.unproject_position(c))

	# Fill — light blue, semi-transparent
	_canvas.draw_colored_polygon(pts, Color(0.20, 0.60, 1.0, 0.30))
	# Border — brighter blue outline
	var border_col: Color = Color(0.35, 0.75, 1.0, 0.90)
	for i: int in pts.size():
		_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], border_col, 2.0)

## Draws a red semi-transparent 4×4 footprint overlay when the Deconstruct tool
## is hovering over a rock chunk. Includes a $2500 cost label above the chunk.
func _draw_rock_chunk_overlay() -> void:
	if active_tool != TOOL_DECONSTRUCT:
		return
	if camera == null:
		return
	# Sentinel check — x < -999 means nothing hovered
	if hovered_rock_chunk_world_pos.x < -999.0:
		return

	# 4×4 chunk footprint (half = 2.0 → 4 units wide/deep)
	# hovered_rock_chunk_world_pos.y = BLOCK_Y (block centre).
	# Raise quad to the top face: BLOCK_HEIGHT/2 + small epsilon above surface.
	# BLOCK_HEIGHT = 2.25 → half = 1.125 → y_off ≈ 1.175 sits just above top face.
	var half: float  = 2.0
	var y_off: float = 1.175
	var base: Vector3 = hovered_rock_chunk_world_pos + Vector3(0.0, y_off, 0.0)
	var corners_3d: Array[Vector3] = [
		base + Vector3(-half, 0.0, -half),
		base + Vector3( half, 0.0, -half),
		base + Vector3( half, 0.0,  half),
		base + Vector3(-half, 0.0,  half),
	]

	# Project corners to screen space
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector3 in corners_3d:
		pts.append(camera.unproject_position(c))

	# Fill — red, semi-transparent
	_canvas.draw_colored_polygon(pts, Color(0.85, 0.12, 0.08, 0.35))
	# Border — brighter red outline, slightly thicker than deconstruct overlay
	var border_col: Color = Color(1.0, 0.25, 0.18, 0.90)
	for i: int in pts.size():
		_canvas.draw_line(pts[i], pts[(i + 1) % pts.size()], border_col, 2.5)

	# Cost label — centered above the chunk's world position
	# Project a point ~1 unit above the chunk center for label anchor
	var label_world: Vector3 = hovered_rock_chunk_world_pos + Vector3(0.0, 1.0, 0.0)
	var label_screen: Vector2 = camera.unproject_position(label_world)
	var cost_str: String = "$1,500"
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text_size: Vector2 = font.get_string_size(cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos: Vector2  = label_screen - Vector2(text_size.x * 0.5, 0.0)
	# Shadow pass for readability
	_canvas.draw_string(font, text_pos + Vector2(1.0, 1.0), cost_str, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, Color(0.0, 0.0, 0.0, 0.75))
	# Main label — same red tint as border
	_canvas.draw_string(font, text_pos, cost_str, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, Color(1.0, 0.45, 0.35, 1.0))

## Draws a centered Yes/No confirmation panel for rock dig.
## Stores button rects in _dig_confirm_yes_rect / _dig_confirm_no_rect
## so _unhandled_input can hit-test them.
func _draw_dig_confirm() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var font: Font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")

	const PANEL_W: float = 320.0
	const PANEL_H: float = 130.0
	const BTN_W:   float = 110.0
	const BTN_H:   float = 38.0
	const CR:      float = 8.0

	var px: float = (vp_size.x - PANEL_W) * 0.5
	var py: float = (vp_size.y - PANEL_H) * 0.5
	var panel_rect: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)

	# Dark semi-transparent background (full screen dim)
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.0, 0.0, 0.0, 0.55), true)

	# Panel background
	_draw_rounded_on(_canvas, panel_rect, CR, Color(0.08, 0.10, 0.07, 0.96))
	# Panel border — kiwi green
	_draw_rounded_outline_on(_canvas, panel_rect, CR, Color(0.42, 0.87, 0.15, 0.80), 2.0)

	# Title
	var title: String = "EXPAND BUNKER"
	var tsz: Vector2 = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	_canvas.draw_string(font,
		Vector2(px + PANEL_W * 0.5 - tsz.x * 0.5, py + 28.0),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.52, 0.97, 0.20, 1.0))

	# Cost line
	var sub: String = "$1,500"
	var ssz: Vector2 = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_canvas.draw_string(font,
		Vector2(px + PANEL_W * 0.5 - ssz.x * 0.5, py + 50.0),
		sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.75, 0.30, 1.0))

	# YES button
	var gap: float = 16.0
	var total_btns_w: float = BTN_W * 2.0 + gap
	var yes_x: float = px + (PANEL_W - total_btns_w) * 0.5
	var btn_y: float = py + PANEL_H - BTN_H - 18.0
	_dig_confirm_yes_rect = Rect2(yes_x, btn_y, BTN_W, BTN_H)
	_draw_rounded_on(_canvas, _dig_confirm_yes_rect, 6.0, Color(0.12, 0.30, 0.08, 0.90))
	_draw_rounded_outline_on(_canvas, _dig_confirm_yes_rect, 6.0, Color(0.42, 0.87, 0.15, 0.90), 1.5)
	var yes_lbl: String = "YES"
	var ylsz: Vector2 = font.get_string_size(yes_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_canvas.draw_string(font,
		Vector2(yes_x + BTN_W * 0.5 - ylsz.x * 0.5, btn_y + BTN_H * 0.5 + 5.0),
		yes_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.80, 1.0, 0.60, 1.0))

	# NO button
	var no_x: float = yes_x + BTN_W + gap
	_dig_confirm_no_rect = Rect2(no_x, btn_y, BTN_W, BTN_H)
	_draw_rounded_on(_canvas, _dig_confirm_no_rect, 6.0, Color(0.25, 0.08, 0.08, 0.90))
	_draw_rounded_outline_on(_canvas, _dig_confirm_no_rect, 6.0, Color(0.85, 0.22, 0.18, 0.80), 1.5)
	var no_lbl: String = "NO"
	var nlsz: Vector2 = font.get_string_size(no_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_canvas.draw_string(font,
		Vector2(no_x + BTN_W * 0.5 - nlsz.x * 0.5, btn_y + BTN_H * 0.5 + 5.0),
		no_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.75, 0.70, 1.0))

func _draw_border() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var pulse: float     = 0.45 + sin(_pulse_t) * 0.45
	var col: Color       = Color(KIWI.r, KIWI.g, KIWI.b, pulse)
	var ins: float       = BORDER_INSET
	var r: Rect2         = Rect2(ins, ins, vp_size.x - ins * 2.0, vp_size.y - ins * 2.0)
	var cr: float        = 12.0

	for pass_i in 3:
		var w: float = BORDER_W - pass_i * 0.8
		var c: Color = Color(col.r, col.g, col.b, col.a * (1.0 - pass_i * 0.25))
		_canvas.draw_line(r.position + Vector2(cr, 0),          r.position + Vector2(r.size.x-cr, 0),         c, w)
		_canvas.draw_line(r.position + Vector2(cr, r.size.y),   r.position + Vector2(r.size.x-cr, r.size.y),  c, w)
		_canvas.draw_line(r.position + Vector2(0, cr),          r.position + Vector2(0, r.size.y-cr),         c, w)
		_canvas.draw_line(r.position + Vector2(r.size.x, cr),   r.position + Vector2(r.size.x, r.size.y-cr),  c, w)
		_canvas.draw_polyline(_arc(r.position + Vector2(cr, cr), cr, PI, PI*1.5), c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(r.size.x-cr, cr), cr, PI*1.5, TAU), c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(cr, r.size.y-cr), cr, PI*0.5, PI), c, w, true)
		_canvas.draw_polyline(_arc(r.position + Vector2(r.size.x-cr, r.size.y-cr), cr, 0.0, PI*0.5), c, w, true)

func _draw_toolbar() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var font: Font       = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	var count: int       = TOOL_LABELS.size()
	var total_w: float   = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float   = (vp_size.x - total_w) * 0.5
	var y: float         = vp_size.y - SLOT_H - 20.0

	for i in count:
		var x: float    = start_x + i * (SLOT_W + SLOT_GAP)
		var rect: Rect2 = Rect2(x, y, SLOT_W, SLOT_H)

		# Undo slot: flash green briefly on click, then return to neutral
		var is_undo: bool   = (i == TOOL_UNDO)
		var undo_flash: bool = is_undo and _undo_flash_t > 0.0

		var slot_bg: Color  = COLOR_BG
		if undo_flash:
			var frac: float = _undo_flash_t / UNDO_FLASH_TIME
			slot_bg = COLOR_BG.lerp(Color(0.12, 0.30, 0.08, 0.88), frac)

		_draw_rounded_on(_canvas, rect, SLOT_CORNER, slot_bg)

		var is_active: bool = (not is_undo) and \
			((i == active_tool) or (i == TOOL_CONSTRUCT and _submenu_open and _submenu_source == "construct") \
				or (i == TOOL_FARMING and _submenu_open and _submenu_source == "farming"))
		var bcol: Color = COLOR_SEL if (is_active or undo_flash) else COLOR_BORDER
		_draw_rounded_outline_on(_canvas, rect, SLOT_CORNER, bcol, 2.0)

		# Icon
		var icon: String    = TOOL_ICONS[i]
		var icsz: Vector2   = font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		_canvas.draw_string(font, Vector2(x + SLOT_W*0.5 - icsz.x*0.5, y + 24.0),
			icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

		# Label
		var lbl: String     = TOOL_LABELS[i]
		var lsz: Vector2    = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		_canvas.draw_string(font, Vector2(x + SLOT_W*0.5 - lsz.x*0.5, y + SLOT_H - 8.0),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_TEXT)

		# Active dot (not for Undo — it's not a persistent mode)
		if is_active:
			_canvas.draw_circle(Vector2(x + SLOT_W*0.5, y + 2.5), 3.0, COLOR_SEL)

# ─── Helpers ──────────────────────────────────────────────────────────────────
func _get_toolbar_slot_at(pos: Vector2) -> int:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var count: int       = TOOL_LABELS.size()
	var total_w: float   = SLOT_W * count + SLOT_GAP * (count - 1)
	var start_x: float   = (vp_size.x - total_w) * 0.5
	var y: float         = vp_size.y - SLOT_H - 20.0
	for i in count:
		var x: float = start_x + i * (SLOT_W + SLOT_GAP)
		if Rect2(x, y, SLOT_W, SLOT_H).has_point(pos):
			return i
	return -1

func _arc(center: Vector2, radius: float, from_a: float, to_a: float) -> Array:
	const STEPS: int = 10
	var pts: Array = []
	for s in range(STEPS + 1):
		var a: float = from_a + (to_a - from_a) * float(s) / STEPS
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

func _make_stylebox(bg: Color, border: Color, corners: Vector4i) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.corner_radius_top_left     = corners.x
	s.corner_radius_top_right    = corners.y
	s.corner_radius_bottom_right = corners.z
	s.corner_radius_bottom_left  = corners.w
	s.content_margin_left   = 14.0
	s.content_margin_right  = 14.0
	s.content_margin_top    = 6.0
	s.content_margin_bottom = 6.0
	return s

func _draw_rounded_on(ctrl: CanvasItem, rect: Rect2, cr: float, col: Color) -> void:
	ctrl.draw_rect(Rect2(rect.position + Vector2(cr, 0), Vector2(rect.size.x - cr*2, rect.size.y)), col, true)
	ctrl.draw_rect(Rect2(rect.position + Vector2(0, cr), Vector2(rect.size.x, rect.size.y - cr*2)), col, true)
	ctrl.draw_circle(rect.position + Vector2(cr, cr), cr, col)
	ctrl.draw_circle(rect.position + Vector2(rect.size.x-cr, cr), cr, col)
	ctrl.draw_circle(rect.position + Vector2(cr, rect.size.y-cr), cr, col)
	ctrl.draw_circle(rect.position + Vector2(rect.size.x-cr, rect.size.y-cr), cr, col)

func _draw_rounded_outline_on(ctrl: CanvasItem, rect: Rect2, cr: float, col: Color, w: float) -> void:
	ctrl.draw_line(rect.position + Vector2(cr, 0),           rect.position + Vector2(rect.size.x-cr, 0),          col, w)
	ctrl.draw_line(rect.position + Vector2(cr, rect.size.y), rect.position + Vector2(rect.size.x-cr, rect.size.y), col, w)
	ctrl.draw_line(rect.position + Vector2(0, cr),           rect.position + Vector2(0, rect.size.y-cr),           col, w)
	ctrl.draw_line(rect.position + Vector2(rect.size.x, cr), rect.position + Vector2(rect.size.x, rect.size.y-cr), col, w)
	ctrl.draw_polyline(_arc(rect.position + Vector2(cr, cr), cr, PI, PI*1.5), col, w, true)
	ctrl.draw_polyline(_arc(rect.position + Vector2(rect.size.x-cr, cr), cr, PI*1.5, TAU), col, w, true)
	ctrl.draw_polyline(_arc(rect.position + Vector2(cr, rect.size.y-cr), cr, PI*0.5, PI), col, w, true)
	ctrl.draw_polyline(_arc(rect.position + Vector2(rect.size.x-cr, rect.size.y-cr), cr, 0.0, PI*0.5), col, w, true)
