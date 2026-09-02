extends StaticBody3D
class_name Bed
## Bed.gd
## Interactable bed. Player presses E nearby to sleep; E again to get up.
## Signals SleepOverlay to handle the fade + time-skip.
##
## Aug 2026 — model swap: the procedural box/cylinder frame is replaced by a
## real Tinkercad OBJ bed model. There are 4 color variants; a REAL placed bed
## picks one at random, while build-mode previews (`_is_preview_only`) always
## show the first variant so the placement ghost is stable instead of
## flickering through colors on every rebuild.
##
## Scale: the model is authored so its mattress top ("sheets" — the surface
## the player sits on) lands at the CHAIR's seat height (Chair.SEAT_SURFACE_Y
## = 0.4971), so the sit animation needs no Y adjustment between chair and bed.
## Measured via a vertex-surface probe: the model's mattress top sits ~4.4
## units up in its upright frame, so MODEL_SCALE = 0.4971 / 4.4.

# ─── Full-fidelity preview mode (Jul 2026) — set TRUE by BuildModeHUD's
## construct-tab preview code BEFORE add_child(), so this instance builds
## its real visual exactly like a placed object but skips every
## side-effecting call (group membership, PowerManager/WaterManager
## registration). MUST be set before add_child() — _ready() fires
## synchronously during add_child() and reads this immediately. See
## docs/systems/build/README.md "Full-fidelity previews" for the full
## convention and why this exists (a previous version instantiated these
## same scripts with no guard and registered 3 real running generators
## into the live PowerManager the instant Build Mode opened).
var _is_preview_only: bool = false

# ─── Signals ─────────────────────────────────────────────────────────────────
## Emitted when player initiates sleep
signal sleep_requested()
## Emitted when player presses E again to get up
signal wake_requested()

# ─── State ───────────────────────────────────────────────────────────────────
var _player_in_range: bool = false
var _player_sleeping: bool = false

## Aug 2026 — the four Tinkercad bed color variants (dark brown / dark green /
## dark red / light blue), each a flat-color OBJ. Each lives in its own folder
## with its `obj.mtl` (the OBJ's `mtllib obj.mtl` must resolve to a sibling of
## the same name — same layout the produce/medical Tinkercad models use).
const MODEL_PATHS: Array[String] = [
	"res://assets/models/bed/dark_brown/tinker.obj",
	"res://assets/models/bed/dark_green/tinker.obj",
	"res://assets/models/bed/dark_red/tinker.obj",
	"res://assets/models/bed/light_blue/tinker.obj",
]

## Scale so the mattress top ("sheets", ~4.4 units up in the upright OBJ) lands
## at the chair seat height (Chair.SEAT_SURFACE_Y = 0.4971). The scaled bed is
## ~2.47m long x 1.01m wide, headboard to ~0.78m.
const MODEL_SCALE: float = 0.4971 / 4.4

func _ready() -> void:
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("bed")   ## Used by MainWorld._connect_bed() to wire all placed beds
		collision_layer = 5   ## bits 1+3 — solid to player/NPC, hoverable in build mode
		collision_mask = 0
	_build_mesh()

## Solid collision matching the scaled model footprint — a LOWER box covering
## the frame/legs (blocks walking through the bed) while leaving the mattress
## top free for the sit/lie position (NPCs lie just above it; the sit animation
## drives position with physics frozen anyway).
const COLLISION_HEIGHT: float = 0.30

## Per-part material tuning (Aug 2026). The bed's GREY surfaces are the metal
## frame — given a darker, rougher, METALLIC look (dark brushed metal). The
## saturated accent surfaces (the mattress color, brown/green/red/blue) keep
## the standard produce mood filter. A surface is "frame" when its base MTL
## color is near-grey (low saturation).
const FRAME_DARK: float = 0.45
const FRAME_DESAT: float = 0.15
const FRAME_ROUGHNESS: float = 0.9
const FRAME_METALLIC: float = 0.7
const FRAME_SAT_THRESHOLD: float = 0.15   ## max-min saturation below this = grey/frame

## Builds the real model + collision. Previews use the first variant (stable
## ghost); real placed beds pick a random color.
func _build_mesh() -> void:
	var idx: int = 0 if _is_preview_only else randi() % MODEL_PATHS.size()
	var mesh: ArrayMesh = load(MODEL_PATHS[idx]) as ArrayMesh
	if mesh == null:
		push_warning("Bed.gd: model missing at %s" % MODEL_PATHS[idx])
		return
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = mesh
	## Tinkercad OBJs export height along Z — rotate upright (same convention
	## the produce/medical Tinkercad models use). The model is centered in X/Z
	## and grounded at Y=0 after this rotation, so no position offset is needed.
	mi.rotation.x = -PI * 0.5
	mi.scale = Vector3.ONE * MODEL_SCALE
	add_child(mi)
	## Per-part filter: grey surfaces = metal frame (darker/rougher/metallic),
	## saturated surfaces = mattress accent (standard produce mood filter).
	## Per-instance overrides — never mutates the shared imported materials.
	for s: int in mesh.get_surface_count():
		var base: Color = Color(1.0, 1.0, 1.0, 1.0)
		var existing: Material = mesh.surface_get_material(s)
		if existing is StandardMaterial3D:
			base = (existing as StandardMaterial3D).albedo_color
		var sat: float = maxf(maxf(base.r, base.g), base.b) - minf(minf(base.r, base.g), base.b)
		if sat < FRAME_SAT_THRESHOLD:
			BuildMaterials.apply_surface_override(mi, s, FRAME_DARK, FRAME_DESAT, FRAME_ROUGHNESS, FRAME_METALLIC)
		else:
			BuildMaterials.apply_surface_override(mi, s, 0.6, 0.12, 0.8, 0.0)

	var scaled_aabb: AABB = mi.transform * mesh.get_aabb()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(scaled_aabb.size.x, COLLISION_HEIGHT, scaled_aabb.size.z)
	cs.position = Vector3(0.0, COLLISION_HEIGHT * 0.5, 0.0)
	cs.shape = box
	add_child(cs)

# ─── Called by InteractionSystem on E press ──────────────────────────────────
func on_interact() -> void:
	if not _player_in_range:
		return
	if not _player_sleeping:
		sleep_requested.emit()
	else:
		wake_requested.emit()

func get_prompt_text() -> String:
	if _player_sleeping:
		return "[E] Wake up"
	return "[E] Sleep"

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

func set_sleeping(sleeping: bool) -> void:
	_player_sleeping = sleeping

# ─── NPC occupancy (NPC Pass 2, Part 13 — additive; player flow above untouched) ──
var _npc_sleeper: Node = null

func is_bed_free() -> bool:
	if _player_sleeping:
		return false
	return _npc_sleeper == null or not is_instance_valid(_npc_sleeper)

func npc_try_lie(npc: Node) -> bool:
	if not is_bed_free():
		return false
	_npc_sleeper = npc
	return true

func npc_stand(npc: Node) -> void:
	if _npc_sleeper == npc:
		_npc_sleeper = null

## Approximate mattress-top height above this node's origin (the scaled
## mattress top = the chair seat height). NPCs lie sunk slightly into it.
const LIE_SURFACE_Y: float = 0.4971
const LIE_SINK: float = 0.15   ## slight recess into the mattress

## World transform an NPC should be moved to while lying down: sunk slightly
## into the mattress, and rotated 90° around the bed's local Z so the
## capsule lies flat along the bed's long (local X) axis instead of
## standing upright.
func get_lie_transform() -> Transform3D:
	var local_pos: Vector3 = Vector3(0.0, LIE_SURFACE_Y - LIE_SINK, 0.0)
	var world_pos: Vector3 = global_transform * local_pos
	var lie_basis: Basis = global_transform.basis * Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(90.0))
	return Transform3D(lie_basis, world_pos)

## World position to stand at when getting up — one step off the bed's side.
func get_bed_stand_position() -> Vector3:
	var local_pos: Vector3 = Vector3(0.0, 0.0, 1.0)
	return global_transform * local_pos

# ─── Player sit positioning (Aug 2026 — mirrors Chair.gd's seat API) ────────
## The bed "sheets" position the player sits on during the animated sit-down
## sleep sequence — the SAME machinery as the chair sit, retargeted from the
## chair's seat to the bed's mattress. The mattress top equals the chair seat
## height (Chair.SEAT_SURFACE_Y = 0.4971), so the controller's seated-Y math
## is reused unchanged; only the X/Z anchor + facing differ.
const SHEETS_SURFACE_Y: float = 0.4971   ## mattress top = chair seat height
const SHEETS_CLEARANCE: float = 0.02     ## like Chair.SEAT_CLEARANCE
const SHEETS_X: float = 0.746            ## 1/5 down the foot (+X end) of the ~2.49m bed (was 0.414 = 1/3)
const SHEETS_EDGE_Z: float = 0.26        ## sitting on the side, pelvis slightly inward of the edge

## World transform the player sits at: 2/3 down the head, on the mattress top,
## on the side edge, facing OUTWARD (away from the bed) on whichever side they
## came from. side = +1 → +Z side (faces +Z); -1 → -Z side (faces -Z). The
## controller flips the seated model PI from this basis's facing (same
## convention as Chair.get_seat_transform), so the yaw offset below makes the
## seated model face the bed's side the player sat on.
func get_sheets_transform(side: float) -> Transform3D:
	var local_pos: Vector3 = Vector3(SHEETS_X, SHEETS_SURFACE_Y, side * SHEETS_EDGE_Z)
	var world_pos: Vector3 = global_transform * local_pos
	var yaw_offset: float = PI if side < 0.0 else 0.0
	var sheets_basis: Basis = global_transform.basis * Basis(Vector3.UP, yaw_offset)
	return Transform3D(sheets_basis, world_pos)

## Side-effect-free ghost mesh for build-mode previews — a box matching the
## scaled model footprint. Extracted from GhostPreview's inline TILE_BED
## branch so the fallback preview matches what the player places.
static func build_ghost_mesh() -> Mesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Scaled model footprint: ~2.47 long x ~0.5 tall x ~1.01 wide.
	var W: float = 2.47; var H: float = 0.5; var D: float = 1.01
	var hx: float = W * 0.5; var hy: float = H * 0.5; var hz: float = D * 0.5
	var verts: Array[Array] = [
		[Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz)],   ## -Z face
		[Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz)],   ## +Z face
		[Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz)],     ## +Y face
		[Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz)], ## -Y face
		[Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz)],       ## +X face
		[Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz)],  ## -X face
	]
	for face: Array in verts:
		for v: Vector3 in face:
			st.add_vertex(v)
	return st.commit()