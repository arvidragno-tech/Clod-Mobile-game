class_name FxLayer
extends Control
## Lightweight juice: pixel particle bursts and floating text.
## Sits on top of gameplay, never blocks input.

const FLOAT_TEXT_RISE := 36.0
const FLOAT_TEXT_TIME := 0.9

## Multiplies particle speeds / sizes (0.5 inside the 2x pixel viewport so
## particles are exactly one art pixel).
var unit_scale: float = 1.0
## Hard cap on simultaneous particle emitters (mobile performance).
const MAX_EMITTERS := 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Square "pixel" particles exploding from `pos` (local coordinates).
func burst(pos: Vector2, color: Color, amount: int = 12, speed: float = 90.0, pixel_size: float = 3.0, gravity: float = 260.0) -> void:
	if get_child_count() >= MAX_EMITTERS:
		return
	if Settings.reduce_motion or Settings.effects_level() == 0:
		amount = maxi(2, amount / 3)
	elif Settings.effects_level() == 1:
		amount = maxi(2, amount * 2 / 3)
	speed *= unit_scale
	gravity *= unit_scale
	pixel_size = maxf(1.0, roundf(pixel_size * unit_scale))
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


## Expanding pixel ring: the "confirmed" pulse (cyan) or a warning pulse.
func ring(pos: Vector2, color: Color, radius: float = 10.0, time: float = 0.35) -> void:
	if get_child_count() >= MAX_EMITTERS:
		return
	var r := _Ring.new()
	r.position = pos
	r.color = color
	r.max_radius = radius * maxf(unit_scale, 0.5) * (2.0 if unit_scale >= 1.0 else 1.0)
	r.px = maxf(1.0, roundf(unit_scale * 2.0))
	add_child(r)
	var t := r.create_tween()
	t.tween_property(r, "progress", 1.0, time)
	t.tween_callback(r.queue_free)


class _Ring extends Node2D:
	var color: Color = Color.WHITE
	var max_radius: float = 10.0
	var px: float = 1.0
	var progress: float = 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		var r := maxf(1.0, max_radius * progress)
		var c := Color(color, 1.0 - progress)
		var steps := maxi(12, int(r * 2.0))
		for i in steps:
			var a := TAU * i / steps
			var p := (Vector2(cos(a), sin(a)) * r / px).round() * px
			draw_rect(Rect2(p, Vector2(px, px)), c)
