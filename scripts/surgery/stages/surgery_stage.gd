class_name SurgeryStage
extends Control
## Base class for one interactive surgery step. A stage:
##  - reads its tuning from SurgeryStageData.params,
##  - mutates the shared SurgicalSiteView to show what the player did,
##  - reports mistakes / effects / juice via signals (it never talks to
##    SurgeryManager or audio directly, which keeps stages reusable),
##  - emits stage_finished(quality, data) exactly once.
## Input is mouse-first (left button = use the selected tool, drag = cut /
## move, hover = highlight); key_action() / wheel_steps() / cancel() add the
## keyboard and right-click / wheel alternatives on PC.

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
## Last pointer position over the field (local units), or INF when outside.
var hover_pos: Vector2 = Vector2.INF

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


## Where the field should be framed for this stage (normalised).
func get_focus() -> Vector2:
	var path := stage.param_vec2_array("path") if stage else ([] as Array[Vector2])
	if path.is_empty() and site and not site.incision_path.is_empty():
		path = site.incision_path
	if not path.is_empty():
		var lo := path[0]
		var hi := path[0]
		for p in path:
			lo = lo.min(p)
			hi = hi.max(p)
		return (lo + hi) / 2.0
	return site.socket_pos if site else Vector2(0.5, 0.5)


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
	if mm:
		hover_pos = mm.position
		if is_pointer_down:
			_pointer_move(mm.position)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_pos = Vector2.INF


## Keyboard alternative for the stage's on-screen controls (SPACE / E hold
## to infuse, LOCK, rotate, SEAT...). Return true when consumed.
func key_action(_action: StringName, _pressed: bool) -> bool:
	return false


## Mouse wheel while this stage is under the cursor; return true to consume
## (e.g. rotate a held implant) instead of zooming the field.
func wheel_steps(_steps: int) -> bool:
	return false


## Right-click: undo the in-progress gesture if the stage supports it.
func cancel() -> bool:
	return false


## Points (local units) worth highlighting when the cursor is near them.
func get_hover_targets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var h := get_autoplay_hints()
	for key in ["targets", "path"]:
		if h.has(key):
			for p: Variant in h[key]:
				if p is Vector2:
					out.append(p)
			if key == "path" and not out.is_empty():
				out = [out[0]]
	if h.has("pairs"):
		for pair: Variant in h["pairs"]:
			out.append(pair[0])
			out.append(pair[1])
	if h.has("implant") and h.get("phase", 0) == 0:
		out.append(h["implant"])
	return out


## Hover colour for the field cursor: correct tool = cyan, wrong = amber.
func hover_color() -> Color:
	if not requires_tool():
		return Palette.ACCENT
	if selected_tool == stage.tool_category:
		return Palette.OK
	return Palette.WARN if selected_tool != &"" else Palette.TEXT_DIM


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


## Explains a click that did nothing (a near miss, the wrong spot, too
## fast), at most once per `cooldown` seconds per message, so no click ever
## feels dead and the toasts don't pile up.
func _hint_limited(text: String, cooldown: float = 1.5) -> void:
	var key := StringName("hint:" + text)
	if float(_cooldowns.get(key, 0.0)) > 0.0:
		return
	_cooldowns[key] = cooldown
	hint.emit(text)


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
	return maxf(art_radius * _px(), _ui(GameConfig.MIN_CONTROL * 0.5))


## Crisp 8px pixel font for labels drawn inside the field.
func _pixel_font() -> Font:
	return get_theme_font(&"font", &"PixelLabel")


const PIXEL_FONT_SIZE := 8
