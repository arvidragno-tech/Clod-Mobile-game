class_name DecisionPreview
extends RefCounted
## BEFORE YOU PAY: the one consequence preview used by every purchase and
## investment (SUPPLY, the black market, suppliers, FACILITY, new clinics,
## hiring). It shows what the game knows for certain (the price, your cash
## now and after, tonight's bill, the stock you'd have, a recurring cost)
## and labels everything else for what it is: a purpose, a limit, or an
## uncertainty. It never predicts income from a purchase: a better tool or
## a new clinic creates an opportunity, not a guaranteed return.
##
## facts(cost, recurring) -> {cost, now, after, bill, short, below_bill, recurring}
## build(parent, cost, opts) -> the preview box (named "DecisionPreview")
##   opts: {stock: "1 → 2", recurring: int (per day), purpose: String,
##          limits: [String], uncertain: String}


static func facts(cost: int, recurring: int = 0) -> Dictionary:
	var now := EconomyManager.money
	var after := now - cost
	var bill := BusinessManager.projected_total() + recurring
	return {"cost": cost, "now": now, "after": after, "bill": bill, "recurring": recurring,
		"short": after < 0, "below_bill": after >= 0 and after < bill}


## One line for a button tooltip or a dialog body.
static func summary(cost: int, recurring: int = 0) -> String:
	var f := facts(cost, recurring)
	var s := "Cost %s · cash %s → %s" % [EconomyManager.format_money(cost), EconomyManager.format_money(int(f["now"])), EconomyManager.format_money(int(f["after"]))]
	if recurring > 0:
		s += " · +%s every night" % EconomyManager.format_money(recurring)
	if bool(f["short"]):
		s += " · you can't afford it"
	elif bool(f["below_bill"]):
		s += " · leaves less than tonight's bill (%s)" % EconomyManager.format_money(int(f["bill"]))
	return s


static func build(parent: Control, cost: int, opts: Dictionary = {}) -> VBoxContainer:
	var f := facts(cost, int(opts.get("recurring", 0)))
	var box := UIKit.vbox(3)
	box.name = "DecisionPreview"
	parent.add_child(box)
	box.add_child(UIKit.label("BEFORE YOU PAY", &"SubHeaderLabel", false, Palette.TEXT_DIM, 13))
	_row(box, "COST", "−%s" % EconomyManager.format_money(cost), Palette.TEXT)
	var after_col := Palette.DANGER if bool(f["short"]) else (Palette.WARN if bool(f["below_bill"]) else Palette.OK)
	var cash := _row(box, "CASH", "%s → %s" % [EconomyManager.format_money(int(f["now"])), EconomyManager.format_money(int(f["after"]))], after_col)
	cash.name = "PreviewCash"
	if int(f["recurring"]) > 0:
		_row(box, "EVERY NIGHT", "+%s (rent, upkeep or wage)" % EconomyManager.format_money(int(f["recurring"])), Palette.WARN)
	if str(opts.get("stock", "")) != "":
		_row(box, "IN STOCK", str(opts["stock"]), Palette.TEXT_DIM)
	if bool(f["short"]):
		box.add_child(UIKit.label("✕ You can't afford it yet.", &"", true, Palette.DANGER, 14))
	elif bool(f["below_bill"]):
		box.add_child(UIKit.label("! Leaves less than tonight's bill (%s): unpaid bills become debt." % EconomyManager.format_money(int(f["bill"])), &"", true, Palette.WARN, 14))
	if str(opts.get("purpose", "")) != "":
		box.add_child(UIKit.label(str(opts["purpose"]), &"DimLabel", true, null, 14))
	for l: Variant in opts.get("limits", []):
		box.add_child(UIKit.label("· " + str(l), &"DimLabel", true, Palette.WARN, 13))
	if str(opts.get("uncertain", "")) != "":
		box.add_child(UIKit.label("? " + str(opts["uncertain"]), &"DimLabel", true, null, 13))
	return box


static func _row(parent: Control, caption: String, value: String, color: Color) -> HBoxContainer:
	var row := UIKit.hbox(8)
	parent.add_child(row)
	var cap := UIKit.caption(caption)
	cap.custom_minimum_size.x = 120
	row.add_child(cap)
	var v := UIKit.label(value, &"MonoLabel", true, color, 16)
	UIKit.expand(v)
	row.add_child(v)
	return row
