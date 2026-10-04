extends BaseScreen
## Settings (PC): GRAPHICS · AUDIO · CONTROLS · GAMEPLAY tabs. Changes apply
## and save immediately (Settings autoload, %APPDATA%/UndercityRipper/
## settings.cfg). Opened from the main menu (SETTINGS / CONTROLS) or the
## pause menu; BACK / ESC returns to wherever it was opened from.

const TABS := ["GRAPHICS", "AUDIO", "CONTROLS", "GAMEPLAY"]

var _return_to: StringName = UIManager.SCREEN_MAIN_MENU
var _tab: int = 0
var _body: HBoxContainer
var _tabs: HBoxContainer
## Action id waiting for a key press (rebinding), or "".
var _listening: String = ""
var _listen_button: Button


func on_enter(params: Dictionary) -> void:
	_return_to = StringName(str(params.get("return_to", UIManager.SCREEN_MAIN_MENU)))
	_tab = clampi(int(params.get("tab", 0)), 0, TABS.size() - 1)
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(bg))
	var m := UIKit.full_rect(UIKit.margin(140, 60, 140, 50))
	add_child(m)
	var col := UIKit.vbox(16)
	m.add_child(col)
	col.add_child(UIKit.header("SYSTEM · PREFERENCES", "SETTINGS", _back))
	_tabs = UIKit.tabs(TABS, _on_tab, "SettingsTab")
	_tabs.custom_minimum_size.x = 960
	_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_tabs)
	(_tabs.get_child(_tab) as Button).button_pressed = true
	var sc := UIKit.scroll()
	col.add_child(sc)
	_body = UIKit.hbox(20)
	UIKit.expand(_body)
	sc.add_child(_body)
	var foot := UIKit.hbox(12)
	col.add_child(foot)
	var path := UIKit.label("Settings file: %s" % ProjectSettings.globalize_path(Settings.PATH), &"SubHeaderLabel")
	path.clip_text = true
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.expand(path)
	foot.add_child(path)
	foot.add_child(UIKit.button("RESET ALL TO DEFAULTS", &"GhostButton", _confirm_reset, "ResetSettings"))
	_build()


func _back() -> void:
	AudioManager.play_sfx(&"back")
	UIManager.go_to(_return_to)


## ESC cancels a pending rebind first.
func on_escape() -> bool:
	if _listening != "":
		_stop_listening()
		return true
	return false


func _on_tab(i: int) -> void:
	_tab = i
	_stop_listening()
	_build()


func _column() -> VBoxContainer:
	var v := UIKit.vbox(14)
	UIKit.expand(v)
	_body.add_child(v)
	return v


func _build() -> void:
	UIKit.clear(_body)
	match _tab:
		0: _build_graphics()
		1: _build_audio()
		2: _build_controls()
		3: _build_gameplay()


func _build_graphics() -> void:
	var left := _column()
	var right := _column()
	var display := UIKit.section(left, "DISPLAY")
	_choice_str(display, "WINDOW MODE", "window_mode", Settings.WINDOW_MODES, Settings.WINDOW_MODE_NAMES, true)
	var res_names: Array[String] = []
	var res_values: Array[String] = []
	for r in Settings.RESOLUTIONS:
		res_values.append("%dx%d" % [r.x, r.y])
		res_names.append("%d×%d" % [r.x, r.y])
	_choice_str(display, "RESOLUTION (WINDOWED)", "resolution", res_values, res_names, true)
	_toggle(display, "VSYNC", "vsync", "Sync to the monitor refresh. Off = lower input latency, possible tearing.", true)
	display.add_child(UIKit.label("Fullscreen and borderless use your desktop resolution. The game renders a 1920×1080 canvas and letterboxes other aspect ratios.", &"DimLabel", true))
	var pixels := UIKit.section(right, "PIXEL ART")
	_choice_str(pixels, "TEXTURE FILTERING", "texture_filter", ["nearest", "linear"], ["NEAREST (CRISP)", "LINEAR (SOFT)"])
	var size := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	var sc := minf(size.x / 1920.0, size.y / 1080.0)
	pixels.add_child(UIKit.label("PIXEL SCALING: art pixel = 3 canvas units. Current window %d×%d → %.2fx canvas → %s." % [size.x, size.y, sc,
		"integer (%dx art pixels)" % roundi(sc * 3.0) if is_equal_approx(sc * 3.0, roundf(sc * 3.0)) else "fractional (nearest sampling keeps pixels sharp)"], &"DimLabel", true))
	pixels.add_child(UIKit.label("Integer-perfect at 1920×1080 (3x) and 1280×720 (2x).", &"DimLabel", true))
	var fx := UIKit.section(right, "EFFECTS")
	_choice_int(fx, "EFFECTS QUALITY", "effects_quality", Settings.EFFECTS_NAMES)
	fx.add_child(UIKit.label("LOW: no CRT overlay or signal glitches, fewer particles. HIGH: full effects.", &"DimLabel", true))


func _build_audio() -> void:
	var left := _column()
	var right := _column()
	var mix := UIKit.section(left, "MIX")
	_slider(mix, "MASTER", "master_volume")
	_slider(mix, "MUSIC", "music_volume")
	_slider(mix, "AMBIENCE", "ambience_volume")
	_slider(mix, "EFFECTS", "sfx_volume")
	var info := UIKit.section(right, "SOUNDSCAPE")
	info.add_child(UIKit.label("Music and ambience change with the place: the clinic hum, the street rain, the operating theatre and the black-market tunnels. Effects cover tools, vitals alarms and UI clicks.", &"DimLabel", true))


func _build_controls() -> void:
	var left := _column()
	var right := _column()
	var mouse := UIKit.section(left, "MOUSE")
	_slider(mouse, "SENSITIVITY", "mouse_sensitivity", 0.25, 3.0, 0.05, true)
	mouse.add_child(UIKit.label("Affects implant rotation drags, wheel tuning and key nudges in surgery.", &"DimLabel", true))
	var help := UIKit.section(left, "MOUSE BUTTONS")
	for line in ["LEFT CLICK · select, use the active tool", "LEFT DRAG · cut, move implants, connect wires", "RIGHT CLICK · put the tool down / cancel / compare", "WHEEL · scroll lists, zoom the operating field", "DOUBLE CLICK · inspect", "HOVER · details and highlights everywhere"]:
		help.add_child(UIKit.label(line, &"DimLabel", true))
	var groups := {}
	for id: String in Controls.ACTIONS:
		var g := str(Controls.ACTIONS[id]["group"])
		if not groups.has(g):
			groups[g] = []
		groups[g].append(id)
	var keys := UIKit.section(right, "KEY BINDINGS", &"CardPanel", "click a key, then press the new one")
	for g: String in groups:
		keys.add_child(UIKit.label(g.to_upper(), &"SubHeaderLabel", false, Palette.ACCENT))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override(&"h_separation", 18)
		grid.add_theme_constant_override(&"v_separation", 4)
		keys.add_child(grid)
		for id: String in groups[g]:
			var l := UIKit.label(str(Controls.ACTIONS[id]["label"]), &"")
			UIKit.expand(l)
			grid.add_child(l)
			var b := UIKit.button(Controls.key_name(id), &"Button", Callable(), "Bind_%s" % id, 44)
			b.custom_minimum_size.x = 200
			b.pressed.connect(_start_listening.bind(id, b))
			grid.add_child(b)
	keys.add_child(UIKit.button("RESET KEY BINDINGS", &"GhostButton", func() -> void:
		Controls.reset_bindings()
		_build(), "ResetBindings"))
	keys.add_child(UIKit.label("A key already in use is swapped onto the other action, so nothing is left unbound. Arrows / WASD always navigate menus.", &"DimLabel", true))


func _build_gameplay() -> void:
	var left := _column()
	var right := _column()
	var text := UIKit.section(left, "TEXT")
	_choice_int(text, "TEXT SPEED", "text_speed", Settings.TEXT_SPEED_NAMES)
	var sample := TypewriterLabel.new()
	sample.text = "\"Lie still. This will sting.\""
	sample.theme_type_variation = &"DimLabel"
	sample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sample)
	sample.play()
	_toggle(text, "LARGE TEXT", "large_text", "Bigger body text across menus.")
	var feel := UIKit.section(left, "FEEDBACK")
	_toggle(feel, "SCREEN SHAKE", "screen_shake", "Camera shake on mistakes and crashes.")
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_toggle(feel, "HAPTICS", "haptics", "Vibration on mistakes and successes.")
	var access := UIKit.section(right, "ACCESSIBILITY")
	_toggle(access, "HIGH CONTRAST", "high_contrast", "Brighter secondary text, lighter CRT overlay.")
	_toggle(access, "REDUCE MOTION", "reduce_motion", "No shake, flicker or glitch effects; fewer particles.")
	access.add_child(UIKit.label("Status is never shown by colour alone: vitals, checks, comparisons and neural bands always carry a label or symbol.", &"DimLabel", true))
	var tut := UIKit.section(right, "TUTORIAL")
	tut.add_child(UIKit.label("Coach marks guide your first operation. HOW TO PLAY in the pause menu (ESC) recaps the controls any time.", &"DimLabel", true))


# --- Rows ----------------------------------------------------------------------

func _slider(parent: Control, caption: String, key: String, lo: float = 0.0, hi: float = 1.0, step: float = 0.05, as_mult: bool = false) -> void:
	var row := UIKit.hbox(12)
	var l := UIKit.label(caption, &"", false)
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var s := HSlider.new()
	s.name = "Slider_%s" % key
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get(key))
	s.custom_minimum_size.y = GameConfig.MIN_CONTROL
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIKit.expand(s)
	var fmt := func(v: float) -> String: return ("x%.2f" % v) if as_mult else ("%d%%" % roundi(v * 100))
	var pct := UIKit.label(fmt.call(s.value), &"MonoLabel", false, Palette.ACCENT)
	pct.custom_minimum_size.x = 90
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		pct.text = fmt.call(v)
		Settings.set_value(key, v))
	s.drag_ended.connect(func(_c: bool) -> void: AudioManager.play_sfx(&"beep" if key != "sfx_volume" else &"confirm", 0.0))
	row.add_child(s)
	row.add_child(pct)
	parent.add_child(row)


func _toggle(parent: Control, caption: String, key: String, hint: String, display: bool = false) -> void:
	var row := UIKit.hbox(12)
	var info := UIKit.vbox(0)
	UIKit.expand(info)
	info.add_child(UIKit.label(caption, &""))
	info.add_child(UIKit.label(hint, &"DimLabel", true))
	row.add_child(info)
	var on := bool(Settings.get(key))
	var b := UIKit.button("ON" if on else "OFF", &"AccentButton" if on else &"Button", Callable(), "Toggle_%s" % key)
	b.custom_minimum_size.x = 110
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		Settings.set_value(key, not bool(Settings.get(key)))
		if display:
			Settings.apply_display()
		_build.call_deferred())
	row.add_child(b)
	parent.add_child(row)


func _choice_row(parent: Control, caption: String, names: Array[String], current: int, key: String, on_pick: Callable) -> void:
	parent.add_child(UIKit.label(caption, &""))
	var row := UIKit.hbox(6)
	for i in names.size():
		var b := UIKit.button(names[i], &"TabButton", Callable(), "Choice_%s_%d" % [key, i])
		b.toggle_mode = true
		b.button_pressed = current == i
		b.clip_text = true
		UIKit.expand(b)
		b.pressed.connect(func() -> void:
			on_pick.call(i)
			_build.call_deferred())
		row.add_child(b)
	parent.add_child(row)


func _choice_int(parent: Control, caption: String, key: String, names: Array[String]) -> void:
	_choice_row(parent, caption, names, int(Settings.get(key)), key, func(i: int) -> void: Settings.set_value(key, i))


func _choice_str(parent: Control, caption: String, key: String, values: Array[String], names: Array[String], display: bool = false) -> void:
	_choice_row(parent, caption, names, values.find(str(Settings.get(key))), key, func(i: int) -> void:
		Settings.set_value(key, values[i])
		if display:
			Settings.apply_display())


# --- Key rebinding ---------------------------------------------------------------

func _start_listening(id: String, b: Button) -> void:
	_stop_listening()
	_listening = id
	_listen_button = b
	b.text = "PRESS A KEY..."
	b.theme_type_variation = &"AccentButton"


func _stop_listening() -> void:
	if _listen_button and is_instance_valid(_listen_button):
		_listen_button.text = Controls.key_name(_listening) if _listening != "" else _listen_button.text
		_listen_button.theme_type_variation = &"Button"
	_listening = ""
	_listen_button = null


func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	if k.physical_keycode == KEY_ESCAPE and _listening != "pause":
		_stop_listening()
		return
	var key := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var id := _listening
	var swapped := Controls.rebind(id, key)
	_listening = ""
	_listen_button = null
	AudioManager.play_sfx(&"confirm", 0.0)
	if swapped != "":
		UIManager.show_toast("%s now on %s (swapped)" % [str(Controls.ACTIONS[swapped]["label"]), Controls.key_name(swapped)], &"warn")
	_build.call_deferred()


func _confirm_reset() -> void:
	UIManager.confirm("RESET SETTINGS?", "Graphics, audio, controls and gameplay go back to defaults.", "RESET", func() -> void:
		Settings.reset_to_defaults()
		Settings.apply_display()
		_build())
