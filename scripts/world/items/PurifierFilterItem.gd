extends PickupableItem
class_name PurifierFilterItem
## PurifierFilterItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Pickupable consumable for WaterPurifier.gd (Jul 2026 — Purifier Filter
## system plan). ONE script/scene for both states — mirrors WaterBottle.gd's
## established pattern exactly (its own header: "purely a display-state
## derived from _is_empty() — no separate scene/class"; same call applies
## here): a fresh filter and a used filter are the same object, distinguished
## by `is_used` + `filter_quality`, not two classes.

# ─── Config ───────────────────────────────────────────────────────────────────
## Proximity range for "[E] Replace Filter" near a purifier — reuses
## WaterBottle.REFILL_RANGE's exact value (2.5) so "how close counts as
## near" reads consistently across every water-adjacent interaction.
const REPLACE_RANGE: float = 2.5

var shelf_stack_limit: int   = 6
var shelf_item_type: String  = "purifier_filter"

# ─── State ────────────────────────────────────────────────────────────────────
var filter_quality: float = 100.0   ## 0-100. Fixed for a used filter, irrelevant/always-100 for a fresh one.
var is_used: bool = false           ## true = "Used Purifier Filter", carries filter_quality at time of ejection

# ─── Node refs ────────────────────────────────────────────────────────────────
var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	_mesh = get_node_or_null("MeshInstance3D")
	_update_used_tint()

# ─── Inventory charge badge (Jul 2026, Purifier QoL plan item 5) ─────────────
## InventoryHUD._get_charge_info() calls this if present, expecting
## [current, max] — a size-2 Array triggers the badge draw
## (_draw_charge_badge()), anything else (including this empty-Array
## sentinel) draws no badge at all (confirmed by reading InventoryHUD's own
## `if charge_info.size() == 2` check before assuming). Fresh filters are
## always 100% — no useful badge info, so they return no badge at all
## rather than a redundant "100/100".
func get_charge_info() -> Array:
	if not is_used:
		return []
	return [int(round(filter_quality)), 100]

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	if is_used:
		return "Used Purifier Filter (%d%%)" % int(round(filter_quality))
	return "Purifier Filter"

func get_prompt_text() -> String:
	return "[F] Pick up  " + get_display_name()

func get_trash_material() -> String:
	return "plastic"

func _find_nearest_purifier() -> WaterPurifier:
	var best: WaterPurifier = null
	var best_dist: float = REPLACE_RANGE
	for node: Node in get_tree().get_nodes_in_group("water_purifier"):
		if node is WaterPurifier:
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as WaterPurifier
	return best

## Color-coded delta (Jul 2026, Purifier QoL plan items 2/3.2) — green when
## this filter is better-or-equal to what's currently installed, red when
## worse. Reuses WaterBottle.GOOD_COLOR_HEX/CRIT_COLOR_HEX's exact hex
## literals (same "duplicated per-file per this project's convention"
## pattern the rest of the water UI already follows) rather than deriving
## new ones. InteractPrompt already renders BBCode (confirmed by
## WaterBottle._fill_quality_bbcode()'s existing [color=#...] usage) — same
## mechanism, no new prompt-coloring plumbing needed.
const GOOD_COLOR_HEX: String = "4dd959"
const CRIT_COLOR_HEX: String = "ff594d"

func get_use_prompt() -> String:
	var purifier: WaterPurifier = _find_nearest_purifier()
	if purifier == null:
		return ""   ## No use prompt away from a purifier — matches WaterBottle's away-from-dispenser case
	var delta_color: String = GOOD_COLOR_HEX if filter_quality >= purifier.filter_quality else CRIT_COLOR_HEX
	return "[E] Replace Filter  [color=#%s](%d%% -> %d%%)[/color]" % [
		delta_color, int(round(purifier.filter_quality)), int(round(filter_quality))]

# ─── Use / Replace ────────────────────────────────────────────────────────────
## Does NOT handle the swap logic itself — filter-swap rules stay owned by
## WaterPurifier, matching this project's existing manager/node-owns-its-own-
## behavior split (WaterDispenser/WaterHookup et al. all follow this shape).
##
## Purifier QoL plan item 3 (Jul 2026) — swapping to a LOWER-quality filter
## is allowed (Brannon: "there will be reasons to swap to lower filters in
## the future"), but requires an explicit Yes/No confirmation via the new
## shared ConfirmDialogUI (modeled on BuildModeHUD's "EXPAND BUNKER" dialog,
## see that file's own header). Equal-or-higher quality swaps proceed
## immediately, no confirmation — same as before this plan.
##
## Job Progress Bar (Aug 2026) — the confirm dialog (when needed) still
## happens immediately, synchronously, at press time — it's a decision
## point, not part of the timed task. The actual swap (purifier.
## replace_filter()) is what's gated behind the job, deferred to
## _finish_replace() either way (confirmed or no-confirmation-needed).
func on_use() -> void:
	var purifier: WaterPurifier = _find_nearest_purifier()
	if purifier == null:
		return

	if filter_quality < purifier.filter_quality:
		var dlg: ConfirmDialogUI = ConfirmDialogUI.new()
		get_tree().get_root().add_child(dlg)
		dlg.open("REPLACE WITH LOWER-QUALITY FILTER?",
			"%d%% -> %d%%" % [int(round(purifier.filter_quality)), int(round(filter_quality))])
		dlg.confirmed.connect(func() -> void:
			dlg.queue_free()
			_start_replace_job(purifier)
		)
		dlg.cancelled.connect(dlg.queue_free)
		return

	_start_replace_job(purifier)

func _start_replace_job(purifier: WaterPurifier) -> void:
	if not is_instance_valid(purifier):
		return
	var isys: Node = _hold_point.get_parent() if _hold_point != null else null
	if isys == null or not isys.has_method("start_job"):
		return
	isys.start_job(purifier, InteractionSystem.JOB_DEFAULT_DURATION, Callable(self, "_finish_replace").bind(purifier), "Replacing Filter...", REPLACE_RANGE)

func _finish_replace(purifier: WaterPurifier) -> void:
	if is_instance_valid(purifier):
		purifier.replace_filter(self)   ## purifier reads self.filter_quality, handles the swap + ejection, then frees this instance

# ─── Used-state tint ──────────────────────────────────────────────────────────
func _update_used_tint() -> void:
	if _mesh == null:
		return
	if is_used:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.32, 0.20, 1.0)   ## dirtied brown tint — reads as "spent"
		_mesh.material_override = mat
	else:
		_mesh.material_override = null

## Called by WaterPurifier.replace_filter() right after setting is_used/
## filter_quality on a newly-ejected instance, so the visual updates
## immediately without waiting for _ready() (the node's already in the tree).
func refresh_visual_state() -> void:
	_update_used_tint()

# ─── Spawn helper (used by WaterPurifier for starting filters + ejection) ────
## Spawns a loose PurifierFilterItem into the world at `base_pos` with a
## small random horizontal offset so multiple spawns don't overlap/launch
## each other (per the plan's §0.2 recommended default — floor-dropped, NOT
## auto-added to inventory, matching how every other placed/spawned object
## in this game ends up as a normal physical pickup).
static func spawn_at(parent: Node, base_pos: Vector3, fresh: bool, quality: float) -> PurifierFilterItem:
	var scene: PackedScene = load("res://scenes/world/PurifierFilterItem.tscn")
	var item: PurifierFilterItem = null
	if scene != null:
		item = scene.instantiate() as PurifierFilterItem
	else:
		item = PurifierFilterItem.new()
	item.is_used = not fresh
	item.filter_quality = quality
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	item.refresh_visual_state()
	return item
