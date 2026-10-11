class_name DialoguePanel
extends Control
## Conversation modal. A large animated portrait (blinks, breathes, looks
## around, cyberware flickers, the expression follows each line) with the
## speaker's name, occupation, faction and relationship status; the line
## types out at the player's text speed; choices sit beneath, tagged by
## approach and odds ([PERSUADE 62%], [BRIBE · 300 cr]). Check results and
## consequences are written into the running log.

signal closed()

const PORTRAIT_SCALE := 3

var dialogue_id: StringName
var _portrait: PixelPortrait
var _name: Label
var _sub: Label
var _status: Label
var _log: VBoxContainer
var _log_scroll: ScrollContainer
var _line: Label
var _options: VBoxContainer
var _type_tween: Tween
var _auto_timer: float = -1.0
var _voice_pitch: float = 1.0
var _last_chars: int = 0


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	add_child(UIKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var panel := UIKit.panel(&"AccentPanel")
	panel.custom_minimum_size = Vector2(1500, 0)
	center.add_child(panel)
	var row := UIKit.hbox(24)
	panel.add_child(row)
	# Portrait column
	var left := UIKit.vbox(8)
	row.add_child(left)
	_portrait = PixelPortrait.new()
	_portrait.name = "DialoguePortrait"
	_portrait.pixel_scale = PORTRAIT_SCALE
	_portrait.framing = PixelPortrait.Framing.BUST
	left.add_child(_portrait)
	_name = UIKit.label("", &"HeaderLabel")
	left.add_child(_name)
	_sub = UIKit.label("", &"DimLabel", true)
	_sub.custom_minimum_size.x = 420
	left.add_child(_sub)
	_status = UIKit.label("", &"SubHeaderLabel")
	left.add_child(_status)
	# Conversation column
	var right := UIKit.vbox(12)
	UIKit.expand(right, true, true)
	row.add_child(right)
	var head := UIKit.hbox(8)
	right.add_child(head)
	var title := UIKit.label("", &"SubHeaderLabel", false, Palette.ACCENT)
	title.name = "DialogueTitle"
	UIKit.expand(title)
	head.add_child(title)
	head.add_child(UIKit.label(StoryManager.act_title(), &"SubHeaderLabel"))
	_log_scroll = UIKit.scroll()
	_log_scroll.custom_minimum_size.y = 170
	right.add_child(_log_scroll)
	_log = UIKit.vbox(6)
	UIKit.expand(_log)
	_log_scroll.add_child(_log)
	var line_box := UIKit.panel(&"CardPanel")
	right.add_child(line_box)
	_line = UIKit.label("", &"MonoLabel", true)
	_line.name = "DialogueLine"
	_line.custom_minimum_size = Vector2(0, 120)
	line_box.add_child(_line)
	line_box.gui_input.connect(_on_line_input)
	_options = UIKit.vbox(8)
	right.add_child(_options)
	DialogueManager.node_changed.connect(_on_node)
	DialogueManager.ended.connect(_on_ended)
	DialogueManager.check_rolled.connect(_on_check)
	if not DialogueManager.is_active():
		DialogueManager.start(dialogue_id)
	AudioManager.enter_dialogue()
	if Settings.pause_dialogue:
		CustomerManager.set_arrivals_paused(true)
	title.text = str(DialogueManager.get_dialogue().get("title", "")).to_upper()
	_setup_speaker()
	_on_node(DialogueManager.current_node())


func _exit_tree() -> void:
	DialogueManager.node_changed.disconnect(_on_node)
	DialogueManager.ended.disconnect(_on_ended)
	DialogueManager.check_rolled.disconnect(_on_check)
	# ESC / closing the modal walks away from the conversation.
	if DialogueManager.is_active():
		DialogueManager.end()
	AudioManager.exit_dialogue()
	CustomerManager.set_arrivals_paused(false)
	closed.emit()


func _setup_speaker() -> void:
	var id := DialogueManager.character_id()
	var d := CharacterPortraitManager.describe(id)
	if d.is_empty():
		return
	_portrait.set_appearance(d["appearance"], d["accent"], d["backdrop"], d["profile"])
	_voice_pitch = float(d.get("voice", 1.0))
	_name.text = str(d["name"]).to_upper()
	_sub.text = "%s · %s" % [d["subtitle"], d["faction"]]
	_refresh_status()


func _refresh_status() -> void:
	var id := DialogueManager.character_id()
	if not CharacterManager.has_character(id):
		return
	var st := CharacterManager.relationship_state(id)
	_status.text = "%s  (%+d)" % [st.to_upper(), CharacterManager.relationship(id)]
	_status.add_theme_color_override(&"font_color", CharacterManager.state_color(st))


func _process(delta: float) -> void:
	# Voice blips while the line types out.
	if _type_tween and _type_tween.is_running():
		var shown := int(_line.visible_ratio * _line.text.length())
		if shown - _last_chars >= 3:
			_last_chars = shown
			if _line.text.substr(shown, 1) != " ":
				AudioManager.play_voice(_voice_pitch)
	if _auto_timer > 0.0:
		_auto_timer -= delta
		if _auto_timer <= 0.0 and DialogueManager.is_active() and not DialogueManager.current_node().has("options"):
			_continue()


func _on_node(n: Dictionary) -> void:
	if n.is_empty() or not is_inside_tree():
		return
	_portrait.set_expression(str(n.get("expr", "neutral")))
	_refresh_status()
	var text := str(n.get("text", ""))
	_line.text = text
	_last_chars = 0
	if _type_tween:
		_type_tween.kill()
	var cps := Settings.chars_per_second()
	if cps > 0.0:
		_line.visible_ratio = 0.0
		_type_tween = create_tween()
		_type_tween.tween_property(_line, "visible_ratio", 1.0, text.length() / cps)
	else:
		_line.visible_ratio = 1.0
	_rebuild_log()
	_build_options()
	AudioManager.play_sfx(&"beep", 0.02)


func _rebuild_log() -> void:
	UIKit.clear(_log)
	var lines := DialogueManager.log_lines
	# Everything but the line currently on screen.
	for i in range(maxi(0, lines.size() - 9), lines.size() - 1):
		var l: Dictionary = lines[i]
		var you := str(l.get("speaker", "")) == "you"
		var txt := ("> " if you else "") + str(l["text"])
		if l.has("result"):
			txt = str(l["result"])
		var c: Color = Palette.ACCENT if you else Palette.TEXT_DIM
		if l.has("result"):
			c = Palette.OK if bool(l.get("success", true)) else Palette.DANGER
		_log.add_child(UIKit.label(txt, &"DimLabel", true, c, 14))
	await get_tree().process_frame
	if is_instance_valid(_log_scroll):
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _build_options() -> void:
	UIKit.clear(_options)
	_auto_timer = -1.0
	var opts := DialogueManager.options()
	if opts.is_empty():
		var last := DialogueManager.is_end_node()
		var b := UIKit.button("END CONVERSATION" if last else "CONTINUE  %s" % Controls.hint("context"), &"AccentButton", _continue, "DialogueEnd" if last else "DialogueNext", 52)
		_options.add_child(b)
		b.grab_focus.call_deferred()
		if Settings.get("auto_advance") == true and not last:
			_auto_timer = 1.6 + _line.text.length() / maxf(1.0, Settings.chars_per_second() if Settings.chars_per_second() > 0 else 60.0)
		return
	var i := 0
	for o in opts:
		var tag := str(o["label"])
		var txt := ("[%s]  " % tag if tag != "" else "") + str(o["text"])
		var b := UIKit.button(txt, &"GhostButton", _pick.bind(int(o["index"])), "DialogueOption_%d" % i, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override(&"font_color", DialogueManager.KIND_COLORS.get(str(o["kind"]), Palette.TEXT))
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = str(o["text"])
		if str(o["locked"]) != "":
			b.disabled = true
			b.tooltip_text = str(o["locked"])
		_options.add_child(b)
		if i == 0:
			b.grab_focus.call_deferred()
		i += 1


func _pick(index: int) -> void:
	if _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_line.visible_ratio = 1.0
	var before := Consequence.snapshot()
	var r := DialogueManager.choose(index)
	Consequence.show("", before)
	if r.is_empty():
		AudioManager.play_sfx(&"denied", 0.0)
		return
	var summary: Array = r.get("summary", [])
	if not summary.is_empty():
		DialogueManager.log_lines.insert(DialogueManager.log_lines.size() - (1 if DialogueManager.is_active() else 0),
			{"speaker": "system", "text": "", "result": "  " + ", ".join(summary), "success": bool(r["success"])})
		if is_inside_tree() and DialogueManager.is_active():
			_rebuild_log()


func _on_check(kind: StringName, success: bool, p: float) -> void:
	AudioManager.play_sfx(&"confirm" if success else &"denied", 0.0)
	var label := "%s %s (%d%%)" % [String(kind).to_upper(), "SUCCEEDED" if success else "FAILED", roundi(p * 100.0)]
	DialogueManager.log_lines.append({"speaker": "system", "text": "", "result": label, "success": success})


func _continue() -> void:
	if _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_line.visible_ratio = 1.0
		return
	DialogueManager.advance()


func _on_ended(_id: StringName) -> void:
	if is_inside_tree():
		UIManager.close_modal()


func _on_line_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_line.visible_ratio = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# Mark it handled first: answering can end the conversation and take the
	# panel out of the tree (no viewport afterwards).
	var vp := get_viewport()
	if (event.is_action("dialogue_next") or event.is_action("context")) and DialogueManager.options().is_empty():
		vp.set_input_as_handled()
		_continue()
		return
	for i in 4:
		if event.is_action("dialogue_%d" % (i + 1)):
			vp.set_input_as_handled()
			var b := _options.get_node_or_null("DialogueOption_%d" % i) as Button
			if b and not b.disabled:
				b.pressed.emit()
			return
