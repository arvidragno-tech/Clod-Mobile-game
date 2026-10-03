class_name TouchSlider
extends Control
## Large, thumb-friendly horizontal slider. Touch or drag anywhere on it to
## set the value (0..1); no need to grab a tiny knob.

signal value_changed(value: float)

const KNOB_WIDTH := 22.0
const TRACK_HEIGHT := 8.0
const TICKS := 10

var value: float = 0.5:
	set(v):
		var clamped := clampf(v, 0.0, 1.0)
		if not is_equal_approx(clamped, value):
			value = clamped
			value_changed.emit(value)
		queue_redraw()

var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = maxf(custom_minimum_size.y, GameConfig.MIN_TOUCH)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			_set_from_x(mb.position.x)
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		_set_from_x(mm.position.x)
		accept_event()


func _set_from_x(x: float) -> void:
	var usable := size.x - KNOB_WIDTH
	value = (x - KNOB_WIDTH / 2.0) / maxf(usable, 1.0)


## Local x position for a given value (used by tests / tutorials).
func x_for_value(v: float) -> float:
	return KNOB_WIDTH / 2.0 + v * (size.x - KNOB_WIDTH)


func _draw() -> void:
	var bg := Rect2(Vector2.ZERO, size)
	draw_rect(bg, Palette.PANEL)
	draw_rect(bg, Palette.LINE_HI, false, 2.0)
	var track_y := size.y / 2.0 - TRACK_HEIGHT / 2.0
	draw_rect(Rect2(KNOB_WIDTH / 2.0, track_y, size.x - KNOB_WIDTH, TRACK_HEIGHT), Palette.BG_1)
	for i in TICKS + 1:
		var x := x_for_value(float(i) / TICKS)
		draw_rect(Rect2(x - 1.0, track_y - 6.0, 2.0, 4.0), Palette.LINE_HI)
	var kx := x_for_value(value)
	draw_rect(Rect2(KNOB_WIDTH / 2.0, track_y, kx - KNOB_WIDTH / 2.0, TRACK_HEIGHT), Palette.ACCENT_DIM)
	var knob := Rect2(kx - KNOB_WIDTH / 2.0, 4.0, KNOB_WIDTH, size.y - 8.0)
	draw_rect(knob, Palette.ACCENT if _dragging else Palette.ACCENT.darkened(0.15))
	draw_rect(Rect2(knob.position.x + KNOB_WIDTH / 2.0 - 1.0, knob.position.y + 6.0, 2.0, knob.size.y - 12.0), Palette.TEXT_DARK)
