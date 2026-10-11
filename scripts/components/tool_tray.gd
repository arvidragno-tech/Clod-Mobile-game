class_name ToolTray
extends VBoxContainer
## Instrument rack (right panel of the surgery workstation): one row per tool
## category the procedure needs, showing icon, name, hotkey, condition and
## effectiveness. Select with a click, number keys 1-9 or Q / R to cycle.
## Emits tool_selected; the tool the current step needs pulses amber.

signal tool_selected(category: StringName)
## Mouse over a row (or keyboard selection): show its description.
signal tool_hovered(category: StringName)

const ROW_HEIGHT := 84.0

var selected: StringName = &""
var categories: Array[StringName] = []
var _buttons: Dictionary = {}
var _hint_category: StringName = &""
var _group := ButtonGroup.new()
var _time: float = 0.0


func build(p_categories: Array[StringName]) -> void:
	categories = p_categories
	add_theme_constant_override(&"separation", 6)
	_group.allow_unpress = true
	for i in categories.size():
		var category := categories[i]
		var tool := InventoryManager.get_best_tool(category)
		var b := Button.new()
		b.name = "Tool_%s" % category
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = &"ToolButton"
		b.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.disabled = tool == null
		b.tooltip_text = _tooltip(category, tool, i)
		b.add_child(_row_content(category, tool, i))
		b.toggled.connect(_on_toggled.bind(category))
		b.mouse_entered.connect(func() -> void: tool_hovered.emit(category))
		b.draw.connect(_draw_hint.bind(b, category))
		add_child(b)
		_buttons[category] = b


func _row_content(category: StringName, tool: ToolData, index: int) -> Control:
	var m := UIKit.margin(10, 6, 12, 6)
	UIKit.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var icon := TextureRect.new()
	icon.texture = PixelArt.scaled(tool.icon_path) if tool else null
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(72, 0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := UIKit.vbox(2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.expand(text)
	row.add_child(text)
	var name_l := UIKit.label(tool.display_name if tool else "%s (NOT OWNED)" % String(category).to_upper(), &"", false, Palette.TEXT if tool else Palette.TEXT_DIM, 16)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	text.add_child(name_l)
	if tool:
		# Only what changes how it handles: wear. Specs are in the tooltip.
		var cond := InventoryManager.get_tool_condition(tool.id)
		if cond < 60.0:
			text.add_child(UIKit.label("worn: %d%%" % roundi(cond), &"SubHeaderLabel", false, Palette.WARN if cond >= 25.0 else Palette.DANGER))
	if index < 9:
		var key := UIKit.label("[%s]" % Controls.key_name("tool_%d" % (index + 1)), &"MonoLabel", false, Palette.ACCENT)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(key)
	return m


func _tooltip(category: StringName, tool: ToolData, index: int) -> String:
	if tool == null:
		return "No %s owned. Buy one at SUPPLY." % String(category).to_upper()
	return "%s  [%s]\nT%d · precision %.2f · speed %.2f · condition %d%%\n%s" % [tool.display_name, Controls.key_name("tool_%d" % (index + 1)) if index < 9 else "-",
		tool.tier, tool.precision * InventoryManager.tool_condition_factor(tool.id), tool.speed, roundi(InventoryManager.get_tool_condition(tool.id)), tool.description]


func get_button(category: StringName) -> Button:
	return _buttons.get(category) as Button


func clear_selection() -> void:
	for b: Button in _buttons.values():
		b.set_pressed_no_signal(false)
	selected = &""
	tool_selected.emit(selected)


## Keyboard: select by rack position (0-based). Returns false if empty/unowned.
func select_index(i: int) -> bool:
	if i < 0 or i >= categories.size():
		return false
	var b := get_button(categories[i])
	if b == null or b.disabled:
		return false
	b.button_pressed = true
	tool_hovered.emit(categories[i])
	return true


## Keyboard: Q / R step through owned tools (wraps).
func cycle(direction: int) -> void:
	if categories.is_empty():
		return
	var start := categories.find(selected)
	if start < 0:
		start = -1 if direction > 0 else 0
	for step in range(1, categories.size() + 1):
		var i := posmod(start + direction * step, categories.size())
		if select_index(i):
			return


func set_hint(category: StringName) -> void:
	_hint_category = category


## Puts the instrument for `category` in hand (the stage's tool, at stage
## start). Returns false if it isn't owned / usable.
func select_category(category: StringName) -> bool:
	var b := get_button(category)
	if b == null or b.disabled:
		return false
	if selected == category and b.button_pressed:
		return true
	b.button_pressed = true
	return true


func _on_toggled(pressed: bool, category: StringName) -> void:
	# Clicking the tool you're holding keeps it in hand (right-click puts it
	# down); a toggle-off click on the active tool felt like a dead click.
	# (Only a click on the held tool itself: when you switch tools the group
	# un-presses the old one first, and that must go through.)
	if not pressed and selected == category and _group.get_pressed_button() == null:
		get_button(category).set_pressed_no_signal(true)
		return
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
		button.draw_rect(Rect2(Vector2.ZERO, button.size).grow(-2.0), Color(Palette.WARN, a), false, 3.0)
