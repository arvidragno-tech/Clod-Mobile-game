class_name SequenceStage
extends SurgeryStage
## A set of points that must be worked in one order: mapping live cortex
## nodes (neural), threading the bus down the vertebrae (spine), laying
## subdermal plates (dermal), clamping vessels from the heart outwards
## (internal). The next point pulses and carries its number; touching
## another one is the stage's own mistake (params "mistake"), and a miss
## away from every point does nothing but explain itself.
##   params: points [[x, y]...] in order, mistake (kind), radius_px,
##           label (what the points are, for the hint)

var points: Array[Vector2] = []
var next_index: int = 0
var _radius_art: float = 5.0
var _mistake_kind: StringName = &"tissue_tear"
var _label: String = "point"
var _errors: int = 0
var _time: float = 0.0


func begin() -> void:
	points = stage.param_vec2_array("points")
	_radius_art = stage.param_float("radius_px", 5.0)
	_mistake_kind = StringName(str(stage.params.get("mistake", "tissue_tear")))
	_label = str(stage.params.get("label", "point"))
	next_index = 0


func get_autoplay_hints() -> Dictionary:
	var pts: Array[Vector2] = []
	for i in range(next_index, points.size()):
		pts.append(site.to_local_pos(points[i]))
	var wrong: Array[Vector2] = []
	if next_index + 1 < points.size():
		wrong.append(site.to_local_pos(points[next_index + 1]))
	return {"targets": pts, "wrong": wrong}


func get_focus() -> Vector2:
	if points.is_empty():
		return super.get_focus()
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return (lo + hi) / 2.0


func _pointer_down(pos: Vector2) -> void:
	if not site.get_field_rect().has_point(pos) or not _check_tool(pos):
		return
	var radius := _touch_radius(_radius_art)
	var hit := -1
	for i in range(next_index, points.size()):
		if pos.distance_to(site.to_local_pos(points[i])) <= radius:
			hit = i
			break
	if hit == next_index:
		feedback.emit(&"good", site.to_local_pos(points[hit]))
		next_index += 1
		if next_index >= points.size():
			_finish(1.0 - 0.15 * _errors)
	elif hit > next_index:
		if _mistake_limited(_mistake_kind, 1.0, pos, 0.6):
			_errors += 1
			feedback.emit(&"bad", pos)
			_hint_limited("Wrong order: %s %d first" % [_label, next_index + 1])
	else:
		_hint_limited("Touch %s %d (it pulses)" % [_label, next_index + 1])


func _stage_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if site == null:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var font := _pixel_font()
	for i in points.size():
		var p := site.to_local_pos(points[i]).floor()
		var r := _radius_art * _px() * 0.6
		if i < next_index:
			draw_circle(p, 2.0, Palette.OK)
			continue
		if i + 1 < points.size() and i >= next_index:
			draw_line(p, site.to_local_pos(points[i + 1]).floor(), Color(Palette.TEXT_DIM, 0.35), 1.0)
		var col := Palette.WARN if i == next_index else Color(Palette.TEXT_DIM, 0.8)
		draw_arc(p, r + (roundf(pulse * 2.0) if i == next_index else 0.0), 0, TAU, 18, col, 1.0)
		if font:
			draw_string(font, p + Vector2(r + 2.0, -r), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, PIXEL_FONT_SIZE, col)
