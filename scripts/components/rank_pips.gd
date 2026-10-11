class_name RankPips
extends Control
## Row of square rank pips drawn on the pixel grid.

var value: int = 0
var max_value: int = 3
var color: Color = Palette.ACCENT
const PIP := 8.0
const GAP := 4.0


func _init(p_value: int = 0, p_max: int = 3, p_color: Color = Palette.ACCENT) -> void:
	value = p_value
	max_value = p_max
	color = p_color
	custom_minimum_size = Vector2(max_value * (PIP + GAP), PIP + 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for i in max_value:
		var r := Rect2(i * (PIP + GAP), 1, PIP, PIP)
		if i < value:
			draw_rect(r, color)
			draw_rect(Rect2(r.position, Vector2(PIP, 2)), color.lightened(0.4))
		else:
			draw_rect(r, Color(color, 0.18))
			draw_rect(r, Color(color, 0.5), false, 1.0)
