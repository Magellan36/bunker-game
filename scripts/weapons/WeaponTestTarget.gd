extends StaticBody3D
## Opt-in damage receiver for the weapon test room. Never alters NPC health.
var total_damage: float = 0.0
var hits: int = 0
var _label: Label3D

func _ready() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.8, 0.35)
	collision.shape = shape
	add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.22, 0.10)
	mesh.material_override = material
	add_child(mesh)
	_label = Label3D.new()
	_label.position.y = 1.2
	_label.font_size = 32
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.text = "Target"
	add_child(_label)

func receive_weapon_hit(context: Dictionary) -> void:
	total_damage += float(context.damage)
	hits += 1
	_label.text = "%d hits · %d damage" % [hits, int(total_damage)]
