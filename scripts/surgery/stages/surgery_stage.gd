class_name SurgeryStage
extends Control
## Base class for one interactive surgery step. A stage:
##  - reads its tuning from SurgeryStageData.params,
##  - mutates the shared SurgicalSiteView to show what the player did,
##  - reports mistakes / effects / juice via signals (it never talks to
##    SurgeryManager or audio directly, which keeps stages reusable),
##  - emits stage_finished(quality, data) exactly once.
## Input is handled as mouse events; on iOS touches arrive as emulated mouse
## events (single-finger), which keeps desktop and device behaviour identical.

signal stage_finished(quality: float, data: Dictionary)
signal mistake(kind: StringName, severity: float, local_pos: Vector2)
## Non-mistake vital changes (e.g. cautery sealing vessels).
signal effect_requested(effects: Dictionary)
## Juice hook: kind is one of &"cut", &"burn", &"spark", &"clamp", &"stitch",
## &"implant", &"good", &"bad".
signal feedback(kind: StringName, local_pos: Vector2)
## Short contextual hint for the player (e.g. "Select SCALPEL").
signal hint(text: String)

const WRONG_TOOL_COOLDOWN := 1.0

var stage: SurgeryStageData
var site: SurgicalSiteView
var customer: CustomerData
var selected_tool: StringName = &""
var tool_precision: float = 1.0
var tool_speed: float = 1.0
var is_finished: bool = false
var is_pointer_down: bool = false
## Extra tuning from SurgeryManager.get_stage_context() (difficulty, neural
## load, alignment / sync multipliers, implant icon).
var context: Dictionary = {}
## UI units per local unit (the field renders in a scaled SubViewport).
var view_scale: float = 1.0

var _wrong_tool_timer: float = 0.0
var _cooldowns: Dictionary = {}


func setup(p_stage: SurgeryStageData, p_site: SurgicalSiteView, p_customer: CustomerData, precision: float, speed: float, p_context: Dictionary = {}) -> void:
	stage = p_stage
	site = p_site
	customer = p_customer
	tool_precision = precision
	tool_speed = speed
	context = p_context


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Called once the stage is in the tree and sized.
func begin() -> void:
	pass


## Optional stage-specific controls (hold button, slider...). Owned by the
## stage; the screen places it below the field and frees it with the stage.
func create_controls() -> Control:
	return null


func requires_tool() -> bool:
	return stage.tool_category != &""


func set_selected_tool(category: StringName) -> void:
	selected_tool = category


## Bot/test helper: describes where to interact. Not used by gameplay.
func get_autoplay_hints() -> Dictionary:
	return {}


func _process(delta: float) -> void:
	_wrong_tool_timer = maxf(0.0, _wrong_tool_timer - delta)
	for key: StringName in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)
	if not is_finished:
		_stage_process(delta)


func _stage_process(_delta: float) -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if is_finished:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			is_pointer_down = true
			_pointer_down(mb.position)
		else:
			is_pointer_down = false
			_pointer_up(mb.position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and is_pointer_down:
		_pointer_move(mm.position)
		accept_event()


func _pointer_down(_pos: Vector2) -> void:
	pass


func _pointer_move(_pos: Vector2) -> void:
	pass


func _pointer_up(_pos: Vector2) -> void:
	pass


## Returns true if the right tool is selected. Otherwise hints and, if a
## different tool is selected, counts a (rate-limited) wrong-tool mistake.
func _check_tool(pos: Vector2) -> bool:
	if not requires_tool() or selected_tool == stage.tool_category:
		return true
	if _wrong_tool_timer <= 0.0:
		_wrong_tool_timer = WRONG_TOOL_COOLDOWN
		hint.emit("Select the %s" % String(stage.tool_category).to_upper())
		if selected_tool != &"":
			mistake.emit(&"wrong_tool", 1.0, pos)
	return false


## Emits a mistake at most once per `cooldown` seconds for the same kind.
func _mistake_limited(kind: StringName, severity: float, pos: Vector2, cooldown: float) -> bool:
	if float(_cooldowns.get(kind, 0.0)) > 0.0:
		return false
	_cooldowns[kind] = cooldown
	mistake.emit(kind, severity, pos)
	return true


func _finish(quality: float, data: Dictionary = {}) -> void:
	if is_finished:
		return
	is_finished = true
	is_pointer_down = false
	stage_finished.emit(clampf(quality, 0.0, 1.0), data)


func _px() -> float:
	return site.art_px()


## Converts UI units (GameConfig touch sizes) into this stage's local units.
func _ui(units: float) -> float:
	return units / maxf(view_scale, 0.001)


## Hit radius for a touch target given its visual radius in design units.
func _touch_radius(art_radius: float) -> float:
	return maxf(art_radius * _px(), _ui(GameConfig.MIN_TOUCH * 0.5))


## Crisp 8px pixel font for labels drawn inside the field.
func _pixel_font() -> Font:
	return get_theme_font(&"font", &"PixelLabel")


const PIXEL_FONT_SIZE := 8
