class_name ToolTray
extends HBoxContainer
## Row of toggle buttons, one per tool category needed by the surgery.
## Emits tool_selected; the needed tool can be highlighted as a hint.

signal tool_selected(category: StringName)

const ICONS := {
	&"scalpel": "res://assets/sprites/tools/scalpel.png",
	&"retractor": "res://assets/sprites/tools/retractor.png",
	&"cautery": "res://assets/sprites/tools/cautery.png",
	&"forceps": "res://assets/sprites/tools/forceps.png",
	&"splicer": "res://assets/sprites/tools/splicer.png",
	&"suture": "res://assets/sprites/tools/suture.png",
}
const BUTTON_SIZE := Vector2(52, 52)

var selected: StringName = &""
var _buttons: Dictionary = {}
var _hint_category: StringName = &""
var _group := ButtonGroup.new()
var _time: float = 0.0


func build(categories: Array[StringName]) -> void:
	add_theme_constant_override(&"separation", 4)
	_group.allow_unpress = true
	for category in categories:
		var b := Button.new()
		b.name = "Tool_%s" % category
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = &"ToolButton"
		b.custom_minimum_size = BUTTON_SIZE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tool := InventoryManager.get_best_tool(category)
		var icon_path: String = tool.icon_path if tool else ICONS.get(category, "")
		b.icon = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		b.tooltip_text = tool.display_name if tool else String(category)
		b.toggled.connect(_on_toggled.bind(category))
		b.draw.connect(_draw_hint.bind(b, category))
		add_child(b)
		_buttons[category] = b


func get_button(category: StringName) -> Button:
	return _buttons.get(category) as Button


func clear_selection() -> void:
	for b: Button in _buttons.values():
		b.set_pressed_no_signal(false)
	selected = &""
	tool_selected.emit(selected)


func set_hint(category: StringName) -> void:
	_hint_category = category


func _on_toggled(pressed: bool, category: StringName) -> void:
	if pressed:
		selected = category
		AudioManager.play_sfx(&"tool")
	elif selected == category:
		selected = &""
	tool_selected.emit(selected)


func _process(delta: float) -> void:
	_time += delta
	if _hint_category != &"" and _hint_category != selected and _buttons.has(_hint_category):
		(_buttons[_hint_category] as Button).queue_redraw()


func _draw_hint(button: Button, category: StringName) -> void:
	if category == _hint_category and selected != category:
		var a := 0.35 + 0.35 * sin(_time * 6.0)
		button.draw_rect(Rect2(Vector2.ZERO, button.size).grow(-2.0), Color(Palette.WARN, a), false, 2.0)
