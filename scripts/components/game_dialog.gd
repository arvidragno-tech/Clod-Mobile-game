class_name GameDialog
extends Control
## Modal dialog with a title, body text and a row of buttons.
## Create through UIManager.show_dialog() / UIManager.confirm().

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _buttons: HBoxContainer = %Buttons


func setup(title: String, body: String, buttons: Array[Dictionary]) -> void:
	_title.text = title
	_body.text = body
	_body.visible = not body.is_empty()
	# Long bodies scroll inside the dialog so the buttons always fit.
	if body.length() > 220:
		var sc := ScrollContainer.new()
		sc.name = "BodyScroll"
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var max_h := clampf(get_viewport_rect().size.y - 330.0, 140.0, 420.0)
		sc.custom_minimum_size = Vector2(268, max_h)
		var parent := _body.get_parent()
		var idx := _body.get_index()
		parent.remove_child(_body)
		sc.add_child(_body)
		_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(sc)
		parent.move_child(sc, idx)
	# More than two choices stack vertically so each label stays readable.
	var container: BoxContainer = _buttons
	if buttons.size() > 2:
		container = VBoxContainer.new()
		container.add_theme_constant_override(&"separation", 8)
		_buttons.add_child(container)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for spec in buttons:
		var b := Button.new()
		if spec.has("name"):
			b.name = str(spec["name"])
		b.text = str(spec.get("label", "OK"))
		b.theme_type_variation = spec.get("style", &"")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = GameConfig.MIN_CONTROL
		b.focus_mode = Control.FOCUS_NONE
		var callback: Callable = spec.get("callback", Callable())
		b.pressed.connect(_on_button_pressed.bind(callback))
		container.add_child(b)
	# Fade in only: a scale pop-in (pivot set before layout) drew the buttons
	# away from where they click for the first moments.
	modulate.a = 0.0
	# Keyboard users land on the first (safe) choice.
	var first := find_children("*", "Button", true, false)
	if not first.is_empty():
		(first[0] as Button).call_deferred("grab_focus")
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


## ESC: activates the dialog's safe choice (RESUME / CANCEL / GOT IT /
## KEEP GOING...), i.e. the first button, unless the dialog is mandatory.
var escape_allowed: bool = true


func on_escape() -> void:
	if not escape_allowed:
		return
	var buttons := find_children("*", "Button", true, false)
	if not buttons.is_empty():
		(buttons[0] as Button).pressed.emit()


func _on_button_pressed(callback: Callable) -> void:
	UIManager.close_modal()
	if callback.is_valid():
		callback.call()
