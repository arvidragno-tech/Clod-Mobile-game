extends BaseScreen
## Settings: audio mix, feedback, text and accessibility. Changes apply and
## save immediately (Settings autoload). Opened from the main menu or the
## clinic pause menu; BACK returns to wherever it was opened from.

var _return_to: StringName = UIManager.SCREEN_MAIN_MENU
var _list: VBoxContainer


func on_enter(params: Dictionary) -> void:
	_return_to = StringName(str(params.get("return_to", UIManager.SCREEN_MAIN_MENU)))
	var m := UIKit.full_rect(UIKit.margin(10, 8, 10, 10))
	add_child(m)
	var col := UIKit.vbox(8)
	m.add_child(col)
	col.add_child(UIKit.header("SYSTEM · PREFERENCES", "SETTINGS", _back))
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = UIKit.vbox(10)
	UIKit.expand(_list)
	sc.add_child(_list)
	_build()


func _back() -> void:
	AudioManager.play_sfx(&"back")
	UIManager.go_to(_return_to)


func _build() -> void:
	UIKit.clear(_list)
	var audio := _section("AUDIO")
	_slider(audio, "MUSIC", "music_volume")
	_slider(audio, "AMBIENCE", "ambience_volume")
	_slider(audio, "EFFECTS", "sfx_volume")
	var feel := _section("FEEDBACK")
	_toggle(feel, "HAPTICS", "haptics", "Vibration on taps, mistakes and successes.")
	_toggle(feel, "SCREEN SHAKE", "screen_shake", "Camera shake on mistakes and crashes.")
	var text := _section("TEXT")
	_choice(text, "TEXT SPEED", "text_speed", Settings.TEXT_SPEED_NAMES)
	_toggle(text, "LARGE TEXT", "large_text", "Bigger body text across menus.")
	var access := _section("ACCESSIBILITY")
	_toggle(access, "HIGH CONTRAST", "high_contrast", "Brighter secondary text, lighter CRT overlay.")
	_toggle(access, "REDUCE MOTION", "reduce_motion", "No shake, flicker or glitch effects; fewer particles.")
	_list.add_child(UIKit.label("Status is never shown by colour alone: vitals, checks and neural bands always carry a label or symbol.", &"DimLabel", true, null, 13))
	var reset := UIKit.button("RESET TO DEFAULTS", &"GhostButton", _confirm_reset, "ResetSettings")
	_list.add_child(reset)


func _section(title: String) -> VBoxContainer:
	var card := UIKit.panel(&"CardPanel")
	var v := UIKit.vbox(8)
	card.add_child(v)
	v.add_child(UIKit.label(title, &"SubHeaderLabel"))
	_list.add_child(card)
	return v


func _slider(parent: Control, caption: String, key: String) -> void:
	var row := UIKit.hbox(8)
	var l := UIKit.label(caption, &"", false)
	l.custom_minimum_size.x = 92
	row.add_child(l)
	var s := HSlider.new()
	s.name = "Slider_%s" % key
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get(key))
	s.custom_minimum_size.y = GameConfig.MIN_TOUCH
	s.focus_mode = Control.FOCUS_NONE
	UIKit.expand(s)
	var pct := UIKit.label("%d%%" % roundi(s.value * 100), &"MonoLabel", false, Palette.ACCENT, 18)
	pct.custom_minimum_size.x = 44
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v * 100)
		Settings.set_value(key, v))
	# Audible preview when the finger lifts.
	s.drag_ended.connect(func(_c: bool) -> void: AudioManager.play_sfx(&"beep" if key != "sfx_volume" else &"confirm", 0.0))
	row.add_child(s)
	row.add_child(pct)
	parent.add_child(row)


func _toggle(parent: Control, caption: String, key: String, hint: String) -> void:
	var row := UIKit.hbox(8)
	var info := UIKit.vbox(0)
	UIKit.expand(info)
	info.add_child(UIKit.label(caption, &""))
	info.add_child(UIKit.label(hint, &"DimLabel", true, null, 13))
	row.add_child(info)
	var on := bool(Settings.get(key))
	var b := UIKit.button("ON" if on else "OFF", &"AccentButton" if on else &"Button", Callable(), "Toggle_%s" % key)
	b.custom_minimum_size.x = 76
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		Settings.set_value(key, not bool(Settings.get(key)))
		if key == "haptics" and Settings.haptics:
			UIManager.haptic(&"success")
		_build.call_deferred())
	row.add_child(b)
	parent.add_child(row)


func _choice(parent: Control, caption: String, key: String, names: Array[String]) -> void:
	parent.add_child(UIKit.label(caption, &""))
	var row := UIKit.hbox(4)
	for i in names.size():
		var b := UIKit.button(names[i], &"TabButton", Callable(), "Choice_%s_%d" % [key, i])
		b.toggle_mode = true
		b.button_pressed = int(Settings.get(key)) == i
		b.clip_text = true
		UIKit.expand(b)
		b.pressed.connect(func() -> void:
			Settings.set_value(key, i)
			_build.call_deferred())
		row.add_child(b)
	parent.add_child(row)
	var sample := TypewriterLabel.new()
	sample.text = "\"Lie still. This will sting.\""
	sample.theme_type_variation = &"DimLabel"
	sample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(sample)
	sample.play()


func _confirm_reset() -> void:
	UIManager.confirm("RESET SETTINGS?", "Audio, feedback, text and accessibility go back to defaults.", "RESET", func() -> void:
		Settings.reset_to_defaults()
		_build())
