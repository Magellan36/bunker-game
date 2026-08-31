extends Control
class_name StatusEffectsContainer
## StatusEffectsContainer.gd
## ─────────────────────────────────────────────────────────────────────────────
## Holds active StatusEffectIcon badges in one of two layouts, chosen PER
## NODE INSTANCE via `vertical_stack_mode` (set in the scene, not per-item)
## — ordinary and medical effects live in two entirely separate container
## instances in HUD.tscn (HUDRoot/StatusEffects and HUDRoot/MedicalEffects
## respectively), not one shared node juggling two layouts:
##
##   - vertical_stack_mode = false (default) — the ORIGINAL fixed,
##     hand-placed staggered-triangle layout that mirrors Brannon's
##     Medieval Dynasty reference screenshot (top badge = oldest active
##     effect, each newer one takes the next slot down/out). Used by
##     HUDRoot/StatusEffects. See SLOT_OFFSETS below.
##
##   - vertical_stack_mode = true (Aug 2026, Pass 1) — badges zig-zag
##     vertically UPWARD from this container's own bottom edge, using the
##     same staggered X alternation as the triangle below, but continued
##     INDEFINITELY (not just for the first 3) since medical conditions
##     can realistically stack much deeper than ordinary status effects
##     ever do — oldest closest to the bottom (index 0), each additional
##     one further up. Used by HUDRoot/MedicalEffects, which HUD.tscn
##     positions directly above the needs-gauge/HUD row, left-aligned to
##     it — see that node's own offsets in HUD.tscn for the actual screen
##     placement; this script only handles the WITHIN-container stacking,
##     not where the container itself sits.
##
## No cap on how many effects can be active in either mode. No placeholder
## is drawn for empty slots (Brannon's explicit call) — an empty slot is
## simply the absence of a child node there.
##
## Usage (ordinary, HUDRoot/StatusEffects):
##     var hud: Node = get_tree().get_first_node_in_group("hud")
##     if hud != null and ("status_effects" in hud):
##         var se: StatusEffectsContainer = hud.get("status_effects") as StatusEffectsContainer
##         se.add_effect("poisoned", null, 12.0, Color(0.85, 0.3, 0.2))
##         se.remove_effect("poisoned")   # early removal, e.g. cured
##
## Usage (medical, HUDRoot/MedicalEffects) — see PlayerMedical.gd for the
## real caller:
##     var me: StatusEffectsContainer = hud.get("medical_effects") as StatusEffectsContainer
##     me.add_medical_effect("open_wound_2", null, Color(0.55, 0.16, 0.14), true)
##     me.update_medical_effect("open_wound_2", 1.0, 0.4, "Open Wound (Left Arm)")
##     me.remove_effect("open_wound_2")   # same removal path as ordinary effects

## Whether this container uses the vertical medical stack instead of the
## triangle. Auto-detected from this node's own name in _ready() rather
## than set via the Inspector/@export — the Godot MCP's node-modify tool
## can't reach custom GDScript @export properties on this node type (only
## base Control properties), so name-based detection sidesteps that
## entirely rather than fighting it. HUDRoot/MedicalEffects in HUD.tscn is
## the trigger name; any other name (e.g. HUDRoot/StatusEffects) keeps the
## original triangle layout.
var vertical_stack_mode: bool = false

func _ready() -> void:
	if name == "MedicalEffects":
		vertical_stack_mode = true

const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(20.0, 0.0),     ## slot 0 — top (oldest). X anchors the shared column.
	Vector2(7.5, 56.0),     ## slot 1 — middle, shifted LEFT of the shared column
	                         ##          by 25% of a badge's width (50 * 0.25 = 12.5,
	                         ##          20.0 - 12.5 = 7.5). Jul 2026 fix.
	Vector2(20.0, 112.0),   ## slot 2 — bottom. X now MATCHES slot 0 exactly
	                         ##          (Jul 2026 fix — was 4.0, off by 16px).
]
const FALLBACK_SPACING: float = 56.0   ## slot index 3+, straight down from slot 2

## Vertical-stack-mode layout (Aug 2026). Reuses SLOT_OFFSETS' exact X/Y
## magnitudes — the same zig-zag stagger the ordinary triangle uses (slot
## 1 shifted 12.5px left of the slot 0/2 column) — just measured UPWARD
## from an anchor point instead of downward from one, per Brannon's "-90°
## rotation of the ordinary layout" direction. MARGIN_BOTTOM places that
## anchor so the first (oldest, index 0) badge's bottom edge sits flush
## with this container's own bottom edge, which HUD.tscn positions
## directly above the needs-gauge/HUD row — so index 0 ends up right
## above the HUD, zig-zagging further up from there exactly like the
## ordinary triangle zig-zags further out.
const VERTICAL_STACK_MARGIN_BOTTOM: float = 56.0

var _order: Array[String] = []          ## effect ids, oldest first
var _badges: Dictionary = {}            ## effect_id (String) -> StatusEffectIcon

## Adds a new badge, or restarts an existing one in place with the same id
## (re-applying a still-active effect refreshes its duration instead of
## stacking a duplicate badge / changing its slot). Timer mode.
func add_effect(id: String, icon: Texture2D, duration: float, ring_color: Color) -> void:
	if _badges.has(id) and is_instance_valid(_badges[id]):
		(_badges[id] as StatusEffectIcon).setup(id, icon, duration, ring_color)
		return
	var badge: StatusEffectIcon = StatusEffectIcon.new()
	add_child(badge)
	badge.expired.connect(_on_badge_expired)
	badge.setup(id, icon, duration, ring_color)
	_badges[id] = badge
	_order.append(id)
	_reflow()

## Medical-mode counterpart to add_effect() (Aug 2026, Pass 1) — see
## StatusEffectIcon.gd's class doc and docs/systems/medical/README.md.
## No duration/countdown; PlayerMedical/NPCMedical drive the ring every
## tick via update_medical_effect(). `id` should be unique per
## condition+body-part (e.g. "open_wound_LEFT_ARM") so multiple
## simultaneous wounds each get their own badge, per the design doc's
## "multiple simultaneous icons are intentional." Re-adding an id that's
## already active re-configures that badge in place rather than
## duplicating it, same as add_effect(). Intended for use on a container
## with vertical_stack_mode = true, but not enforced here — the mode only
## affects _reflow()'s layout math, not which add_* method is "allowed."
func add_medical_effect(id: String, icon: Texture2D, ring_color: Color, has_heal_ring: bool) -> void:
	if _badges.has(id) and is_instance_valid(_badges[id]):
		(_badges[id] as StatusEffectIcon).setup_medical(id, icon, ring_color, has_heal_ring)
		return
	var badge: StatusEffectIcon = StatusEffectIcon.new()
	add_child(badge)
	badge.expired.connect(_on_badge_expired)   ## unused in medical mode, connected for consistency
	badge.setup_medical(id, icon, ring_color, has_heal_ring)
	_badges[id] = badge
	_order.append(id)
	_reflow()

## Updates a medical badge's fill fractions + hover tooltip. No-op if `id`
## isn't currently active (e.g. it resolved/was removed the same frame a
## stale update was queued) — callers don't need to guard this themselves.
func update_medical_effect(id: String, severity_frac: float, heal_frac: float, tooltip: String) -> void:
	if not _badges.has(id) or not is_instance_valid(_badges[id]):
		return
	(_badges[id] as StatusEffectIcon).update_medical(severity_frac, heal_frac, tooltip)

## Sets/clears a medical badge's separate outer ring (Aug 2026, Pass 2 —
## currently Infection severity on an infected Open Wound). No-op if `id`
## isn't currently active, same as update_medical_effect().
func update_medical_outer_ring(id: String, has_outer: bool, frac: float, color: Color) -> void:
	if not _badges.has(id) or not is_instance_valid(_badges[id]):
		return
	(_badges[id] as StatusEffectIcon).set_outer_ring(has_outer, frac, color)

## Removes a badge early (e.g. the effect was cured before its timer ran
## out, or a medical condition resolved). Safe to call with an id that
## isn't currently active (no-op).
func remove_effect(id: String) -> void:
	if not _badges.has(id):
		return
	var badge: StatusEffectIcon = _badges[id]
	_badges.erase(id)
	_order.erase(id)
	if is_instance_valid(badge):
		badge.queue_free()
	_reflow()

func _on_badge_expired(id: String) -> void:
	remove_effect(id)

## Repositions every active badge according to its current index in
## `_order` (0 = oldest). Called after every add/remove so the remaining
## badges always slide into the earlier slots. Layout picked per this
## instance's vertical_stack_mode.
func _reflow() -> void:
	for i in range(_order.size()):
		var badge: StatusEffectIcon = _badges[_order[i]]
		if not is_instance_valid(badge):
			continue
		badge.position = _stack_position(i) if vertical_stack_mode else _slot_position(i)

func _slot_position(index: int) -> Vector2:
	if index < SLOT_OFFSETS.size():
		return SLOT_OFFSETS[index]
	var last: Vector2 = SLOT_OFFSETS[SLOT_OFFSETS.size() - 1]
	var extra: int = index - (SLOT_OFFSETS.size() - 1)
	return Vector2(last.x, last.y + FALLBACK_SPACING * float(extra))

## Vertical-stack-mode layout — continues the SAME zig-zag alternation
## (SLOT_OFFSETS[0]/[1]'s X values, 20.0/7.5) indefinitely rather than
## falling back to a straight line after 3 badges like the ordinary
## triangle does. Medical conditions can realistically stack much deeper
## than ordinary status effects ever do (multiple wounds after a fight,
## 10+ simultaneous conditions), so the zig-zag needs to keep going for as
## many badges as are actually active — built upward from an anchor point
## instead of downward. See the VERTICAL_STACK_MARGIN_BOTTOM comment above
## for where that anchor comes from.
func _stack_position(index: int) -> Vector2:
	var anchor_y: float = size.y - VERTICAL_STACK_MARGIN_BOTTOM
	var x: float = SLOT_OFFSETS[0].x if index % 2 == 0 else SLOT_OFFSETS[1].x
	var y: float = anchor_y - FALLBACK_SPACING * float(index)
	return Vector2(x, y)
