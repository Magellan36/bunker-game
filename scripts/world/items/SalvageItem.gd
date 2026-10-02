extends PickupableItem
class_name SalvageItem
## SalvageItem.gd (Oct 2026)
## What a demolished object leaves behind after the bunker is sealed (see
## BuildEconomy.drop_salvage). One sphere per material, carrying a count of
## Research Station units. Pick it up, carry it to the station's chute and
## press F: the chute takes as many units as it has room for and the rest
## stays in the sphere (ResearchStation._feed_salvage).
##
## PLACEHOLDER VISUAL: a plain tinted sphere sized by its count, per
## Brannon's "formless spheres for right now". Replace with real salvage
## models when they exist (tracked in docs/systems/phase/README.md).

const MATERIAL_TINTS: Dictionary = {
	"metal":   Color(0.56, 0.58, 0.60),
	"plastic": Color(0.72, 0.76, 0.70),
	"paper":   Color(0.78, 0.71, 0.56),
	"organic": Color(0.46, 0.38, 0.26),
}

var salvage_material: String = "metal"
var salvage_units: int = 1

var _mesh: MeshInstance3D = null
var _shape: CollisionShape3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	mass = 0.4
	super._ready()
	add_to_group("inventory_item")
	add_to_group("salvage")
	_build_placeholder_mesh()


func get_display_name() -> String:
	return "%d %s" % [salvage_units, salvage_material.capitalize()]

func get_prompt_text() -> String:
	return "[F] Pick up  Salvage · %s" % get_display_name()

## The chute and Trash Bag both read this (see ResearchStation).
func get_trash_material() -> String:
	return salvage_material

func get_salvage_units() -> int:
	return salvage_units

## Called by the chute after a partial feed.
func set_salvage_units(units: int) -> void:
	salvage_units = maxi(1, units)
	_resize()


# ─── Save/Load ────────────────────────────────────────────────────────────
func get_item_save_state() -> Dictionary:
	return {"material": salvage_material, "units": salvage_units}

func apply_item_save_state(state: Dictionary) -> void:
	salvage_material = String(state.get("material", salvage_material))
	salvage_units = maxi(1, int(state.get("units", salvage_units)))


# ─── Visual ───────────────────────────────────────────────────────────────
func _radius() -> float:
	return clampf(0.10 + 0.022 * float(salvage_units - 1), 0.10, 0.20)

func _build_placeholder_mesh() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = MATERIAL_TINTS.get(salvage_material, MATERIAL_TINTS["metal"])
	_material.roughness = 0.45 if salvage_material == "metal" else 0.85
	_material.metallic = 0.55 if salvage_material == "metal" else 0.0
	_mesh = MeshInstance3D.new()
	_mesh.name = "SalvageMesh"
	_mesh.material_override = _material
	add_child(_mesh)
	_shape = CollisionShape3D.new()
	_shape.name = "SalvageShape"
	add_child(_shape)
	_resize()

func _resize() -> void:
	if _mesh == null or _shape == null:
		return
	var r: float = _radius()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, r, 0.0)
	var col := SphereShape3D.new()
	col.radius = r
	_shape.shape = col
	_shape.position = _mesh.position
