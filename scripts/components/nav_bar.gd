class_name NavBar
extends HBoxContainer
## Clinic bottom navigation: icon + label buttons at pixel density.

signal nav_pressed(id: StringName)

const ITEMS := [
	[&"supply", "SUPPLY", "res://assets/sprites/ui/icons/supply.png"],
	[&"skills", "SKILLS", "res://assets/sprites/ui/icons/skills.png"],
	[&"upgrades", "CLINIC", "res://assets/sprites/ui/icons/upgrade.png"],
	[&"dossier", "DOSSIER", "res://assets/sprites/ui/icons/dossier.png"],
	[&"blackmarket", "MARKET", "res://assets/sprites/ui/icons/blackmarket.png"],
]

var _buttons: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override(&"separation", 4)
	for item: Array in ITEMS:
		var b := Button.new()
		b.name = "Nav_%s" % item[0]
		b.text = item[1]
		b.icon = PixelArt.scaled(item[2])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.theme_type_variation = &"NavButton"
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: nav_pressed.emit(item[0]))
		add_child(b)
		_buttons[item[0]] = b


func set_locked(id: StringName, locked: bool) -> void:
	var b: Button = _buttons.get(id)
	if b:
		b.modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE


func set_badge(id: StringName, on: bool) -> void:
	var b: Button = _buttons.get(id)
	if b:
		b.add_theme_color_override(&"font_color", Palette.WARN if on else Palette.TEXT_DIM)
