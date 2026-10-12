class_name ConnectInterfaceStage
extends SurgeryStage
## Drag a wire from each implant pin to the nerve terminal with the same
## colour AND shape. Wrong splices shock the neural link.

## Pin offsets from the implant centre, in art px.
const PIN_OFFSETS: Array[Vector2] = [Vector2(-6, -5), Vector2(6, -5), Vector2(0, 7)]
const MARK_RADIUS_ART := 2.5
const ZAP_COLOR := Palette.DANGER

var endpoints: Array[Vector2] = []  # norm
var endpoint_color_index: Array[int] = []
var connected: Array[bool] = []
var _active_pin: int = -1
var _drag_pos: Vector2 = Vector2.ZERO
var _wrong: int = 0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func begin() -> void:
	endpoints = stage.param_vec2_array("endpoints")
	endpoint_color_index.clear()
	for i in endpoints.size():
		endpoint_color_index.append(i % Palette.SPLICE_COLORS.size())
	_rng.randomize()
	# Shuffle until no terminal sits in its "obvious" slot.
	for attempt in 10:
		_shuffle(endpoint_color_index)
		var identity := true
		for i in endpoint_color_index.size():
			if endpoint_color_index[i] != i:
				identity = false
		if not identity:
			break
	connected.resize(PIN_OFFSETS.size())
	connected.fill(false)


func _shuffle(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func pin_local(index: int) -> Vector2:
	var center := site.to_local_pos(site.implant_pos)
	return center + PIN_OFFSETS[index].rotated(site.implant_angle) * _px()


func endpoint_local(index: int) -> Vector2:
	return site.to_local_pos(endpoints[index])


func get_autoplay_hints() -> Dictionary:
	var pairs: Array = []
	for pin in PIN_OFFSETS.size():
		if connected[pin]:
			continue
		var target := endpoint_color_index.find(pin)
		pairs.append([pin_local(pin), endpoint_local(target)])
	var wrong_target := -1
	for pin in PIN_OFFSETS.size():
		if not connected[pin]:
			wrong_target = (endpoint_color_index.find(pin) + 1) % endpoints.size()
			return {"pairs": pairs, "wrong": [pin_local(pin), endpoint_local(wrong_target)]}
	return {"pairs": pairs}


func _pointer_down(pos: Vector2) -> void:
	var best := -1
	var best_d := INF
	for i in PIN_OFFSETS.size():
		if connected[i]:
			continue
		var d := pos.distance_to(pin_local(i))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and best_d <= _touch_radius(MARK_RADIUS_ART + 2.0) and _check_tool(pos):
		_active_pin = best
		_drag_pos = pos
		feedback.emit(&"spark", pin_local(best))
	elif best >= 0 and best_d <= _touch_radius(MARK_RADIUS_ART + 2.0) * 2.0:
		_hint_limited("Grab a wire right at its coloured pin")


func _pointer_move(pos: Vector2) -> void:
	_drag_pos = pos


func _pointer_up(pos: Vector2) -> void:
	if _active_pin < 0:
		return
	var pin := _active_pin
	_active_pin = -1
	var target := -1
	var best_d := INF
	for i in endpoints.size():
		var d := pos.distance_to(endpoint_local(i))
		if d < best_d:
			best_d = d
			target = i
	if target < 0 or best_d > _touch_radius(MARK_RADIUS_ART + 3.0):
		_hint_limited("Drop the wire on the terminal of the same colour")
		return
	if endpoint_color_index[target] == pin and not connected[pin]:
		connected[pin] = true
		site.connections.append({"from": site.to_norm(pin_local(pin)), "to": endpoints[target], "color": Palette.SPLICE_COLORS[pin]})
		feedback.emit(&"spark", endpoint_local(target))
		if connected.count(true) == PIN_OFFSETS.size():
			_finish(1.0 - 0.25 * _wrong)
	else:
		_wrong += 1
		mistake.emit(&"wrong_connection", 1.0, endpoint_local(target))
		feedback.emit(&"bad", endpoint_local(target))


func _stage_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if site == null or endpoints.is_empty():
		return
	var px := _px()
	for i in endpoints.size():
		var color_index := endpoint_color_index[i]
		var used := connected[color_index]
		_draw_mark(endpoint_local(i), color_index, used, true)
	for pin in PIN_OFFSETS.size():
		_draw_mark(pin_local(pin), pin, connected[pin], false)
	if _active_pin >= 0:
		var from := pin_local(_active_pin)
		var color := Palette.SPLICE_COLORS[_active_pin]
		var steps := int(from.distance_to(_drag_pos))
		for s in steps:
			var p := from.lerp(_drag_pos, float(s) / maxf(steps, 1))
			draw_rect(Rect2(p.floor(), Vector2(2, 2)), color.darkened(0.4))
			draw_rect(Rect2(p.floor(), Vector2(1, 1)), color)


## Colour + shape marker: 0 = triangle, 1 = diamond, 2 = square.
func _draw_mark(center: Vector2, color_index: int, dimmed: bool, terminal: bool) -> void:
	var color := Palette.SPLICE_COLORS[color_index]
	if dimmed:
		color = color.darkened(0.5)
	var r := roundf(MARK_RADIUS_ART * _px() * (1.1 if terminal else 0.8))
	center = center.floor()
	if terminal and not dimmed:
		var pulse := 0.5 + 0.5 * sin(_time * 5.0 + color_index)
		draw_arc(center, r + 3.0 + roundf(pulse * 2.0), 0, TAU, 20, Color(color, 0.6), 1.0)
	var pts: PackedVector2Array
	match color_index:
		0:
			pts = PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, r * 0.8), center + Vector2(-r, r * 0.8)])
		1:
			pts = PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)])
		_:
			pts = PackedVector2Array([center + Vector2(-r, -r) * 0.8, center + Vector2(r, -r) * 0.8, center + Vector2(r, r) * 0.8, center + Vector2(-r, r) * 0.8])
	draw_colored_polygon(pts, Palette.BG_0)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(center + (p - center) * 0.7)
	draw_colored_polygon(inner, color)
