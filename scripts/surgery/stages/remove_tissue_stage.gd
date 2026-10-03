class_name RemoveTissueStage
extends SurgeryStage
## Hold the cautery over dark, damaged tissue until it burns away.
## Touching the yellow nerves damages neural stability.

const NODE_RADIUS_ART := 2.2
## Extra reach of the laser around the finger (art px).
const BURN_REACH_ART := 2.5
const NERVE_COOLDOWN := 0.6
const PLACEMENT_ATTEMPTS := 400
const MIN_NODE_SPACING_ART := 5.5
const SEAL_EFFECT := {"bleed_rate": -0.06}

var _burn_time: float = 0.35
var _nerve_radius_art: float = 2.2
var _nerve_hits: int = 0
var _pointer: Vector2 = Vector2.ZERO
var _burning: bool = false
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func begin() -> void:
	_burn_time = stage.param_float("burn_time", 0.35) / maxf(tool_speed, 0.1)
	_nerve_radius_art = stage.param_float("nerve_radius_px", 2.2)
	var count := stage.param_int("nodes", 4) + (customer.extra_damaged_tissue if customer else 0)
	_rng.seed = hash(String(customer.id) if customer else "seed")
	site.damaged_nodes = _generate_nodes(count)
	if site.damaged_nodes.is_empty():
		push_warning("RemoveTissueStage: no room for damaged tissue, skipping")
		_finish.call_deferred(1.0)


func _generate_nodes(count: int) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var art := float(SurgicalSiteView.ART_SIZE)
	var margin := (NODE_RADIUS_ART + 1.0) / art
	for attempt in PLACEMENT_ATTEMPTS:
		if nodes.size() >= count:
			break
		var p := Vector2(_rng.randf_range(0.3, 0.7), _rng.randf_range(0.25, 0.75))
		if not site.is_inside_opening(p, margin, 1.0):
			continue
		if site.distance_to_nerves(p) < _nerve_radius_art + NODE_RADIUS_ART:
			continue
		var crowded := false
		for n in nodes:
			if (n["pos"] as Vector2).distance_to(p) * art < MIN_NODE_SPACING_ART:
				crowded = true
				break
		if not crowded:
			nodes.append({"pos": p, "radius": NODE_RADIUS_ART, "burn": 0.0})
	return nodes


func get_autoplay_hints() -> Dictionary:
	var pts: Array[Vector2] = []
	for n in site.damaged_nodes:
		pts.append(site.to_local_pos(n["pos"]))
	return {"targets": pts, "burn_time": _burn_time}


func _pointer_down(pos: Vector2) -> void:
	_pointer = pos
	_burning = site.get_field_rect().has_point(pos) and _check_tool(pos)


func _pointer_move(pos: Vector2) -> void:
	_pointer = pos


func _pointer_up(_pos: Vector2) -> void:
	_burning = false


func _stage_process(delta: float) -> void:
	_time += delta
	if _burning and is_pointer_down:
		_burn(delta)
	queue_redraw()


func _burn(delta: float) -> void:
	var norm := site.to_norm(_pointer)
	if site.distance_to_nerves(norm) < _nerve_radius_art:
		if _mistake_limited(&"nerve_burn", 1.0, _pointer, NERVE_COOLDOWN):
			_nerve_hits += 1
	var reach := (NODE_RADIUS_ART + BURN_REACH_ART) * _px()
	var removed: Array[int] = []
	for i in site.damaged_nodes.size():
		var node: Dictionary = site.damaged_nodes[i]
		var center := site.to_local_pos(node["pos"])
		if center.distance_to(_pointer) <= reach:
			node["burn"] = float(node["burn"]) + delta / _burn_time
			if fmod(_time, 0.12) < delta:
				feedback.emit(&"burn", center)
			if float(node["burn"]) >= 1.0:
				removed.append(i)
	removed.reverse()
	for i in removed:
		var center := site.to_local_pos(site.damaged_nodes[i]["pos"])
		site.damaged_nodes.remove_at(i)
		feedback.emit(&"spark", center)
		effect_requested.emit(SEAL_EFFECT)
	if site.damaged_nodes.is_empty():
		_finish(1.0 - 0.2 * _nerve_hits)


func _draw() -> void:
	if site == null:
		return
	# Target brackets around remaining tissue.
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for n in site.damaged_nodes:
		var c := site.to_local_pos(n["pos"])
		var r := (NODE_RADIUS_ART + 1.5) * _px()
		draw_arc(c, r + pulse * 2.0, 0, TAU, 16, Color(Palette.WARN, 0.6), 1.5)
	if _burning and is_pointer_down:
		var reach := (NODE_RADIUS_ART + BURN_REACH_ART) * _px()
		draw_arc(_pointer, reach * 0.5, 0, TAU, 16, Palette.DANGER, 2.0)
		draw_rect(Rect2(_pointer - Vector2(2, 2), Vector2(4, 4)), Palette.WARN)
