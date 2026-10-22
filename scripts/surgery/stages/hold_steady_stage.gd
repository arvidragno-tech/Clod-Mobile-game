class_name HoldSteadyStage
extends SurgeryStage
## Keep something steady while it sets: hold the pointer on a marker that
## drifts with the patient (a pupil as the lens fuses, a tendon under
## tension, a knee taking load, an airway seal under pressure) until the
## bar fills. Slipping off it while you hold is the stage's own mistake
## (params "mistake"), at most once a second; letting go just pauses.
##   params: anchor [x, y], drift_px (how far it wanders), period (seconds
##           per loop), duration (seconds to hold), mistake (kind),
##           radius_px, label (what you're holding)

var anchor: Vector2 = Vector2(0.5, 0.5)
var progress: float = 0.0
var duration: float = 4.0
var _drift_art: float = 6.0
var _period: float = 5.0
var _radius_art: float = 6.0
var _mistake_kind: StringName = &"tissue_tear"
var _label: String = "it"
var _holding: bool = false
var _pointer: Vector2 = Vector2.INF
var _errors: int = 0
var _time: float = 0.0


func begin() -> void:
	anchor = stage.param_vec2("anchor", site.socket_pos if site else Vector2(0.5, 0.5))
	_drift_art = stage.param_float("drift_px", 6.0)
	_period = maxf(1.0, stage.param_float("period", 5.0))
	# Steadier hands (precision) shrink the wander; faster tools set sooner.
	_drift_art /= maxf(0.5, tool_precision)
	duration = stage.param_float("duration", 4.0) / maxf(0.5, tool_speed)
	_radius_art = stage.param_float("radius_px", 6.0)
	_mistake_kind = StringName(str(stage.params.get("mistake", "tissue_tear")))
	_label = str(stage.params.get("label", "it"))


## Where the marker is now (local units).
func marker_pos() -> Vector2:
	var w := TAU * _time / _period
	var off := Vector2(sin(w), sin(w * 2.0) * 0.5) * _drift_art * _px()
	return site.to_local_pos(anchor) + off


func get_autoplay_hints() -> Dictionary:
	return {"marker": marker_pos(), "targets": [marker_pos()], "progress": progress / duration}


func get_focus() -> Vector2:
	return anchor


func _pointer_down(pos: Vector2) -> void:
	if not site.get_field_rect().has_point(pos) or not _check_tool(pos):
		return
	_pointer = pos
	if pos.distance_to(marker_pos()) <= _touch_radius(_radius_art):
		_holding = true
		feedback.emit(&"clamp", pos)
	else:
		_hint_limited("Hold on %s (the ring) and follow it" % _label)


func _pointer_move(pos: Vector2) -> void:
	_pointer = pos


func _pointer_up(_pos: Vector2) -> void:
	_holding = false


func _stage_process(delta: float) -> void:
	_time += delta
	if _holding and is_pointer_down:
		if _pointer.distance_to(marker_pos()) <= _touch_radius(_radius_art) * 1.25:
			progress += delta
			if progress >= duration:
				feedback.emit(&"good", marker_pos())
				_finish(1.0 - 0.12 * _errors)
		elif _mistake_limited(_mistake_kind, 1.0, _pointer, 1.0):
			_errors += 1
			_hint_limited("You slipped: back onto %s" % _label)
	queue_redraw()


func _draw() -> void:
	if site == null:
		return
	var p := marker_pos().floor()
	var r := _radius_art * _px() * 0.6
	var on := _holding and is_pointer_down
	draw_arc(site.to_local_pos(anchor).floor(), _drift_art * _px(), 0, TAU, 24, Color(Palette.TEXT_DIM, 0.25), 1.0)
	draw_arc(p, r, 0, TAU, 20, Palette.OK if on else Palette.WARN, 1.0)
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Palette.OK if on else Palette.WARN)
	# Progress around the ring.
	draw_arc(p, r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(progress / duration, 0.0, 1.0), 24, Palette.ACCENT, 2.0)
