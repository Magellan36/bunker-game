extends PickupableItem
class_name TrashBag
## TrashBag.gd
## Runtime-only pickupable object — no construct-menu entry, no tile ID,
## created exclusively by TrashCan._empty_into_bag(). "Heavier object" per
## design: deliberately NOT added to the "inventory_item" group (can't go
## in pocket inventory, Dresser, End Table, or a Trash Can), but IS
## shelf-storable (stack limit 1), same class of exception as TestCrate/
## CanCase/WaterCase.
##
## contents is a full structured snapshot of everything that was thrown
## away, captured by TrashCan.extract_trash_record() at the moment the bag
## was created — see that function's doc comment for exactly what's
## captured. This is the data future trash/recycling features will read;
## keep this field's shape stable once other systems start consuming it.

var shelf_stack_limit: int  = 1
var shelf_item_type: String = "trash_bag"

var contents: Array[Dictionary] = []

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	_build_placeholder_mesh()

func get_display_name() -> String:
	return "Trash Bag (%d)" % contents.size()

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % get_display_name()

## Basic model per design direction — plain black sphere for now.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	_mesh.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.04, 0.04, 1.0)
	mat.roughness = 0.9
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Procedural collision — this object has no .tscn (see PickupableItem.gd's
	## own doc comment: subclasses add CollisionShape3D after super._ready(),
	## exactly the supported pattern for a pure-script item like this one).
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.22
	col.shape = shape
	add_child(col)