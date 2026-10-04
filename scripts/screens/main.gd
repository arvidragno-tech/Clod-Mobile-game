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
	Settings.changed.connect(_apply_settings)
	SaveManager.save_failed.connect(func(reason: String) -> void:
		UIManager.show_toast("SAVE FAILED (%s). Free some storage." % reason, &"danger"))
	_apply_settings()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	UIManager.go_to(UIManager.SCREEN_MAIN_MENU)


func _apply_safe_area() -> void:
	var insets := SafeAreaUtil.get_insets(get_viewport())
	for container: MarginContainer in [_safe_area, _overlay_safe_area]:
		container.add_theme_constant_override(&"margin_left", int(insets.position.x))
		container.add_theme_constant_override(&"margin_top", int(insets.position.y))
		container.add_theme_constant_override(&"margin_right", int(insets.size.x))
		container.add_theme_constant_override(&"margin_bottom", int(insets.size.y))


## Text size / contrast on the shared theme; calmer CRT for accessibility.
func _apply_settings() -> void:
	Accessibility.apply(theme if theme else ThemeDB.get_project_theme())
	var crt := get_node_or_null("CrtLayer/CrtOverlay") as ColorRect
	if crt and crt.material is ShaderMaterial:
		var m := crt.material as ShaderMaterial
		m.set_shader_parameter(&"noise_strength", 0.0 if Settings.reduce_motion else 0.025)
		m.set_shader_parameter(&"scanline_strength", 0.035 if Settings.high_contrast else 0.07)
		m.set_shader_parameter(&"vignette_strength", 0.2 if Settings.high_contrast else 0.35)
