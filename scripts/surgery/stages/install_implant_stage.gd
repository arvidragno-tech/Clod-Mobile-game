class_name InstallImplantStage
extends SurgeryStage
## Drag the implant from the tray into the socket, rotate it until the key
## notch lines up with the slot, then press SEAT.
##
## All implant geometry (anchor pixels, the key slot / notch radius, the art's
## reach) comes from SurgicalSiteView, so the marks drawn here sit exactly on
## the socket and implant the site draws.

## Tray sits just above the bottom of the visible field.
const TRAY_MARGIN := 22.0
const ROTATE_STEP_DEG := 15.0
## Keys / wheel never step past the alignment window (it can be under 8° on
## hard implants, so a fixed 15° step could jump over it forever).
const MIN_ROTATE_STEP_DEG := 3.0
const RETURN_TWEEN_SEC := 0.2

enum Phase { PLACE, ROTATE, DONE }

var phase: Phase = Phase.PLACE
var _snap_art: float = 9.0
var _tolerance_deg: float = 12.0
var _dragging: bool = false
var _rotating: bool = false
var _last_angle: float = 0.0
var _seat_button: Button
var _return_tween: Tween
var _rng := RandomNumberGenerator.new()


func begin() -> void:
	_snap_art = stage.param_float("snap_px", 9.0) * tool_precision
	_tolerance_deg = stage.param_float("align_tolerance_deg", 12.0) * tool_precision * float(context.get("alignment_mult", 1.0))
	site.socket_pos = stage.param_vec2("socket", Vector2(0.5, 0.5))
	site.show_socket = true
	site.set_implant_icon(str(context.get("implant_icon", "")))
	site.implant_state = SurgicalSiteView.ImplantState.IN_TRAY
	site.implant_pos = tray_pos()
	_rng.randomize()
	var offset := _rng.randf_range(60.0, 150.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	site.implant_angle = deg_to_rad(offset)
	site.implant_aligned = false


func create_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var left := _make_button("RotateLeft", "<<  [%s]" % Controls.key_name("rotate_left"), &"Button")
	left.pressed.connect(_rotate_step.bind(-1.0))
	row.add_child(left)
	_seat_button = _make_button("SeatButton", "SEAT IMPLANT   [%s]" % Controls.key_name("context"), &"AccentButton")
	_seat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_button.disabled = true
	_seat_button.pressed.connect(_seat)
	row.add_child(_seat_button)
	var right := _make_button("RotateRight", "[%s]  >>" % Controls.key_name("rotate_right"), &"Button")
	right.pressed.connect(_rotate_step.bind(1.0))
	row.add_child(right)
	return row


func _make_button(node_name: String, text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(170, 64)
	b.focus_mode = Control.FOCUS_NONE
	return b


func key_action(action: StringName, pressed: bool) -> bool:
	if not pressed:
		return action in [&"rotate_left", &"rotate_right", &"context", &"interact"]
	match action:
		&"rotate_left":
			_rotate_step(-1.0)
			return true
		&"rotate_right":
			_rotate_step(1.0)
			return true
		&"context", &"interact":
			if phase == Phase.PLACE:
				hint.emit("Drag the implant from the tray onto the socket ring first.")
			else:
				_seat()
			return true
	return false


## Wheel rotates the implant once it sits in the socket.
func wheel_steps(steps: int) -> bool:
	if phase != Phase.ROTATE or is_finished:
		return false
	_rotate_step(signf(steps))
	return true


## Right-click while carrying the implant puts it back on the tray.
func cancel() -> bool:
	if not _dragging:
		return false
	_dragging = false
	is_pointer_down = false
	site.implant_state = SurgicalSiteView.ImplantState.IN_TRAY
	_return_tween = create_tween()
	_return_tween.tween_property(site, "implant_pos", tray_pos(), RETURN_TWEEN_SEC)
	return true


func get_autoplay_hints() -> Dictionary:
	return {
		"phase": phase,
		"implant": site.implant_center(),
		"socket": site.socket_center(),
		"angle_error_deg": rad_to_deg(_angle_error()),
		"seat_button": _seat_button,
	}


func tray_pos() -> Vector2:
	var vis := site.get_visible_field_rect()
	return site.to_norm(Vector2(vis.get_center().x, vis.end.y - TRAY_MARGIN))


func _angle_error() -> float:
	return wrapf(site.implant_angle, -PI, PI)


## Grabbing anywhere on the art (at any angle) picks the implant up.
func _implant_hit(pos: Vector2) -> bool:
	return pos.distance_to(site.implant_center()) <= maxf(site.implant_reach() + 2.0, _ui(GameConfig.MIN_CONTROL * 0.5))


func _pointer_down(pos: Vector2) -> void:
	match phase:
		Phase.PLACE:
			if _implant_hit(pos) and _check_tool(pos):
				_dragging = true
				site.implant_state = SurgicalSiteView.ImplantState.HELD
				site.implant_pos = site.to_norm(pos)
		Phase.ROTATE:
			if site.get_field_rect().has_point(pos) and _check_tool(pos):
				_rotating = true
				_last_angle = (pos - site.implant_center()).angle()


func _pointer_move(pos: Vector2) -> void:
	if _dragging:
		site.implant_pos = site.to_norm(pos)
	elif _rotating:
		var center := site.implant_center()
		if pos.distance_to(center) < 3.0:
			return
		var a := (pos - center).angle()
		# 1:1 with the cursor: the implant turns exactly as far as you drag.
		site.implant_angle = wrapf(site.implant_angle + wrapf(a - _last_angle, -PI, PI), -PI, PI)
		_last_angle = a
		_update_alignment()


func _pointer_up(pos: Vector2) -> void:
	if _dragging:
		_dragging = false
		var socket_local := site.socket_center()
		if pos.distance_to(socket_local) <= _snap_art * _px() + _ui(GameConfig.CLICK_SLOP) * 0.5:
			site.implant_pos = site.socket_pos
			site.implant_state = SurgicalSiteView.ImplantState.PLACED
			phase = Phase.ROTATE
			feedback.emit(&"clamp", socket_local)
			hint.emit("Drag around the implant, scroll the wheel or press %s / %s to align the notch" % [Controls.key_name("rotate_left"), Controls.key_name("rotate_right")])
			_update_alignment()
			if _seat_button:
				_seat_button.disabled = false
		else:
			var miss := pos.distance_to(socket_local)
			if miss <= (_snap_art * 2.2) * _px() + _ui(GameConfig.CLICK_SLOP):
				hint.emit("Just short of the socket: drop it inside the ring.")
			elif site.is_inside_opening(site.to_norm(pos)):
				mistake.emit(&"implant_drop", 1.0, pos)
			site.implant_state = SurgicalSiteView.ImplantState.IN_TRAY
			_return_tween = create_tween()
			_return_tween.tween_property(site, "implant_pos", tray_pos(), RETURN_TWEEN_SEC)
	_rotating = false


func _rotate_step(direction: float) -> void:
	if phase != Phase.ROTATE or is_finished:
		return
	# Kept wrapped so the angle never grows without bound over many turns.
	site.implant_angle = wrapf(site.implant_angle + deg_to_rad(rotate_step_deg()) * direction, -PI, PI)
	_update_alignment()


func rotate_step_deg() -> float:
	return clampf(_tolerance_deg * 0.8, MIN_ROTATE_STEP_DEG, ROTATE_STEP_DEG)


func _update_alignment() -> void:
	var was := site.implant_aligned
	site.implant_aligned = absf(rad_to_deg(_angle_error())) <= _tolerance_deg
	if site.implant_aligned and not was:
		feedback.emit(&"good", site.implant_center())
	# SEAT says whether it's lined up (seating misaligned is allowed, but
	# it's a choice, not an accident).
	if _seat_button and phase == Phase.ROTATE:
		_seat_button.text = ("SEAT IMPLANT   [%s]" if site.implant_aligned else "SEAT (MISALIGNED)   [%s]") % Controls.key_name("context")
		_seat_button.theme_type_variation = &"AccentButton" if site.implant_aligned else &"DangerButton"


func _seat() -> void:
	if phase != Phase.ROTATE or is_finished:
		return
	phase = Phase.DONE
	var error_deg := absf(rad_to_deg(_angle_error()))
	var alignment := 1.0 - clampf(error_deg / 90.0, 0.0, 1.0)
	if error_deg > _tolerance_deg:
		mistake.emit(&"misalignment", clampf(error_deg / 45.0, 0.5, 1.5), site.socket_center())
	else:
		alignment = 1.0 - 0.15 * error_deg / maxf(_tolerance_deg, 1.0)
		site.implant_angle = 0.0
	site.implant_state = SurgicalSiteView.ImplantState.SEATED
	site.show_socket = false
	feedback.emit(&"implant", site.socket_center())
	if _seat_button:
		_seat_button.disabled = true
	_finish(alignment, {"alignment": alignment})


func _stage_process(_delta: float) -> void:
	# Keep the resting implant docked to the visible field edge: the field
	# can shrink after begin() when this stage's control row is added.
	if site.implant_state == SurgicalSiteView.ImplantState.IN_TRAY and not is_pointer_down \
			and (_return_tween == null or not _return_tween.is_running()):
		site.implant_pos = tray_pos()
	queue_redraw()


func _draw() -> void:
	if site == null:
		return
	var socket := site.socket_center()
	if phase == Phase.PLACE:
		# The drop zone: the same radius _pointer_up() snaps within.
		var r := _snap_art * _px()
		draw_arc(socket + Vector2(0.5, 0.5), r, 0, TAU, 24, Color(Palette.ACCENT, 0.5 if not _dragging else 0.9), 1.0)
	elif phase == Phase.ROTATE:
		# Where the notch is vs where it must go: the target frames the
		# socket's key slot, the notch rides on the same radius.
		var target := site.socket_key_pos()
		var notch := site.implant_notch_pos()
		draw_line(socket + Vector2(0.5, 0.5), target + Vector2(0.5, 0.5), Color(Palette.OK, 0.5), 1.0)
		draw_rect(Rect2(target - Vector2(3, 3), Vector2(7, 7)), Palette.OK, false, 1.0)
		draw_rect(Rect2(notch - Vector2(2, 2), Vector2(5, 5)), Palette.OK if site.implant_aligned else Palette.WARN)
