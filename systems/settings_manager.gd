extends Node
## Player preferences, stored separately from the game save
## (user://settings.cfg) so starting a new game never resets them.
## Every consumer reads the values here; `changed` fires after any edit.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
## Characters per second for typewriter text (index = text_speed).
const TEXT_SPEEDS: Array[float] = [28.0, 55.0, 110.0, 0.0]
const TEXT_SPEED_NAMES: Array[String] = ["SLOW", "NORMAL", "FAST", "INSTANT"]
## Extra font size (UI units) applied by "Large text".
const LARGE_TEXT_BONUS := 2

const DEFAULTS := {
	"music_volume": 0.6,
	"ambience_volume": 0.8,
	"sfx_volume": 0.9,
	"haptics": true,
	"screen_shake": true,
	"text_speed": 1,
	"large_text": false,
	"high_contrast": false,
	"reduce_motion": false,
}

var music_volume: float = 0.6
var ambience_volume: float = 0.8
var sfx_volume: float = 0.9
var haptics: bool = true
var screen_shake: bool = true
var text_speed: int = 1
var large_text: bool = false
var high_contrast: bool = false
var reduce_motion: bool = false

var path: String = PATH


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	for key: String in DEFAULTS:
		var v: Variant = cfg.get_value(SECTION, key, DEFAULTS[key]) if err == OK else DEFAULTS[key]
		# Guard against hand-edited / corrupt values of the wrong type.
		if typeof(v) != typeof(DEFAULTS[key]) and not (typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
			v = DEFAULTS[key]
		set(key, v)
	music_volume = clampf(music_volume, 0.0, 1.0)
	ambience_volume = clampf(ambience_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	text_speed = clampi(text_speed, 0, TEXT_SPEEDS.size() - 1)
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in DEFAULTS:
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(path)
	if err != OK:
		push_warning("Settings: cannot save (%s)" % error_string(err))


## Sets one value, persists and notifies.
func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	set(key, value)
	save_settings()
	changed.emit()


func reset_to_defaults() -> void:
	for key: String in DEFAULTS:
		set(key, DEFAULTS[key])
	save_settings()
	changed.emit()


func shake_allowed() -> bool:
	return screen_shake and not reduce_motion


## Characters per second, or 0 for instant.
func chars_per_second() -> float:
	return TEXT_SPEEDS[text_speed]


func font_bonus() -> int:
	return LARGE_TEXT_BONUS if large_text else 0
