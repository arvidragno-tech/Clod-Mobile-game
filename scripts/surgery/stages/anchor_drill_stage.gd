class_name AnchorDrillStage
extends SurgeryStage
## Bone anchors for limb / spine chrome: select the DRILL, hold on each anchor
## point and release when the depth sits in the green band. Too deep cracks
## bone; too shallow leaves a loose anchor (worse implant seating).

const ANCHOR_RADIUS_ART := 4.0

var anchors: Array[Vector2] = []
var depths: Array[float] = []
var done: Array[bool] = []
var zone_min: float = 58.0
var zone_max: float = 78.0
var depth_rate: float = 55.0
var _active: int = -1
var _errors: int = 0
var _loose: int = 0
var _time: float = 0.0


func begin() -> void:
	anchors = stage.param_vec2_array("anchors")
	depths.resize(anchors.size())
	depths.fill(0.0)
	done.resize(anchors.size())
	done.fill(false)
	depth_rate = stage.param_float("depth_rate", depth_rate) * tool_speed
	# Better drills / precision widen the safe band.
	var widen := (tool_precision - 1.0) * 6.0
	zone_min = stage.param_float("zone_min", zone_min) - widen
	zone_max = stage.param_float("zone_max", zone_max) + widen
	site.anchors.clear()
	for a in anchors:
		site.anchors.append({"pos": a, "depth": 0.0, "ok": true})


func get_autoplay_hints() -> Dictionary:
	var pts: Array[Vector2] = []
	for i in anchors.size():
		if not done[i]:
			pts.append(site.to_local_pos(anchors[i]))
	return {"targets": pts, "zone_min": zone_min, "zone_max": zone_max, "depth_rate": depth_rate}


func current_depth() -> float:
	return depths[_active] if _active >= 0 else 0.0


func _pointer_down(pos: Vector2) -> void:
	if not _check_tool(pos):
		return
	var best := -1
	var best_d := INF
	for i in anchors.size():
		if done[i]:
			continue
		var d := pos.distance_to(site.to_local_pos(anchors[i]))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and best_d <= _touch_radius(ANCHOR_RADIUS_ART):
		_active = best
		feedback.emit(&"clamp", site.to_local_pos(anchors[best]))


func _pointer_up(_pos: Vector2) -> void:
	if _active < 0:
		return
	_settle(_active)
	_active = -1


func _stage_process(delta: float) -> void:
	_time += delta
	if _active >= 0 and is_pointer_down:
		depths[_active] = minf(100.0, depths[_active] + depth_rate * delta)
		site.anchors[_active]["depth"] = depths[_active] / 100.0
		if fmod(_time, 0.1) < delta:
			feedback.emit(&"drill", site.to_local_pos(anchors[_active]))
		if depths[_active] >= 100.0:
			_settle(_active)
			_active = -1
	queue_redraw()


func _settle(i: int) -> void:
	var d := depths[i]
	var pos := site.to_local_pos(anchors[i])
	done[i] = true
	if d > zone_max:
		_errors += 1
		mistake.emit(&"bone_crack", clampf((d - zone_max) / 15.0, 0.5, 1.5), pos)
		site.anchors[i]["ok"] = false
	elif d < zone_min:
		_loose += 1
		mistake.emit(&"loose_anchor", 1.0, pos)
		site.anchors[i]["ok"] = false
	else:
		feedback.emit(&"good", pos)
	if done.count(false) == 0:
		var quality := 1.0 - 0.2 * _errors - 0.15 * _loose
		_finish(quality, {"anchor_quality": quality})


func _draw() -> void:
	if site == null:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for i in anchors.size():
		if done[i]:
			continue
		var p := site.to_local_pos(anchors[i]).floor()
		draw_arc(p, ANCHOR_RADIUS_ART * _px() * 0.7 + roundf(pulse * 2.0), 0, TAU, 16, Palette.WARN, 1.0)
	if _active >= 0:
		var p := site.to_local_pos(anchors[_active]).floor()
		# Depth gauge beside the anchor
		var g := Rect2(p + Vector2(10, -16), Vector2(5, 32))
		draw_rect(g.grow(1), Color(Palette.BG_0, 0.85))
		var zt := g.end.y - g.size.y * zone_max / 100.0
		var zb := g.end.y - g.size.y * zone_min / 100.0
		draw_rect(Rect2(g.position.x, zt, g.size.x, zb - zt), Color(Palette.OK, 0.35))
		var h := g.size.y * current_depth() / 100.0
		var col := Palette.DANGER if current_depth() > zone_max else (Palette.OK if current_depth() >= zone_min else Palette.ACCENT)
		draw_rect(Rect2(g.position.x + 1, g.end.y - h, g.size.x - 2, h), col)
		draw_rect(g, Palette.LINE_HI, false, 1.0)
