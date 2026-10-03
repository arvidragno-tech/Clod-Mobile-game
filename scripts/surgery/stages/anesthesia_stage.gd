class_name AnesthesiaStage
extends SurgeryStage
## HOLD the infuse button; release with the dose inside the green band.
## Under-dosing leaves the patient in pain, over-dosing harms them.

const GAUGE_WIDTH_ART := 8.0
const PAIN_TOLERANCE_ZONE_SHIFT := 20.0

var dose: float = 0.0
var zone_min: float = 55.0
var zone_max: float = 72.0
var fill_rate: float = 38.0
var _holding: bool = false
var _button: Button


func begin() -> void:
	fill_rate = stage.param_float("fill_rate", fill_rate)
	# Patients with low pain tolerance need more sedative.
	var shift := (1.0 - (customer.pain_tolerance if customer else 1.0)) * PAIN_TOLERANCE_ZONE_SHIFT
	zone_min = clampf(stage.param_float("zone_min", zone_min) + shift, 10.0, 90.0)
	zone_max = clampf(stage.param_float("zone_max", zone_max) + shift, zone_min + 5.0, 95.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func create_controls() -> Control:
	_button = Button.new()
	_button.name = "InfuseButton"
	_button.text = "HOLD TO INFUSE"
	_button.theme_type_variation = &"AccentButton"
	_button.custom_minimum_size = Vector2(0, 56)
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.focus_mode = Control.FOCUS_NONE
	_button.set_meta(&"silent", true)
	_button.button_down.connect(_on_hold_start)
	_button.button_up.connect(_on_hold_end)
	return _button


func get_autoplay_hints() -> Dictionary:
	return {"button": _button, "zone_min": zone_min, "zone_max": zone_max, "fill_rate": fill_rate}


func _on_hold_start() -> void:
	if is_finished:
		return
	_holding = true
	feedback.emit(&"spark", _gauge_rect().get_center())


func _on_hold_end() -> void:
	if not _holding or is_finished:
		return
	_holding = false
	_evaluate()


func _stage_process(delta: float) -> void:
	if _holding:
		dose = minf(100.0, dose + fill_rate * delta)
		if dose >= 100.0:
			_holding = false
			_evaluate()
	queue_redraw()


func _evaluate() -> void:
	var center := (zone_min + zone_max) / 2.0
	var half := (zone_max - zone_min) / 2.0
	var pos := _gauge_rect().get_center()
	var quality := 1.0
	if dose < zone_min:
		mistake.emit(&"underdose", clampf((zone_min - dose) / 20.0, 0.4, 1.5), pos)
		quality = 0.4
	elif dose > zone_max:
		mistake.emit(&"overdose", clampf((dose - zone_max) / 15.0, 0.4, 1.5), pos)
		quality = 0.3
	else:
		quality = 1.0 - 0.3 * absf(dose - center) / half
		feedback.emit(&"good", pos)
	if _button:
		_button.disabled = true
	_finish(quality, {"dose": dose})


func _gauge_rect() -> Rect2:
	var field := site.get_field_rect()
	var w := GAUGE_WIDTH_ART * _px()
	return Rect2(field.end.x - w - 3.0 * _px(), field.position.y + field.size.y * 0.15, w, field.size.y * 0.7)


func _draw() -> void:
	if site == null:
		return
	var r := _gauge_rect()
	draw_rect(r.grow(4.0), Color(Palette.BG_0, 0.85))
	draw_rect(r, Palette.BG_1)
	var zone_top := r.end.y - r.size.y * zone_max / 100.0
	var zone_bottom := r.end.y - r.size.y * zone_min / 100.0
	draw_rect(Rect2(r.position.x, zone_top, r.size.x, zone_bottom - zone_top), Color(Palette.OK, 0.25))
	draw_rect(Rect2(r.position.x, zone_top, r.size.x, 2), Palette.OK)
	draw_rect(Rect2(r.position.x, zone_bottom - 2, r.size.x, 2), Palette.OK)
	var fill_h := r.size.y * dose / 100.0
	var fill_color := Palette.ACCENT
	if dose > zone_max:
		fill_color = Palette.DANGER
	elif dose >= zone_min:
		fill_color = Palette.OK
	# Segmented fill
	var seg := maxf(_px() * 2.0, 4.0)
	var y := r.end.y - seg
	while y >= r.end.y - fill_h - 0.5:
		draw_rect(Rect2(r.position.x + 2, y + 1, r.size.x - 4, seg - 2), fill_color)
		y -= seg
	draw_rect(r, Palette.LINE_HI, false, 2.0)
	var font := get_theme_font(&"font", &"MonoLabel")
	draw_string(font, Vector2(r.position.x - 20, r.position.y - 10), "DOSE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40, 18, Palette.TEXT_DIM)
	draw_string(font, Vector2(r.position.x - 60, r.end.y - fill_h + 6), "%d%%" % roundi(dose), HORIZONTAL_ALIGNMENT_RIGHT, 52, 22, fill_color)
