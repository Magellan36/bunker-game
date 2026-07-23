extends StaticBody3D
class_name WaterPurifier
## WaterPurifier.gd
## ─────────────────────────────────────────────────────────────────────────────
## Construct-menu tile (TILE_WATER_PURIFIER = 20, $240, Water submenu — see
## BuildModeHUD.CATEGORIES) that attaches directly onto an existing pipe run,
## same "click near a placed pipe" candidate-search BuildModeController._spawn_
## placed_object() performs (see WaterPurifierAttach.gd) — NOT a floor/wall
## snap like every other construct tile.
##
## GRAPH ROLE: occupies a normal WaterGraph node (role "purifier") splitting
## one pipe edge into two (key_a <-> purifier <-> key_b), exactly like a
## WaterPipeElbow "corner" node splits an edge — see
## WaterPurifierAttach.insert_purifier_at(). Any water reaching a consumer
## ONLY via a path that passes through a "purifier" node reads as 100% pure
## — see WaterGraph.get_unpurified_reachable_keys() / WaterManager.
## get_received_rate_mL() for the algorithm.
##
## DELETION ORDER (explicit design decision): deconstructing a purifier does
## NOT delete either adjoining pipe edge — it reverts this node's role back
## to "corner" in place (same key, same edges, water_nodes.register_node()
## is idempotent on role), frees this device's visual, and refunds $240. The
## pipe stays fully intact/connected. Any edge-deletion path (hookup
## reposition, generalized WaterManager.delete_and_refund_edge()) separately
## REFUSES to delete an edge touching a node still marked role == "purifier"
## — that guard plus this "revert first" deconstruct is what enforces
## "purifier must be removed before the pipe beneath it," without any
## cascade-delete complexity.

const RADIUS: float = 0.135   ## WaterPipeSegment.PIPE_RADIUS * 1.5
const LENGTH: float = 0.34
const COLOR_BODY: Color = Color(0.30, 0.55, 0.42, 1.0)   ## green-teal, distinct from plain grey pipe
const COLOR_BAND: Color = Color(0.85, 0.90, 0.30, 1.0)   ## yellow warning band, reads as "treatment unit"

## This purifier's own WaterGraph node key — set by WaterPurifierAttach right
## after insertion.
var node_key: String = ""

## Purifier Filter plan (Jul 2026) — 0-100, current INSTALLED filter's
## remaining life. Depletes continuously over FILTER_LIFESPAN_DAYS in-game
## days; never fully stops purifying (floors implicitly via
## get_output_quality()'s own formula, not a hard clamp here beyond 0).
var filter_quality: float = 100.0
const FILTER_LIFESPAN_DAYS: float = 10.0

## Info panel (read-only) — same lazy-instantiate/reuse pattern as
## WaterHookup._info_ui.
var _info_ui: CanvasLayer = null

## Band material ref (Jul 2026, Purifier QoL plan item 1) — was a local var
## inside _build_mesh() before; promoted to a member so _refresh_band_tint()
## can reach it after initial construction. Tinting just the band (not the
## whole body) mirrors WaterDispenser's tank-fill approach of tinting a
## specific part of the object rather than recoloring the whole thing — the
## purifier still clearly reads as "a purifier" at a glance.
var _band_mat: StandardMaterial3D = null

## One-time low-filter warning trigger (Jul 2026, Purifier QoL plan item 4)
## — fires once when filter_quality crosses from above 50% to at-or-below,
## not every frame it stays low. Re-arms if quality goes back above 50%
## (filter replaced), so a SECOND future depletion warns again.
var _warned_low: bool = false

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	## Jul 2026 (clean-pulse VFX) — purifier nodes are registered into
	## WaterGraph WITHOUT a consumer_ref (see WaterPurifierAttach
	## .insert_purifier_at()'s register_node() call — role-only, no back-
	## reference), so WaterManager can't find this instance via
	## get_consumer_ref(). This group + node_key match is the same
	## findability pattern find_pipe_visual() already uses for
	## "water_pipe_visual" — see WaterManager._find_purifier_by_key().
	add_to_group("water_purifier")
	_build_mesh()
	_refresh_band_tint()
	## Debug print (Jul 2026, Purifier Filter plan §7) — a 10-in-game-day
	## depletion is too slow to eyeball-verify without either a fast-forward
	## cheat or seeing the computed rate once here. This is the MAX rate
	## (incoming water quality <=50%, see _compute_wear_multiplier()) — the
	## LIVE rate varies below this depending on incoming water quality.
	print("[PurifierFilter] max_depletion_per_second=%.8f (FILTER_LIFESPAN_DAYS=%.1f)" % [
		_compute_depletion_per_second(), FILTER_LIFESPAN_DAYS])

func _exit_tree() -> void:
	if _info_ui != null and is_instance_valid(_info_ui):
		_info_ui.queue_free()
		_info_ui = null

## Filter depletion tick (Jul 2026, Purifier Filter plan §3.1) — same real-
## seconds-per-game-day conversion WaterDispenser.gd already uses
## (PlayerStats._seconds_per_game_hour * 24.0, with the same 86400.0 real-
## day fallback if PlayerStats isn't found yet — copied verbatim, not
## re-derived). Rate scaled by incoming water quality (Jul 2026 follow-up —
## see _compute_wear_multiplier()).
func _process(delta: float) -> void:
	var rate: float = _compute_depletion_per_second() * _compute_wear_multiplier()
	filter_quality = maxf(0.0, filter_quality - rate * delta)
	_refresh_band_tint()
	_check_low_filter_warning()

## Purifier QoL plan item 1 — tint the yellow warning band by the SAME
## red/yellow/green thresholds every other quality readout in the game
## already uses (WaterQualityColor.get_color()), not a separately-tracked
## scale.
func _refresh_band_tint() -> void:
	if _band_mat == null:
		return
	_band_mat.albedo_color = WaterQualityColor.get_color(filter_quality)

## Purifier QoL plan item 4 — one-time notice at the SAME 50% threshold
## WaterQualityColor's own <=50.0 red cutoff uses (Brannon's confirmed
## thresholds note: these are the same number, not two independently-
## tracked ones).
func _check_low_filter_warning() -> void:
	if filter_quality <= 50.0 and not _warned_low:
		_warned_low = true
		_fire_low_filter_notice()
	elif filter_quality > 50.0 and _warned_low:
		_warned_low = false

func _fire_low_filter_notice() -> void:
	var notice_script: GDScript = load("res://scripts/ui/hud/TransientNotice.gd")
	if notice_script == null:
		return
	var notice: CanvasLayer = CanvasLayer.new()
	notice.set_script(notice_script)
	get_tree().get_root().add_child(notice)
	if notice.has_method("show_message"):
		notice.call("show_message", "Purifier filter below 50%")



func _compute_depletion_per_second() -> float:
	var seconds_per_game_day: float = 86400.0   ## real-day fallback if PlayerStats isn't found yet
	var stats: Node = get_tree().get_first_node_in_group("player_stats")
	if stats != null and "_seconds_per_game_hour" in stats:
		seconds_per_game_day = stats._seconds_per_game_hour * 24.0
	return 100.0 / (FILTER_LIFESPAN_DAYS * seconds_per_game_day)

## Wear multiplier (Jul 2026 follow-up, Brannon's confirmed spec) — filter
## wear now varies with INCOMING (pre-purification) water quality instead of
## always ticking at the max rate. `_compute_depletion_per_second()`'s
## return value is the MAX rate, hit at incoming quality <=50% (dirtier
## water works the filter harder); the rate scales DOWN linearly to 25% of
## that max at 100% incoming quality (cleaner water barely wears it).
## Disconnected from any water source -> 0 (no water flowing through it at
## all, so nothing to wear the filter down with).
## Uses WaterManager.get_upstream_raw_quality() — the exact same value
## WaterInfoUI's purifier panel already shows as INPUT, so this reads
## consistently with what the player sees in that panel.
func _compute_wear_multiplier() -> float:
	if node_key.is_empty():
		return 0.0
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return 0.0
	var upstream: Dictionary = wm.get_upstream_raw_quality(node_key)
	if not bool(upstream.get("connected", false)):
		return 0.0
	var incoming: float = float(upstream.get("quality", 100.0))
	if incoming <= 50.0:
		return 1.0
	if incoming >= 100.0:
		return 0.25
	## Linear interpolation: 1.0 at incoming=50, 0.25 at incoming=100.
	var t: float = (incoming - 50.0) / 50.0
	return 1.0 - t * 0.75

## The one formula, used everywhere a downstream consumer's actual water
## quality needs to reflect this purifier's current filter wear (Brannon's
## confirmed spec, Purifier Filter plan header): output degrades at HALF the
## rate filter quality does. Filter 100% -> 100% water. Filter 50% -> 75%
## water. Filter 0% -> 50% water (never fully stops purifying, just floors
## at 50%). Called by WaterManager._resolve_output_quality() — this is the
## SOURCE OF TRUTH the manager reads, never re-derived elsewhere.
func get_output_quality() -> float:
	return 50.0 + filter_quality * 0.5


# ─── Deconstruct — revert to a plain corner, keep the pipe intact ────────────
## Called by BuildModeController._try_deconstruct()'s TILE_WATER_PURIFIER
## branch BEFORE this node is queue_free()'d. Reverts the graph node's role
## from "purifier" back to "corner" at the SAME key/position — edges are
## keyed by node key, not role, so both adjoining pipe segments stay exactly
## as connected as they were. No pipe refund; only this device's own $240
## construct cost is refunded (handled by the generic deconstruct path, same
## as any other placed object).
func revert_to_corner() -> void:
	if node_key.is_empty():
		return
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	var pos: Vector3 = wm.get_node_data(node_key).get("pos", global_position)
	wm.register_node(pos, "corner")
	## Spawn a plain elbow visual in this purifier's place so the corner
	## still reads as a normal pipe bend, matching every other mid-run corner.
	var elbow_script: GDScript = load("res://scripts/world/water/WaterPipeElbow.gd")
	if elbow_script != null:
		var elbow: Node3D = Node3D.new()
		elbow.set_script(elbow_script)
		var parent: Node = get_parent()
		if parent != null:
			parent.add_child(elbow)
			elbow.global_position = pos
			elbow.set("node_key", node_key)
	wm.recompute_flow_directions()


# ─── Interaction — read-only info panel (extends WaterInfoUI, mode="purifier") ─
func get_interact_prompt() -> String:
	return "[E] Check Purifier"

func on_interact() -> void:
	if _info_ui == null or not is_instance_valid(_info_ui):
		var ui_script: GDScript = load("res://scripts/ui/water/WaterInfoUI.gd")
		if ui_script == null:
			push_warning("WaterPurifier: WaterInfoUI.gd not found")
			return
		_info_ui = CanvasLayer.new()
		_info_ui.set_script(ui_script)
		_info_ui.name = "WaterInfoUI"
		get_tree().get_root().add_child(_info_ui)
		if _info_ui.has_signal("closed"):
			_info_ui.closed.connect(_on_ui_closed)

	if _info_ui.has_method("open"):
		_info_ui.open("Water Purifier", "purifier", self)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Public accessor mirroring WaterHookup.get_node_key() — read by
## WaterInfoUI's purifier branch to trace the upstream hookup's raw quality.
func get_node_key() -> String:
	return node_key


# ─── Filter swap (Jul 2026, Purifier Filter plan §3.4) ───────────────────────
## Called by PurifierFilterItem.on_use(). Exact behavior per Brannon's spec:
## 1. Eject whatever's currently installed as a new "Used Purifier Filter"
##    carrying THIS purifier's filter_quality at the moment of ejection.
## 2. Install the new filter's quality as this purifier's own.
## 3. Consume the item that was just used.
## 4. Force a recompute so dispensers/sinks/arrows all reflect the new value
##    immediately, not on the next unrelated graph mutation.
## This single method covers BOTH "insert a fresh 100% filter" and "reinsert
## a used X% filter" identically — new_filter.filter_quality is already
## whatever it should be in either case, so there's no branching needed for
## which kind of filter was inserted. This also naturally implements
## "reinserting a used filter resumes depleting from that %" — filter_quality
## just continues ticking down in _process() from whatever this sets it to.
## No double-eject risk: the currently-installed filter was never a live
## world/inventory node to begin with (it's just this purifier's own float),
## so there's nothing for `new_filter` to be confused with.
func replace_filter(new_filter: PurifierFilterItem) -> void:
	## 1. Eject the currently-installed filter as a new Used item, dropped
	## at a small offset from this purifier — reuses PurifierFilterItem's
	## own spawn helper (same drop-nearby treatment as the starting-filters
	## spawn, see spawn_starting_filters() below).
	var parent: Node = get_parent()
	if parent != null:
		PurifierFilterItem.spawn_at(parent, global_position, false, filter_quality)

	## 2. Install the new filter's quality as this purifier's own.
	filter_quality = new_filter.filter_quality

	## 3. Consume the item that was just used.
	new_filter.queue_free()

	## 4. Filter quality changed -> delivered water quality changed for
	## every downstream consumer -> force a recompute so dispensers/sinks/
	## arrows all reflect the new value immediately.
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm != null:
		wm.recompute_flow_directions()

## Spawns the two starting filters (Jul 2026, plan §2) — called once by
## WaterPurifierAttach.insert_purifier_at() right after this purifier is
## added to the tree and positioned. Two fresh (100%) PurifierFilterItem
## instances dropped on the floor near this purifier's base, NOT auto-added
## to inventory — matches how every other placed/spawned object in this
## game ends up as a normal physical pickup rather than a silent inventory
## grant (plan §0.2's recommended default).
func spawn_starting_filters() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	PurifierFilterItem.spawn_at(parent, global_position, true, 100.0)
	PurifierFilterItem.spawn_at(parent, global_position, true, 100.0)


# ─── Clean-pulse VFX (Jul 2026) ───────────────────────────────────────────────
## Tweened expanding flat ring (Brannon's confirmed pick over a particle
## burst or particle+ring combo — reads clearly at this game's top-down
## camera angle; a TorusMesh already lies flat in the XZ plane with no
## rotation needed, same reasoning DustMotes.gd's factory functions use for
## picking the cheapest primitive that reads correctly from this camera).
## Called by WaterManager._process_purity_and_dual_arrows() — ONE call per
## purifier per recompute pass (deduped there, regardless of how many
## consumers' purity-flip attributed to this specific purifier), matching
## Brannon's "one pulse total per recompute pass" answer. WaterManager only
## decides WHEN to call this; how it looks lives entirely here, matching the
## project's existing manager/node-script separation.
const PULSE_COLOR:       Color = Color(0.55, 0.90, 1.00, 0.85)   ## light cyan-blue "clean" tint
const PULSE_DURATION:    float = 0.4
const PULSE_START_SCALE: float = 0.3
const PULSE_END_SCALE:   float = 2.5

func play_clean_pulse() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	var ring_mi: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = RADIUS * 1.5
	torus.outer_radius = RADIUS * 2.2
	ring_mi.mesh = torus

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color     = PULSE_COLOR
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test    = true   ## reads clearly even if it expands past nearby pipes/walls — same convention WireSegment's ghost material uses
	ring_mi.set_surface_override_material(0, mat)

	parent.add_child(ring_mi)
	ring_mi.global_position = global_position
	ring_mi.scale = Vector3.ONE * PULSE_START_SCALE

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ring_mi, "scale", Vector3.ONE * PULSE_END_SCALE, PULSE_DURATION)
	tween.tween_property(mat, "albedo_color:a", 0.0, PULSE_DURATION)
	tween.chain().tween_callback(ring_mi.queue_free)


# ─── Orientation + mesh ───────────────────────────────────────────────────────
## Rotates this purifier's body to match whichever axis (X or Z) the pipe run
## it's attached to travels along — called once, right after insertion, by
## WaterPurifierAttach.insert_purifier_at().
func orient_along(pos_a: Vector3, pos_b: Vector3) -> void:
	var dir: Vector3 = (pos_b - pos_a).normalized()
	if dir == Vector3.ZERO:
		return
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	look_at(global_position + dir, up)
	rotate_object_local(Vector3.RIGHT, PI * 0.5)

static func build_ghost_mesh() -> Mesh:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius    = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height        = LENGTH
	cyl.radial_segments = 12
	return cyl

func _build_mesh() -> void:
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.45
	body_mat.metallic     = 0.55

	## Stored as a member (Jul 2026, Purifier QoL plan item 1), not just a
	## local — _refresh_band_tint() re-tints this after initial construction
	## to reflect current filter_quality via WaterQualityColor's thresholds.
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = COLOR_BAND
	_band_mat.roughness    = 0.60
	_band_mat.metallic     = 0.20

	## NO extra local rotation on these mesh instances (Jul 2026 fix — was
	## previously rotation_degrees = Vector3(90,0,0) on both, "CylinderMesh
	## is Y-aligned; lie along local Z"). That comment's premise was wrong
	## for this node specifically: orient_along() (called once at spawn,
	## right after _build_mesh()) already rotates the WHOLE WaterPurifier
	## body via look_at()+rotate_object_local(RIGHT, 90°) — the exact same
	## sequence WaterPipeSegment.gd uses to align ITS OWN mesh instance's
	## local Y-axis along the pipe direction. Since orient_along rotates
	## this node's root (not a child mesh), the root's own local Y-axis
	## already lies along the pipe run by the time _build_mesh() runs its
	## course — a CylinderMesh child needs NO further rotation to inherit
	## that alignment. The old extra 90°-around-X on the child re-tipped the
	## already-aligned cylinder onto local Z, landing it perpendicular to
	## the pipe — exactly the reported bug.
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_cyl: CylinderMesh  = CylinderMesh.new()
	body_cyl.top_radius    = RADIUS
	body_cyl.bottom_radius = RADIUS
	body_cyl.height        = LENGTH
	body_cyl.radial_segments = 12
	body_mi.mesh = body_cyl
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)

	var band_mi: MeshInstance3D = MeshInstance3D.new()
	var band_cyl: CylinderMesh  = CylinderMesh.new()
	band_cyl.top_radius    = RADIUS * 1.08
	band_cyl.bottom_radius = RADIUS * 1.08
	band_cyl.height        = LENGTH * 0.22
	band_cyl.radial_segments = 12
	band_mi.mesh = band_cyl
	band_mi.set_surface_override_material(0, _band_mat)
	add_child(band_mi)

	body_mi.create_trimesh_collision()
	for child in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0
