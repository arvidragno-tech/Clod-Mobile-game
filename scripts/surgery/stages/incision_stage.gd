class_name IncisionStage
extends SurgeryStage
## Drag the scalpel along the guide. Drifting off the line causes bleeding.
## Lifting the finger is fine: resume from the end of the cut.

const COMPLETE_FRACTION := 0.97
## How far ahead of the current cut the finger may jump (art px).
const MAX_ADVANCE_ART := 10.0
const DEVIATION_COOLDOWN := 0.35
const CUT_FEEDBACK_EVERY_ART := 4.0

var path_local: Array[Vector2] = []
var _norm_path: Array[Vector2] = []
var _origin: Vector2 = Vector2.INF
var _total_len: float = 0.0
var _progress_len: float = 0.0
var _cutting: bool = false
var _tolerance_art: float = 3.0
var _deviation_events: int = 0
var _deviation_sum: float = 0.0
var _deviation_samples: int = 0
var _since_feedback: float = 0.0
var _time: float = 0.0


func begin() -> void:
	var norm_path := stage.param_vec2_array("path")
	site.set_incision_path(norm_path)
	_tolerance_art = stage.param_float("tolerance_px", 3.0) * tool_precision
	_norm_path = norm_path
	_sync_path()


## Rebuilds the local-space path if the field moved (the field area resizes
## when the previous stage's controls are removed). Progress is kept as a
## length, which is unaffected by translation.
func _sync_path() -> void:
	var origin := site.to_local_pos(Vector2.ZERO)
	if origin == _origin:
		return
	_origin = origin
	path_local.clear()
	for p in _norm_path:
		path_local.append(site.to_local_pos(p))
	_total_len = 0.0
	for i in range(path_local.size() - 1):
		_total_len += path_local[i].distance_to(path_local[i + 1])


func _stage_process(delta: float) -> void:
	_sync_path()
	_incision_process(delta)


func get_autoplay_hints() -> Dictionary:
	_sync_path()
	return {"path": path_local}


func get_progress() -> float:
	return _progress_len / maxf(_total_len, 0.001)


func _cut_head() -> Vector2:
	return _point_at(_progress_len)


func _point_at(length: float) -> Vector2:
	var remaining := length
	for i in range(path_local.size() - 1):
		var seg := path_local[i].distance_to(path_local[i + 1])
		if remaining <= seg:
			return path_local[i].lerp(path_local[i + 1], remaining / maxf(seg, 0.001))
		remaining -= seg
	return path_local[path_local.size() - 1]


## Returns [length_along_path, distance_from_path] for a local point.
func _project(pos: Vector2) -> Array[float]:
	var best_len := 0.0
	var best_dist := INF
	var acc := 0.0
	for i in range(path_local.size() - 1):
		var a := path_local[i]
		var b := path_local[i + 1]
		var closest := Geometry2D.get_closest_point_to_segment(pos, a, b)
		var d := pos.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best_len = acc + a.distance_to(closest)
		acc += a.distance_to(b)
	return [best_len, best_dist]


func _pointer_down(pos: Vector2) -> void:
	_sync_path()
	if pos.distance_to(_cut_head()) > _ui(GameConfig.TOUCH_SLOP) + _tolerance_art * _px():
		if _progress_len <= 0.0:
			hint.emit("Start the cut at the marker")
		return
	if not _check_tool(pos):
		return
	_cutting = true
	if site.cut_points.is_empty():
		site.cut_points.append(site.to_norm(_cut_head()))


func _pointer_move(pos: Vector2) -> void:
	if not _cutting:
		return
	var proj := _project(pos)
	var along := proj[0]
	var dist_art := proj[1] / _px()
	if along <= _progress_len or along > _progress_len + MAX_ADVANCE_ART * _px():
		return
	_since_feedback += (along - _progress_len) / _px()
	_progress_len = along
	_deviation_sum += dist_art
	_deviation_samples += 1
	if dist_art > _tolerance_art:
		var severity := clampf(dist_art / _tolerance_art - 1.0, 0.3, 1.5)
		if _mistake_limited(&"cut_deviation", severity, pos, DEVIATION_COOLDOWN):
			_deviation_events += 1
			site.add_blood_splat(site.to_norm(pos), 5)
	site.cut_points.append(site.to_norm(pos))
	site.cut_progress = get_progress()
	if _since_feedback >= CUT_FEEDBACK_EVERY_ART:
		_since_feedback = 0.0
		feedback.emit(&"cut", pos)
	if get_progress() >= COMPLETE_FRACTION:
		site.cut_points.append(site.incision_path[site.incision_path.size() - 1])
		site.cut_progress = 1.0
		var avg_dev := _deviation_sum / maxf(_deviation_samples, 1)
		var quality := 1.0 - 0.18 * _deviation_events - 0.2 * clampf(avg_dev / _tolerance_art, 0.0, 1.0)
		_finish(maxf(quality, 0.2))


func _pointer_up(_pos: Vector2) -> void:
	_cutting = false


func _incision_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if path_local.size() < 2:
		return
	var px := 1.0
	# Dotted guide line, one art pixel per dot
	var dash := 3.0
	var travelled := 0.0
	for i in range(path_local.size() - 1):
		var a := path_local[i]
		var b := path_local[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var p := a.lerp(b, t / seg)
			if fmod(travelled + t, dash * 2.0) < dash and travelled + t > _progress_len:
				draw_rect(Rect2(p.floor(), Vector2(1, 1)), Color(Palette.ACCENT, 0.9))
			t += px
		travelled += seg
	# Tolerance corridor (subtle)
	var corridor := Color(Palette.ACCENT, 0.07)
	for i in range(path_local.size() - 1):
		draw_line(path_local[i], path_local[i + 1], corridor, _tolerance_art * _px() * 2.0)
	# Cut head / start marker
	var head := _cut_head()
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	draw_arc(head.floor(), 5.0 + roundf(pulse * 2.0), 0, TAU, 20, Palette.WARN, 1.0)
	draw_rect(Rect2(head.floor() - Vector2(1, 1), Vector2(2, 2)), Palette.WARN)
	# End marker
	var end := path_local[path_local.size() - 1].floor()
	draw_rect(Rect2(end - Vector2(2, 2), Vector2(5, 5)), Palette.ACCENT, false, 1.0)
