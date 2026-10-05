extends BaseScreen
## STAFF: your ripperdocs and the hiring board. Each person is shown with a
## live portrait (their look changes as they grow, burn out or get hurt),
## specialization, skill, speed, precision, reliability, salary,
## personality, ethics, traits, loyalty, stress, ambition and where they
## work. Hire, fire, move between clinics, answer raise requests.

var _tab: int = 0
var _body: VBoxContainer
var _panels: Array[Control] = []


func on_enter(params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"staff")
	col.add_child(UIKit.header("CLINIC · %d / %d STAFF" % [StaffManager.count(), StaffManager.capacity_total()], "STAFF", GameManager.go_to_clinic))
	col.add_child(UIKit.tabs(["TEAM", "HIRING BOARD"], _select, "StaffTab"))
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	col.add_child(sc)
	_body = UIKit.vbox(12)
	UIKit.expand(_body, true, false)
	sc.add_child(_body)
	_tab = int(params.get("tab", 0 if StaffManager.count() > 0 else 1))
	var tabs := col.get_child(col.get_child_count() - 2)
	if _tab == 1 and tabs.get_child_count() > 1:
		(tabs.get_child(1) as Button).button_pressed = true
	if StaffManager.candidates.is_empty():
		StaffManager.refresh_candidates()
	StaffManager.staff_changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	if StaffManager.staff_changed.is_connected(_rebuild):
		StaffManager.staff_changed.disconnect(_rebuild)


func get_panels() -> Array[Control]:
	return _panels


func _select(i: int) -> void:
	_tab = i
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_body)
	_panels.clear()
	if _tab == 0:
		if StaffManager.employees.is_empty():
			_body.add_child(UIKit.label("Nobody works for you yet. The hiring board has names; the Staff upgrade makes room.", &"DimLabel", true))
		for e in StaffManager.employees:
			var card := _person(e, false, -1)
			_body.add_child(card)
			_panels.append(card)
	else:
		_body.add_child(UIKit.label("Room for %d more · candidates change every day" % maxi(0, StaffManager.capacity_total() - StaffManager.count()), &"SubHeaderLabel", false, Palette.ACCENT))
		for i in StaffManager.candidates.size():
			var card := _person(StaffManager.candidates[i], true, i)
			_body.add_child(card)
			_panels.append(card)


func _stat(parent: Control, label: String, v: int) -> void:
	parent.add_child(UIKit.label("%-12s %s" % [label, UIKit.pips(v, 5)], &"MonoLabel", false, Palette.TEXT, 15))


func _person(e: Dictionary, candidate: bool, index: int) -> Control:
	var card := UIKit.panel(&"CardPanel" if candidate else &"AccentPanel")
	var h := UIKit.hbox(16)
	card.add_child(h)
	var p := PixelPortrait.new()
	p.framing = PixelPortrait.Framing.FACE
	p.set_appearance(e["appearance"], Palette.ACCENT, &"clinic", StringName(str(e.get("anim", "calm"))))
	h.add_child(p)
	# Identity
	var a := UIKit.vbox(4)
	a.custom_minimum_size.x = 420
	h.add_child(a)
	a.add_child(UIKit.label(str(e["name"]).to_upper(), &"SubHeaderLabel", false, Palette.ACCENT))
	a.add_child(UIKit.label("%d yrs · %s · %s" % [int(e["age"]), StaffManager.spec_label(e), str(e.get("personality", "")).capitalize()], &"DimLabel", true, null, 13))
	a.add_child(UIKit.label(str(e.get("background", "")), &"DimLabel", true, null, 13))
	var spec: Dictionary = StaffManager.specializations.get(str(e["specialization"]), {})
	a.add_child(UIKit.label(str(spec.get("text", "")), &"DimLabel", true, Palette.TEXT_DIM, 13))
	if not candidate:
		# Their life outside these walls.
		var life := StaffLifeManager.ensure_life(e)
		var ll := UIKit.label("Home: %s\nMoney: %s\nFears: %s\nWants: %s" % [StaffLifeManager.family_label(e), StaffLifeManager.money_label(e),
			str(life.get("fear", "")).to_lower(), str(life.get("dream", "")).to_lower()], &"DimLabel", true, Palette.TEXT, 13)
		ll.name = "Life_%s" % str(e["id"])
		a.add_child(ll)
	# Stats
	var b := UIKit.vbox(2)
	b.custom_minimum_size.x = 260
	h.add_child(b)
	_stat(b, "SKILL", int(e["skill"]))
	_stat(b, "SPEED", int(e["speed"]))
	_stat(b, "PRECISION", int(e["precision"]))
	_stat(b, "RELIABILITY", int(e["reliability"]))
	b.add_child(UIKit.label("SALARY %d/day" % int(e["salary"]), &"MonoLabel", false, Palette.WARN, 15))
	# Character: ethics, traits, mood
	var c := UIKit.vbox(3)
	UIKit.expand(c)
	h.add_child(c)
	var eth: Array[String] = []
	for k: Variant in e.get("ethics", []):
		eth.append(str(StaffManager.ethics.get(str(k), {}).get("name", k)))
	c.add_child(UIKit.label("Ethics: %s" % (", ".join(eth) if not eth.is_empty() else "flexible"), &"DimLabel", true, null, 13))
	var tr := StaffManager.visible_traits(e)
	var tl := UIKit.label("Traits: %s" % (", ".join(tr) if not tr.is_empty() else "-"), &"DimLabel", true, Palette.ACCENT, 13)
	var tips: Array[String] = []
	for t: Variant in e.get("traits", []):
		var td: Dictionary = StaffManager.traits.get(str(t), {})
		if bool(td.get("visible", true)):
			tips.append("%s: %s" % [td.get("name", t), td.get("text", "")])
	tl.tooltip_text = "\n".join(tips)
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(tl)
	if not candidate:
		c.add_child(UIKit.label("Loyalty %d (%s)" % [roundi(float(e["loyalty"])), StaffManager.loyalty_label(e)], &"DimLabel", false, null, 13))
		c.add_child(UIKit.meter(float(e["loyalty"]) / 100.0, Palette.OK))
		c.add_child(UIKit.label("Stress %d%s" % [roundi(float(e["stress"])), "  · RESTING" if str(e["status"]) == "resting" else ""], &"DimLabel", false, null, 13))
		c.add_child(UIKit.meter(float(e["stress"]) / 100.0, Palette.DANGER if float(e["stress"]) > 70 else Palette.WARN))
		c.add_child(UIKit.label("Ambition %d · jobs %d · lost %d · at %s" % [roundi(float(e["ambition"])), int(e["jobs_done"]), int(e["deaths"]),
			str(ClinicManager.get_tier_data(int(e["clinic"])).get("name", ""))], &"DimLabel", true, null, 13))
		var bonds := HFlowContainer.new()
		bonds.name = "Bonds_%s" % str(e["id"])
		bonds.add_theme_constant_override(&"h_separation", 10)
		for o in StaffLifeManager.colleagues(e):
			var st := StaffLifeManager.bond(e, o)
			var bl := UIKit.label("%s: %s" % [str(o["name"]).get_slice(" ", 0), StaffLifeManager.bond_label(st).to_upper()], &"DimLabel", false, StaffLifeManager.bond_color(st), 13)
			bl.tooltip_text = "%s about %s · regard %+d" % [str(e["name"]), str(o["name"]), StaffLifeManager.rel(e, o)]
			bl.mouse_filter = Control.MOUSE_FILTER_PASS
			bonds.add_child(bl)
		if bonds.get_child_count() > 0:
			c.add_child(bonds)
		var hist: Array = e.get("history", [])
		if not hist.is_empty():
			c.add_child(UIKit.label(str(hist[hist.size() - 1]), &"DimLabel", true, Palette.TEXT_DIM, 12))
	# Actions
	var btns := UIKit.vbox(6)
	btns.custom_minimum_size.x = 230
	h.add_child(btns)
	var id := StringName(str(e["id"]))
	if candidate:
		var why := StaffManager.hire_block_reason(e)
		var hb := UIKit.button("HIRE · %s" % EconomyManager.format_money(StaffManager.signing_fee(e)) if why == "" else why.to_upper(), &"AccentButton" if why == "" else &"GhostButton",
			_hire.bind(index), "Hire_%d" % index, 48)
		hb.disabled = why != ""
		btns.add_child(hb)
		btns.add_child(UIKit.label("signing fee = 2 days' pay", &"DimLabel", true, null, 12))
	else:
		if bool(e.get("raise_pending", false)):
			btns.add_child(UIKit.label("Wants a raise.", &"SubHeaderLabel", false, Palette.WARN))
			btns.add_child(UIKit.button("GIVE RAISE (+15%)", &"AccentButton", func() -> void: StaffManager.give_raise(id, true), "Raise_%s" % id, 40))
			btns.add_child(UIKit.button("REFUSE", &"GhostButton", func() -> void: StaffManager.give_raise(id, false), "RefuseRaise_%s" % id, 36))
		for i in ClinicManager.owned:
			if i != int(e["clinic"]):
				btns.add_child(UIKit.button("MOVE TO %s" % str(ClinicManager.get_tier_data(i)["name"]).to_upper(), &"GhostButton",
					func() -> void:
						if not StaffManager.transfer(id, i):
							UIManager.show_toast("No room there.", &"warn"), "Transfer_%s_%d" % [id, i], 36))
		btns.add_child(UIKit.button("FIRE", &"DangerButton", _fire.bind(id), "Fire_%s" % id, 36))
	return card


func _hire(index: int) -> void:
	var nm := str(StaffManager.candidates[index]["name"])
	if StaffManager.hire(index):
		UIManager.celebrate(&"purchase", "%s joins the clinic." % nm)
		SaveManager.save_game()


func _fire(id: StringName) -> void:
	var e := StaffManager.get_employee(id)
	UIManager.confirm("LET THEM GO", "Fire %s? One day's severance. The others will notice." % e.get("name", ""), "FIRE", func() -> void:
		if StaffManager.fire(id):
			SaveManager.save_game(), true)
