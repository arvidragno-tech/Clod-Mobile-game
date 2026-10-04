extends Node
## Player preferences, stored separately from the game saves
## (user://settings.cfg, i.e. %APPDATA%/UndercityRipper on Windows) so
## starting a new game never resets them.
## Every consumer reads the values here; `changed` fires after any edit.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
## Characters per second for typewriter text (index = text_speed).
const TEXT_SPEEDS: Array[float] = [28.0, 55.0, 110.0, 0.0]
const TEXT_SPEED_NAMES: Array[String] = ["SLOW", "NORMAL", "FAST", "INSTANT"]
## Extra font size (UI units) applied by "Large text".
const LARGE_TEXT_BONUS := 2

## Windowed sizes offered in Graphics (16:9; 1920x1080 is the design size).
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 720)]
const WINDOW_MODES: Array[String] = ["windowed", "borderless", "fullscreen"]
const WINDOW_MODE_NAMES: Array[String] = ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
const EFFECTS_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]

const DEFAULTS := {
	"master_volume": 0.9,
	"window_mode": "windowed",
	"resolution": "1600x900",
	"vsync": true,
	"texture_filter": "nearest",
	"effects_quality": 2,
	"mouse_sensitivity": 1.0,
	"bindings": {},
	"last_slot": 1,
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

var master_volume: float = 0.9
var window_mode: String = "windowed"
var resolution: String = "1600x900"
var vsync: bool = true
var texture_filter: String = "nearest"
var effects_quality: int = 2
var mouse_sensitivity: float = 1.0
var bindings: Dictionary = {}
var last_slot: int = 1
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
	master_volume = clampf(master_volume, 0.0, 1.0)
	mouse_sensitivity = clampf(mouse_sensitivity, 0.25, 3.0)
	effects_quality = clampi(effects_quality, 0, 2)
	last_slot = clampi(last_slot, 1, 3)
	if not WINDOW_MODES.has(window_mode):
		window_mode = "windowed"
	if parse_resolution(resolution) == Vector2i.ZERO:
		resolution = DEFAULTS["resolution"]
	if texture_filter != "nearest" and texture_filter != "linear":
		texture_filter = "nearest"
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


static func parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## Applies window mode, windowed size, vsync and texture filtering. The
## logical canvas stays 1920x1080 (canvas_items stretch, keep aspect), so
## other 16:9 sizes scale uniformly and other aspects letterbox.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var size := parse_resolution(resolution)
			var screen := DisplayServer.screen_get_usable_rect()
			if screen.size.x > 0:
				size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
			DisplayServer.window_set_size(size)
			if screen.size.x > 0:
				DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	apply_filter()


func apply_filter() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR if texture_filter == "linear" else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST


func shake_allowed() -> bool:
	return screen_shake and not reduce_motion


## Characters per second, or 0 for instant.
func chars_per_second() -> float:
	return TEXT_SPEEDS[text_speed]


func font_bonus() -> int:
	return LARGE_TEXT_BONUS if large_text else 0
