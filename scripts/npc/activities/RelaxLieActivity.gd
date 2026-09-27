extends LieActivity
class_name RelaxLieActivity
## RelaxLieActivity.gd — RelaxActivity's bed option: lie down on a bed for a
## break (awake, reduced regen). All behaviour lives in LieActivity's
## relax_mode; the owning RelaxActivity's session timer ends it.

func _init() -> void:
	relax_mode = true
