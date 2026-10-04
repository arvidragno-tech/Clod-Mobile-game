extends BaseScreen
## PC title screen: full-screen key art with the menu column on the darker
## left third. Mouse or keyboard (arrows / WASD + Enter, ESC on dialogs).

const FLICKER_MIN_SEC := 1.5
const FLICKER_MAX_SEC := 5.0

var _subtitle: Label
var _flicker_timer: float = 2.0
var _menu: VBoxContainer


func on_enter(_params: Dictionary) -> void:
	var backdrop := CityBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(UIKit.full_rect(backdrop))
	var m := UIKit.full_rect(UIKit.margin(140, 110, 140, 70))
	add_child(m)
	var row := UIKit.hbox(0)
	m.add_child(row)
	var col := UIKit.vbox(14)
	col.custom_minimum_size.x = 560
	row.add_child(col)
	row.add_child(UIKit.expand(Control.new()))
	col.add_child(UIKit.label("UNDERGROUND CYBER-SURGERY", &"SubHeaderLabel"))
	var title := UIKit.label("UNDERCITY", &"TitleLabel")
	col.add_child(title)
	_subtitle = UIKit.label("RIPPER", &"TitleLabel")
	_subtitle.add_theme_color_override(&"font_color", Palette.BRAND)
	_subtitle.add_theme_color_override(&"font_shadow_color", Color(Palette.BRAND_DIM, 0.8))
	_subtitle.add_theme_font_size_override(&"font_size", 96)
	col.add_child(_subtitle)
	col.add_child(UIKit.label("Cut clean. Get paid. Stay off the grid.", &"DimLabel"))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 40
	col.add_child(spacer)
	_menu = UIKit.vbox(10)
	_menu.name = "Menu"
	col.add_child(_menu)
	var has_save := SaveManager.has_any_save()
	if has_save:
		var info := SaveManager.get_slot_info(SaveManager.latest_slot())
		var cont := _item("CONTINUE", &"AccentButton", GameManager.continue_game, "ContinueButton")
		cont.tooltip_text = "Slot %d · LV %d · %s" % [SaveManager.latest_slot(), int(info.get("level", 1)), EconomyManager.format_money(int(info.get("money", 0)))]
		cont.set_meta(&"default", true)
	var new_game := _item("NEW GAME", &"Button" if has_save else &"AccentButton", _on_new_game, "NewGameButton")
	if not has_save:
		new_game.set_meta(&"default", true)
	var load := _item("LOAD GAME", &"Button", func() -> void: UIManager.go_to(UIManager.SCREEN_LOAD, {"mode": "load", "return_to": UIManager.SCREEN_MAIN_MENU}), "LoadButton")
	load.disabled = not has_save
	_item("SETTINGS", &"GhostButton", func() -> void: UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.SCREEN_MAIN_MENU}), "SettingsButton")
	_item("CONTROLS", &"GhostButton", func() -> void: UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.SCREEN_MAIN_MENU, "tab": 2}), "ControlsButton")
	_item("CREDITS", &"GhostButton", func() -> void: UIManager.go_to(UIManager.SCREEN_CREDITS), "CreditsButton")
	_item("QUIT", &"DangerButton", _on_quit, "QuitButton")
	col.add_child(UIKit.expand(Control.new(), false, true))
	col.add_child(UIKit.label("v%s · WINDOWS PC · 1920×1080 · MOUSE + KEYBOARD" % ProjectSettings.get_setting("application/config/version", "0"), &"SubHeaderLabel"))
	var keys_panel := UIKit.panel(&"HudPanel")
	keys_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	keys_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_panel.offset_right = -40
	keys_panel.offset_bottom = -30
	keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys_panel.add_child(UIKit.label("[↑ ↓ / W S] select   [ENTER] confirm   [F9] quick load   [ESC] quit", &"SubHeaderLabel"))
	add_child(keys_panel)


func _item(text: String, style: StringName, cb: Callable, node_name: String) -> Button:
	var b := UIKit.button(text, style, cb, node_name, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_menu.add_child(b)
	return b


func _process(delta: float) -> void:
	if Settings.reduce_motion or _subtitle == null:
		return
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(FLICKER_MIN_SEC, FLICKER_MAX_SEC)
		var t := create_tween()
		t.tween_property(_subtitle, "modulate:a", 0.25, 0.04)
		t.tween_property(_subtitle, "modulate:a", 1.0, 0.05)
		t.tween_property(_subtitle, "modulate:a", 0.5, 0.03)
		t.tween_property(_subtitle, "modulate:a", 1.0, 0.06)


func _on_new_game() -> void:
	if SaveManager.has_any_save():
		UIManager.go_to(UIManager.SCREEN_LOAD, {"mode": "new", "return_to": UIManager.SCREEN_MAIN_MENU})
	else:
		GameManager.start_new_game_in_slot(1)


func _on_quit() -> void:
	UIManager.confirm("QUIT TO DESKTOP?", "Your clinic is saved.", "QUIT", GameManager.quit_to_desktop, true)


## ESC on the title screen asks to quit.
func on_escape() -> bool:
	_on_quit()
	return true
