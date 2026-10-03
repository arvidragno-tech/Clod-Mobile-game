class_name FxLayer
extends Control
## Lightweight juice: pixel particle bursts and floating text.
## Sits on top of gameplay, never blocks input.

const FLOAT_TEXT_RISE := 36.0
const FLOAT_TEXT_TIME := 0.9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Square "pixel" particles exploding from `pos` (local coordinates).
func burst(pos: Vector2, color: Color, amount: int = 12, speed: float = 90.0, pixel_size: float = 3.0, gravity: float = 260.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.scale_amount_min = pixel_size
	p.scale_amount_max = pixel_size
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


## Rising, fading label (e.g. "-9 NEURAL", "+¤320").
func float_text(pos: Vector2, text: String, color: Color, big: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"BigMonoLabel" if big else &"MonoLabel"
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.reset_size()
	label.position = (pos - label.size / 2.0).round()
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "position:y", label.position.y - FLOAT_TEXT_RISE, FLOAT_TEXT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(label, "modulate:a", 0.0, FLOAT_TEXT_TIME * 0.5).set_delay(FLOAT_TEXT_TIME * 0.5)
	t.chain().tween_callback(label.queue_free)
