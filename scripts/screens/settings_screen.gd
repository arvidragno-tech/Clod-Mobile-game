extends BaseScreen
## Settings (PC): GRAPHICS · AUDIO · CONTROLS · GAMEPLAY tabs. Changes apply
## and save immediately (Settings autoload, %APPDATA%/UndercityRipper/
## settings.cfg). Opened from the main menu (SETTINGS / CONTROLS) or the
## pause menu; BACK / ESC returns to wherever it was opened from.

const TABS := ["GRAPHICS", "AUDIO", "CONTROLS", "GAMEPLAY", "ACCESSIBILITY"]

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
	_tabs.custom_minimum_size.x = 1200
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


func is_rebinding() -> bool:
	return _listening != ""


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
		4: _build_accessibility()


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
	_choice_int(display, "FRAME RATE LIMIT", "fps_limit", Settings.FPS_NAMES, true)
	display.add_child(UIKit.label("Fullscreen and borderless use your desktop resolution. The game renders a 1920×1080 canvas and letterboxes other aspect ratios.", &"DimLabel", true))
	var pixels := UIKit.section(left, "PIXEL ART")
	_choice_str(pixels, "PIXEL SCALING", "pixel_scaling", Settings.PIXEL_SCALING, Settings.PIXEL_SCALING_NAMES, true)
	_choice_str(pixels, "TEXTURE FILTERING", "texture_filter", ["nearest", "linear"], ["NEAREST (PIXEL PERFECT)", "LINEAR (SOFT)"], true)
	var size := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	var sc := minf(size.x / 1920.0, size.y / 1080.0)
	pixels.add_child(UIKit.label("Art pixel = 3 canvas units. Window %d×%d → %.2fx. Integer scaling keeps every pixel square (black borders on odd sizes)." % [size.x, size.y, sc], &"DimLabel", true))
	var fx := UIKit.section(right, "EFFECTS")
	_toggle(fx, "CRT FILTER", "crt_filter", "Vignette and grain over the whole screen.")
	_toggle(fx, "SCANLINES", "scanlines", "Thin dark lines like an old monitor.")
	_slider(fx, "SCREEN SHAKE", "shake_intensity", 0.0, 1.5, 0.05, true)
	_slider(fx, "ROOM BRIGHTNESS", "brightness", 0.8, 1.8, 0.05, true)
	_choice_int(fx, "LIGHTING QUALITY", "lighting_quality", Settings.EFFECTS_NAMES)
	_choice_int(fx, "PARTICLE QUALITY", "effects_quality", Settings.EFFECTS_NAMES)
	_toggle(fx, "GLOW", "glow", "Emissive cyberware, monitors and signs glow and flicker.")
	_toggle(fx, "ENVIRONMENT EFFECTS", "environment_effects", "Dust in the lamp light, steam, sparks, drips and rain.")


func _build_audio() -> void:
	var left := _column()
	var right := _column()
	var mix := UIKit.section(left, "MIX")
	_slider(mix, "MASTER", "master_volume")
	_slider(mix, "MUSIC", "music_volume")
	_slider(mix, "SOUND EFFECTS", "sfx_volume")
	_slider(mix, "AMBIENT", "ambience_volume")
	_slider(mix, "DIALOGUE", "dialogue_volume")
	_slider(mix, "INTERFACE", "ui_volume")
	var info := UIKit.section(right, "SOUNDSCAPE")
	info.add_child(UIKit.label("Each slider drives its own audio bus: music, effects (tools, vitals, the city), ambient beds (pumps, vents, CRT hum, rain), dialogue voices and interface clicks.", &"DimLabel", true))
	info.add_child(UIKit.label("Music is dark and minimal on purpose; conversations drop to a near-silent drone.", &"DimLabel", true))


func _build_controls() -> void:
	var left := _column()
	left.custom_minimum_size.x = 520
	left.size_flags_horizontal = Control.SIZE_FILL
	var right := _column()
	right.size_flags_stretch_ratio = 2.0
	# Presets.
	var pre := UIKit.section(left, "PRESET", &"CardPanel", "", "")
	var cur := Controls.current_preset()
	var names: Array[String] = []
	var ids: Array[String] = []
	for p: String in Controls.PRESETS:
		ids.append(p)
		names.append(str(Controls.PRESET_LABELS[p]))
	_choice_row(pre, "LAYOUT", names, ids.find(cur), "preset", func(i: int) -> void:
		Controls.apply_preset(ids[i])
		_feedback("✓ Controls set to %s" % Controls.PRESET_LABELS[ids[i]], &"success"))
	pre.add_child(UIKit.label("Now: %s. DEFAULT: WASD + arrows. WASD: movement on WASD only. LEFT-HANDED: arrows + number pad, mouse in the left hand. Changing any key makes it CUSTOM." % Controls.PRESET_LABELS[cur], &"DimLabel", true))
	var mouse := UIKit.section(left, "MOUSE")
	_slider(mouse, "SENSITIVITY", "mouse_sensitivity", 0.25, 3.0, 0.05, true)
	mouse.add_child(UIKit.label("Affects implant rotation drags, wheel tuning and key nudges in surgery.", &"DimLabel", true))
	var help := UIKit.section(left, "FIXED MOUSE ACTIONS")
	for line in ["LEFT CLICK · select, use the active tool", "LEFT DRAG · cut, move implants, connect wires", "RIGHT CLICK · put the tool down / cancel / compare", "WHEEL · scroll lists, zoom the operating field", "Middle, side buttons, right click and the wheel can be bound to any action."]:
		help.add_child(UIKit.label(line, &"DimLabel", true))
	var clashes := Controls.all_conflicts()
	if not clashes.is_empty():
		var warn := UIKit.section(left, "⚠ CONFLICTS", &"DangerPanel")
		for id: String in clashes:
			var others: Array[String] = []
			for o: String in clashes[id]:
				others.append(str(Controls.ACTIONS[o]["label"]))
			warn.add_child(UIKit.label("%s shares a key with %s" % [Controls.ACTIONS[id]["label"], ", ".join(others)], &"DimLabel", true, Palette.WARN))
	pre.add_child(UIKit.button("RESET ALL CONTROLS", &"GhostButton", func() -> void:
		UIManager.confirm("RESET ALL CONTROLS?", "Every key and mouse binding goes back to the default layout.", "RESET", func() -> void:
			Controls.reset_bindings()
			_feedback("✓ All controls reset to defaults", &"success")), "ResetBindings"))
	# Bindings table with search.
	var keys := UIKit.section(right, "KEYBINDS", &"CardPanel", "click a key, then press the new key (with CTRL / SHIFT / ALT if you like) · ESC cancels · DEL unassigns")
	var top := UIKit.hbox(10)
	keys.add_child(top)
	var search := LineEdit.new()
	search.name = "ControlSearch"
	search.placeholder_text = "Search controls (map, tool, save, F5...)"
	search.custom_minimum_size = Vector2(420, GameConfig.MIN_CONTROL)
	search.clear_button_enabled = true
	search.text = _search
	UIKit.expand(search)
	top.add_child(search)
	_bind_status = UIKit.label(_status_text, &"MonoLabel", false, Palette.OK)
	_bind_status.name = "BindStatus"
	top.add_child(_bind_status)
	# The table scrolls on its own so PRESET / MOUSE stay in view beside it.
	var tsc := UIKit.scroll()
	tsc.name = "BindScroll"
	tsc.custom_minimum_size.y = 560
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	keys.add_child(tsc)
	_table = UIKit.vbox(6)
	_table.name = "BindTable"
	UIKit.expand(_table)
	tsc.add_child(_table)
	tsc.get_v_scroll_bar().value_changed.connect(func(v: float) -> void: _table_scroll = int(v))
	_restore_table_scroll(tsc, _table_scroll)
	search.text_changed.connect(func(t: String) -> void:
		_search = t
		_fill_bindings())
	_fill_bindings()


var _search: String = ""
var _table_scroll: int = 0


## Puts the rebuilt table back where the player was (after layout settles).
func _restore_table_scroll(tsc: ScrollContainer, to: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(tsc):
		tsc.scroll_vertical = to
var _table: VBoxContainer
var _bind_status: Label
var _status_text: String = ""


func _fill_bindings() -> void:
	if _table == null or not is_instance_valid(_table):
		return
	UIKit.clear(_table)
	var clashes := Controls.all_conflicts()
	var shown := Controls.search(_search)
	if shown.is_empty():
		_table.add_child(UIKit.label("No control matches \"%s\"." % _search, &"DimLabel"))
		return
	for cat: String in Controls.CATEGORIES:
		var ids := Controls.actions_in(cat).filter(func(i: String) -> bool: return shown.has(i))
		if ids.is_empty():
			continue
		var head := UIKit.hbox(10)
		var t := UIKit.label(str(Controls.CATEGORY_LABELS.get(cat, cat.to_upper())), &"SubHeaderLabel", false, Palette.ACCENT)
		UIKit.expand(t)
		head.add_child(t)
		var rc := UIKit.button("RESET CATEGORY", &"GhostButton", func() -> void:
			Controls.reset_category(cat)
			_feedback("✓ %s reset to defaults" % Controls.CATEGORY_LABELS.get(cat, cat), &"success"), "ResetCat_%s" % cat, 36)
		rc.disabled = ids.all(func(i: String) -> bool: return Controls.is_default(i))
		head.add_child(rc)
		_table.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override(&"h_separation", 10)
		grid.add_theme_constant_override(&"v_separation", 4)
		_table.add_child(grid)
		for h in ["ACTION", "PRIMARY", "SECONDARY", ""]:
			grid.add_child(UIKit.label(h, &"SubHeaderLabel"))
		for id: String in ids:
			var mark := "⚠ " if clashes.has(id) else ("○ " if Controls.is_unassigned(id) else "")
			var l := UIKit.label(mark + str(Controls.ACTIONS[id]["label"]) + (" *" if Controls.is_critical(id) else ""), &"", false, Palette.WARN if mark != "" else null)
			l.tooltip_text = "Always keeps at least one key." if Controls.is_critical(id) else ""
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			UIKit.expand(l)
			grid.add_child(l)
			var slots := Controls.get_slots(id)
			for slot in Controls.SLOTS:
				var txt := Controls.code_name(slots[slot]) if slots[slot] != 0 else "UNASSIGNED"
				var b := UIKit.button(txt, &"Button" if slots[slot] != 0 else &"GhostButton", Callable(), "Bind_%s_%d" % [id, slot], 40)
				b.custom_minimum_size.x = 170
				b.pressed.connect(_start_listening.bind(id, slot, b))
				grid.add_child(b)
			var r := UIKit.button("↺", &"GhostButton", func() -> void:
				var before := Controls.key_name(id)
				Controls.reset_action(id)
				_feedback("✓ %s reset (%s → %s)" % [Controls.ACTIONS[id]["label"], before, Controls.key_name(id)], &"success"), "ResetBind_%s" % id, 40)
			r.tooltip_text = "Reset this action to its default"
			r.disabled = Controls.is_default(id)
			grid.add_child(r)


## One line of feedback for a controls change: the status label and a toast.
func _feedback(text: String, kind: StringName) -> void:
	_status_text = text
	UIManager.show_toast(text, kind)
	_build.call_deferred()


func _build_gameplay() -> void:
	var left := _column()
	var right := _column()
	var text := UIKit.section(left, "TEXT AND DIALOGUE")
	_choice_int(text, "TEXT SPEED", "text_speed", Settings.TEXT_SPEED_NAMES)
	var sample := TypewriterLabel.new()
	sample.text = "\"Lie still. This will sting.\""
	sample.theme_type_variation = &"DimLabel"
	sample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sample)
	sample.play()
	_toggle(text, "AUTO-ADVANCE DIALOGUE", "auto_advance", "Lines without choices move on by themselves.")
	_toggle(text, "PAUSE DURING DIALOGUE", "pause_dialogue", "Nobody walks in while you're talking.")
	_toggle(text, "STORY CUTSCENES", "story_cutscenes", "Short scenes at chapter changes and big story moments. ESC skips any of them.")
	var play := UIKit.section(left, "GAME")
	_choice_int(play, "DIFFICULTY", "difficulty", Settings.DIFFICULTY_NAMES)
	play.add_child(UIKit.label("STORY: wider tolerances, more time, cheaper rent. BRUTAL: tight hands, short timers, expensive city.", &"DimLabel", true))
	_choice_int(play, "AUTOSAVE", "autosave", Settings.AUTOSAVE_NAMES)
	_toggle(play, "PAUSE ON FOCUS LOSS", "pause_focus_loss", "Alt-Tab freezes the patient and the door.")
	_choice_int(play, "EMERGENCY COUNTDOWN", "time_pressure", Settings.TIME_PRESSURE_NAMES)
	play.add_child(UIKit.label("How long a bleeding patient waits for your triage decision. OFF: they wait until you decide.", &"DimLabel", true))
	var help := UIKit.section(right, "HELP")
	# One setting for all guidance (tutorial, gradual sections, first-time cards).
	_choice_row(help, "TUTORIAL & GUIDANCE", Settings.GUIDANCE_MODE_NAMES, Settings.guidance_mode(), "guidance_mode", Settings.set_guidance_mode)
	help.add_child(UIKit.label("GUIDED: the first operation step by step; new sections appear when they become useful, each with a short introduction. BRIEF: no tutorial; new sections appear with a one-line notice. OFF: every section from the start, no tutorial.", &"DimLabel", true))
	_toggle(help, "CONFIRM DANGEROUS ACTIONS", "confirm_dangerous", "Ask before firing staff, selling clinics, borrowing, refusing and aborting.")
	var rh := UIKit.button("SHOW FIRST-TIME HINTS AGAIN (%d SEEN)" % Settings.seen_hints.size(), &"GhostButton", func() -> void:
		Hints.reset_all()
		UIManager.show_toast("✓ First-time hints will show again", &"success")
		_build.call_deferred(), "ResetHints", 40)
	rh.disabled = Settings.seen_hints.is_empty()
	help.add_child(rh)
	_toggle(help, "TOOLTIPS", "tooltips", "Hover details on props, stats and buttons.")
	_toggle(help, "DAMAGE FEEDBACK", "damage_feedback", "Screen shake and red flashes on mistakes.")
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_toggle(help, "HAPTICS", "haptics", "Vibration on mistakes and successes.")


func _build_accessibility() -> void:
	var left := _column()
	var right := _column()
	var size := UIKit.section(left, "SIZE")
	size.add_child(UIKit.label("The whole game scales with the window (Graphics > RESOLUTION / WINDOW MODE). TEXT SCALE and LARGE TEXT size the text on top of that.", &"DimLabel", true))
	_slider(size, "TEXT SCALE", "text_scale", 0.85, 1.4, 0.05, true, true)
	_toggle(size, "LARGE TEXT", "large_text", "Extra size on body text across menus.")
	var vis := UIKit.section(left, "VISION")
	_toggle(vis, "HIGH CONTRAST", "high_contrast", "Brighter secondary text, lighter CRT overlay.")
	_toggle(vis, "COLOUR-BLIND INDICATORS", "colorblind", "Adds [+] [~] [!] markers wherever good / risky / bad is colour-coded.")
	var motion := UIKit.section(right, "MOTION AND EFFECTS")
	_toggle(motion, "REDUCED SHAKE", "reduced_shake", "Shake is kept but gentle.")
	_toggle(motion, "REDUCED FLASHING", "reduced_flashing", "No strobing lights, glitch bursts or cyberware flicker; flashes dimmed.")
	_toggle(motion, "REDUCED EFFECTS", "reduced_effects", "Minimum particles, no CRT filter.")
	_toggle(motion, "REDUCE MOTION", "reduce_motion", "No shake, flicker, glitches or idle animation bursts.")
	motion.add_child(UIKit.label("Status is never shown by colour alone: vitals, checks, comparisons and neural bands always carry a label.", &"DimLabel", true))


# --- Rows ----------------------------------------------------------------------

func _slider(parent: Control, caption: String, key: String, lo: float = 0.0, hi: float = 1.0, step: float = 0.05, as_mult: bool = false, on_release: bool = false) -> void:
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
	# Layout-changing sliders (text scale) apply when the drag ends, so the
	# page doesn't relayout (and move the slider) under the mouse.
	var dragging := [false]
	s.drag_started.connect(func() -> void: dragging[0] = true)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = fmt.call(v)
		if not (on_release and dragging[0]):
			Settings.set_value(key, v))
	s.drag_ended.connect(func(_c: bool) -> void:
		dragging[0] = false
		if on_release:
			Settings.set_value(key, s.value)
			_build.call_deferred()
		AudioManager.play_sfx(&"beep" if key != "sfx_volume" else &"confirm", 0.0))
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


func _choice_int(parent: Control, caption: String, key: String, names: Array[String], display: bool = false) -> void:
	_choice_row(parent, caption, names, int(Settings.get(key)), key, func(i: int) -> void:
		Settings.set_value(key, i)
		if display:
			Settings.apply_display())


func _choice_str(parent: Control, caption: String, key: String, values: Array[String], names: Array[String], display: bool = false) -> void:
	_choice_row(parent, caption, names, values.find(str(Settings.get(key))), key, func(i: int) -> void:
		Settings.set_value(key, values[i])
		if display:
			Settings.apply_display())


# --- Rebinding ---------------------------------------------------------------------

var _listen_slot: int = 0


func _start_listening(id: String, slot: int, b: Button) -> void:
	_stop_listening()
	_listening = id
	_listen_slot = slot
	_listen_button = b
	b.text = "PRESS ANY KEY..."
	b.theme_type_variation = &"AccentButton"


func _stop_listening() -> void:
	_pending_mod = 0
	if _listen_button and is_instance_valid(_listen_button) and _listening != "":
		_listen_button.text = Controls.code_name(Controls.get_slots(_listening)[_listen_slot])
		_listen_button.theme_type_variation = &"Button"
	_listening = ""
	_listen_button = null


var _pending_mod: int = 0


func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	var k := event as InputEventKey
	var m := event as InputEventMouseButton
	if k == null and m == null:
		return
	# A modifier alone binds on release (so CTRL then S makes CTRL+S).
	if k and not k.pressed:
		if _pending_mod != 0 and Controls.code_for(k) == _pending_mod:
			get_viewport().set_input_as_handled()
			var code := _pending_mod
			_pending_mod = 0
			_apply_bind(code)
		return
	if not event.is_pressed() or event.is_echo():
		return
	# The click that started listening is a left click; ignore left clicks.
	if m and m.button_index == MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if k and k.physical_keycode == KEY_ESCAPE and not k.ctrl_pressed and not k.shift_pressed and not k.alt_pressed and _listening != "pause":
		_stop_listening()
		_feedback("Rebinding cancelled", &"info")
		return
	if k and k.physical_keycode == KEY_DELETE:
		var id := _listening
		var slot := _listen_slot
		_listening = ""
		if Controls.clear_slot(id, slot):
			_feedback("○ %s: slot %d unassigned" % [Controls.ACTIONS[id]["label"], slot + 1], &"info")
		else:
			_feedback("⚠ %s needs at least one key" % Controls.ACTIONS[id]["label"], &"warn")
		return
	var code := Controls.code_for(event)
	if code == 0:
		return
	if k and (k.physical_keycode in Controls.MODIFIER_KEYS):
		_pending_mod = code
		if _listen_button and is_instance_valid(_listen_button):
			_listen_button.text = Controls.code_name(code) + "+..."
		return
	_pending_mod = 0
	_apply_bind(code)


func _apply_bind(code: int) -> void:
	var id := _listening
	var slot := _listen_slot
	_listening = ""
	_listen_button = null
	var label := str(Controls.ACTIONS[id]["label"])
	var before := Controls.code_name(Controls.get_slots(id)[slot]) if Controls.get_slots(id)[slot] != 0 else "unassigned"
	var clash := Controls.conflicts_for(id, code)
	if clash.is_empty():
		Controls.rebind(id, code, slot)
		AudioManager.play_sfx(&"confirm", 0.0)
		_feedback("✓ %s: %s → %s" % [label, before, Controls.code_name(code)], &"success")
		return
	var names: Array[String] = []
	for o: String in clash:
		names.append(str(Controls.ACTIONS[o]["label"]))
	var blockers := Controls.replace_blockers(id, code)
	var buttons: Array[Dictionary] = []
	if blockers.is_empty():
		buttons.append({"label": "REPLACE", "style": &"AccentButton", "name": "BindReplace", "callback": func() -> void:
			Controls.rebind(id, code, slot, "replace")
			_feedback("✓ %s: %s → %s · %s is now unassigned there" % [label, before, Controls.code_name(code), ", ".join(names)], &"success")})
	buttons.append({"label": "SWAP", "style": &"" if blockers.is_empty() else &"AccentButton", "name": "BindSwap", "callback": func() -> void:
		Controls.rebind(id, code, slot, "swap")
		_feedback("✓ %s: %s → %s · %s gets %s" % [label, before, Controls.code_name(code), ", ".join(names), before], &"success")})
	buttons.append({"label": "CANCEL", "style": &"GhostButton", "name": "BindCancel", "callback": func() -> void:
		_feedback("Nothing changed", &"info")})
	AudioManager.play_sfx(&"denied", 0.0)
	var body := "%s is already assigned to:\n%s\n\nREPLACE: they lose %s.  SWAP: they get %s instead." % [Controls.code_name(code), ", ".join(names), Controls.code_name(code), before]
	if not blockers.is_empty():
		body = "%s is already assigned to:\n%s\n\n%s must keep a key, so you can only SWAP (it gets %s)." % [Controls.code_name(code), ", ".join(names), ", ".join(names), before]
	UIManager.show_dialog("KEY CONFLICT", body, buttons)


func _confirm_reset() -> void:
	UIManager.confirm("RESET SETTINGS?", "Graphics, audio, controls and gameplay go back to defaults.", "RESET", func() -> void:
		Settings.reset_to_defaults()
		Settings.apply_display()
		_build())
