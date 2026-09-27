extends Node
## WindAmbience.gd (Sep 2026)
## Surface wind for the main menu: a continuous "rushing" bed plus an optional
## howl layer that swells with gusts. `gust` (0..1) is a slow noise signal that
## also drives ash particle speed, so the sound and the picture move together.
## Both streams are optional; without them the gust signal still runs.

@export var bed_stream: AudioStream
@export var gust_stream: AudioStream
@export var audio_bus: StringName = &"Master"
@export var bed_volume_db: float = -9.0
@export var gust_volume_db: float = -7.0
## Gusts per second, roughly. Lower is lazier.
@export var gust_frequency: float = 0.05
@export var fade_in_seconds: float = 3.5
## Particle systems whose speed follows the gusts.
@export var particles: Array[GPUParticles3D] = []
@export var particle_speed_range: Vector2 = Vector2(0.6, 1.7)

## Current gust strength, 0..1.
var gust: float = 0.0

var _gain: float = 0.0
var _gain_tween: Tween
var _clock: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _bed: AudioStreamPlayer
var _howl: AudioStreamPlayer


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 31
	_bed = _make_player(bed_stream)
	_howl = _make_player(gust_stream)
	fade_to(1.0, fade_in_seconds)


## Fades the whole wind mix to `gain` (0..1) over `seconds`.
func fade_to(gain: float, seconds: float) -> void:
	if is_instance_valid(_gain_tween):
		_gain_tween.kill()
	_gain_tween = create_tween()
	_gain_tween.tween_property(self, "_gain", clampf(gain, 0.0, 1.0), maxf(seconds, 0.01))


func _process(delta: float) -> void:
	_clock += delta
	# Two octaves: a slow swell and a quicker flutter riding on it.
	var swell := _noise.get_noise_1d(_clock * gust_frequency * 10.0)
	var flutter := _noise.get_noise_1d(_clock * gust_frequency * 55.0 + 300.0)
	gust = clampf(0.5 + swell * 0.75 + flutter * 0.2, 0.0, 1.0)
	if _bed != null:
		_bed.volume_db = bed_volume_db + linear_to_db(maxf(_gain, 0.0001)) + gust * 4.0
		_bed.pitch_scale = 0.94 + gust * 0.1
	if _howl != null:
		var howl := pow(gust, 2.2) * _gain
		_howl.volume_db = gust_volume_db + linear_to_db(maxf(howl, 0.0001))
	for system: GPUParticles3D in particles:
		if system != null:
			system.speed_scale = lerpf(particle_speed_range.x, particle_speed_range.y, gust)


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	if stream == null:
		return null
	if "loop" in stream:
		stream.set("loop", true)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = audio_bus
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player
