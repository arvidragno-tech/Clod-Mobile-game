class_name FieldHover
extends Control
## Mouse feedback inside the operating field, drawn in field (art) pixels so
## it stays crisp at every zoom: a reticle at the cursor tinted by the tool
## state (cyan/green = right tool, amber = wrong tool, grey = none) and a
## pulsing box around the nearest interactive target under the cursor.

const SNAP_ART := 10.0

var stage: SurgeryStage
var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if stage == null or not is_instance_valid(stage) or stage.is_finished:
		return
	var p := stage.hover_pos
	if p == Vector2.INF:
		return
	var c := stage.hover_color()
	# Reticle: 1-art-px cross with a gap, the cursor itself is the OS arrow.
	var q := p.floor()
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_rect(Rect2(q + d * 3.0, Vector2.ONE), Color(c, 0.9))
		draw_rect(Rect2(q + d * 4.0, Vector2.ONE), Color(c, 0.6))
	# Nearest target within reach gets a pulsing bracket.
	var best := Vector2.INF
	var best_d := SNAP_ART * stage.site.art_px()
	for t in stage.get_hover_targets():
		var d := t.distance_to(p)
		if d < best_d:
			best_d = d
			best = t
	if best != Vector2.INF:
		var a := 0.55 + 0.35 * sin(_time * 8.0)
		var r := Rect2(best.floor() - Vector2(5, 5), Vector2(11, 11))
		_bracket(r, Color(c, a))


func _bracket(r: Rect2, c: Color) -> void:
	var l := 3.0
	for corner: Vector2 in [r.position, Vector2(r.end.x - 1, r.position.y), Vector2(r.position.x, r.end.y - 1), r.end - Vector2.ONE]:
		var sx := 1.0 if corner.x <= r.position.x else -1.0
		var sy := 1.0 if corner.y <= r.position.y else -1.0
		draw_rect(Rect2(corner, Vector2.ONE), c)
		for i in range(1, int(l)):
			draw_rect(Rect2(corner + Vector2(sx * i, 0), Vector2.ONE), c)
			draw_rect(Rect2(corner + Vector2(0, sy * i), Vector2.ONE), c)
