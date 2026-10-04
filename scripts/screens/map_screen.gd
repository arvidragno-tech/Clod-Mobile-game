extends BaseScreen
## CITY MAP: Caldera and its seven districts. Click a district to read it
## (architecture, light, population, factions, who walks in, danger,
## your influence) and to see, buy or move to the clinic there.

const MAP_PATH := "res://assets/sprites/ui/city_map.png"

var _map: CityMapView
var _info: VBoxContainer
var _selected: StringName = &""
var _panels: Array[Control] = []


func on_enter(_params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"map")
	col.add_child(UIKit.header("CALDERA · %d DISTRICTS" % WorldManager.order.size(), "CITY MAP", GameManager.go_to_clinic))
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
	var mcol := UIKit.vbox(6)
	frame.add_child(mcol)
	mcol.add_child(_map)
	mcol.add_child(UIKit.label("◆ district  ·  ■ your clinics  ·  pulsing ring = your practice  ·  click a district for details", &"SubHeaderLabel", true))
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
	_select(WorldManager.current_district_id())


func get_panels() -> Array[Control]:
	return _panels


func _refresh() -> void:
	_map.queue_redraw()
	_select(_selected)


func _select(id: StringName) -> void:
	_selected = id
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
