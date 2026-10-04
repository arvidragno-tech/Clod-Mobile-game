extends Control
## Root scene (PC). Applies window/display settings and the pixel cursors,
## registers the overlay layers with UIManager and opens the main menu.

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
	Settings.apply_display()
	_apply_cursors()
	UIManager.go_to(UIManager.SCREEN_MAIN_MENU)


## Pixel-art hardware cursors (2x art, hard edges): arrow, pointing hand for
## anything clickable, crosshair for surgical work, grab while dragging.
func _apply_cursors() -> void:
	var hot: Dictionary = {}
	var d: Variant = DataLoader.load_json("res://assets/sprites/ui/cursors/hotspots.json")
	if d is Dictionary:
		hot = d
	var shapes := {"arrow": Input.CURSOR_ARROW, "hand": Input.CURSOR_POINTING_HAND, "cross": Input.CURSOR_CROSS,
		"grab": Input.CURSOR_DRAG}
	for name: String in shapes:
		var tex := load("res://assets/sprites/ui/cursors/%s.png" % name) as Texture2D
		if tex:
			var h: Array = hot.get(name, [0, 0])
			Input.set_custom_mouse_cursor(tex, shapes[name], Vector2(float(h[0]), float(h[1])))
	Input.set_custom_mouse_cursor(load("res://assets/sprites/ui/cursors/grab.png"), Input.CURSOR_CAN_DROP, Vector2(16, 16))


## Text size / contrast on the shared theme; calmer CRT for accessibility.
func _apply_settings() -> void:
	Accessibility.apply(theme if theme else ThemeDB.get_project_theme())
	Settings.apply_filter()
	var crt := get_node_or_null("CrtLayer/CrtOverlay") as ColorRect
	if crt and crt.material is ShaderMaterial:
		var m := crt.material as ShaderMaterial
		m.set_shader_parameter(&"noise_strength", 0.0 if Settings.reduce_motion else 0.025)
		m.set_shader_parameter(&"scanline_strength", 0.035 if Settings.high_contrast else 0.07)
		m.set_shader_parameter(&"vignette_strength", 0.2 if Settings.high_contrast else 0.35)
		crt.visible = Settings.effects_quality > 0
