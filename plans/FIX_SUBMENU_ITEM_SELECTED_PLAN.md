# Fix: Missing `_on_submenu_item_selected()` in BuildModeHUD.gd

## Error
```
Error at (447, 21): Function "_on_submenu_item_selected()" not found in base self.
```

## Root Cause
`scripts/ui/build/BuildModeHUD.gd`'s `_unhandled_input()` calls `_on_submenu_item_selected(item)` (line 447) when the player clicks a row in the open submenu:

```gdscript
if _submenu_open:
	var item: int = _get_submenu_item_at(pos)
	if item != -1:
		_on_submenu_item_selected(item)
		get_viewport().set_input_as_handled()
		return
```

But this function was **never actually written** anywhere in the file — it's the only reference to that name in the whole script (confirmed via `grep -n "_on_submenu_item_selected" scripts/ui/build/BuildModeHUD.gd`, which returns only the call site, no `func` definition). The two-level submenu system (`_submenu_level` = `"root"`/`"items"`, `_active_category`, category drill-down, Back row, item pick → spawn/place) was built out in `_on_submenu_draw()` and `_update_preview_hover_spin()`, but the actual click-handling function that reacts to a row click was left unimplemented.

## Fix
Add this new function to `scripts/ui/build/BuildModeHUD.gd`. Place it right after `_get_submenu_item_at()` (around line 800, just before `_refresh_submenu_previews()`), since it's the natural counterpart to that lookup function:

```gdscript
## Called when the player clicks a resolved row index inside the open
## submenu (see _get_submenu_item_at()). Row meaning depends on level:
##   - "root" level: row = index into _current_categories().keys() → drill
##     into that category's item list.
##   - "items" level: row 0 = "‹ Back" → return to root. row >= 1 = index
##     (row - 1) into the active category's item array → pick that item.
func _on_submenu_item_selected(item: int) -> void:
	var cats: Dictionary = _current_categories()

	if _submenu_level == "root":
		var cat_keys: Array = cats.keys()
		if item < 0 or item >= cat_keys.size():
			return
		_active_category = cat_keys[item]
		_submenu_level   = "items"
		_position_submenu()   ## row count changed — resize/reposition panel
		_canvas.queue_redraw()
		return

	# ── "items" level ──
	if item == 0:
		## Back row
		_submenu_level   = "root"
		_active_category = ""
		_position_submenu()
		_canvas.queue_redraw()
		return

	var cat_items: Array = cats.get(_active_category, [])
	var idx_in_cat: int  = item - 1   ## row 0 is Back, so shift by one
	if idx_in_cat < 0 or idx_in_cat >= cat_items.size():
		return

	var tile_id: int = cat_items[idx_in_cat]["tile_id"]

	if _submenu_source == "construct":
		## Placeable tile — emit for BuildModeController to start a ghost,
		## then close the submenu (picking a tile always closes it).
		construct_item_chosen.emit(tile_id)
		_close_submenu()
	else:
		## Farming/shop item — emit to spawn/buy immediately, but per the
		## A6 fix (see HANDOVER.md) the shop submenu stays open after a
		## purchase so the player can buy multiple items in a row.
		farming_item_chosen.emit(tile_id)
		_canvas.queue_redraw()
```

### Why these details, specifically
- **Root-level drill-down**: `_current_categories()` returns `CATEGORIES` or `FARMING_SHOP_ITEMS` depending on `_submenu_source`; `_on_submenu_draw()`'s root-level branch already iterates `cats.keys()` in the same order, so indexing `cat_keys[item]` matches exactly what's drawn on screen.
- **Back row = index 0**: confirmed by `_submenu_current_rows()` (`items.size() + 1` for the Back row) and by `_on_submenu_draw()`'s items-level branch, which draws Back at `row_y = SUB_PAD` (row 0) and items starting at `row_y = SUB_PAD + (i + 1) * SUB_ITEM_H` (row `i + 1`). `_update_preview_hover_spin()` uses this identical `idx_in_cat = row - 1` offset, so the click handler must match it.
- **`tile_id` key**: both `CATEGORIES` and `FARMING_SHOP_ITEMS` items use the dict key `"tile_id"` (even for shop items where it's really an item_id) — every existing lookup in the file (`_on_submenu_draw`, `_update_preview_hover_spin`) reads `item["tile_id"]`, so the new handler must too.
- **`_position_submenu()` on level change**: `_submenu_current_rows()` returns a different count for `"root"` vs `"items"`, and `_position_submenu()` resizes/repositions `_submenu_root` based on that count — every existing place that changes `_submenu_level` (`_open_submenu`, `_close_submenu`) also calls `_position_submenu()`/relies on it, so drilling in/out must too or the panel will stay the wrong size.
- **Construct closes, farming stays open**: matches the documented A6 behavior in HANDOVER.md ("Farming shop menu no longer closes after purchase") and the existing `_on_toolbar_click(TOOL_FARMING)` comment ("picking an item spawns it immediately (no ghost)").

## Verification
1. Run `bash tools/godot_check.sh <headless Godot 4.6.3 binary>` — must show no "not found in base self" error for `_on_submenu_item_selected`.
2. Confirm exactly one definition exists: `grep -n "func _on_submenu_item_selected" scripts/ui/build/BuildModeHUD.gd` → one line.
3. In-editor playtest:
   - Open Construct submenu → click a category → item list shows (not a crash). Click "‹ Back" → returns to category list. Click an item → ghost preview starts and submenu closes.
   - Open Shop (Farming) submenu → click a category → click an item → item is purchased/spawned AND the submenu stays open (per A6). Click "‹ Back" → returns to category list.
