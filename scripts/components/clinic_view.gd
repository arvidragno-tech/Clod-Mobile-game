class_name ClinicView
extends Control
## Draws the clinic backdrop for the current facility tier at exactly
## GameConfig.PIXEL_SCALE (cropping to fit), places the waiting customer's
## composited body sprite in front of the door, and adds subtle life:
## dust motes in the lamp light and a flickering bulb in the basement.

signal customer_tapped()

## Point (in background pixels) where the customer's feet stand.
const CUSTOMER_FOOT := Vector2(27, 179)
## 0 = keep top edge, 1 = keep bottom edge when cropping vertically.
const VERTICAL_FOCUS := 0.35
const DUST_COUNT := 14
const BUBBLE_BOB_PX := 2.0

var _background: Texture2D
var _scale: float = 2.0
var _offset: Vector2 = Vector2.ZERO
var _customer_tex: Texture2D
var _has_customer: bool = false
var _customer_alpha: float = 1.0
var _bubble: Label
var _time: float = 0.0
var _flicker: float = 0.0
var _next_flicker: float = 2.0
var _dust: Array[Vector3] = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bubble = UIKit.label("!", &"BigMonoLabel", false, Palette.WARN)
	_bubble.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_bubble.add_theme_constant_override(&"outline_size", 6)
	_bubble.visible = false
	add_child(_bubble)
	for i in DUST_COUNT:
		_dust.append(Vector3(randf_range(60, 140), randf_range(60, 170), randf_range(0.0, TAU)))
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: refresh_background())
	resized.connect(_layout)
	refresh_background()


func refresh_background() -> void:
	_background = PixelArt.tex(ClinicManager.get_background_path())
	_layout()


func show_customer(customer: CustomerData, animate: bool) -> void:
	_customer_tex = CharacterArt.body(customer.appearance) if not customer.appearance.is_empty() else null
	_has_customer = true
	_bubble.visible = true
	if animate:
		_customer_alpha = 0.0
		create_tween().tween_property(self, "_customer_alpha", 1.0, 0.4)
	_layout()


func hide_customer() -> void:
	_has_customer = false
	_bubble.visible = false
	queue_redraw()


func get_customer_rect() -> Rect2:
	if _customer_tex == null:
		return Rect2(_offset + CUSTOMER_FOOT * _scale - Vector2(16, 64) * _scale, Vector2(32, 64) * _scale)
	var s := Vector2(_customer_tex.get_size()) * _scale
	return Rect2(_offset + CUSTOMER_FOOT * _scale - Vector2(s.x / 2.0, s.y), s)


func _layout() -> void:
	if _background == null or size.x <= 0.0:
		return
	var img := Vector2(_background.get_size())
	# Exact pixel density; only scale up (integer) if the view is huge (iPad).
	_scale = float(GameConfig.PIXEL_SCALE)
	while img.x * _scale < size.x or img.y * _scale < size.y:
		_scale += 1.0
	var drawn := img * _scale
	_offset = Vector2((size.x - drawn.x) / 2.0, (size.y - drawn.y) * VERTICAL_FOCUS).round()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_next_flicker = randf_range(1.5, 7.0) if ClinicManager.tier <= 1 else randf_range(6.0, 14.0)
		_flicker = 0.22
	_flicker = maxf(0.0, _flicker - delta)
	for i in _dust.size():
		var d := _dust[i]
		d.y -= delta * 3.0
		d.x += sin(_time * 0.7 + d.z) * delta * 2.0
		if d.y < 50.0:
			d.y = 175.0
		_dust[i] = d
	if _bubble.visible:
		_bubble.reset_size()
		var r := get_customer_rect()
		var bob := roundf(sin(_time * 4.0) * BUBBLE_BOB_PX) * _scale / 2.0
		_bubble.position = Vector2(r.get_center().x - _bubble.size.x / 2.0, r.position.y - _bubble.size.y + bob)
	queue_redraw()


func _draw() -> void:
	if _background == null:
		return
	draw_texture_rect(_background, Rect2(_offset, Vector2(_background.get_size()) * _scale), false)
	# Dust motes catching the lamp light (one art pixel each).
	for d in _dust:
		var a := 0.25 + 0.2 * sin(_time * 2.0 + d.z)
		draw_rect(Rect2((_offset + Vector2(floorf(d.x), floorf(d.y)) * _scale), Vector2.ONE * _scale), Color(1, 0.95, 0.85, a))
	if _has_customer and _customer_tex:
		var r := get_customer_rect()
		# Contact shadow (pixel-snapped ellipse)
		var foot := _offset + CUSTOMER_FOOT * _scale
		for k in 3:
			var w := (14 - k * 4) * _scale
			draw_rect(Rect2(foot.x - w / 2.0, foot.y - _scale + k * 0.0, w, _scale), Color(0, 0, 0, 0.25 + k * 0.15))
		draw_texture_rect(_customer_tex, r, false, Color(1, 1, 1, _customer_alpha))
	if _flicker > 0.0 and fmod(_flicker * 40.0, 2.0) < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))


func _gui_input(event: InputEvent) -> void:
	if not _has_customer:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if get_customer_rect().grow(GameConfig.TOUCH_SLOP).has_point(mb.position):
			customer_tapped.emit()
			accept_event()
