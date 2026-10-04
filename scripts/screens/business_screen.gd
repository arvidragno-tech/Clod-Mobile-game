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
	_rebuild()


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
	h.add_child(UIKit.label("%+d" % amount, &"MonoLabel", false, Palette.OK if amount >= 0 else Palette.DANGER, 17))
	parent.add_child(h)
