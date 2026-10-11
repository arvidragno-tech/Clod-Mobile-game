class_name NeuralLoadMeter
extends Control
## Segmented neural-load bar with colour bands (stable → critical), the
## current load and an optional projected load after the install.

const MAX_SHOWN := 110.0
const BAR_H := 10.0

var current: float = 0.0
var projected: float = -1.0
var unknown: bool = false
var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size.y = 34
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_load(p_current: float, p_projected: float = -1.0, p_unknown: bool = false) -> void:
	current = p_current
	projected = p_projected
	unknown = p_unknown
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if projected >= 85.0 or current >= 85.0:
		queue_redraw()


func _draw() -> void:
	var font := get_theme_font(&"font", &"SubHeaderLabel")
	var mono := get_theme_font(&"font", &"MonoLabel")
	var shown := projected if projected >= 0.0 else current
	var b := NeuralLoad.band(shown)
	draw_string(font, Vector2(0, 11), "NEURAL LOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT_DIM)
	var label := "??" if unknown else ("%d%%" % roundi(current) + (" > %d%%" % roundi(projected) if projected >= 0.0 else ""))
	draw_string(mono, Vector2(0, 13), label + "  " + str(b["name"]), HORIZONTAL_ALIGNMENT_RIGHT, size.x, 18, b["color"])
	var y := 18.0
	var segs := 22
	var seg_w := (size.x - (segs - 1)) / segs
	for i in segs:
		var v0 := MAX_SHOWN * i / segs
		var band := NeuralLoad.band(v0)
		var col: Color = band["color"]
		var r := Rect2(floorf(i * (seg_w + 1)), y, floorf(seg_w), BAR_H)
		draw_rect(r, Color(col, 0.14))
		if unknown:
			continue
		if v0 < current:
			draw_rect(r, col)
		elif projected >= 0.0 and v0 < projected:
			var blink := 0.55 + 0.45 * sin(_time * 6.0) if projected >= 85.0 else 0.7
			draw_rect(r, Color(col, blink * 0.7))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), col)
