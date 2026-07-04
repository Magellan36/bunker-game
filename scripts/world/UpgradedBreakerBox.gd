extends "res://scripts/world/BreakerBox.gd"
## UpgradedBreakerBox.gd  — v1.0
## "Smart" breaker variant. Inherits 100% of BreakerBox's mesh, wire-snapping,
## registration, and settings-panel mechanics unmodified — this script only
## ADDS the "upgraded" flag registration and a cosmetic accent so it reads as
## a distinct, more expensive object in the world.
##
## BEHAVIOR DIFFERENCE (lives entirely in PowerManager, not here):
## When the shared grid + battery a cross-zone share depends on is fully
## exhausted, PowerManager checks every breaker in the shared component for
## `upgraded == true`.  If found (and untripped + currently passing power),
## THAT breaker self-trips to isolate the two zones — the generator side
## stays powered, only the deficit (load) side goes OFFLINE — instead of the
## standard behavior (both zones sustained-brownout, feeding gens tripped).
## See PowerManager._find_upgraded_breakers_in_component() /
## _self_trip_upgraded_breaker() / the cross-zone branch in
## _evaluate_per_component().
##
## Everything else — trip/reset, pass-through toggles, settings panel, wire
## registration, wall-snapping — is inherited byte-for-byte from BreakerBox.gd.
## Do NOT duplicate any of that logic here; only add on top of it.

# ─── Accent colour — distinguishes the smart breaker visually in-world ───────
## A cool blue-white accent so it reads as "upgraded hardware" next to the
## plain grey/green standard breaker, without touching BreakerBox's palette.
const ACCENT_COLOR: Color = Color(0.25, 0.65, 1.00, 1.0)


func _ready() -> void:
	## Base BreakerBox._ready() builds the mesh, banner, settings panel, and
	## kicks off PM registration (deferred). Run it first, then layer our
	## cosmetic accent on top of the already-built mesh.
	super._ready()
	_add_accent_stripe()


## Registration is deferred in the base class (register_wire_node/register_breaker
## happen inside _register_wire_deferred, called via call_deferred from
## _register_with_pm). We override the SAME deferred entry point so our
## set_breaker_upgraded() call fires immediately after _breaker_id is assigned
## — before the very first _solve_network() the base class triggers, so the
## first solve already sees this breaker as upgraded (no extra re-solve needed,
## though set_breaker_upgraded() safely re-solves again if called after).
func _register_wire_deferred() -> void:
	super._register_wire_deferred()
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm != null and pm.has_method("set_breaker_upgraded") and not _breaker_id.is_empty():
		pm.call("set_breaker_upgraded", _breaker_id, true)
		_wdbg("[UpgradedBreakerBox] marked upgraded: breaker_id=%s" % _breaker_id)


## Cosmetic-only accent stripe down the front panel so the smart breaker is
## visually distinguishable from a standard BreakerBox at a glance. Added as
## an extra child mesh — does not modify any inherited node or material.
func _add_accent_stripe() -> void:
	var stripe_mi:   MeshInstance3D = MeshInstance3D.new()
	var stripe_mesh: BoxMesh        = BoxMesh.new()
	stripe_mesh.size = Vector3(0.045, BOX_SIZE.y * 0.62, 0.028)
	stripe_mi.mesh   = stripe_mesh
	stripe_mi.position = Vector3(
		-(BOX_SIZE.x * 0.5) + 0.05,
		BOX_SIZE.y * 0.5,
		BOX_SIZE.z * 0.5 + 0.016)
	var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
	stripe_mat.albedo_color              = ACCENT_COLOR
	stripe_mat.emission_enabled          = true
	stripe_mat.emission                  = ACCENT_COLOR
	stripe_mat.emission_energy_multiplier = 1.4
	stripe_mat.roughness                 = 0.35
	stripe_mat.metallic                  = 0.65
	stripe_mi.set_surface_override_material(0, stripe_mat)
	add_child(stripe_mi)


## Cosmetic label override — shows "Smart" in the interact prompt so players
## can tell which breaker variant they're looking at before opening the panel.
func get_interact_prompt() -> String:
	return "Smart Breaker Settings [E]"
