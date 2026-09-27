class_name UIMotion
extends RefCounted
## Presentation-only timings and device preference; no gameplay save/autoload.
const ENTER: float = 0.16
const EXIT: float = 0.10
const CONTENT: float = 0.13
const FEEDBACK: float = 0.08
const SCROLL: float = 0.10
const RESPONSE: float = 10.0
const CONFIG_PATH: String = "user://ui_preferences.cfg"
static var _loaded: bool = false
static var _reduced: bool = false

static func reduced() -> bool:
	if not _loaded:
		var config: ConfigFile = ConfigFile.new()
		if config.load(CONFIG_PATH) == OK:
			_reduced = config.get_value("accessibility", "reduced_motion", false) == true
		_loaded = true
	return _reduced

static func set_reduced(enabled: bool) -> Error:
	_loaded = true
	_reduced = enabled
	var config: ConfigFile = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("accessibility", "reduced_motion", enabled)
	return config.save(CONFIG_PATH)

static func duration(seconds: float) -> float:
	return 0.0 if reduced() else seconds

static func weight(delta: float, response: float = RESPONSE) -> float:
	return 1.0 if reduced() else 1.0 - exp(-response * delta)
