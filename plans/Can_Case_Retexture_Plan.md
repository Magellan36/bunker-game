PLAN: CanCase — Fix Scene Deviation + Add Visual Can-Depletion Logic
Context (read first, do not skip)
scenes/world/CanCase.tscn and its 8 supporting textures at res://assets/textures/items/can_case/ were already added in a prior commit and are correct — do not regenerate or re-author the model/textures. Two things remain, and this plan covers only those two:

A formatting deviation in the already-committed CanCase.tscn: 3 unique_id node attributes are quoted strings (unique_id="403391416") instead of Godot's real unquoted-integer format (unique_id=403391416), which every other scene in this repo uses. Fix this.
Missing gameplay logic: scripts/world/items/CanCase.gd currently ejects a FoodCan on each E press but never touches the case's own visible can meshes — the tray never visually empties. Add that.
Nothing else about the scene, materials, or textures needs to change. Do not touch FoodCan.tscn, FoodCan.gd, FarmingShopHelper.gd, or BuildModeHUD.gd — none of them need changes for this task.

Step 0 — Setup
git checkout main
git pull
git checkout -b feature/can-case-depletion-logic
Step 1 — Verify starting state (do this before editing anything)
Confirm all of the following are true. If any are false, STOP and report back instead of proceeding — it means the repo state has changed since this plan was written.

scenes/world/CanCase.tscn exists and its [node name="CanCase" type="RigidBody3D" ...] line contains can_count = 12.
scenes/world/CanCase.tscn contains [ext_resource type="Texture2D" path="res://assets/textures/items/can_case/..."] lines for all 8 of: cardboard_tray_diffuse.png, cardboard_roughness.png, cardboard_front_strip.png, can_label_red.png, can_label_purple.png, can_label_brown.png, can_lid_top.png, can_lid_normal.png.
All 8 files above actually exist on disk at res://assets/textures/items/can_case/ and are non-empty valid PNGs.
scenes/world/CanCase.tscn contains 12 Node3D children under VisualRoot named Can_01 through Can_12, each with a Body and Lid MeshInstance3D child.
scripts/world/items/CanCase.gd's script ext_resource in the scene points to res://scripts/world/items/CanCase.gd (not res://scripts/player/CanCase.gd).
If all 5 check out, proceed to Step 2.

Step 2 — Fix the unique_id quoting deviation in scenes/world/CanCase.tscn
Make these 3 exact text replacements in the file (nothing else in the file changes):

Replacement 1:

[node name="CanCase" type="RigidBody3D" unique_id="403391416" groups=["pickup"]]
becomes

[node name="CanCase" type="RigidBody3D" unique_id=403391416 groups=["pickup"]]
Replacement 2:

[node name="CollisionShape3D" type="CollisionShape3D" parent="." unique_id="87744957"]
becomes

[node name="CollisionShape3D" type="CollisionShape3D" parent="." unique_id=87744957]
Replacement 3:

[node name="SpawnPoint" type="Node3D" parent="." unique_id="295681397"]
becomes

[node name="SpawnPoint" type="Node3D" parent="." unique_id=295681397]
Only the quotation marks around the three numeric IDs are removed. Do not change the numbers themselves, do not change any other attribute on those lines, and do not touch any other unique_id-free node in the file (most nodes in this scene have no unique_id at all — that's correct and expected, leave them as-is).

Step 3 — Replace scripts/world/items/CanCase.gd in full
Overwrite the entire file with the exact content below. This is a full-file replacement, not a patch.

extends PickupableItem
## CanCase.gd
## A case of food cans (visual model: 12 cans, 4×3 layout in VisualRoot).
## Pickupable and carriable like a crate.
## While PLACED: press E to eject one can from the case.
## While HELD:   E does nothing (interact blocked while carrying).
## Each ejection also hides one visible can mesh under VisualRoot so the case
## model visually empties out in sync with can_count — see _hide_next_can_visual().

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var item_name: String  = "Can Case"
@export var can_count: int     = 12   ## Matches the 12 visible Can_01..Can_12 nodes in CanCase.tscn

## Shelf stacking — 4 cases lay flat per slot (2×2 grid)
var shelf_stack_limit: int   = 4
var shelf_item_type: String  = "can_case"

const CAN_SCENE: String = "res://scenes/world/FoodCan.tscn"
const VISUAL_CAN_PREFIX: String = "Can_"   ## VisualRoot child name prefix, e.g. "Can_01"

# ─── Node refs ───────────────────────────────────────────────────────────────
## Add a Node3D child named "SpawnPoint" in the editor — sets where cans eject from.
@onready var spawn_point: Node3D = $SpawnPoint
@onready var visual_root: Node3D = get_node_or_null("VisualRoot")

var _player_stats: Node = null  ## Injected by MainWorld
var _can_visuals: Array[Node3D] = []   ## Populated in _ready(), depleted highest-numbered-first

func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Scale down by 1/4
	scale = Vector3(0.75, 0.75, 0.75)
	_collect_can_visuals()

## Builds _can_visuals in ascending name order (Can_01 .. Can_12) from VisualRoot's
## children so _hide_next_can_visual() can pop from the end (Can_12 hidden first).
func _collect_can_visuals() -> void:
	_can_visuals.clear()
	if visual_root == null:
		push_warning("CanCase: no 'VisualRoot' node found — visual can depletion disabled.")
		return
	var found: Array[Node3D] = []
	for child in visual_root.get_children():
		if child is Node3D and String(child.name).begins_with(VISUAL_CAN_PREFIX):
			found.append(child)
	found.sort_custom(func(a, b): return String(a.name) < String(b.name))
	_can_visuals = found

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name

func get_interact_prompt() -> String:
	if can_count <= 0:
		return ""
	return "[E] Take can (%d)" % can_count

# ─── Interact: eject a can — works both placed and while held ─────────────────
func on_interact() -> void:
	if can_count <= 0:
		return

	var can_res: Resource = load(CAN_SCENE)
	if can_res == null:
		push_error("CanCase: Could not load FoodCan.tscn at '%s'" % CAN_SCENE)
		return

	var can: RigidBody3D = can_res.instantiate()

	if "_player_stats" in can:
		can._player_stats = _player_stats if _player_stats != null \
			else get_tree().get_first_node_in_group("player_stats")

	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("CanCase: No node in group 'world' found.")
		return

	world.add_child(can)
	can.global_position = spawn_point.global_position
	can.linear_velocity = -global_transform.basis.z * 2.5 + Vector3(0, 1.5, 0)

	can_count -= 1
	_hide_next_can_visual()

## Hides the next remaining visible can mesh (highest-numbered first) so the
## case model visually empties in sync with can_count. Safe no-op once
## _can_visuals is empty (e.g. can_count configured higher than 12 elsewhere).
func _hide_next_can_visual() -> void:
	if _can_visuals.is_empty():
		return
	var next_can: Node3D = _can_visuals.pop_back()
	next_can.visible = false
Exact diff summary (for the agent's own sanity check after writing the file)
Versus the current file, this changes only:

Top doc comment: "16 food cans" → "food cans (visual model: 12 cans...)".
@export var can_count: int = 16 → = 12.
New const VISUAL_CAN_PREFIX: String = "Can_".
New @onready var visual_root: Node3D = get_node_or_null("VisualRoot").
New var _can_visuals: Array[Node3D] = [].
_ready() gains a trailing call to _collect_can_visuals().
New _collect_can_visuals() function.
on_interact() gains one new trailing line: _hide_next_can_visual() (after can_count -= 1).
New _hide_next_can_visual() function.
Everything else — get_prompt_text(), get_interact_prompt(), the entire FoodCan spawn/eject block inside on_interact(), shelf_stack_limit, shelf_item_type, CAN_SCENE — is byte-for-byte identical to what's already committed. Do not alter it.

Why this works (for the agent's understanding, not something to implement differently)
Can_01..Can_12 in the scene are plain Node3D holders, each with a Body and Lid MeshInstance3D child. Setting .visible = false on the parent Node3D hides both children automatically — Godot's visibility flag cascades down the tree via is_visible_in_tree(). No need to hide Body/Lid individually.
_can_visuals is built once in _ready(), sorted by name (Can_01 < Can_02 < ... < Can_12 via plain string comparison, which works here because all names are zero-padded to 2 digits).
pop_back() removes and returns the last array element — i.e., Can_12 (highest-numbered) disappears first, then Can_11, down to Can_01 on the 12th press. This matches the depletion order already specified when the model was designed.
If can_count is ever set higher than 12 from elsewhere (it shouldn't be, but nothing enforces it), _hide_next_can_visual() just becomes a silent no-op once _can_visuals is empty — no crash, no error spam.
visual_root uses get_node_or_null (not $VisualRoot) so a missing node warns once instead of throwing at _ready() — consistent with this codebase's existing defensive pattern (see FoodCan.gd's _mesh = get_node_or_null("MeshInstance3D")).
Step 4 — Verification (required, do not skip)
Run the project's headless compile check:
tools/godot_check.sh /path/to/Godot_v4.6.3-stable_linux.x86_64
Must pass with zero parse/type errors. This also runs a --headless --import pass, which will generate .import sidecars for the 8 textures if they haven't been opened in-editor yet — confirm no import errors appear for anything under assets/textures/items/can_case/.

Regenerate architecture.json:
python3 tools/gen_architecture.py
Manual in-editor playtest — perform every one of these and report actual results, don't assume:
Open scenes/world/CanCase.tscn directly in the editor once. Confirm no red "broken resource" icons anywhere in the scene tree (this would indicate a texture path typo or the unique_id fix broke parsing — it shouldn't, but verify).
Buy a Can Case from the in-game Shop → Resources category ($60). Confirm it spawns with the real textured cardboard-tray-and-12-cans model (not a plain colored box, not pink/checkerboard missing-texture material).
Place the case on the ground. Walk up, confirm the [E] Take can (12) prompt shows.
Press E once: confirm (a) a FoodCan physically ejects from SpawnPoint, (b) exactly one can (Can_12) disappears from the tray, (c) the prompt now reads [E] Take can (11).
Press E 11 more times (12 total): confirm cans disappear in order Can_12 → Can_11 → ... → Can_01, one per press, and the tray is visually empty (bare cardboard base) after the 12th.
Press E a 13th time: confirm nothing happens — no new can spawns, no error/warning in the console, and get_interact_prompt() returns nothing (no prompt shown).
Pick the case up (F), confirm E does nothing while held (existing base-class behavior), then drop it (F) and confirm it settles normally with physics.
Place 2–4 Can Cases on a Shelving unit — confirm they still stack in the existing 2×2 flat-lay pattern (unaffected by this change, but confirm nothing regressed).
Open the build-mode Shop menu, hover the Can Case row — confirm the 3D preview thumbnail shows the textured model and still hover-spins correctly.
Definition of done
All 3 unique_id values in scenes/world/CanCase.tscn are unquoted integers.
scripts/world/items/CanCase.gd matches Step 3's content exactly, with only the 9 changes listed in the diff summary versus the prior version.
tools/godot_check.sh passes clean.
architecture.json regenerated.
Every bullet in the Step 4 manual playtest checklist completed and reported back with actual observed results (not assumed).
Commit message references both fixes: the unique_id formatting correction and the new visual can-depletion logic.
