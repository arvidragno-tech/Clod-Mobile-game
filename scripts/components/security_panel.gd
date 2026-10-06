class_name SecurityPanel
extends Control
## SECURITY: the heat level and what it means, and every break-in as a
## case: what was taken, the clues so far, ways to dig (cameras, questioning
## staff, asking around) and who to confront.

signal closed()

var _box: VBoxContainer


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	add_child(UIKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var p := UIKit.panel(&"AccentPanel")
	p.custom_minimum_size = Vector2(1200, 760)
	center.add_child(p)
	var outer := UIKit.vbox(10)
	p.add_child(outer)
	var head := UIKit.hbox(10)
	outer.add_child(head)
	var t := UIKit.label("SECURITY", &"HeaderLabel")
	UIKit.expand(t)
	head.add_child(t)
	head.add_child(UIKit.button("CLOSE  %s" % Controls.hint("pause"), &"GhostButton", _close, "SecurityClose", 40))
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	outer.add_child(sc)
	_box = UIKit.vbox(12)
	UIKit.expand(_box)
	sc.add_child(_box)
	SecurityManager.cases_changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	if SecurityManager.cases_changed.is_connected(_rebuild):
		SecurityManager.cases_changed.disconnect(_rebuild)
	closed.emit()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_box)
	var lv := SecurityManager.level()
	var hot := FactionManager.heat >= 50.0
	var lp := UIKit.panel(&"DangerPanel" if hot else &"CardPanel")
	_box.add_child(lp)
	var lv_box := UIKit.vbox(4)
	lp.add_child(lv_box)
	lv_box.add_child(UIKit.label("HEAT %d · %s" % [roundi(FactionManager.heat), str(lv.get("label", ""))], &"SubHeaderLabel", false, Palette.DANGER if hot else Palette.WARN))
	lv_box.add_child(UIKit.label(str(lv.get("text", "")), &"DimLabel", true))
	lv_box.add_child(UIKit.label("Break-in risk tonight: about %d%%. Security rating %d (FACILITY > SECURITY lowers it)." % [roundi(SecurityManager.theft_chance() * 100.0), ClinicManager.security_rating()], &"DimLabel", true, null, 13))
	if SecurityManager.cases.is_empty():
		_box.add_child(UIKit.label("No break-ins. Keep it that way.", &"DimLabel"))
	for i in range(SecurityManager.cases.size() - 1, -1, -1):
		_box.add_child(_case_card(SecurityManager.cases[i]))


func _case_card(c: Dictionary) -> Control:
	var id := int(c["id"])
	var open := str(c["status"]) == "open"
	var card := UIKit.panel(&"AccentPanel" if open else &"CardPanel")
	card.name = "Case_%d" % id
	var v := UIKit.vbox(6)
	card.add_child(v)
	v.add_child(UIKit.label("CASE #%d · DAY %d · %s" % [id, int(c["day"]), str(c["status"]).to_upper()], &"SubHeaderLabel", false, Palette.ACCENT if open else Palette.TEXT_DIM))
	v.add_child(UIKit.label("Taken: %s" % c["loot_text"], &"", true))
	for clue: Variant in c["clues"]:
		v.add_child(UIKit.label("· " + str(clue), &"DimLabel", true, Palette.TEXT, 14))
	if not open:
		v.add_child(UIKit.label(str(c.get("outcome", "")), &"DimLabel", true, Palette.OK if str(c["status"]) == "solved" else Palette.WARN, 14))
		return card
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override(&"h_separation", 8)
	acts.add_theme_constant_override(&"v_separation", 8)
	v.add_child(acts)
	for a: Array in [["cameras", "CHECK THE CAMERAS"], ["question", "QUESTION STAFF"], ["ask", "ASK AROUND (100)"]]:
		var why := SecurityManager.can_use(id, str(a[0]))
		var b := UIKit.button(str(a[1]), &"GhostButton", func() -> void:
			var clue := SecurityManager.investigate(id, str(a[0]))
			if clue != "":
				AudioManager.play_sfx(&"beep", 0.0)
				SaveManager.save_game(), "Investigate_%d_%s" % [id, a[0]], 36)
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else {"cameras": "Footage from the night.", "question": "Ask your staff. The innocent resent it.", "ask": "Pay the street for gossip."}[str(a[0])]
		acts.add_child(b)
	acts.add_child(UIKit.button("LET IT GO", &"GhostButton", func() -> void: SecurityManager.close_case(id), "CloseCase_%d" % id, 36))
	v.add_child(UIKit.label("CONFRONT:", &"SubHeaderLabel", false, Palette.WARN))
	var who := HFlowContainer.new()
	who.add_theme_constant_override(&"h_separation", 8)
	who.add_theme_constant_override(&"v_separation", 8)
	v.add_child(who)
	var i := 0
	for s in SecurityManager.suspects(id):
		var key := str(s["key"])
		var b2 := UIKit.button(str(s["label"]).to_upper(), &"DangerButton", Callable(), "Confront_%d_%d" % [id, i], 36)
		# Two clicks: the first arms it (stays in this panel), the second accuses.
		b2.pressed.connect(func() -> void:
			if not b2.has_meta(&"armed"):
				b2.set_meta(&"armed", true)
				b2.text = "ACCUSE %s? CLICK AGAIN" % str(s["label"]).to_upper()
				return
			var r := SecurityManager.confront(id, key)
			UIManager.show_toast(str(r.get("text", "")), &"success" if bool(r.get("right", false)) else &"danger")
			SaveManager.save_game())
		who.add_child(b2)
		i += 1
	return card


func _close() -> void:
	UIManager.close_modal()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
