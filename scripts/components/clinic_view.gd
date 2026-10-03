class_name ClinicView
extends Control
## Draws the clinic backdrop scaled to "cover" the control (keeping pixels
## square) and places the waiting customer in front of the door, in image
## coordinates, so the layout holds on every iPhone aspect ratio.

signal customer_tapped()

const BACKGROUND := preload("res://assets/sprites/clinic/clinic_bg.png")
## Point (in background pixels) where the customer's feet stand.
const CUSTOMER_FOOT := Vector2(37, 150)
## Neon sign rectangle in background pixels (for the flicker effect).
const SIGN_RECT := Rect2(57, 17, 46, 24)
## 0 = keep top edge, 1 = keep bottom edge when cropping vertically.
const VERTICAL_FOCUS := 0.4
const BUBBLE_BOB_PX := 3.0

var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _customer_sprite: TextureRect
var _bubble: Label
var _has_customer: bool = false
var _time: float = 0.0
var _flicker: float = 0.0
var _next_flicker: float = 2.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_customer_sprite = TextureRect.new()
	_customer_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_customer_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_customer_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_customer_sprite.visible = false
	add_child(_customer_sprite)
	_bubble = Label.new()
	_bubble.text = "!"
	_bubble.theme_type_variation = &"BigMonoLabel"
	_bubble.add_theme_color_override(&"font_color", Palette.WARN)
	_bubble.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_bubble.add_theme_constant_override(&"outline_size", 6)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	add_child(_bubble)
	resized.connect(_layout)
	_layout()


func show_customer(customer: CustomerData, animate: bool) -> void:
	var tex := load(customer.sprite_path) as Texture2D if ResourceLoader.exists(customer.sprite_path) else null
	_customer_sprite.texture = tex
	_customer_sprite.visible = tex != null
	_has_customer = true
	_bubble.visible = true
	_layout()
	if animate:
		_customer_sprite.modulate = Color(1, 1, 1, 0)
		var t := create_tween()
		t.tween_property(_customer_sprite, "modulate", Color.WHITE, 0.4)
		_bubble.modulate.a = 0.0
		t.tween_property(_bubble, "modulate:a", 1.0, 0.2)


func hide_customer() -> void:
	_has_customer = false
	_customer_sprite.visible = false
	_bubble.visible = false


func get_customer_rect() -> Rect2:
	return Rect2(_customer_sprite.position, _customer_sprite.size)


func _layout() -> void:
	var img := Vector2(BACKGROUND.get_size())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_scale = maxf(size.x / img.x, size.y / img.y)
	var drawn := img * _scale
	_offset = Vector2((size.x - drawn.x) / 2.0, (size.y - drawn.y) * VERTICAL_FOCUS).round()
	if _customer_sprite and _customer_sprite.texture:
		var sprite_size := Vector2(_customer_sprite.texture.get_size()) * _scale
		_customer_sprite.size = sprite_size
		_customer_sprite.position = (_offset + CUSTOMER_FOOT * _scale - Vector2(sprite_size.x / 2.0, sprite_size.y)).round()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_next_flicker = randf_range(1.5, 6.0)
		_flicker = 0.25
	_flicker = maxf(0.0, _flicker - delta)
	if _bubble.visible:
		_bubble.reset_size()
		var bob := roundf(sin(_time * 4.0) * BUBBLE_BOB_PX)
		_bubble.position = Vector2(_customer_sprite.position.x + _customer_sprite.size.x / 2.0 - _bubble.size.x / 2.0, _customer_sprite.position.y - _bubble.size.y + bob)
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(BACKGROUND, Rect2(_offset, Vector2(BACKGROUND.get_size()) * _scale), false)
	if _flicker > 0.0 and fmod(_flicker * 40.0, 2.0) < 1.0:
		var r := Rect2(_offset + SIGN_RECT.position * _scale, SIGN_RECT.size * _scale)
		draw_rect(r, Color(Palette.BG_0, 0.55))


func _gui_input(event: InputEvent) -> void:
	if not _has_customer:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if get_customer_rect().grow(GameConfig.TOUCH_SLOP).has_point(mb.position):
			customer_tapped.emit()
			accept_event()
