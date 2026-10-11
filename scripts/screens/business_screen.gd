extends BaseScreen
## BUSINESS: the books. Today's ledger by category, tonight's bills, the
## last days' profit as a bar chart, per-clinic running costs, staff
## payroll and debt (pay down / borrow from the Landlord). Everything in
## plain numbers: green in, red out.

var _panels: Array[Control] = []
var _root: VBoxContainer


func on_enter(_params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"business")
	col.add_child(UIKit.header("DAY %d · %s" % [BusinessManager.day, ClinicManager.get_tier_name().to_upper()], "BUSINESS", GameManager.go_to_clinic))
	_root = UIKit.vbox(14)
	UIKit.expand(_root, true, true)
	col.add_child(_root)
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild.call_deferred())
	EventBus.day_started.connect(func(_d: int) -> void: _rebuild.call_deferred())
	PeopleManager.debt_changed.connect(_on_debts_changed)
	_rebuild()


func _exit_tree() -> void:
	if PeopleManager.debt_changed.is_connected(_on_debts_changed):
		PeopleManager.debt_changed.disconnect(_on_debts_changed)


func _on_debts_changed() -> void:
	_rebuild.call_deferred()


func get_panels() -> Array[Control]:
	return _panels


func _kpi(parent: Control, title: String, value: String, color: Color) -> void:
	var p := UIKit.panel(&"CardPanel")
	UIKit.expand(p)
	var v := UIKit.vbox(2)
	p.add_child(v)
	v.add_child(UIKit.label(title, &"SubHeaderLabel"))
	v.add_child(UIKit.label(value, &"BigMonoLabel", false, color))
	parent.add_child(p)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_root)
	_panels.clear()
	var kpis := UIKit.hbox(12)
	_root.add_child(kpis)
	var pt := BusinessManager.profit_today()
	var week := 0
	for k: StringName in BusinessManager.LABELS:
		week += BusinessManager.category_over(k, 6)
	_kpi(kpis, "CASH", EconomyManager.format_money(EconomyManager.money), Palette.TEXT)
	_kpi(kpis, "TODAY", "%+d" % pt, Palette.OK if pt >= 0 else Palette.DANGER)
	_kpi(kpis, "LAST 7 DAYS", "%+d" % week, Palette.OK if week >= 0 else Palette.DANGER)
	_kpi(kpis, "TONIGHT'S BILL", "-%d" % BusinessManager.projected_total(), Palette.WARN)
	_kpi(kpis, "DEBT", "%d" % BusinessManager.debt, Palette.DANGER if BusinessManager.debt > 0 else Palette.TEXT_DIM)
	_kpi(kpis, "OWED TO YOU", "%d" % PeopleManager.total_owed_to_you(), Palette.WARN if PeopleManager.total_owed_to_you() > 0 else Palette.TEXT_DIM)
	var row := UIKit.hbox(14)
	UIKit.expand(row, true, true)
	_root.add_child(row)
	# --- Today's ledger
	var today := UIKit.section(row, "TODAY'S LEDGER · DAY %d" % BusinessManager.day)
	_panels.append(today.get_parent())
	(today.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger_rows(today, BusinessManager.today)
	today.add_child(UIKit.label("TONIGHT", &"SubHeaderLabel", false, Palette.WARN))
	for c in BusinessManager.projected_costs():
		_line(today, "%s · %s" % [BusinessManager.label(c["category"]), str(c["note"])], -int(c["amount"]))
	today.add_child(UIKit.label("Jobs today %d / %d" % [BusinessManager.jobs_today, BusinessManager.capacity()], &"DimLabel"))
	# --- History chart + totals
	var hist := UIKit.section(row, "PROFIT PER DAY")
	_panels.append(hist.get_parent())
	(hist.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(hist.get_parent() as Control).size_flags_stretch_ratio = 1.3
	var chart := ProfitChart.new()
	chart.custom_minimum_size = Vector2(0, 220)
	hist.add_child(chart)
	hist.add_child(UIKit.label("LIFETIME", &"SubHeaderLabel"))
	_ledger_rows(hist, BusinessManager.totals)
	# --- Property, payroll and debt
	var side := UIKit.section(row, "OBLIGATIONS")
	_panels.append(side.get_parent())
	(side.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in ClinicManager.owned:
		var c := ClinicManager.daily_costs(i)
		var t := ClinicManager.get_tier_data(i)
		side.add_child(UIKit.label("%s%s" % [str(t["name"]), "  (active)" if i == ClinicManager.tier else ""], &"", true, Palette.ACCENT if i == ClinicManager.tier else Palette.TEXT, 15))
		side.add_child(UIKit.label("rent %d · running %d · upkeep %d /day" % [int(c["rent"]), int(c["operating"]), int(c["upkeep"])], &"MonoLabel", true, Palette.TEXT_DIM, 15))
	var staff := get_node_or_null("/root/StaffManager")
	if staff:
		side.add_child(UIKit.label("Payroll: %d staff · %d/day" % [int(staff.call("count")), int(staff.call("daily_salaries"))], &"DimLabel", true))
	side.add_child(UIKit.label("DEBT", &"SubHeaderLabel", false, Palette.DANGER))
	side.add_child(UIKit.label("Owed %d at 8%% a day. Pell Ormond holds the paper." % BusinessManager.debt if BusinessManager.debt > 0 else "You owe nobody. For now.", &"DimLabel", true))
	var pay := UIKit.button("PAY DEBT", &"AccentButton", func() -> void:
		var n := BusinessManager.pay_debt()
		if n > 0:
			UIManager.celebrate(&"sell", "Paid %d" % n)
			SaveManager.save_game(), "PayDebtButton", 44)
	pay.disabled = BusinessManager.debt <= 0 or EconomyManager.money <= 0
	side.add_child(pay)
	var borrow := UIKit.button("BORROW 500 FROM THE LANDLORD", &"GhostButton", func() -> void:
		UIManager.confirm("THE LANDLORD", "Pell Ormond lends 500. You owe 575, and 8% a day after that. He always collects.", "TAKE IT", func() -> void:
			BusinessManager.borrow(500)
			SaveManager.save_game(), true), "BorrowButton", 40)
	borrow.disabled = BusinessManager.debt > 2000
	side.add_child(borrow)
	_patient_debts(row)


## OWED TO YOU: patients who couldn't pay. Demand it, put them on a plan,
## let it go, send a fixer, or take a favour instead.
func _patient_debts(row: Control) -> void:
	var box := UIKit.section(row, "OWED TO YOU")
	_panels.append(box.get_parent())
	(box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	box.add_child(sc)
	var list := UIKit.vbox(10)
	UIKit.expand(list)
	sc.add_child(list)
	var open := PeopleManager.open_debts()
	if open.is_empty():
		list.add_child(UIKit.label("Nobody owes you anything. Patients who can't cover a fee end up here.", &"DimLabel", true))
		return
	for d in open:
		var id := int(d["id"])
		var who := PeopleManager.get_person(StringName(str(d["person"])))
		var card := UIKit.panel(&"CardPanel")
		card.name = "Debt_%d" % id
		var v := UIKit.vbox(4)
		card.add_child(v)
		v.add_child(UIKit.label("%s · %d cr" % [str(who.get("name", "Someone")), int(d["amount"])], &"SubHeaderLabel", true, Palette.WARN))
		var status := "on a plan: %d a night" % int(d["plan"]) if str(d["status"]) == "plan" else "open since day %d" % int(d["day"])
		v.add_child(UIKit.label("%s · %s · %s" % [str(d["reason"]), status, PeopleManager.rel_state(StringName(str(d["person"])))], &"DimLabel", true, null, 13))
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override(&"h_separation", 6)
		acts.add_theme_constant_override(&"v_separation", 6)
		v.add_child(acts)
		var demand := UIKit.button("DEMAND", &"GhostButton", func() -> void:
			var got := PeopleManager.demand(id)
			UIManager.show_toast("They scrape together %d cr. They won't forget being pushed." % got, &"warn")
			SaveManager.save_game(), "Demand_%d" % id, 32)
		demand.tooltip_text = "They pay what they can now. Relationship drops."
		acts.add_child(demand)
		if str(d["status"]) == "open":
			var plan := UIKit.button("PLAN", &"GhostButton", func() -> void:
				PeopleManager.set_plan(id)
				SaveManager.save_game(), "Plan_%d" % id, 32)
			plan.tooltip_text = "A share every night. Poorer people sometimes miss one."
			acts.add_child(plan)
		var wo := UIKit.button("WRITE OFF", &"GhostButton", func() -> void:
			PeopleManager.write_off(id)
			UIManager.show_toast("Debt forgiven. They'll remember.", &"info")
			SaveManager.save_game(), "WriteOff_%d" % id, 32)
		wo.tooltip_text = "Let it go. They remember kindness; civilians hear about it."
		acts.add_child(wo)
		var fx := UIKit.button("SEND A FIXER", &"DangerButton", func() -> void:
			UIManager.confirm("SEND A FIXER", "A fixer collects 60%% of the debt (%d cr) the hard way. %s gets hurt, the street hears, heat rises." % [int(round(int(d["amount"]) * 0.6)), str(who.get("name", "They"))], "SEND THEM", func() -> void:
				var got := PeopleManager.send_collector(id)
				UIManager.show_toast("The fixer brings back %d cr. Don't ask how." % got, &"danger")
				SaveManager.save_game(), true), "Collector_%d" % id, 32)
		acts.add_child(fx)
		var fav := UIKit.button("FAVOUR", &"GhostButton", func() -> void:
			PeopleManager.favor(id)
			UIManager.show_toast("They'll repay you in kind on their next visit.", &"info")
			SaveManager.save_game(), "Favor_%d" % id, 32)
		fav.tooltip_text = "Forget the money; they'll bring supplies, parts or information instead."
		acts.add_child(fav)
		list.add_child(card)


func _ledger_rows(parent: Control, ledger: Dictionary) -> void:
	var keys := ledger.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(ledger[a]) > int(ledger[b]))
	var any := false
	for k: Variant in keys:
		if int(ledger[k]) != 0:
			_line(parent, BusinessManager.label(StringName(str(k))), int(ledger[k]))
			any = true
	if not any:
		parent.add_child(UIKit.label("Nothing yet.", &"DimLabel"))


func _line(parent: Control, text: String, amount: int) -> void:
	var h := UIKit.hbox(8)
	var l := UIKit.label(text, &"DimLabel", false, null, 15)
	l.clip_text = true
	UIKit.expand(l)
	h.add_child(l)
	h.add_child(UIKit.label(Accessibility.tag(&"good" if amount >= 0 else &"bad") + "%+d" % amount, &"MonoLabel", false, Palette.OK if amount >= 0 else Palette.DANGER, 17))
	parent.add_child(h)
