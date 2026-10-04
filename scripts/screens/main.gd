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
	if OS.get_cmdline_user_args().has("--smoke-test") or OS.get_cmdline_args().has("--smoke-test"):
		_smoke_test.call_deferred()


## Release-build QA (`UndercityRipper.exe --smoke-test`): new game in slot 3,
## visit the main screens, save, reload, screenshot each step to
## user://smoke/, print SMOKE OK / SMOKE FAIL and quit. Used to verify the
## exported Windows build (save path, rendering, scenes in the .pck).
func _smoke_test() -> void:
	var fails: Array[String] = []
	var dir := "user://smoke"
	DirAccess.make_dir_recursive_absolute(dir)
	var step := func(id: StringName, params: Dictionary = {}) -> void:
		if id != &"":
			UIManager.go_to(id, params)
		for i in 90:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/%s.png" % [dir, UIManager.current_screen_id])
		if UIManager.current_screen_id != id and id != &"":
			fails.append("screen %s did not open" % id)
	await step.call(&"")
	GameManager.start_new_game_in_slot(3)
	TutorialManager.skip()
	for id: StringName in [UIManager.SCREEN_CLINIC, UIManager.SCREEN_INVENTORY, UIManager.SCREEN_DATABASE, UIManager.SCREEN_SHOP,
			UIManager.SCREEN_SKILLS, UIManager.SCREEN_UPGRADES, UIManager.SCREEN_DOSSIER, UIManager.SCREEN_SETTINGS]:
		await step.call(id, {"return_to": UIManager.SCREEN_CLINIC})
	var money := EconomyManager.money + 123
	EconomyManager.add_money(123)
	if not SaveManager.save_game():
		fails.append("save failed")
	SaveManager.reset_all()
	if not SaveManager.load_game() or EconomyManager.money != money:
		fails.append("reload mismatch")
	var path := ProjectSettings.globalize_path(SaveManager.save_path)
	if not FileAccess.file_exists(SaveManager.save_path):
		fails.append("no save file at " + path)
	print("SMOKE save file: ", path)
	print("SMOKE window: ", DisplayServer.window_get_size(), " mode ", DisplayServer.window_get_mode())
	print("SMOKE OK" if fails.is_empty() else "SMOKE FAIL: " + ", ".join(fails))
	SaveManager.use_slot(1)
	get_tree().quit(0 if fails.is_empty() else 1)


func _exit_tree() -> void:
	PixelArt.clear_cache()
	CharacterArt.clear_cache()


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
