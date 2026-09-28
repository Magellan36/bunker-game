extends Light3D
## FlickerLamp.gd (Sep 2026)
## The one warm light on the surface: the lantern on the storage cart by the
## bunker entrance. A gentle waver plus an occasional stutter. Reduced motion
## keeps only the gentle waver. `glow_material` (the lantern glass) brightens
## and dims with the light so the source itself reads as lit.

@export var waver_amount: float = 0.07
@export var waver_speed: float = 2.2
@export var stutter_interval: Vector2 = Vector2(6.0, 15.0)
@export var stutter_depth: float = 0.6
@export var glow_material: StandardMaterial3D

var _base_glow: float = 1.0

var _base_energy: float = 1.0
var _clock: float = 0.0
var _next_stutter: float = 0.0
var _stutter_age: float = -1.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_base_energy = light_energy
	if glow_material != null:
		_base_glow = glow_material.emission_energy_multiplier
	_rng.randomize()
	_noise.frequency = 1.0
	_noise.seed = 3
	_next_stutter = _rng.randf_range(stutter_interval.x, stutter_interval.y)


func _process(delta: float) -> void:
	_clock += delta
	var level := 1.0 + _noise.get_noise_1d(_clock * waver_speed * 10.0) * waver_amount
	if not UIMotion.reduced():
		if _clock >= _next_stutter:
			_stutter_age = 0.0
			_next_stutter = _clock + _rng.randf_range(stutter_interval.x, stutter_interval.y)
		if _stutter_age >= 0.0:
			_stutter_age += delta
			# Two quick dips over ~0.3 s, the second shallower.
			var dip := maxf(sin(_stutter_age * 21.0), 0.0) * exp(-_stutter_age * 6.0)
			level *= 1.0 - dip * stutter_depth
			if _stutter_age > 0.6:
				_stutter_age = -1.0
	light_energy = _base_energy * level
	if glow_material != null:
		glow_material.emission_energy_multiplier = _base_glow * level
