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
const FPS_LIMITS: Array[int] = [30, 60, 120, 144, 0]
const FPS_NAMES: Array[String] = ["30", "60", "120", "144", "UNLIMITED"]
const PIXEL_SCALING: Array[String] = ["fit", "integer"]
const PIXEL_SCALING_NAMES: Array[String] = ["FIT (FILL WINDOW)", "INTEGER (PIXEL PERFECT)"]
const DIFFICULTY_NAMES: Array[String] = ["STORY", "STANDARD", "BRUTAL"]
const AUTOSAVE_NAMES: Array[String] = ["OFF", "EVERY JOB", "EVERY NIGHT"]
## How much the game explains (presentation only; never changes the rules).
const GUIDANCE_NAMES: Array[String] = ["MINIMAL", "STANDARD", "DETAILED"]
## The one player-facing guidance choice (3.9), stored in the existing keys:
## GUIDED = tutorial + gradual sections + cards; BRIEF = gradual sections
## with one-line notices, no tutorial; OFF = everything, no tutorial.
const GUIDANCE_MODE_NAMES: Array[String] = ["GUIDED", "BRIEF", "OFF"]
## Emergency triage countdown multiplier (index = time_pressure; 0 = no countdown).
const TIME_PRESSURE: Array[float] = [1.0, 2.0, 0.0]
const TIME_PRESSURE_NAMES: Array[String] = ["NORMAL", "RELAXED (x2)", "OFF"]
const UI_SCALES: Array[float] = [0.9, 1.0, 1.1]
const UI_SCALE_NAMES: Array[String] = ["SMALL", "NORMAL", "LARGE"]

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
	# Graphics
	"fps_limit": 1,
	"pixel_scaling": "fit",
	"crt_filter": true,
	"scanlines": true,
	"shake_intensity": 1.0,
	"brightness": 1.2,
	"lighting_quality": 2,
	"glow": true,
	"environment_effects": true,
	# Audio
	"dialogue_volume": 0.9,
	"ui_volume": 0.7,
	# Gameplay
	"auto_advance": false,
	"confirm_dangerous": true,
	"tutorial_hints": true,
	"guidance_level": 1,
	"progressive_features": true,
	"controls_setup_done": false,
	"seen_hints": [],
	"tooltips": true,
	"pause_dialogue": true,
	"story_cutscenes": true,
	"pause_focus_loss": true,
	"time_pressure": 0,
	"difficulty": 1,
	"autosave": 1,
	"damage_feedback": true,
	# Accessibility
	"ui_scale": 1,
	"text_scale": 1.0,
	"colorblind": false,
	"reduced_shake": false,
	"reduced_flashing": false,
	"reduced_effects": false,
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
var fps_limit: int = 1
var pixel_scaling: String = "fit"
var crt_filter: bool = true
var scanlines: bool = true
var shake_intensity: float = 1.0
## Shadow lift for the clinic room and street views (1.0 = as drawn).
var brightness: float = 1.2
var lighting_quality: int = 2
var glow: bool = true
var environment_effects: bool = true
var dialogue_volume: float = 0.9
var ui_volume: float = 0.7
var auto_advance: bool = false
var confirm_dangerous: bool = true
var tutorial_hints: bool = true
## 0 MINIMAL (only what needs you), 1 STANDARD, 2 DETAILED (numbers and
## reasons everywhere). Changes what is shown, never the game rules.
var guidance_level: int = 1
## New games introduce clinic sections as they become relevant (Features);
## off shows every section from the start.
var progressive_features: bool = true
## First launch: the main menu offers DEFAULT / CUSTOMIZE controls once.
var controls_setup_done: bool = false
## Learn-as-you-go hints already shown (ids); player knowledge, so it
## lives with the settings, not the save.
var seen_hints: Array = []
var tooltips: bool = true
var pause_dialogue: bool = true
## Short in-engine scenes at chapter changes and big story moments (always
## skippable); off skips them entirely.
var story_cutscenes: bool = true
var pause_focus_loss: bool = true
## Emergency countdowns: 0 normal, 1 relaxed, 2 off (accessibility).
var time_pressure: int = 0
var difficulty: int = 1
var autosave: int = 1
var damage_feedback: bool = true
var ui_scale: int = 1
var text_scale: float = 1.0
var colorblind: bool = false
var reduced_shake: bool = false
var reduced_flashing: bool = false
var reduced_effects: bool = false

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
	time_pressure = clampi(time_pressure, 0, TIME_PRESSURE.size() - 1)
	fps_limit = clampi(fps_limit, 0, FPS_LIMITS.size() - 1)
	if not PIXEL_SCALING.has(pixel_scaling):
		pixel_scaling = "fit"
	shake_intensity = clampf(shake_intensity, 0.0, 1.5)
	brightness = clampf(brightness, 0.8, 1.8)
	lighting_quality = clampi(lighting_quality, 0, 2)
	dialogue_volume = clampf(dialogue_volume, 0.0, 1.0)
	ui_volume = clampf(ui_volume, 0.0, 1.0)
	difficulty = clampi(difficulty, 0, 2)
	guidance_level = clampi(guidance_level, 0, GUIDANCE_NAMES.size() - 1)
	autosave = clampi(autosave, 0, 2)
	# 3.6: the window stretch is the only UI scale (one authority). The old
	# UI SCALE shrank the logical canvas below the 1920x1080 layouts and
	# pushed buttons off-screen; LARGE carries over as bigger text.
	if ui_scale == 2:
		text_scale = maxf(text_scale, 1.1)
	ui_scale = 1
	text_scale = clampf(text_scale, 0.85, 1.4)
	changed.emit()


## A shared material that lifts dark scenes by the brightness setting.
var _room_material: ShaderMaterial


func room_material() -> ShaderMaterial:
	if _room_material == null:
		_room_material = ShaderMaterial.new()
		_room_material.shader = load("res://assets/shaders/room_light.gdshader")
		changed.connect(func() -> void: _room_material.set_shader_parameter(&"lift", brightness))
	_room_material.set_shader_parameter(&"lift", brightness)
	return _room_material


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
## The window mode / size last put on the window: other settings re-apply
## without snapping a resized window back (vsync, filtering...).
var _applied_window: String = ""


func apply_display(force: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var key := "%s|%s" % [window_mode, resolution]
	if not force and key == _applied_window:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		apply_runtime()
		return
	_applied_window = key
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
	apply_runtime()


## Settings that apply without touching the window: frame cap, filtering,
## pixel scaling mode, UI scale.
func apply_runtime() -> void:
	Engine.max_fps = FPS_LIMITS[fps_limit]
	apply_filter()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var root := tree.root
		_apply_stretch(root)
		if not root.size_changed.is_connected(_on_window_resized):
			root.size_changed.connect(_on_window_resized)


## One scaling authority: the 1920x1080 canvas stretched to the window
## (keep aspect). INTEGER only when the window holds a whole multiple of the
## canvas; below that it would crop the screen, so it falls back to FIT.
## No extra content scale factor: every layout is built for the canvas.
func _apply_stretch(root: Window) -> void:
	var win := root.size
	var whole := win.x >= GameConfig.VIEWPORT_WIDTH and win.y >= GameConfig.VIEWPORT_HEIGHT
	var mode := Window.CONTENT_SCALE_STRETCH_INTEGER if pixel_scaling == "integer" and whole else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if root.content_scale_stretch != mode:
		root.content_scale_stretch = mode
	if not is_equal_approx(root.content_scale_factor, 1.0):
		root.content_scale_factor = 1.0


func _on_window_resized() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		_apply_stretch(tree.root)


func apply_filter() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR if texture_filter == "linear" else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST


func shake_allowed() -> bool:
	return screen_shake and not reduce_motion and shake_intensity > 0.0


## Multiplier for every camera shake.
func shake_scale() -> float:
	return shake_intensity * (0.35 if reduced_shake else 1.0)


## Flashes, glitches and strobing lights.
func flashing_allowed() -> bool:
	return not reduced_flashing and not reduce_motion


## Particle / ambient effect level 0..2 (reduced effects forces the minimum).
func effects_level() -> int:
	return 0 if reduced_effects else effects_quality


func crt_enabled() -> bool:
	return crt_filter and not reduced_effects and effects_quality > 0


## Characters per second, or 0 for instant.
func chars_per_second() -> float:
	return TEXT_SPEEDS[text_speed]


func font_bonus() -> int:
	return LARGE_TEXT_BONUS if large_text else 0


## Multiplier for every themed font size (text scale slider).
func font_scale() -> float:
	return text_scale



## Multiplier for real-time emergency countdowns (0 = no countdown).
func time_pressure_mult() -> float:
	return TIME_PRESSURE[clampi(time_pressure, 0, TIME_PRESSURE.size() - 1)]


func is_minimal() -> bool:
	return guidance_level == 0


func is_detailed() -> bool:
	return guidance_level >= 2


func guidance_mode() -> int:
	if not progressive_features:
		return 2
	if not tutorial_hints or guidance_level == 0:
		return 1
	return 0


func set_guidance_mode(mode: int) -> void:
	match mode:
		0:
			set_value("tutorial_hints", true)
			set_value("progressive_features", true)
			set_value("guidance_level", 1)
		1:
			set_value("tutorial_hints", false)
			set_value("progressive_features", true)
			set_value("guidance_level", 0)
		_:
			set_value("tutorial_hints", false)
			set_value("progressive_features", false)
			set_value("guidance_level", 0)
