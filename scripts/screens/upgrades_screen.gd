extends BaseScreen
## FACILITY: the active clinic's upgrades and the property ladder.
##
## Tab 0 (UPGRADES): a window into the room (the same lit art and upgrade
## overlays the clinic shows) above six upgrade categories - surgery,
## diagnostics, security, black market, staff, customer facilities - each
## with three levels that visibly change the room.
## Tab 1 (PROPERTY): the seven clinics of Caldera with price, rent, running
## costs, capacities, security and Undermarket access; buy, move in, sell.

## Art window shown in the preview (art px of the 600x336 HD room).
const PREVIEW := Rect2i(0, 21, 600, 168)

var _tab: int = 0
var _body: VBoxContainer
var _panels: Array[Control] = []


func on_enter(params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"upgrades")
	col.add_child(UIKit.header("CLINIC · %s" % WorldManager.district_name().to_upper(), "FACILITY", GameManager.go_to_clinic))
	col.add_child(UIKit.tabs(["UPGRADES", "PROPERTY"], _select, "FacilityTab"))
	_body = UIKit.vbox(12)
	UIKit.expand(_body, true, true)
	col.add_child(_body)
	_tab = int(params.get("tab", 0))
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: _rebuild())
	EventBus.clinic_purchased.connect(func(_i: int) -> void: _rebuild())
	EventBus.clinic_upgrade_installed.connect(func(_c: StringName, _l: int) -> void: _rebuild())
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild.call_deferred())
	_rebuild()


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
		_build_upgrades()
	else:
		_build_property()


# --- Upgrades --------------------------------------------------------------------

func _build_upgrades() -> void:
	var top := UIKit.hbox(16)
	_body.add_child(top)
	var pv := ClinicPreview.new()
	pv.region = PREVIEW
	top.add_child(pv)
	var stats := UIKit.panel(&"AccentPanel")
	UIKit.expand(stats, true, false)
	top.add_child(stats)
	_panels.append(stats)
	var sv := UIKit.vbox(6)
	stats.add_child(sv)
	var t := ClinicManager.get_tier_data()
	sv.add_child(UIKit.label(ClinicManager.get_tier_name().to_upper(), &"HeaderLabel", true))
	sv.add_child(UIKit.label("%s · %s" % [WorldManager.district_name(), str(WorldManager.current_district().get("label", ""))], &"SubHeaderLabel", true, Palette.ACCENT))
	sv.add_child(UIKit.label(str(t.get("description", "")), &"DimLabel", true))
	sv.add_child(UIKit.label("Upgrade slots  %d / %d" % [ClinicManager.used_slots(), ClinicManager.slots()], &"MonoLabel", true, Palette.TEXT))
	sv.add_child(UIKit.meter(float(ClinicManager.used_slots()) / maxf(1.0, ClinicManager.slots()), Palette.ACCENT))
	sv.add_child(UIKit.label("Security %d · Staff %d · Jobs/day %d" % [ClinicManager.security_rating(), ClinicManager.staff_capacity(), ClinicManager.surgery_capacity()], &"MonoLabel", true, Palette.TEXT_DIM, 17))
	var c := ClinicManager.daily_costs()
	sv.add_child(UIKit.label("Per day: rent %d · running %d · upkeep %d" % [int(c["rent"]), int(c["operating"]), int(c["upkeep"])], &"MonoLabel", true, Palette.WARN, 17))
	var mods := ClinicManager.get_modifiers()
	if not mods.is_empty():
		sv.add_child(UIKit.label(UIKit.describe_modifiers(mods), &"DimLabel", true, Palette.ACCENT, 13))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	UIKit.expand(grid, true, false)
	# The cards scroll when text is large, instead of falling off-screen.
	var gsc := UIKit.scroll()
	gsc.name = "UpgradeScroll"
	UIKit.expand(gsc, true, true)
	_body.add_child(gsc)
	gsc.add_child(grid)
	for cat in ClinicManager.CATEGORIES:
		var card := _category_card(cat)
		grid.add_child(card)
		_panels.append(card)


func _category_card(cat: StringName) -> Control:
	var lv := ClinicManager.upgrade_level(cat)
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card, true, true)
	var v := UIKit.vbox(4)
	card.add_child(v)
	var head := UIKit.hbox(8)
	v.add_child(head)
	var title := UIKit.label(ClinicManager.category_name(cat).to_upper(), &"SubHeaderLabel", false, Palette.ACCENT)
	UIKit.expand(title)
	head.add_child(title)
	head.add_child(UIKit.label(UIKit.pips(lv, ClinicManager.MAX_UPGRADE_LEVEL), &"MonoLabel", false, Palette.ACCENT))
	if lv > 0:
		v.add_child(UIKit.label("Installed: %s" % str(ClinicManager.upgrade_def(cat, lv).get("name", "")), &"DimLabel", true, Palette.OK, 13))
	if lv < ClinicManager.MAX_UPGRADE_LEVEL:
		var d := ClinicManager.upgrade_def(cat, lv + 1)
		v.add_child(UIKit.label("NEXT  %s  · upkeep %d/day" % [str(d.get("name", "")).to_upper(), int(d.get("upkeep", 0))], &"", true, Palette.TEXT, 15))
		v.add_child(UIKit.label(str(d.get("text", "")), &"DimLabel", true, null, 13))
		var reason := ClinicManager.install_block_reason(cat)
		var b := UIKit.button(("INSTALL · %s" % EconomyManager.format_money(int(d.get("cost", 0)))) if reason == "" else reason.to_upper(),
			&"AccentButton" if reason == "" else &"GhostButton", _install.bind(cat), "Install_%s" % cat, 44)
		b.disabled = reason != ""
		v.add_child(b)
	else:
		v.add_child(UIKit.label("Fully fitted.", &"DimLabel", true))
	return card


func _install(cat: StringName) -> void:
	if ClinicManager.install(cat):
		var lv := ClinicManager.upgrade_level(cat)
		UIManager.celebrate(&"purchase", "Installed: %s" % str(ClinicManager.upgrade_def(cat, lv).get("name", "")))
		SaveManager.save_game()


# --- Property ----------------------------------------------------------------------

func _build_property() -> void:
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	_body.add_child(sc)
	var list := UIKit.vbox(10)
	UIKit.expand(list, true, false)
	sc.add_child(list)
	var next := ClinicManager.next_index()
	for i in ClinicManager.tiers.size():
		var row := _clinic_row(i, i == next)
		list.add_child(row)
		_panels.append(row)


func _clinic_row(i: int, is_next: bool) -> Control:
	var t := ClinicManager.get_tier_data(i)
	var active := i == ClinicManager.tier
	var own := ClinicManager.owns(i)
	var card := UIKit.panel(&"AccentPanel" if active else &"CardPanel")
	var h := UIKit.hbox(16)
	card.add_child(h)
	var thumb := ClinicPreview.new()
	thumb.clinic_index = i
	thumb.region = Rect2i(228, 118, 124, 72)
	thumb.scale_override = 2
	h.add_child(thumb)
	var v := UIKit.vbox(3)
	UIKit.expand(v)
	h.add_child(v)
	var district := StringName(str(t.get("district", "")))
	var tag := "ACTIVE" if active else ("OWNED" if own else "FOR LEASE")
	v.add_child(UIKit.label("%d · %s   [%s]" % [i + 1, str(t["name"]).to_upper(), tag], &"SubHeaderLabel", false, Palette.ACCENT if active else (Palette.OK if own else Palette.TEXT)))
	v.add_child(UIKit.label("%s · %s" % [WorldManager.district_name(district), str(WorldManager.get_district(district).get("label", ""))], &"DimLabel", false, null, 13))
	v.add_child(UIKit.label(str(t.get("description", "")), &"DimLabel", true, null, 13))
	v.add_child(UIKit.label("Rent %d + running %d /day · %d jobs/day · staff %d · security %d · slots %d · Undermarket %s · chrome T%d" % [
		int(t["rent"]), int(t["operating_cost"]), int(t["surgery_capacity"]), int(t["staff_capacity"]), int(t["security"]),
		int(t["upgrade_slots"]), UIKit.pips(int(t["black_market_access"]), 3), int(t["max_cyberware_tier"])], &"MonoLabel", true, Palette.TEXT_DIM, 15))
	var btns := UIKit.vbox(6)
	btns.custom_minimum_size.x = 260
	h.add_child(btns)
	if active:
		btns.add_child(UIKit.label("You work here.", &"DimLabel"))
	elif own:
		btns.add_child(UIKit.button("MOVE PRACTICE HERE", &"AccentButton", _move.bind(i), "MoveClinic_%d" % i, 44))
		var sb := UIKit.button("SELL · +%s" % EconomyManager.format_money(int(ClinicManager.price(i) * ClinicManager.SELL_BACK)), &"GhostButton", _sell.bind(i), "SellClinic_%d" % i, 40)
		btns.add_child(sb)
	else:
		var reason := ClinicManager.purchase_block_reason(i)
		var label := ("BUY & MOVE · %s" % EconomyManager.format_money(ClinicManager.price(i))) if reason == "" else reason.to_upper()
		var b := UIKit.button(label, &"BrandButton" if reason == "" else &"GhostButton", _buy_and_move.bind(i), "UpgradeClinic" if is_next else "BuyClinic_%d" % i, 52)
		b.disabled = reason != ""
		btns.add_child(b)
		if reason == "":
			btns.add_child(UIKit.button("BUY ONLY (STAFF IT)", &"GhostButton", _buy.bind(i), "BuyOnly_%d" % i, 40))
		btns.add_child(UIKit.label("LV %d · REP %d" % [int(t["min_level"]), int(t["min_reputation"])], &"MonoLabel", false, Palette.WARN, 15))
	return card


func _buy_and_move(i: int) -> void:
	if ClinicManager.buy(i):
		ClinicManager.move_to(i)
		UIManager.celebrate(&"upgrade", "Welcome to the %s" % ClinicManager.get_tier_name())
		SaveManager.save_game()


func _buy(i: int) -> void:
	if ClinicManager.buy(i):
		UIManager.celebrate(&"purchase", "Bought: %s. Assign staff to run it." % str(ClinicManager.get_tier_data(i)["name"]))
		SaveManager.save_game()


func _move(i: int) -> void:
	if ClinicManager.move_to(i):
		UIManager.celebrate(&"upgrade", "Practice moved to the %s" % ClinicManager.get_tier_name())
		SaveManager.save_game()


func _sell(i: int) -> void:
	UIManager.confirm("SELL CLINIC", "Sell the %s for %s? Upgrades there are lost." % [str(ClinicManager.get_tier_data(i)["name"]), EconomyManager.format_money(int(ClinicManager.price(i) * ClinicManager.SELL_BACK))],
		"SELL", func() -> void:
			if ClinicManager.sell(i):
				UIManager.celebrate(&"sell", "Sold.")
				SaveManager.save_game(), true)
