extends BaseScreen
## CITY MAP: Caldera, its seven districts and the places you know. Click a
## district to read it (architecture, light, population, factions, who
## walks in, danger, your influence, its places) and to see, buy or move to
## the clinic there. Click a place to see what it's like right now, who's
## there, what you can do there, and how to get there (walk, metro, cab:
## time, cost, risk).

const MAP_PATH := "res://assets/sprites/ui/city_map.png"

var _map: CityMapView
var _info: VBoxContainer
var _selected: StringName = &""
var _panels: Array[Control] = []


func on_enter(params: Dictionary) -> void:
	(func() -> void: Hints.first("map")).call_deferred()
	var col := UIKit.workstation(self, &"map")
	col.add_child(UIKit.header("CALDERA · %d DISTRICTS · %d PLACES KNOWN · YOU: %s" % [WorldManager.order.size(), LocationManager.known_locations().size(),
		LocationManager.location_name(LocationManager.player_location).to_upper()], "CITY MAP", GameManager.go_to_clinic))
	var row := UIKit.hbox(16)
	UIKit.expand(row, true, true)
	col.add_child(row)
	var frame := UIKit.panel(&"HudPanel")
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(frame)
	_panels.append(frame)
	_map = CityMapView.new()
	_map.name = "CityMap"
	_map.district_clicked.connect(_select)
	_map.location_clicked.connect(select_location)
	var mcol := UIKit.vbox(6)
	frame.add_child(mcol)
	mcol.add_child(_map)
	mcol.add_child(UIKit.label("◆ district  ·  ■ place (colour = kind; dim = closed)  ·  green ring = you  ·  click a place to travel", &"SubHeaderLabel", true))
	_legend(mcol)
	var side := UIKit.panel(&"AccentPanel")
	UIKit.expand(side, true, true)
	row.add_child(side)
	_panels.append(side)
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	side.add_child(sc)
	_info = UIKit.vbox(8)
	UIKit.expand(_info, true, false)
	sc.add_child(_info)
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: _refresh())
	EventBus.clinic_purchased.connect(func(_i: int) -> void: _refresh())
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: _refresh())
	var focus := StringName(str(params.get("location", "")))
	if focus != &"" and LocationManager.is_known(focus):
		select_location(focus)
	else:
		_select(LocationManager.district_of(LocationManager.player_location))
	if WorldSimulationManager.has_encounter():
		TravelFlow.show_encounter.call_deferred()


func get_panels() -> Array[Control]:
	return _panels


func _legend(parent: Control) -> void:
	var row := UIKit.hbox(14)
	parent.add_child(row)
	for t: String in ["clinic", "bar", "night_market", "black_market", "industrial", "residential", "transit", "corporate", "restricted"]:
		var item := UIKit.hbox(4)
		var sw := ColorRect.new()
		sw.color = CityMapView.TYPE_COLORS.get(t, Palette.TEXT)
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sw)
		item.add_child(UIKit.label(str(LocationManager.types.get(t, {}).get("label", t)).split(" ")[0], &"DimLabel", false, null, 13))
		row.add_child(item)


func _refresh() -> void:
	if not is_inside_tree() or _info == null:
		return
	_map.queue_redraw()
	if _selected_location != &"":
		select_location(_selected_location)
	else:
		_select(_selected)


var _selected_location: StringName = &""


## A place: what it's like now, who's there, what you can do, how to get there.
func select_location(id: StringName) -> void:
	_selected_location = id
	_map.selected_location = id
	_map.selected = LocationManager.district_of(id)
	_map.queue_redraw()
	UIKit.clear(_info)
	var l := LocationManager.get_location(id)
	var st := WorldSimulationManager.state(id)
	var here := LocationManager.player_location == id
	_info.add_child(UIKit.label("%s · %s" % [LocationManager.type_label(id), WorldManager.district_name(LocationManager.district_of(id)).to_upper()], &"SubHeaderLabel", false, Palette.ACCENT))
	_info.add_child(UIKit.label(LocationManager.location_name(id).to_upper(), &"HeaderLabel", true))
	_info.add_child(UIKit.label("%s%s · %s" % ["YOU ARE HERE · " if here else "", WorldSimulationManager.state_label(id), LocationManager.hours_text(id)], &"MonoLabel", true, WorldSimulationManager.state_color(id)))
	_info.add_child(UIKit.label(str(l.get("description", "")) if id != LocationManager.CLINIC else "Your practice in %s." % WorldManager.district_name(), &"", true))
	_info.add_child(UIKit.label("Activity %s · Danger %s · Police %s" % [WorldSimulationManager.activity_label(int(st["activity"])), UIKit.pips(int(st["danger"]), 4), UIKit.pips(int(st["authority"]), 4)], &"MonoLabel", true, Palette.TEXT_DIM, 17))
	var facs: Dictionary = st["factions"]
	if not facs.is_empty():
		var fl: Array[String] = []
		for f: Variant in facs:
			if float(facs[f]) >= 0.5:
				fl.append("%s %s" % [FactionManager.get_name_of(StringName(str(f))), UIKit.pips(roundi(float(facs[f])), 4)])
		_info.add_child(UIKit.label("PRESENCE  " + "  ·  ".join(fl), &"DimLabel", true))
	var people := WorldSimulationManager.people_at(id)
	if not people.is_empty():
		var names: Array[String] = []
		var known := 0
		for p: Dictionary in people:
			var role: String = {"cast": "", "staff": "your staff", "patient": "your patient", "supplier": "supplier"}.get(str(p.get("kind", "")), "")
			var note := str(p.get("note", ""))
			if str(p.get("kind", "")) == "cast" or role != "":
				known += 1
			names.append("%s%s" % [str(p["name"]), (" — " + (note if note != "" else role)) if (note != "" or role != "") else ""])
		_info.add_child(UIKit.label("PEOPLE HERE NOW  (%d you know)" % known, &"SubHeaderLabel"))
		_info.add_child(UIKit.label("\n".join(names.slice(0, 6)) + ("\n+%d more" % (names.size() - 6) if names.size() > 6 else ""), &"DimLabel", true))
	var ev := WorldSimulationManager.event_at(id)
	if not ev.is_empty():
		_info.add_child(UIKit.label("HAPPENING NOW: %s" % str(ev.get("title", "")), &"SubHeaderLabel", true, Palette.WARN))
	var services := LocationServices.DEFS
	var sl: Array[String] = []
	for sid: Variant in l.get("services", []):
		sl.append(str(services.get(str(sid), {}).get("label", sid)).to_lower())
	if not sl.is_empty():
		_info.add_child(UIKit.label("YOU CAN", &"SubHeaderLabel"))
		_info.add_child(UIKit.label(", ".join(sl), &"DimLabel", true))
	if id != LocationManager.CLINIC:
		var on := Follows.is_following(Follows.key("place", String(id)))
		var fb := UIKit.button("★ FOLLOWING" if on else "☆ FOLLOW THIS PLACE", &"AccentButton" if on else &"GhostButton", func() -> void:
			var now := Follows.toggle("place", String(id), LocationManager.location_name(id))
			UIManager.show_toast(("★ Following %s" if now else "Stopped following %s") % LocationManager.location_name(id), &"success" if now else &"info")
			select_location(id), "FollowPlace", 36)
		fb.tooltip_text = "Keep it on your journal's MAIN page and the clinic's priorities when something happens there."
		_info.add_child(fb)
	# Getting there.
	var card := UIKit.panel(&"CardPanel")
	_info.add_child(card)
	var v := UIKit.vbox(6)
	card.add_child(v)
	if here:
		v.add_child(UIKit.label("YOU ARE HERE", &"SubHeaderLabel", false, Palette.OK))
		if id != LocationManager.CLINIC:
			v.add_child(UIKit.button("GO IN", &"AccentButton", func() -> void: UIManager.go_to(UIManager.SCREEN_LOCATION), "MapEnter", 44))
		else:
			v.add_child(UIKit.label("Your clinic. Pick a place on the map to go out.", &"DimLabel", true))
		return
	var block := LocationManager.leave_block(id)
	v.add_child(UIKit.label("GET THERE  (now %s)" % TimeManager.clock_text(), &"SubHeaderLabel"))
	if block != "":
		v.add_child(UIKit.label(block, &"DimLabel", true, Palette.WARN))
		return
	var best := str(LocationManager.best_trip(id).get("mode", ""))
	for t: Dictionary in LocationManager.trips(id):
		if str(t["block"]).begins_with("Same district"):
			continue
		var cost := int(t["cost"])
		var risk := "low risk" if float(t["risk"]) < 0.3 else ("some risk" if float(t["risk"]) < 0.7 else "risky after dark")
		var txt := "%s · %s · %s" % [str(t["label"]), TimeManager.duration_text(int(t["minutes"])), EconomyManager.format_money(cost) if cost > 0 else "free"]
		var b := UIKit.button(txt, &"AccentButton" if str(t["mode"]) == best else &"Button", func() -> void: TravelFlow.go(id, str(t["mode"])), "Travel_%s" % str(t["mode"]), 44)
		b.clip_text = true
		b.custom_minimum_size.x = 0
		b.disabled = str(t["block"]) != ""
		b.tooltip_text = str(t["block"]) if str(t["block"]) != "" else risk
		v.add_child(b)
		v.add_child(UIKit.label("  " + (str(t["block"]) if str(t["block"]) != "" else risk), &"DimLabel", true, Palette.TEXT_DIM, 13))


func _select(id: StringName) -> void:
	_selected = id
	_selected_location = &""
	_map.selected_location = &""
	_map.selected = id
	_map.queue_redraw()
	UIKit.clear(_info)
	var d := WorldManager.get_district(id)
	if d.is_empty():
		return
	var unlocked := WorldManager.is_district_unlocked(id)
	_info.add_child(UIKit.label(str(d.get("label", "")), &"SubHeaderLabel", false, Palette.ACCENT))
	_info.add_child(UIKit.label(str(d["name"]).to_upper(), &"HeaderLabel"))
	if not unlocked:
		_info.add_child(UIKit.label("LOCKED · %s" % WorldManager.unlock_reason(id), &"MonoLabel", false, Palette.WARN))
	_info.add_child(UIKit.label(str(d.get("description", "")), &"", true))
	for pair: Array in [["ARCHITECTURE", "architecture"], ["LIGHT", "lighting"], ["PEOPLE", "population"]]:
		_info.add_child(UIKit.label(pair[0], &"SubHeaderLabel"))
		_info.add_child(UIKit.label(str(d.get(pair[1], "")), &"DimLabel", true))
	_info.add_child(UIKit.label("FACTIONS", &"SubHeaderLabel"))
	var fl: Array[String] = []
	for f: Variant in d.get("factions", {}):
		fl.append("%s %s" % [FactionManager.get_name_of(StringName(str(f))), UIKit.pips(int(d["factions"][f]), 3)])
	_info.add_child(UIKit.label("  ·  ".join(fl), &"DimLabel", true))
	_info.add_child(UIKit.label("WALK-INS", &"SubHeaderLabel"))
	var cl: Array[String] = []
	for a: Variant in d.get("customers", {}):
		cl.append(CharacterAppearanceManager.occupation_label(str(a)))
	_info.add_child(UIKit.label(", ".join(cl), &"DimLabel", true))
	_info.add_child(UIKit.label("Danger %s · Heat x%.2f · Pay x%.2f · Influence %d" % [UIKit.pips(int(d.get("danger", 1)), 3),
		float(d.get("heat_mult", 1.0)), float(d.get("wealth", 1.0)), WorldManager.get_influence(id)], &"MonoLabel", true, Palette.TEXT_DIM, 17))
	_info.add_child(UIKit.label("PLACES", &"SubHeaderLabel"))
	var places := LocationManager.in_district(id)
	for lid in places:
		var b := UIKit.button("%s · %s" % [LocationManager.location_name(lid).to_upper(), WorldSimulationManager.state_label(lid)],
			&"GhostButton", select_location.bind(lid), "Loc_%s" % String(lid), 40)
		b.clip_text = true
		b.custom_minimum_size.x = 0
		b.tooltip_text = LocationManager.type_label(lid)
		_info.add_child(b)
	var unknown := LocationManager.in_district(id, false).size() - places.size()
	if unknown > 0:
		_info.add_child(UIKit.label("%d place%s here you haven't found yet. Patients, fixers and staff know things." % [unknown, "s" if unknown > 1 else ""], &"DimLabel", true, Palette.TEXT_DIM, 13))
	elif places.is_empty():
		_info.add_child(UIKit.label("Nothing you know of.", &"DimLabel", true, Palette.TEXT_DIM, 13))
	for i in ClinicManager.tiers.size():
		var t := ClinicManager.get_tier_data(i)
		if StringName(str(t.get("district", ""))) != id:
			continue
		var card := UIKit.panel(&"CardPanel")
		_info.add_child(card)
		var v := UIKit.vbox(4)
		card.add_child(v)
		var state := "YOUR PRACTICE" if i == ClinicManager.tier else ("OWNED" if ClinicManager.owns(i) else "FOR LEASE · %s" % EconomyManager.format_money(ClinicManager.price(i)))
		v.add_child(UIKit.label("%s  [%s]" % [str(t["name"]).to_upper(), state], &"SubHeaderLabel", false, Palette.ACCENT if ClinicManager.owns(i) else Palette.TEXT))
		v.add_child(UIKit.label("Rent %d/day · %d jobs/day · Undermarket %s" % [int(t["rent"]), int(t["surgery_capacity"]), UIKit.pips(int(t["black_market_access"]), 3)], &"DimLabel", true, null, 13))
		if ClinicManager.owns(i) and i != ClinicManager.tier:
			v.add_child(UIKit.button("MOVE PRACTICE HERE", &"AccentButton", func() -> void:
				if ClinicManager.move_to(i):
					UIManager.celebrate(&"upgrade", "Practice moved to the %s" % ClinicManager.get_tier_name())
					SaveManager.save_game(), "MapMove_%d" % i, 44))
		elif not ClinicManager.owns(i):
			v.add_child(UIKit.button("VIEW IN PROPERTY", &"GhostButton", func() -> void:
				UIManager.go_to(UIManager.SCREEN_UPGRADES, {"tab": 1}), "MapProperty_%d" % i, 40))
