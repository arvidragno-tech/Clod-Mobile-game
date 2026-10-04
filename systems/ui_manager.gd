extends Node
## Screen navigation, transitions, toasts, dialogs and global feedback
## (screen shake, flashes, haptics). The Main scene registers its layers here
## on startup; screens never instantiate each other directly.

const SCREEN_MAIN_MENU := &"main_menu"
const SCREEN_CLINIC := &"clinic"
const SCREEN_CUSTOMER := &"customer"
const SCREEN_DIAGNOSIS := &"diagnosis"
const SCREEN_SURGERY := &"surgery"
const SCREEN_RESULTS := &"results"
const SCREEN_SHOP := &"shop"
const SCREEN_BLACK_MARKET := &"black_market"
const SCREEN_SKILLS := &"skills"
const SCREEN_UPGRADES := &"upgrades"
const SCREEN_DOSSIER := &"dossier"
const SCREEN_SETTINGS := &"settings"

const SCREEN_SCENES := {
	SCREEN_MAIN_MENU: "res://scenes/main_menu/main_menu.tscn",
	SCREEN_CLINIC: "res://scenes/clinic/clinic.tscn",
	SCREEN_CUSTOMER: "res://scenes/customer/customer_screen.tscn",
	SCREEN_DIAGNOSIS: "res://scenes/diagnosis/diagnosis_screen.tscn",
	SCREEN_SURGERY: "res://scenes/surgery/surgery_screen.tscn",
	SCREEN_RESULTS: "res://scenes/results/results_screen.tscn",
	SCREEN_SHOP: "res://scenes/shop/shop_screen.tscn",
	SCREEN_BLACK_MARKET: "res://scenes/black_market/black_market_screen.tscn",
	SCREEN_SKILLS: "res://scenes/skills/skills_screen.tscn",
	SCREEN_UPGRADES: "res://scenes/upgrades/upgrades_screen.tscn",
	SCREEN_DOSSIER: "res://scenes/dossier/dossier_screen.tscn",
	SCREEN_SETTINGS: "res://scenes/settings/settings_screen.tscn",
}

const DIALOG_SCENE := preload("res://ui/components/dialog.tscn")
const TOAST_COLORS := {
	&"info": Palette.ACCENT,
	&"success": Palette.OK,
	&"warn": Palette.WARN,
	&"danger": Palette.DANGER,
}

var current_screen: BaseScreen = null
var current_screen_id: StringName = &""
## Haptic feedback strengths: [duration_ms, amplitude 0..1].
const HAPTICS := {
	&"ui": [8, 0.25],
	&"success": [45, 0.55],
	&"warning": [35, 0.5],
	&"mistake": [60, 0.75],
	&"critical": [260, 1.0],
	&"implant": [80, 0.85],
}
## Which sound profile (music + ambience) each screen uses.
const SCREEN_AUDIO := {
	SCREEN_MAIN_MENU: &"menu", SCREEN_SURGERY: &"surgery", SCREEN_BLACK_MARKET: &"market",
}

var _screen_host: Control
var _fade: ColorRect
var _flash: ColorRect
var _toast_box: VBoxContainer
var _modal_host: Control
var _transitioning: bool = false
var _shake_tween: Tween


func register_layers(screen_host: Control, fade: ColorRect, flash: ColorRect, toast_box: VBoxContainer, modal_host: Control) -> void:
	_screen_host = screen_host
	_fade = fade
	_flash = flash
	_toast_box = toast_box
	_modal_host = modal_host
	get_tree().node_added.connect(_on_node_added)


func is_transitioning() -> bool:
	return _transitioning


# --- Navigation --------------------------------------------------------------

func go_to(screen_id: StringName, params: Dictionary = {}) -> void:
	if _transitioning or _screen_host == null:
		return
	var path: String = SCREEN_SCENES.get(screen_id, "")
	if path.is_empty():
		push_error("UIManager: unknown screen '%s'" % screen_id)
		return
	_transitioning = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if current_screen:
		var out := create_tween()
		out.tween_property(_fade, "color:a", 1.0, GameConfig.SCREEN_FADE_OUT_SEC)
		await out.finished
		current_screen.on_exit()
		current_screen.queue_free()
		current_screen = null
	close_modal()
	var scene := load(path) as PackedScene
	var screen := scene.instantiate() as BaseScreen
	_screen_host.add_child(screen)
	current_screen = screen
	current_screen_id = screen_id
	AudioManager.set_profile(SCREEN_AUDIO.get(screen_id, &"clinic"))
	screen.on_enter(params)
	EventBus.screen_changed.emit(screen_id)
	var fade_in := create_tween()
	fade_in.tween_property(_fade, "color:a", 0.0, GameConfig.SCREEN_FADE_IN_SEC)
	await fade_in.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false


# --- Feedback ----------------------------------------------------------------

func show_toast(text: String, kind: StringName = &"info") -> void:
	if _toast_box == null:
		return
	# Keep at most MAX_TOASTS on screen: the oldest makes way immediately.
	var live: Array[Node] = _toast_box.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	while live.size() >= GameConfig.MAX_TOASTS:
		var oldest: Node = live.pop_front()
		_toast_box.remove_child(oldest)
		oldest.queue_free()
	var toast := PanelContainer.new()
	toast.theme_type_variation = &"ToastPanel"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", TOAST_COLORS.get(kind, Palette.ACCENT))
	toast.add_child(label)
	_toast_box.add_child(toast)
	toast.modulate.a = 0.0
	var t := toast.create_tween()
	t.tween_property(toast, "modulate:a", 1.0, 0.12)
	t.tween_interval(GameConfig.TOAST_DURATION_SEC)
	t.tween_property(toast, "modulate:a", 0.0, 0.25)
	t.tween_callback(toast.queue_free)


func shake(strength: float = 4.0) -> void:
	if current_screen == null or not Settings.shake_allowed():
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	var target := current_screen
	_shake_tween = create_tween()
	var steps := 6
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * strength * falloff
		_shake_tween.tween_property(target, "position", offset.round(), GameConfig.SHAKE_DURATION_SEC / steps)
	_shake_tween.tween_property(target, "position", Vector2.ZERO, 0.03)


## Overlay container above screens (below modals) for coach marks.
func get_overlay_host() -> Control:
	return _modal_host.get_parent() as Control if _modal_host else null


## One place for "something good happened" feedback, so every purchase,
## unlock and upgrade feels consistent (sound + flash + haptic + toast).
func celebrate(kind: StringName, text: String = "") -> void:
	match kind:
		&"purchase":
			AudioManager.play_sfx(&"purchase", 0.03)
			flash(Palette.ACCENT, 0.08)
			haptic(&"success")
		&"bm_purchase":
			AudioManager.play_sfx(&"glitch", 0.05)
			AudioManager.play_sfx(&"purchase", 0.03)
			flash(Palette.BRAND, 0.14)
			haptic(&"success")
		&"tool":
			AudioManager.play_sfx(&"purchase", 0.0)
			AudioManager.play_sfx(&"activate", 0.0)
			flash(Palette.ACCENT, 0.15)
			haptic(&"implant")
		&"unlock":
			AudioManager.play_sfx(&"unlock", 0.0)
			flash(Palette.OK, 0.15)
			haptic(&"success")
		&"upgrade":
			AudioManager.play_sfx(&"servo", 0.0)
			AudioManager.play_sfx(&"levelup", 0.0)
			flash(Palette.BRAND, 0.28)
			shake(2.0)
			haptic(&"implant")
		&"sell":
			AudioManager.play_sfx(&"cash", 0.03)
			haptic(&"ui")
	if text != "":
		show_toast(text, &"success")


func is_shaking() -> bool:
	return _shake_tween != null and _shake_tween.is_running()


func flash(color: Color, peak_alpha: float = 0.25) -> void:
	if _flash == null:
		return
	_flash.color = Color(color, peak_alpha)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.3)


## Plays a haptic of the given kind (see HAPTICS). Respects Settings.
## Test builds can read last_haptic to verify feedback fired.
var last_haptic: StringName = &""


func haptic(kind: StringName = &"ui") -> void:
	if not Settings.haptics:
		return
	last_haptic = kind
	var h: Array = HAPTICS.get(kind, HAPTICS[&"ui"])
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(int(h[0]), float(h[1]))


# --- Dialogs -----------------------------------------------------------------

## Shows a modal dialog. `buttons` is an array of
## {"label": String, "style": StringName (theme variation), "callback": Callable}.
func show_dialog(title: String, body: String, buttons: Array[Dictionary]) -> GameDialog:
	var dialog := DIALOG_SCENE.instantiate() as GameDialog
	show_modal(dialog)
	dialog.setup(title, body, buttons)
	return dialog


func confirm(title: String, body: String, confirm_label: String, on_confirm: Callable, danger: bool = false) -> void:
	var buttons: Array[Dictionary] = [
		{"label": "CANCEL", "style": &"GhostButton", "callback": Callable()},
		{"label": confirm_label, "style": &"DangerButton" if danger else &"AccentButton", "callback": on_confirm},
	]
	show_dialog(title, body, buttons)


func show_modal(content: Control) -> void:
	close_modal()
	_modal_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_host.add_child(content)


func close_modal() -> void:
	if _modal_host == null:
		return
	for child in _modal_host.get_children():
		_modal_host.remove_child(child)
		child.queue_free()
	_modal_host.mouse_filter = Control.MOUSE_FILTER_IGNORE


func has_modal() -> bool:
	return _modal_host != null and _modal_host.get_child_count() > 0


## Every button in the game gets a click sound + haptic tick automatically.
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(&"silent"):
		(node as BaseButton).pressed.connect(_on_any_button_pressed)


func _on_any_button_pressed() -> void:
	AudioManager.play_sfx(&"click", 0.02)
	haptic(&"ui")
