class_name VitalBar
extends Control
## Segmented pixel status bar with a label and numeric readout.
## Used for patient vitals and any other 0..max meter.

const SEGMENTS := 20
const SEGMENT_GAP := 1.0
const BAR_HEIGHT := 8.0
const LABEL_HEIGHT := 18.0
const BLINK_HZ := 4.0

@export var label_text: String = "VITAL"
@export var bar_color: Color = Palette.ACCENT
@export var max_value: float = 100.0
## When true, high values are bad (e.g. blood loss, pain).
@export var invert_warning: bool = false
@export var suffix: String = ""

var value: float = 0.0
var warning: bool = false

var _display_value: float = 0.0
var _hit_flash: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(custom_minimum_size.x, LABEL_HEIGHT + BAR_HEIGHT + 4.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: float, immediate: bool = false) -> void:
	var drop := v < value - 0.5 if not invert_warning else v > value + 0.5
	if drop and absf(v - value) > 2.0:
		_hit_flash = 1.0
	value = clampf(v, 0.0, max_value)
	if immediate:
		_display_value = value
	queue_redraw()


func set_warning(active: bool) -> void:
	warning = active
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var changed := false
	if absf(_display_value - value) > 0.05:
		_display_value = move_toward(_display_value, value, maxf(absf(value - _display_value) * 8.0, 10.0) * delta)
		changed = true
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
		changed = true
	if changed or warning:
		queue_redraw()


func _draw() -> void:
	var label_font := get_theme_font(&"font", &"SubHeaderLabel")
	var value_font := get_theme_font(&"font", &"MonoLabel")
	var blink_on := warning and fmod(_time * BLINK_HZ, 1.0) < 0.5
	var label_color := Palette.DANGER if blink_on else Accessibility.dim()
	# Colour-independent: a warning also prefixes the caption with "!".
	draw_string(label_font, Vector2(0, 12), ("! " if warning else "") + label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_color)
	var readout := ("%d%s" % [roundi(_display_value), suffix]) + (" !" if warning else "")
	var value_color := Palette.DANGER if warning else Palette.TEXT
	draw_string(value_font, Vector2(0, 15), readout, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 20, value_color)

	var y := LABEL_HEIGHT
	var seg_w := (size.x - SEGMENT_GAP * (SEGMENTS - 1)) / SEGMENTS
	var filled := (_display_value / max_value) * SEGMENTS
	var on_color := bar_color.lerp(Color.WHITE, _hit_flash * 0.6)
	if blink_on:
		on_color = Palette.DANGER
	var off_color := Color(bar_color.darkened(0.78), 1.0)
	for i in SEGMENTS:
		var x := floorf(i * (seg_w + SEGMENT_GAP))
		var rect := Rect2(x, y, floorf(seg_w), BAR_HEIGHT)
		var fill_amount := clampf(filled - i, 0.0, 1.0)
		draw_rect(rect, off_color)
		if fill_amount > 0.0:
			var c := on_color if fill_amount >= 1.0 else on_color.darkened(0.45)
			draw_rect(rect, c)
