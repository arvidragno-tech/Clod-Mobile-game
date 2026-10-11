extends BaseScreen
## A place in the city, where you are now: the street (LocationView), what
## it's like right now (activity, danger, police, whose turf), what's
## happening (an event to deal with, a missing patient's trail), who's here
## (cast, your patients, staff on a break, suppliers) and what you can do
## (services). RETURN TO CLINIC goes home the sensible way; CITY MAP to go
## anywhere else.

var _id: StringName
var _view: LocationView
var _left: VBoxContainer
var _right: VBoxContainer
var _status: Label
var _panels: Array[Control] = []
var _last_text: String = ""


func on_enter(_params: Dictionary) -> void:
	(func() -> void: Hints.first("follow")).call_deferred()
	_id = LocationManager.player_location
	if not LocationManager.is_away():
		GameManager.go_to_clinic.call_deferred()
		return
	var col := UIKit.workstation(self, &"map")
	col.add_child(UIKit.header("%s · %s" % [WorldManager.district_name(LocationManager.district_of(_id)).to_upper(), LocationManager.type_label(_id)],
		LocationManager.location_name(_id).to_upper(), _open_map))
	var row := UIKit.hbox(16)
	UIKit.expand(row, true, true)
	col.add_child(row)
	# Left: the street and what's going on.
	var lp := UIKit.panel(&"HudPanel")
	UIKit.expand(lp, true, true)
	row.add_child(lp)
	_panels.append(lp)
	var lsc := UIKit.scroll()
	UIKit.expand(lsc, true, true)
	lp.add_child(lsc)
	var lcol := UIKit.vbox(10)
	UIKit.expand(lcol, true, false)
	lsc.add_child(lcol)
	_view = LocationView.new()
	_view.name = "LocationView"
	_view.location_id = _id
	_view.custom_minimum_size = Vector2(0, 300)
	lcol.add_child(_view)
	_status = UIKit.label("", &"MonoLabel", true)
	lcol.add_child(_status)
	_left = UIKit.vbox(10)
	lcol.add_child(_left)
	# Right: people, services, travel.
	var rp := UIKit.panel(&"AccentPanel")
	rp.custom_minimum_size.x = 620
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(rp)
	_panels.append(rp)
	var rsc := UIKit.scroll()
	UIKit.expand(rsc, true, true)
	rp.add_child(rsc)
	_right = UIKit.vbox(10)
	UIKit.expand(_right, true, false)
	rsc.add_child(_right)
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: _refresh.call_deferred())
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _refresh.call_deferred())
	WorldSimulationManager.changed.connect(_refresh_deferred)
	# Something might already be going on as you walk in.
	if WorldSimulationManager.event_at(_id).is_empty() and WorldSimulationManager.auto_roll and not WorldSimulationManager.events.has(String(_id)):
		if randf() < 0.45:
			WorldSimulationManager.start_event(_id)
	_refresh()
	if WorldSimulationManager.has_encounter():
		TravelFlow.show_encounter.call_deferred()


func get_panels() -> Array[Control]:
	return _panels


var _queued := false


func _refresh_deferred() -> void:
	if _queued:
		return
	_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_queued = false
	if not is_inside_tree() or _left == null:
		return
	var st := WorldSimulationManager.state(_id)
	var dom := StringName(str(st["dominant"]))
	_status.text = "%s · %s · Activity %s · Danger %s · Police %s%s" % [TimeManager.stamp(), WorldSimulationManager.state_label(_id),
		WorldSimulationManager.activity_label(int(st["activity"])), UIKit.pips(int(st["danger"]), 4), UIKit.pips(int(st["authority"]), 4),
		(" · %s turf" % FactionManager.get_name_of(dom)) if (st["flags"] as Array).has(&"controlled") else ""]
	_status.add_theme_color_override(&"font_color", WorldSimulationManager.state_color(_id))
	_build_left()
	_build_right()


func _build_left() -> void:
	UIKit.clear(_left)
	var l := LocationManager.get_location(_id)
	_left.add_child(UIKit.label(str(l.get("description", "")), &"", true))
	var feel := "%s %s" % [str(l.get("architecture", "")), str(l.get("atmosphere", ""))]
	if feel.strip_edges() != "":
		_left.add_child(UIKit.label(feel.strip_edges(), &"DimLabel", true, Palette.TEXT_DIM, 14))
	if _last_text != "":
		var card := UIKit.panel(&"CardPanel")
		_left.add_child(card)
		card.add_child(UIKit.label(_last_text, &"", true, Palette.OK))
	# A missing patient's trail.
	var mc := WorldSimulationManager.missing_at(_id)
	if not mc.is_empty():
		var v := UIKit.section(_left, str(mc["title"]), &"AccentPanel")
		v.add_child(UIKit.label(str(mc["text"]), &"", true))
		var choices: Array = mc["choices"]
		for i in choices.size():
			var c: Dictionary = choices[i]
			var b := UIKit.button(str(c["label"]), &"AccentButton" if i == 0 else &"Button", _act_missing.bind(i), "Missing_%d" % i, 44)
			var reason := EventManager.get_choice_block_reason(c)
			b.disabled = reason != ""
			b.tooltip_text = reason
			v.add_child(b)
	# What's happening here now.
	var ev := WorldSimulationManager.event_at(_id)
	if not ev.is_empty():
		var v := UIKit.section(_left, "HAPPENING NOW · %s" % str(ev.get("title", "")), &"AccentPanel")
		v.add_child(UIKit.label(str(ev.get("text", "")), &"", true))
		var choices: Array = ev.get("choices", [])
		for i in choices.size():
			var c: Dictionary = choices[i]
			var mins := int(c.get("minutes", 0))
			var label := str(c.get("label", "OK")) + ((" (%s)" % TimeManager.duration_text(mins)) if mins > 0 else "")
			var b := UIKit.button(label, &"AccentButton" if i == 0 else &"Button", _choose.bind(i), "LocEvent_%d" % i, 44)
			var reason := EventManager.get_choice_block_reason(c)
			b.disabled = reason != ""
			v.add_child(b)
			if reason != "":
				v.add_child(UIKit.label("  " + reason, &"DimLabel", false, Palette.WARN, 13))
	# The street feed.
	var feed := WorldSimulationManager.feed_at(_id)
	if not feed.is_empty():
		var v := UIKit.section(_left, "HERE LATELY")
		for f: Dictionary in feed:
			v.add_child(UIKit.label("D%d %s  %s" % [int(f["day"]), str(f["time"]), str(f["text"])], &"DimLabel", true, null, 14))


func _build_right() -> void:
	UIKit.clear(_right)
	# Travel first: going home is always one click.
	var tv := UIKit.section(_right, "LEAVE")
	var home := LocationManager.best_trip(LocationManager.CLINIC)
	var hb := LocationManager.leave_block(LocationManager.CLINIC)
	var txt := "RETURN TO CLINIC"
	if not home.is_empty():
		txt += "  ·  %s %s%s" % [str(home["label"]).to_lower(), TimeManager.duration_text(int(home["minutes"])), (" · %s" % EconomyManager.format_money(int(home["cost"]))) if int(home["cost"]) > 0 else ""]
	var rb := UIKit.button(txt, &"AccentButton", _go_home, "ReturnClinic", 48)
	rb.disabled = hb != "" or home.is_empty()
	rb.tooltip_text = hb
	tv.add_child(rb)
	tv.add_child(UIKit.button("CITY MAP  ·  go somewhere else", &"Button", _open_map, "OpenMap", 44))
	if TimeManager.minute >= TimeManager.close_minute() - 60:
		tv.add_child(UIKit.label("It's almost four. Time to go home and close up.", &"DimLabel", true, Palette.WARN, 14))
	if not ClinicLifeManager.waiting.is_empty():
		tv.add_child(UIKit.label("%d waiting at your clinic." % ClinicLifeManager.waiting.size(), &"DimLabel", true, Palette.WARN, 14))
	if CustomerManager.queue.size() > 0:
		tv.add_child(UIKit.label("%d on their way to your clinic." % CustomerManager.queue.size(), &"DimLabel", true, Palette.TEXT_DIM, 14))
	# People.
	var pv := UIKit.section(_right, "PEOPLE HERE")
	var people := WorldSimulationManager.people_at(_id)
	if people.is_empty():
		pv.add_child(UIKit.label("Nobody you know. %s" % _crowd_line(), &"DimLabel", true))
	for i in people.size():
		var p: Dictionary = people[i]
		var r := UIKit.hbox(8)
		pv.add_child(r)
		var info := UIKit.vbox(0)
		UIKit.expand(info)
		r.add_child(info)
		var kind := str(p["kind"])
		var col: Color = {"cast": Palette.ACCENT, "staff": Palette.OK, "supplier": Palette.WARN}.get(kind, Palette.TEXT)
		info.add_child(UIKit.label(str(p["name"]), &"SubHeaderLabel", false, col))
		info.add_child(UIKit.label(str(p["note"]), &"DimLabel", true, null, 13))
		var can := WorldSimulationManager.can_talk(kind, str(p["id"]))
		var label := "TALK" if not bool(p.get("talk", false)) else "THEY WANT A WORD"
		var b := UIKit.button(label, &"AccentButton" if bool(p.get("talk", false)) else &"Button", _talk.bind(kind, str(p["id"])), "Talk_%d" % i, 40)
		b.custom_minimum_size.x = 170
		b.disabled = not can
		b.tooltip_text = "" if can else "You've talked today"
		r.add_child(b)
		# FOLLOW: the game keeps track of where they go next.
		var fkind := "cast" if kind == "cast" else ("person" if kind == "patient" else "")
		if fkind != "":
			var pid := str(p["id"])
			var pname := str(p["name"])
			var on := Follows.is_following(Follows.key(fkind, pid))
			var f := UIKit.button("★" if on else "☆", &"AccentButton" if on else &"GhostButton", func() -> void:
				var now := Follows.toggle(fkind, pid, pname)
				UIManager.show_toast(("★ Following %s: the journal shows where they are" if now else "Stopped following %s") % pname, &"success" if now else &"info")
				_refresh_deferred(), "FollowPerson_%d" % i, 40)
			f.tooltip_text = "Follow: keep track of where %s is (journal MAIN, clinic priorities, ★ on the map)." % pname
			r.add_child(f)
	# Services.
	var sv := UIKit.section(_right, "WHAT YOU CAN DO HERE")
	var services := LocationServices.list(_id)
	if services.is_empty():
		sv.add_child(UIKit.label("Nothing for you here but the view.", &"DimLabel", true))
	for s: Dictionary in services:
		var mins := int(s.get("minutes", 0))
		var cost := int(s.get("cost", 0))
		var bits: Array[String] = []
		if mins > 0:
			bits.append(TimeManager.duration_text(mins))
		if cost > 0:
			bits.append(EconomyManager.format_money(cost))
		var b := UIKit.button("%s%s" % [str(s["label"]), ("  ·  " + " · ".join(bits)) if not bits.is_empty() else ""], &"Button", _service.bind(str(s["id"])), "Service_%s" % str(s["id"]), 44)
		b.disabled = str(s["block"]) != ""
		sv.add_child(b)
		sv.add_child(UIKit.label(str(s["block"]) if str(s["block"]) != "" else str(s["desc"]), &"DimLabel", true, Palette.WARN if str(s["block"]) != "" else null, 13))
		if str(s["id"]) == "checkpoint" and str(s["block"]) == "":
			var b2 := UIKit.button("TRY THE FENCE INSTEAD (risky)", &"GhostButton", _service.bind("checkpoint", 1), "Service_checkpoint_fence", 40)
			sv.add_child(b2)
	var dom := WorldSimulationManager.dominant_faction(_id)
	if dom != &"" and absf(WorldSimulationManager.price_mult(_id) - 1.0) > 0.01:
		sv.add_child(UIKit.label("Prices here x%.2f (%s: %s)" % [WorldSimulationManager.price_mult(_id), FactionManager.get_name_of(dom), FactionManager.get_standing(dom)], &"DimLabel", true, Palette.TEXT_DIM, 13))


func _crowd_line() -> String:
	var a := int(WorldSimulationManager.state(_id)["activity"])
	return ["The place is empty.", "A few strangers.", "Strangers going about their night.", "Packed with strangers."][clampi(a, 0, 3)]


func _choose(i: int) -> void:
	var before := Consequence.snapshot()
	var t := WorldSimulationManager.resolve_event(_id, i)
	Consequence.show("", before)
	AudioManager.play_sfx(&"stage", 0.0)
	_last_text = t
	SaveManager.save_game()
	_refresh()


func _act_missing(i: int) -> void:
	var before := Consequence.snapshot()
	var t := WorldSimulationManager.act_missing(_id, i)
	Consequence.show("", before)
	_last_text = t
	SaveManager.save_game()
	_refresh()


func _service(sid: String, option: int = 0) -> void:
	var before := Consequence.snapshot()
	var r := LocationServices.perform(_id, sid, option)
	if bool(r.get("ok", false)):
		Consequence.show("", before)
	if str(r.get("screen", "")) != "":
		match str(r["screen"]):
			"shop":
				UIManager.go_to(UIManager.SCREEN_SHOP)
			"black_market":
				UIManager.go_to(UIManager.SCREEN_BLACK_MARKET)
		return
	if not bool(r.get("ok", false)):
		AudioManager.play_sfx(&"denied")
		UIManager.show_toast(str(r.get("text", "")), &"warn")
		return
	AudioManager.play_sfx(&"stage", 0.0)
	_last_text = str(r.get("text", ""))
	_refresh()


func _talk(kind: String, id: String) -> void:
	var r := WorldSimulationManager.talk(kind, id)
	var d := StringName(str(r.get("dialogue", "")))
	if d != &"":
		var panel := DialoguePanel.new()
		panel.name = "DialoguePanel"
		panel.dialogue_id = d
		AudioManager.play_sfx(&"customer", 0.0)
		UIManager.show_modal(panel)
		panel.closed.connect(func() -> void:
			SaveManager.save_game()
			_refresh())
		return
	_last_text = str(r.get("text", ""))
	SaveManager.save_game()
	_refresh()


func _go_home() -> void:
	TravelFlow.go(LocationManager.CLINIC)


func _open_map() -> void:
	UIManager.go_to(UIManager.SCREEN_MAP, {"location": String(_id)})
