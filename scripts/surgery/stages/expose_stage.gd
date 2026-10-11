class_name ExposeStage
extends SurgeryStage
## Tap each clamp point with the retractor to open the incision.
## Jabbing tissue away from the clamp points tears it.

const TEAR_COOLDOWN := 0.5
const OPEN_TWEEN_SEC := 0.25
## Taps further than this multiple of the hit radius from any clamp count as
## tears (closer misses are forgiven).
const TEAR_DISTANCE_MULT := 1.6

var clamp_points: Array[Vector2] = []
var placed: Array[bool] = []
var _radius_art: float = 6.0
var _errors: int = 0
var _time: float = 0.0


func begin() -> void:
	clamp_points = stage.param_vec2_array("clamps")
	placed.resize(clamp_points.size())
	placed.fill(false)
	_radius_art = stage.param_float("radius_px", 6.0)


func get_autoplay_hints() -> Dictionary:
	var pts: Array[Vector2] = []
	for i in clamp_points.size():
		if not placed[i]:
			pts.append(site.to_local_pos(clamp_points[i]))
	return {"targets": pts}


func _pointer_down(pos: Vector2) -> void:
	if not site.get_field_rect().has_point(pos):
		return
	if not _check_tool(pos):
		return
	var radius := _touch_radius(_radius_art)
	var best := -1
	var best_d := INF
	for i in clamp_points.size():
		if placed[i]:
			continue
		var d := pos.distance_to(site.to_local_pos(clamp_points[i]))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and best_d <= radius:
		_place(best)
	elif best_d > radius * TEAR_DISTANCE_MULT:
		if _mistake_limited(&"tissue_tear", 1.0, pos, TEAR_COOLDOWN):
			_errors += 1
			site.add_blood_splat(site.to_norm(pos), 4)
	else:
		_hint_limited("Close: clamp right on the bracket marker")


func _place(index: int) -> void:
	placed[index] = true
	site.clamps.append(clamp_points[index])
	var count := placed.count(true)
	var target := float(count) / clamp_points.size()
	create_tween().tween_property(site, "opening", target, OPEN_TWEEN_SEC)
	feedback.emit(&"clamp", site.to_local_pos(clamp_points[index]))
	if count == clamp_points.size():
		_finish(1.0 - 0.2 * _errors)


func _stage_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for i in clamp_points.size():
		if placed[i]:
			continue
		var p := site.to_local_pos(clamp_points[i])
		var r := _radius_art * _px() * 0.6
		draw_arc(p.floor(), r + roundf(pulse * 2.0), 0, TAU, 20, Palette.WARN, 1.0)
		draw_rect(Rect2(p.floor() - Vector2(1, 1), Vector2(3, 3)), Palette.WARN)
