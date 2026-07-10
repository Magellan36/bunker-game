extends Node
class_name LightingDirector
## LightingDirector.gd
## Global atmosphere reactor — tints ambient volumetric fog and flips the
## HUD's critical vignette to an alarm color in response to the power grid's
## OVERALL state. Scope is deliberately narrow — see the deviation note below.
##
## ── Deliberate deviation from the original graphics-plan draft ─────────────
## The draft's `_set_practical_lights()` idea (globally dimming every
## Light3D on grid_state_changed) was DROPPED here. WallLight.gd already owns
## per-light energy via set_powered()/set_shed(), driven by PER-ZONE
## reachability — a whole system (cross-zone sustained brownout, upgraded/
## smart breakers, priority shedding) already exists for this, and a zone
## with its own generator correctly stays lit while a different zone is
## TRIPPED. A second, global light-energy multiplier keyed off the single
## overall `grid_state` enum would fight that per-zone system and incorrectly
## dim healthy zones during an unrelated zone's outage. LightingDirector
## therefore only touches things that ARE legitimately global: ambient fog
## tint and the HUD alarm vignette. Do not add a global light-energy
## multiplier here without re-confirming this reasoning first.
##
## Injected by MainWorld._setup_lighting_director() BEFORE add_child():
## world_env, hud_vignette. Same injection pattern PauseMenuUI uses for
## world_node/player.

var world_env:    WorldEnvironment = null
var hud_vignette: ColorRect = null

var _pm: PowerManager = null

const STABLE_FOG_TINT:   Color = Color(0.5, 0.55, 0.6)
const DEGRADED_FOG_TINT: Color = Color(0.4, 0.37, 0.3)
const DARK_FOG_TINT:     Color = Color(0.08, 0.08, 0.1)
const ALARM_VIGNETTE_COLOR:  Color = Color(0.7, 0.05, 0.0, 1.0)
## HUD.gd's own default critical-stat pulse color (vignette.gdshader's
## `vignette_color` uniform default) — restored once the grid is healthy
## again so a resolved power fault doesn't leave the vignette alarm-red
## forever if a survival stat is also critical at the same time.
const NORMAL_VIGNETTE_COLOR: Color = Color(0.6, 0.0, 0.0, 1.0)

const FOG_TWEEN_SECS: float = 2.0


func _ready() -> void:
	_pm = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if _pm != null:
		_pm.grid_state_changed.connect(_on_grid_state_changed)
	else:
		push_warning("[LightingDirector] No PowerManager found in 'power_manager' group")


## PowerManager.grid_state_changed signature confirmed directly against
## PowerManager.gd before writing this (it's GridState enum, NOT String —
## the original graphics-plan draft assumed String and flagged it as
## unconfirmed; this was the Phase 2 groundwork verification step).
func _on_grid_state_changed(new_state: PowerManager.GridState, _old_state: PowerManager.GridState) -> void:
	match new_state:
		PowerManager.GridState.ONLINE:
			_tween_fog_tint(STABLE_FOG_TINT)
			_set_vignette_color(NORMAL_VIGNETTE_COLOR)
		PowerManager.GridState.OVERLOADED, PowerManager.GridState.BROWNOUT:
			_tween_fog_tint(DEGRADED_FOG_TINT.lerp(STABLE_FOG_TINT, 0.5))
			_set_vignette_color(NORMAL_VIGNETTE_COLOR)
		PowerManager.GridState.TRIPPED, PowerManager.GridState.OFFLINE:
			_tween_fog_tint(DARK_FOG_TINT)
			_set_vignette_color(ALARM_VIGNETTE_COLOR)


func _set_vignette_color(color: Color) -> void:
	if hud_vignette == null:
		return
	var mat: ShaderMaterial = hud_vignette.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("vignette_color", color)


func _tween_fog_tint(color: Color) -> void:
	if world_env == null or world_env.environment == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(world_env.environment, "volumetric_fog_albedo", color, FOG_TWEEN_SECS)
