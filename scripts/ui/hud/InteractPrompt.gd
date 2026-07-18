extends CanvasLayer
## InteractPrompt.gd
## Renders floating world-space prompt panels anchored to 3D positions.
##
## ARCHITECTURE (rewritten v64):
##   - Single source of truth: _active[] array set each frame by the caller
##   - Panel pool grows on demand, never shrinks (avoids alloc/free per frame)
##   - ALL visibility, position, alpha, and text updates happen in ONE place: _process()
##   - set_prompts() ONLY updates _active[]. _process() does all rendering.
##   - This eliminates the race between set_prompts() hiding panels and _process()
##     showing them, which caused the flicker/not-appearing bug.
##


# ─── Template panel ───────────────────────────────────────────────────────────
@onready var _template_panel: PanelContainer = $Panel
@onready var _template_label: RichTextLabel  = $Panel/Label

## Vertical world-space offset so the panel floats above the object origin
const WORLD_OFFSET: Vector3 = Vector3(0.0, 1.2, 0.0)

## Fade band: fully opaque [0 .. FADE_START], linear fade [FADE_START .. FADE_END]
## FADE_END must match InteractionSystem.MAX_PROMPT_DIST so alpha hits 0
## exactly when the distance cap removes the entry.
const FADE_START: float = 2.2
const FADE_END:   float = 3.2

# ─── State ────────────────────────────────────────────────────────────────────
## What the caller wants shown this frame.
## Array of { text: String, world_pos: Vector3, dist: float }
var _active: Array = []

## Pool of PanelContainers. Index matches _active[]. Grows, never shrinks.
var _pool: Array = []   ## Array[PanelContainer]

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_template_panel.visible = false

func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	# ── No camera — hide everything ──────────────────────────────────────────
	if camera == null:
		for p: PanelContainer in _pool:
			p.visible = false
		return

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < _active.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)

	# ── Update active panels ──────────────────────────────────────────────────
	for i: int in _active.size():
		var entry: Dictionary    = _active[i]
		var p: PanelContainer    = _pool[i] as PanelContainer
		var world_pos: Vector3   = entry["world_pos"] + WORLD_OFFSET

		# Behind camera check
		if camera.is_position_behind(world_pos):
			p.visible = false
			continue

		# Compute screen position
		p.reset_size()
		var screen_pos: Vector2 = camera.unproject_position(world_pos)

		# Distance-based alpha
		var dist: float  = entry.get("dist", 0.0)
		var alpha: float = 1.0
		if dist > FADE_START:
			alpha = clampf(1.0 - (dist - FADE_START) / (FADE_END - FADE_START), 0.0, 1.0)

		# Update text
		var lbl: RichTextLabel = p.get_node_or_null("Label") as RichTextLabel
		var txt: String = entry.get("text", "")
		if lbl != null and lbl.text != txt:
			lbl.text = txt

		# Apply — order matters: set text → reset_size → position → modulate → visible
		p.reset_size()
		p.position  = screen_pos - p.size / 2.0
		p.modulate  = Color(1.0, 1.0, 1.0, alpha)
		p.visible   = true

	# ── Hide surplus pool panels ──────────────────────────────────────────────
	for i: int in range(_active.size(), _pool.size()):
		var p: PanelContainer = _pool[i] as PanelContainer
		if p.visible:
			p.visible = false

# ─── Public API ───────────────────────────────────────────────────────────────
## Primary API — call every frame from InteractionSystem._update_prompt().
## Pass an Array of { "text": String, "world_pos": Vector3, "dist": float }
## Pass [] to hide all panels.
func set_prompts(new_entries: Array) -> void:
	_active = new_entries

func show_prompt(text: String, world_position: Vector3) -> void:
	set_prompts([{ "text": text, "world_pos": world_position, "dist": 0.0 }])

func hide_prompt() -> void:
	set_prompts([])
