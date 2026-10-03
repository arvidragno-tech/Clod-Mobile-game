class_name CalibrateStage
extends SurgeryStage
## Match the implant's signal wave to the patient's neural carrier with the
## slider, then LOCK. Several bands; poor sync lowers implant performance.

const FREQ_MIN := 1.0
const FREQ_MAX := 5.0
const SYNC_RANGE := 0.18
const DRIFT_AMPLITUDE := 0.04
const DRIFT_SPEED := 0.8
const WAVE_SAMPLES := 48

var rounds: int = 3
var good_sync: float = 0.8
var poor_sync: float = 0.55
var round_index: int = 0
var target_base: float = 0.5
var slider_value: float = 0.5
var sync_results: Array[float] = []
var _time: float = 0.0
var _slider: TouchSlider
var _lock_button: Button
var _rng := RandomNumberGenerator.new()


func begin() -> void:
	rounds = stage.param_int("rounds", 3)
	good_sync = stage.param_float("good_sync", 0.8)
	poor_sync = stage.param_float("poor_sync", 0.55)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_new_round()


func create_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_slider = TouchSlider.new()
	_slider.name = "TuneSlider"
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(0, 56)
	_slider.value = slider_value
	_slider.value_changed.connect(func(v: float) -> void: slider_value = v)
	row.add_child(_slider)
	_lock_button = Button.new()
	_lock_button.name = "LockButton"
	_lock_button.text = "LOCK"
	_lock_button.theme_type_variation = &"AccentButton"
	_lock_button.custom_minimum_size = Vector2(88, 56)
	_lock_button.focus_mode = Control.FOCUS_NONE
	_lock_button.pressed.connect(_lock)
	row.add_child(_lock_button)
	return row


func get_autoplay_hints() -> Dictionary:
	return {"target": current_target(), "slider": _slider, "lock_button": _lock_button}


func current_target() -> float:
	return clampf(target_base + DRIFT_AMPLITUDE * sin(_time * DRIFT_SPEED), 0.0, 1.0)


func current_sync() -> float:
	return clampf(1.0 - absf(slider_value - current_target()) / SYNC_RANGE, 0.0, 1.0)


func _new_round() -> void:
	# Keep each new target well away from the current slider position.
	for attempt in 8:
		target_base = _rng.randf_range(0.15, 0.85)
		if absf(target_base - slider_value) > 0.25:
			break


func _lock() -> void:
	if is_finished:
		return
	var sync := current_sync()
	sync_results.append(sync)
	var center := site.get_field_rect().get_center()
	if sync < poor_sync:
		mistake.emit(&"poor_calibration", clampf(1.0 - sync, 0.4, 1.2), center)
	elif sync >= good_sync:
		feedback.emit(&"good", center)
	else:
		feedback.emit(&"spark", center)
	round_index += 1
	if round_index >= rounds:
		var total := 0.0
		for s in sync_results:
			total += s
		var avg := total / sync_results.size()
		if _lock_button:
			_lock_button.disabled = true
		_finish(avg, {"sync": avg})
	else:
		_new_round()


func _stage_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if site == null:
		return
	var field := site.get_field_rect()
	var panel := Rect2(field.position.x + 8, field.position.y + field.size.y * 0.18, field.size.x - 16, field.size.y * 0.64)
	draw_rect(panel, Color(Palette.BG_0, 0.9))
	draw_rect(panel, Palette.ACCENT_DIM, false, 2.0)
	var px := _px()
	var mid := panel.get_center().y
	var amp := panel.size.y * 0.22
	_draw_wave(panel, mid, amp, current_target(), 0.0, Color(Palette.TEXT_DIM, 0.8), px)
	var sync := current_sync()
	var wave_color := Palette.DANGER.lerp(Palette.OK, sync)
	_draw_wave(panel, mid, amp * 0.9, slider_value, 0.3, wave_color, px)
	var font := get_theme_font(&"font", &"MonoLabel")
	draw_string(font, panel.position + Vector2(8, 22), "BAND %d/%d" % [mini(round_index + 1, rounds), rounds], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.TEXT_DIM)
	draw_string(font, panel.position + Vector2(0, 22), "SYNC %d%%" % roundi(sync * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 8, 22, wave_color)
	# Sync meter
	var meter := Rect2(panel.position.x + 8, panel.end.y - 16, panel.size.x - 16, 8)
	draw_rect(meter, Palette.BG_1)
	draw_rect(Rect2(meter.position, Vector2(meter.size.x * sync, meter.size.y)), wave_color)
	var good_x := meter.position.x + meter.size.x * good_sync
	draw_rect(Rect2(good_x, meter.position.y - 3, 2, meter.size.y + 6), Palette.OK)


func _draw_wave(panel: Rect2, mid: float, amp: float, freq_norm: float, phase: float, color: Color, px: float) -> void:
	var freq := lerpf(FREQ_MIN, FREQ_MAX, freq_norm)
	var step := maxf(px, 3.0)
	var x := panel.position.x + 6.0
	while x < panel.end.x - 6.0:
		var t := (x - panel.position.x) / panel.size.x
		var y := mid + sin(TAU * (t * freq - _time * 0.5) + phase) * amp
		draw_rect(Rect2(floorf(x / step) * step, floorf(y / step) * step, step, step), color)
		x += step
