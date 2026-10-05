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
const SCREEN_INVENTORY := &"inventory"
const SCREEN_DATABASE := &"database"
const SCREEN_LOAD := &"load_game"
const SCREEN_CREDITS := &"credits"
const SCREEN_BUSINESS := &"business"
const SCREEN_MAP := &"map"
const SCREEN_STAFF := &"staff"

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
	SCREEN_INVENTORY: "res://scenes/inventory/inventory_screen.tscn",
	SCREEN_DATABASE: "res://scenes/database/database_screen.tscn",
	SCREEN_LOAD: "res://scenes/load_game/load_game_screen.tscn",
	SCREEN_CREDITS: "res://scenes/credits/credits_screen.tscn",
	SCREEN_BUSINESS: "res://scenes/business/business_screen.tscn",
	SCREEN_MAP: "res://scenes/map/map_screen.tscn",
	SCREEN_STAFF: "res://scenes/staff/staff_screen.tscn",
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
	SCREEN_MAIN_MENU: &"menu", SCREEN_SURGERY: &"surgery", SCREEN_BLACK_MARKET: &"market", SCREEN_MAP: &"city",
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
	clear_toasts()
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

## Toasts belong to the screen that raised them.
func clear_toasts() -> void:
	if _toast_box:
		for t in _toast_box.get_children():
			_toast_box.remove_child(t)
			t.queue_free()


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
	if current_screen == null or not Settings.shake_allowed() or not Settings.damage_feedback:
		return
	strength *= Settings.shake_scale()
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
	if _flash == null or not Settings.damage_feedback:
		return
	if not Settings.flashing_allowed():
		peak_alpha *= 0.25
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


## The night's books after closing (BusinessManager.end_day report).
func show_day_report(report: Dictionary) -> void:
	var lines: Array[String] = []
	var ledger: Dictionary = report.get("ledger", {})
	var keys := ledger.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return int(ledger[x]) > int(ledger[y]))
	for k: Variant in keys:
		if int(ledger[k]) != 0:
			lines.append("%-22s %+6d" % [BusinessManager.label(StringName(str(k))), int(ledger[k])])
	if lines.is_empty():
		lines.append("A quiet day. Nothing changed hands.")
	lines.append("")
	lines.append("PROFIT  %+d      CASH  %d" % [int(report.get("profit", 0)), int(report.get("money", 0))])
	if int(report.get("debt", 0)) > 0:
		lines.append("DEBT    %d  (8%% a day)" % int(report["debt"]))
	for n: Variant in report.get("notes", []):
		lines.append("· " + str(n))
	var ok: Array[Dictionary] = [{"label": "OPEN UP · DAY %d" % (int(report.get("day", 1)) + 1), "style": &"AccentButton", "name": "DayReportClose"}]
	AudioManager.play_sfx(&"cash", 0.0)
	show_dialog("NIGHT %d · %s" % [int(report.get("day", 1)), str(report.get("clinic", "")).to_upper()], "\n".join(lines), ok)


func confirm(title: String, body: String, confirm_label: String, on_confirm: Callable, danger: bool = false) -> void:
	var buttons: Array[Dictionary] = [
		{"label": "CANCEL", "style": &"GhostButton", "callback": Callable()},
		{"label": confirm_label, "style": &"DangerButton" if danger else &"AccentButton", "callback": on_confirm},
	]
	show_dialog(title, body, buttons)


## Dangerous actions ask first (unless the player turned that off).
func guard(title: String, body: String, label: String, action: Callable) -> void:
	if Settings.confirm_dangerous:
		confirm(title, body, label, action, true)
	else:
		action.call()


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


## Every button in the game gets a click sound, a hover tick and the hand
## cursor automatically.
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(&"silent"):
		var b := node as BaseButton
		b.pressed.connect(_on_any_button_pressed)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if b.focus_mode == Control.FOCUS_NONE and not b.has_meta(&"no_focus"):
			b.focus_mode = Control.FOCUS_ALL
		b.mouse_entered.connect(_on_button_hover.bind(b))


func _on_button_hover(b: BaseButton) -> void:
	if not b.disabled and b.is_visible_in_tree():
		AudioManager.play_sfx(&"hover", 0.03)


# --- Desktop input ----------------------------------------------------------------

## Screens where the global hotkeys (I, J, B, M, C, F5/F9) navigate.
const HUB_SCREENS := [SCREEN_CLINIC, SCREEN_SHOP, SCREEN_SKILLS, SCREEN_UPGRADES, SCREEN_DOSSIER, SCREEN_INVENTORY,
	SCREEN_DATABASE, SCREEN_BLACK_MARKET, SCREEN_SETTINGS, SCREEN_CUSTOMER, SCREEN_BUSINESS, SCREEN_MAP, SCREEN_STAFF]


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	# First arrow/WASD/Enter press puts keyboard focus on the screen.
	if event.is_action("ui_up") or event.is_action("ui_down") or event.is_action("ui_left") or event.is_action("ui_right"):
		var nav_ok := has_modal() or current_screen == null or not (current_screen is BaseScreen) or (current_screen as BaseScreen).keyboard_nav
		if nav_ok and get_viewport().gui_get_focus_owner() == null:
			focus_first()
			get_viewport().set_input_as_handled()
			return
	if event.is_action("cycle_panel"):
		if cycle_panels():
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or _transitioning or current_screen == null:
		return
	if event.is_action("pause"):
		get_viewport().set_input_as_handled()
		_on_escape()
		return
	if has_modal():
		return
	var hub := HUB_SCREENS.has(current_screen_id)
	var routes := {"inventory": SCREEN_INVENTORY, "journal": SCREEN_DOSSIER, "database": SCREEN_DATABASE, "map": SCREEN_MAP, "facility": SCREEN_UPGRADES, "business": SCREEN_BUSINESS, "staff": SCREEN_STAFF}
	for action: String in routes:
		if event.is_action(action) and hub:
			get_viewport().set_input_as_handled()
			if current_screen_id != routes[action]:
				go_to(routes[action])
			return
	if event.is_action("customer_info") and hub and CustomerManager.has_customer():
		get_viewport().set_input_as_handled()
		GameManager.open_customer()
	elif event.is_action("quicksave") and hub:
		get_viewport().set_input_as_handled()
		GameManager.quick_save()
	elif event.is_action("quickload") and (hub or current_screen_id == SCREEN_MAIN_MENU):
		get_viewport().set_input_as_handled()
		GameManager.quick_load()


## ESC: close the dialog, else go back, else pause.
func _on_escape() -> void:
	if has_modal():
		var m := _modal_host.get_child(_modal_host.get_child_count() - 1)
		if m.has_method("on_escape"):
			m.call("on_escape")
		return
	if current_screen.has_method("on_escape") and current_screen.call("on_escape"):
		return
	var back := current_screen.find_child("BackButton", true, false) as BaseButton
	if back and back.is_visible_in_tree() and not back.disabled:
		back.pressed.emit()
		return
	if current_screen_id != SCREEN_MAIN_MENU:
		GameManager.open_pause_menu()


## Gives keyboard focus to the screen's preferred control (meta "default").
func focus_first() -> void:
	var root: Node = _modal_host.get_child(_modal_host.get_child_count() - 1) if has_modal() else current_screen
	if root == null:
		return
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.has_meta(&"default") and c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
			c.grab_focus()
			return
	for n in root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return


## TAB: moves keyboard focus to the next panel registered by the screen
## (screen.get_panels()). Returns false if the screen has none.
func cycle_panels() -> bool:
	if current_screen == null or has_modal() or not current_screen.has_method("get_panels"):
		return false
	var panels: Array = current_screen.call("get_panels")
	panels = panels.filter(func(p: Variant) -> bool: return is_instance_valid(p) and (p as Control).is_visible_in_tree())
	if panels.is_empty():
		return false
	var owner := get_viewport().gui_get_focus_owner()
	var idx := -1
	for i in panels.size():
		if owner and (panels[i] == owner or (panels[i] as Node).is_ancestor_of(owner)):
			idx = i
	for k in panels.size():
		var p: Control = panels[(idx + 1 + k) % panels.size()]
		for n in p.find_children("*", "Control", true, false):
			var c := n as Control
			if c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
				c.grab_focus()
				flash_panel(p)
				return true
	return false


func flash_panel(p: Control) -> void:
	var t := p.create_tween()
	p.modulate = Color(1.25, 1.35, 1.35)
	t.tween_property(p, "modulate", Color.WHITE, 0.25)


func _on_any_button_pressed() -> void:
	AudioManager.play_sfx(&"click", 0.02)
	haptic(&"ui")
