class_name CloseIncisionStage
extends SurgeryStage
## Tap the stitch points in numbered order to staple the incision shut.

const SIDE_OFFSET_ART := 2.5
const POINT_RADIUS_ART := 3.0
const LOOSEN_OPENING := 0.45
const STITCH_EFFECT := {"bleed_rate": -0.08}
const BAD_STITCH_COOLDOWN := 0.4

var points: Array[Vector2] = []  # norm
var next_index: int = 0
var _errors: int = 0
var _time: float = 0.0


func begin() -> void:
	var count := stage.param_int("stitches", 6)
	points.clear()
	for i in count:
		var t := (i + 0.5) / count
		var side := -1.0 if i % 2 == 0 else 1.0
		var sample := _sample_path(site.incision_path, t)
		var normal := Vector2(-sample[1].y, sample[1].x)
		points.append(sample[0] + normal * side * SIDE_OFFSET_ART / SurgicalSiteView.DESIGN_GRID)
	# Retractors come out; the wound relaxes.
	site.clamps.clear()
	create_tween().tween_property(site, "opening", LOOSEN_OPENING, 0.3)


## Returns [point, unit tangent] at fraction t (by arc length) of a polyline.
static func _sample_path(path: Array[Vector2], t: float) -> Array[Vector2]:
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	var target := t * total
	for i in range(path.size() - 1):
		var l := path[i].distance_to(path[i + 1])
		if target <= l or i == path.size() - 2:
			var dir := (path[i + 1] - path[i]).normalized()
			return [path[i].lerp(path[i + 1], clampf(target / maxf(l, 0.0001), 0.0, 1.0)), dir]
		target -= l
	return [path[0], Vector2.DOWN]


func get_autoplay_hints() -> Dictionary:
	var pts: Array[Vector2] = []
	for i in range(next_index, points.size()):
		pts.append(site.to_local_pos(points[i]))
	return {"targets": pts}


func _pointer_down(pos: Vector2) -> void:
	if not site.get_field_rect().has_point(pos) or not _check_tool(pos):
		return
	var best := -1
	var best_d := INF
	for i in range(next_index, points.size()):
		var d := pos.distance_to(site.to_local_pos(points[i]))
		if d < best_d:
			best_d = d
			best = i
	if best < 0 or best_d > _touch_radius(POINT_RADIUS_ART) * 0.8:
		if best >= 0 and best_d <= _touch_radius(POINT_RADIUS_ART) * 1.8:
			_hint_limited("Click right on stitch point %d" % (next_index + 1))
		return
	if best == next_index:
		site.stitches.append(points[best])
		next_index += 1
		var remaining := 1.0 - float(next_index) / points.size()
		create_tween().tween_property(site, "opening", LOOSEN_OPENING * remaining, 0.15)
		feedback.emit(&"stitch", site.to_local_pos(points[best]))
		effect_requested.emit(STITCH_EFFECT)
		if next_index >= points.size():
			site.closed = true
			site.opening = 0.0
			_finish(1.0 - 0.2 * _errors)
	elif _mistake_limited(&"bad_stitch", 1.0, pos, BAD_STITCH_COOLDOWN):
		_errors += 1
		_hint_limited("Out of order: stitch point %d is next" % (next_index + 1))


func _stage_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if site == null:
		return
	var font := _pixel_font()
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	for i in range(next_index, points.size()):
		var p := site.to_local_pos(points[i])
		var is_next := i == next_index
		var color := Palette.WARN if is_next else Color(Palette.TEXT_DIM, 0.8)
		var r := roundf(POINT_RADIUS_ART * _px() * 0.6 + (pulse * 2.0 if is_next else 0.0))
		draw_arc(p.floor(), r, 0, TAU, 16, color, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var label_pos := p.floor() + Vector2(side * (r + 6.0) - 3.0, 4.0)
		draw_string(font, label_pos, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, PIXEL_FONT_SIZE, color)
