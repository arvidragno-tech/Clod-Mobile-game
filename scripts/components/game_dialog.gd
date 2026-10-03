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
	for spec in buttons:
		var b := Button.new()
		b.text = str(spec.get("label", "OK"))
		b.theme_type_variation = spec.get("style", &"")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = GameConfig.MIN_TOUCH
		b.focus_mode = Control.FOCUS_NONE
		var callback: Callable = spec.get("callback", Callable())
		b.pressed.connect(_on_button_pressed.bind(callback))
		_buttons.add_child(b)
	var panel := %Panel as Control
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.12)
	t.tween_property(panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_button_pressed(callback: Callable) -> void:
	UIManager.close_modal()
	if callback.is_valid():
		callback.call()
