extends StaticBody3D
class_name Bed
## Bed.gd
## Interactable bed. Player presses E nearby to sleep.
## Signals SleepOverlay to handle the fade + time-skip.
## Place on a StaticBody3D with a MeshInstance3D and CollisionShape3D child.

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

func _ready() -> void:
	if _is_preview_only:
		return
	add_to_group("interactable")
	add_to_group("bed")   ## Used by MainWorld._connect_bed() to wire all placed beds

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

## Side-effect-free ghost mesh for build-mode previews — extracted
## verbatim from GhostPreview.gd's inline TILE_BED branch so the preview
## matches what the player actually places. No registration, no signals,
## no groups — just a plain Mesh.
static func build_ghost_mesh() -> Mesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W: float = 2.0; var H: float = 0.5; var D: float = 1.0
	# Build a simple box centred at (0, H/2, 0)
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
