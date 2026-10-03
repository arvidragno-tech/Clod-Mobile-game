class_name QuickActionButton
extends Button
## Emergency action button (COAG / SEDATE / STABIL) with a cooldown sweep and
## a pulsing highlight when it's the counter to an active complication.

var action_id: StringName
var cooldown_ratio: float = 0.0
var urgent: bool = false
var _time: float = 0.0


func setup(id: StringName, label: String, icon_texture: Texture2D) -> void:
	action_id = id
	name = "Quick_%s" % id
	text = label
	icon = icon_texture
	expand_icon = false
	theme_type_variation = &"QuickButton"
	custom_minimum_size = Vector2(0, GameConfig.MIN_TOUCH)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	icon_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _process(delta: float) -> void:
	_time += delta
	disabled = cooldown_ratio > 0.0
	queue_redraw()


func _draw() -> void:
	if cooldown_ratio > 0.0:
		draw_rect(Rect2(0, 0, size.x * cooldown_ratio, size.y), Color(Palette.BG_0, 0.6))
	if urgent:
		var a := 0.5 + 0.5 * sin(_time * 12.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.DANGER, a), false, 3.0)
