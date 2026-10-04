class_name CoachMark
extends Control
## Tutorial coach mark: a small instruction card plus pulsing pixel brackets
## around the control the player should use. Purely an overlay: it never
## blocks touches except on its own SKIP / GOT IT buttons. The card sits on
## the opposite half of the screen from the highlighted control.

signal skip_pressed
signal done_pressed

const BRACKET := 8.0
const PULSE_HZ := 1.6

var step: Dictionary = {}
var _card: PanelContainer
var _target_name: String = ""
var _time: float = 0.0
var _rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(p_step: Dictionary, number: int, total: int) -> void:
	step = p_step
	_target_name = str(step.get("target", ""))
	_card = UIKit.panel(&"AccentPanel")
	_card.name = "CoachCard"
	# Opaque, hard-edged (no blur) card so it reads clearly over any screen.
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = false
	sb.bg_color = Color("0b0f16")
	sb.border_color = Palette.ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	_card.add_theme_stylebox_override(&"panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var v := UIKit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var head := UIKit.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UIKit.label("> " + str(step.get("title", "")), &"HeaderLabel")
	UIKit.expand(t)
	head.add_child(t)
	head.add_child(UIKit.label("%d/%d" % [number, total], &"MonoLabel", false, Palette.TEXT_DIM, 18))
	v.add_child(head)
	var body := TypewriterLabel.new()
	body.text = str(step.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override(&"font_size", 15 + Settings.font_bonus())
	v.add_child(body)
	body.play()
	var row := UIKit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	var last := number == total
	if last:
		var done := UIKit.button("GOT IT", &"AccentButton", done_pressed.emit, "CoachDone", 44)
		done.custom_minimum_size.x = 110
		row.add_child(done)
	else:
		var skip := UIKit.button("SKIP TUTORIAL", &"GhostButton", skip_pressed.emit, "CoachSkip", 44)
		skip.add_theme_font_size_override(&"font_size", 12)
		row.add_child(skip)
	v.add_child(row)
	_card.modulate.a = 0.0
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.2)


func _process(delta: float) -> void:
	_time += delta
	var target := _find_target()
	_rect = Rect2()
	if target and target.is_visible_in_tree():
		var r := target.get_global_rect()
		_rect = Rect2(r.position - get_global_rect().position, r.size).grow(4.0)
	_place_card()
	queue_redraw()


func _find_target() -> Control:
	if _target_name.is_empty() or UIManager.current_screen == null:
		return null
	return UIManager.current_screen.find_child(_target_name, true, false) as Control


func _place_card() -> void:
	if _card == null:
		return
	var w := minf(size.x - 16.0, 340.0)
	_card.size = Vector2(w, 0)
	_card.reset_size()
	_card.size.x = w
	var h := _card.get_combined_minimum_size().y
	var target_low := _rect.has_area() and _rect.get_center().y > size.y * 0.5
	var y := 64.0 if target_low else size.y - h - 76.0
	# Never cover the highlighted control.
	if _rect.has_area():
		if target_low and y + h > _rect.position.y - 4.0:
			y = maxf(8.0, _rect.position.y - h - 8.0)
		elif not target_low and y < _rect.end.y + 4.0:
			y = minf(size.y - h - 8.0, _rect.end.y + 8.0)
	_card.position = Vector2(roundf((size.x - w) / 2.0), roundf(y))


func _draw() -> void:
	if not _rect.has_area() or Settings.reduce_motion and fmod(_time, 2.0) > 1.6:
		return
	var pulse := 0.5 + 0.5 * sin(_time * TAU * PULSE_HZ)
	var c := Color(Palette.ACCENT, 0.55 + 0.45 * pulse)
	var g := 0.0 if Settings.reduce_motion else roundf(pulse * 3.0)
	var r := _rect.grow(g)
	var px := 2.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_rect(Rect2(corner + Vector2(minf(0.0, sx * BRACKET), minf(0.0, sy * px)), Vector2(BRACKET, px)), c)
		draw_rect(Rect2(corner + Vector2(minf(0.0, sx * px), minf(0.0, sy * BRACKET)), Vector2(px, BRACKET)), c)
