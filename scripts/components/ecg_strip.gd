class_name EcgStrip
extends Control
## Animated ECG trace for the vitals monitor, drawn on a 2-unit pixel grid.
## Heart rate follows pain and blood loss; colour follows health.

const PX := 2.0
var heart_rate: float = 72.0
var health: float = 100.0
var flatline: bool = false
var _phase: float = 0.0
var _trace: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	custom_minimum_size.y = 22
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_phase += delta * heart_rate / 60.0
	var cols := int(size.x / PX)
	if _trace.size() != cols:
		_trace.resize(cols)
	# Scroll left and append the new sample.
	for i in range(cols - 1):
		_trace[i] = _trace[i + 1]
	if cols > 0:
		_trace[cols - 1] = 0.0 if flatline else _sample(fmod(_phase, 1.0))
	queue_redraw()


func _sample(t: float) -> float:
	if t < 0.08:
		return sin(t / 0.08 * PI) * 0.15
	if t < 0.12:
		return -0.2
	if t < 0.16:
		return 1.0
	if t < 0.2:
		return -0.35
	if t < 0.4:
		return sin((t - 0.2) / 0.2 * PI) * 0.22
	return 0.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("061210"))
	var col := Palette.OK if health > GameConfig.WARN_HEALTH else Palette.DANGER
	if flatline:
		col = Palette.DANGER
	var mid := floorf(size.y / 2.0 / PX) * PX
	var amp := size.y * 0.4
	var prev := mid
	for i in _trace.size():
		var y := floorf((mid - _trace[i] * amp) / PX) * PX
		var top := minf(prev, y)
		draw_rect(Rect2(i * PX, top, PX, absf(prev - y) + PX), Color(col, 0.35 + 0.65 * float(i) / maxf(1.0, _trace.size())))
		prev = y
	var font := get_theme_font(&"font", &"MonoLabel")
	draw_string(font, Vector2(size.x - 54, 16), "%d BPM" % roundi(heart_rate if not flatline else 0.0), HORIZONTAL_ALIGNMENT_RIGHT, 52, 16, col)
