extends Node
## LightningStorm.gd (Sep 2026)
## In-cloud (sheet) lightning for the main-menu surface view. No bolt artwork:
## a strike is a light pulse from behind the skyline, a brief lift of the sky
## and ambient energy, an auto-exposure dip afterwards (the "surface camera"
## re-exposing), then thunder delayed by the strike's distance.
##
## Photosensitivity: pulses are spaced >= MIN_PULSE_GAP so no strike exceeds
## three flashes in any one second (WCAG 2.3.1). With reduced motion enabled a
## strike is a single slow swell at reduced brightness.
##
## Audio is optional. Assign thunder recordings to `thunder_streams`; with none
## assigned the storm is silent but otherwise identical.

signal struck(distance_km: float)

const MIN_PULSE_GAP: float = 0.34
const ATTACK: float = 0.035
const REDUCED_ATTACK: float = 0.32

@export var world_environment: WorldEnvironment
@export var flash_light: DirectionalLight3D
@export var thunder_streams: Array[AudioStream] = []
@export var audio_bus: StringName = &"Master"
@export var enabled: bool = true
@export var first_strike_delay: float = 4.5
## Seconds between strikes (min, max).
@export var interval_range: Vector2 = Vector2(7.0, 17.0)
## Strike distance in km (min, max); closer is brighter and louder.
@export var distance_range_km: Vector2 = Vector2(0.9, 7.0)
## Compass range (degrees about +Y) strikes come from. Default: behind the
## right-hand skyline, where the menu composition wants the drama.
@export var azimuth_range_deg: Vector2 = Vector2(-55.0, 20.0)
@export var light_flash_energy: float = 5.0
@export var sky_flash_energy: float = 3.0
@export var ambient_flash_energy: float = 0.9
## Depth fog dominates the overcast sky, so it has to flash too.
@export var fog_flash_energy: float = 2.5
## How far exposure dips after a strike (0 disables the re-expose effect).
@export var exposure_dip: float = 0.28
## Real thunder travels ~2.9 s per km; this compresses it for the menu.
@export var sound_delay_scale: float = 0.4
@export var thunder_volume_db: Vector2 = Vector2(0.0, -14.0)

## Current flash brightness, 0..1+. Read by the UI to react to strikes.
var intensity: float = 0.0

var _env: Environment
var _clock: float = 0.0
var _next_strike: float = 0.0
var _pulses: Array[Dictionary] = []
var _exposure_debt: float = 0.0
var _base_background: float = 1.0
var _base_ambient: float = 0.5
var _base_exposure: float = 1.0
var _base_fog_light: float = 1.0
var _players: Array[AudioStreamPlayer] = []
var _last_stream: int = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if world_environment != null and world_environment.environment != null:
		_env = world_environment.environment
		_base_background = _env.background_energy_multiplier
		_base_ambient = _env.ambient_light_energy
		_base_exposure = _env.tonemap_exposure
		_base_fog_light = _env.fog_light_energy
	if flash_light != null:
		flash_light.light_energy = 0.0
		flash_light.visible = false
	for i: int in range(3):
		var player := AudioStreamPlayer.new()
		player.bus = audio_bus
		add_child(player)
		_players.append(player)
	_next_strike = first_strike_delay


## Fires a strike now. distance_km < 0 picks a random distance.
func trigger(distance_km: float = -1.0) -> void:
	if distance_km < 0.0:
		distance_km = _rng.randf_range(distance_range_km.x, distance_range_km.y)
	var span := maxf(distance_range_km.y - distance_range_km.x, 0.01)
	var nearness := 1.0 - clampf((distance_km - distance_range_km.x) / span, 0.0, 1.0)
	var strength := lerpf(0.3, 1.0, nearness)
	if flash_light != null:
		flash_light.rotation_degrees = Vector3(_rng.randf_range(-34.0, -10.0),
			_rng.randf_range(azimuth_range_deg.x, azimuth_range_deg.y) + 180.0, 0.0)
	if UIMotion.reduced():
		_add_pulse(0.0, strength * 0.45, 2.4, REDUCED_ATTACK)
	else:
		_add_pulse(0.0, strength, 8.5, ATTACK)
		var restrokes := _rng.randi_range(0, 2)
		var at := 0.0
		for i: int in range(restrokes):
			at += _rng.randf_range(MIN_PULSE_GAP, MIN_PULSE_GAP + 0.18)
			_add_pulse(at, strength * _rng.randf_range(0.4, 0.8), 11.0, ATTACK)
	var delay := distance_km * 2.915 * sound_delay_scale
	get_tree().create_timer(delay, false).timeout.connect(_play_thunder.bind(nearness))
	struck.emit(distance_km)


func _process(delta: float) -> void:
	_clock += delta
	if enabled and _clock >= _next_strike:
		trigger()
		_next_strike = _clock + _rng.randf_range(interval_range.x, interval_range.y)
	intensity = _evaluate()
	_exposure_debt = maxf(_exposure_debt - delta * 0.45, intensity)
	_apply()


func _add_pulse(offset: float, peak: float, decay: float, attack: float) -> void:
	_pulses.append({"start": _clock + offset, "peak": peak, "decay": decay, "attack": attack})


func _evaluate() -> float:
	var value := 0.0
	var i := _pulses.size() - 1
	while i >= 0:
		var pulse: Dictionary = _pulses[i]
		var age: float = _clock - float(pulse["start"])
		var attack: float = pulse["attack"]
		var level := 0.0
		if age >= 0.0:
			if age < attack:
				level = float(pulse["peak"]) * age / attack
			else:
				level = float(pulse["peak"]) * exp(-(age - attack) * float(pulse["decay"]))
				if level < 0.002:
					_pulses.remove_at(i)
		value = maxf(value, level)
		i -= 1
	return value


func _apply() -> void:
	if flash_light != null:
		flash_light.light_energy = intensity * light_flash_energy
		flash_light.visible = intensity > 0.003
	if _env == null:
		return
	_env.background_energy_multiplier = _base_background * (1.0 + intensity * sky_flash_energy)
	_env.ambient_light_energy = _base_ambient + intensity * ambient_flash_energy
	_env.fog_light_energy = _base_fog_light * (1.0 + intensity * fog_flash_energy)
	_env.tonemap_exposure = _base_exposure * (1.0 - clampf(_exposure_debt, 0.0, 1.0) * exposure_dip * 0.5)


func _play_thunder(nearness: float) -> void:
	if thunder_streams.is_empty():
		return
	var index := _rng.randi_range(0, thunder_streams.size() - 1)
	if thunder_streams.size() > 1 and index == _last_stream:
		index = (index + 1) % thunder_streams.size()
	_last_stream = index
	var stream := thunder_streams[index]
	if stream == null:
		return
	var player := _players[0]
	for candidate: AudioStreamPlayer in _players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = stream
	player.volume_db = lerpf(thunder_volume_db.y, thunder_volume_db.x, nearness)
	# Distant thunder is a lower, softer rumble.
	player.pitch_scale = lerpf(0.84, 1.03, nearness) * _rng.randf_range(0.97, 1.03)
	player.play()
