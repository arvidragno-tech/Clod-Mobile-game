extends Control
## Root scene. Applies the iPhone safe area (notch / Dynamic Island / home
## indicator) to the screen host and overlays, registers layers with
## UIManager and opens the main menu.

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _overlay_safe_area: MarginContainer = %OverlaySafeArea
@onready var _screen_host: Control = %ScreenHost
@onready var _fade: ColorRect = %Fade
@onready var _flash: ColorRect = %Flash
@onready var _toast_box: VBoxContainer = %ToastBox
@onready var _modal_host: Control = %ModalHost


func _ready() -> void:
	UIManager.register_layers(_screen_host, _fade, _flash, _toast_box, _modal_host)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	AudioManager.play_ambient(&"clinic")
	UIManager.go_to(UIManager.SCREEN_MAIN_MENU)


func _apply_safe_area() -> void:
	var insets := SafeAreaUtil.get_insets(get_viewport())
	for container: MarginContainer in [_safe_area, _overlay_safe_area]:
		container.add_theme_constant_override(&"margin_left", int(insets.position.x))
		container.add_theme_constant_override(&"margin_top", int(insets.position.y))
		container.add_theme_constant_override(&"margin_right", int(insets.size.x))
		container.add_theme_constant_override(&"margin_bottom", int(insets.size.y))
