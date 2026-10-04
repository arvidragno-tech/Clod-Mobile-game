extends BaseScreen
## Clinic storage (PC grid inventory). Category tabs (CYBERWARE, TOOLS,
## MEDICAL SUPPLIES, COMPONENTS, BLACK MARKET), sort + text filter, a slot
## grid with drag & drop, and a detail panel with two COMPARE slots.
##   hover / click: details · double-click (F): open in the database
##   right-click: set as CURRENT for comparison · drag: reorder, or drop on
##   a COMPARE slot.

const TABS := ["CYBERWARE", "TOOLS", "MEDICAL SUPPLIES", "COMPONENTS", "BLACK MARKET"]
const SORTS := ["MANUAL", "NAME", "TIER", "VALUE", "CONDITION", "NEURAL LOAD"]
const COLUMNS := 8
const ICONS := {
	&"supplies": "res://assets/sprites/ui/icons/supplies.png",
	&"parts": "res://assets/sprites/ui/icons/parts.png",
	&"tokens": "res://assets/sprites/ui/icons/tokens.png",
}

var _tab: int = 0
var _sort: int = 0
var _filter: String = ""
var _grid: GridContainer
var _detail: VBoxContainer
var _compare: VBoxContainer
var _count: Label
var _compare_a: ItemSlot
var _compare_b: ItemSlot
var _selected_key: String = ""
var _panels: Array[Control] = []


func on_enter(params: Dictionary) -> void:
	_tab = clampi(int(params.get("tab", 0)), 0, TABS.size() - 1)
	var col := UIKit.workstation(self, &"inventory")
	var head := UIKit.header("CLINIC · STORAGE", "INVENTORY", GameManager.go_to_clinic)
	col.add_child(head)
	_count = UIKit.label("", &"MonoLabel", false, Palette.TEXT_DIM)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIKit.expand(_count)
	head.add_child(_count)
	var tabs := UIKit.tabs(TABS, _on_tab, "InvTab")
	col.add_child(tabs)
	(tabs.get_child(_tab) as Button).button_pressed = true
	# Toolbar: sort + filter
	var bar := UIKit.hbox(12)
	col.add_child(bar)
	bar.add_child(UIKit.label("SORT", &"SubHeaderLabel"))
	var sort := OptionButton.new()
	sort.name = "SortBy"
	for s in SORTS:
		sort.add_item(s)
	sort.custom_minimum_size = Vector2(240, GameConfig.MIN_CONTROL)
	sort.item_selected.connect(func(i: int) -> void:
		_sort = i
		_rebuild())
	bar.add_child(sort)
	bar.add_child(UIKit.label("FILTER", &"SubHeaderLabel"))
	var filter := LineEdit.new()
	filter.name = "Filter"
	filter.placeholder_text = "name, slot, maker..."
	filter.custom_minimum_size = Vector2(360, GameConfig.MIN_CONTROL)
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(t: String) -> void:
		_filter = t.strip_edges().to_lower()
		_rebuild())
	bar.add_child(filter)
	bar.add_child(UIKit.expand(Control.new()))
	bar.add_child(UIKit.label("[LMB] select  [2x LMB / F] inspect  [RMB] compare  [DRAG] move", &"SubHeaderLabel"))
	# Body
	var row := UIKit.hbox(18)
	UIKit.expand(row, true, true)
	col.add_child(row)
	var gp := UIKit.panel(&"CardPanel")
	UIKit.expand(gp, true, true)
	row.add_child(gp)
	_panels.append(gp)
	var sc := UIKit.scroll()
	gp.add_child(sc)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	sc.add_child(_grid)
	var side := UIKit.vbox(14)
	side.custom_minimum_size.x = 540
	row.add_child(side)
	var dp := UIKit.panel(&"AccentPanel")
	UIKit.expand(dp, true, true)
	side.add_child(dp)
	_panels.append(dp)
	var dsc := UIKit.scroll()
	dp.add_child(dsc)
	_detail = UIKit.vbox(10)
	_detail.name = "Detail"
	UIKit.expand(_detail)
	dsc.add_child(_detail)
	var cp := UIKit.panel(&"CardPanel")
	side.add_child(cp)
	_panels.append(cp)
	_compare = UIKit.vbox(10)
	cp.add_child(_compare)
	var slots := UIKit.hbox(12)
	_compare_a = _drop_slot("CompareA", "CURRENT")
	_compare_b = _drop_slot("CompareB", "NEW")
	slots.add_child(UIKit.label("COMPARE", &"SubHeaderLabel", false, Palette.ACCENT))
	slots.add_child(_compare_a)
	slots.add_child(UIKit.label("vs", &"MonoLabel"))
	slots.add_child(_compare_b)
	var clear := UIKit.button("CLEAR", &"GhostButton", _clear_compare, "CompareClear")
	clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slots.add_child(clear)
	_compare.add_child(slots)
	EventBus.inventory_changed.connect(_rebuild)
	EventBus.resources_changed.connect(_rebuild)
	_rebuild()


func get_panels() -> Array[Control]:
	return _panels


func _drop_slot(node_name: String, text: String) -> ItemSlot:
	var s := ItemSlot.new()
	s.drop_zone = true
	s.placeholder = text
	s.name = node_name
	s.custom_minimum_size = Vector2(96, 96)
	s.tooltip_text = "Drag an implant or tool here (or right-click one in the grid)"
	s.dropped.connect(_on_compare_drop)
	s.clicked.connect(func(slot: ItemSlot) -> void:
		if not slot.is_empty():
			_show(slot.kind, slot.key))
	return s


func _on_tab(i: int) -> void:
	_tab = i
	_selected_key = ""
	_rebuild()


# --- Items per tab --------------------------------------------------------------

## Entries: {kind, key, name, icon, count, condition, tier, value, load, accent, search}
func _entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match _tab:
		0, 4:
			for inst in InventoryManager.get_instances():
				var bm := inst.source == &"black_market"
				if bm != (_tab == 4):
					continue
				var d := inst.get_data()
				if d == null:
					continue
				out.append({"kind": &"implant", "key": inst.uid, "name": d.display_name, "icon": PixelArt.scaled(d.icon_path),
					"count": 1, "condition": inst.condition, "tier": d.tier, "value": d.price, "load": inst.get_neural_load(),
					"accent": d.get_rarity_color(), "search": "%s %s %s %s" % [d.display_name, d.category, d.manufacturer, d.rarity]})
			if _tab == 4:
				out.append(_resource(&"tokens", "Black-market tokens", InventoryManager.tokens))
		1:
			for id in InventoryManager.owned_tools:
				var t := InventoryManager.get_tool(id)
				if t == null:
					continue
				out.append({"kind": &"tool", "key": String(id), "name": t.display_name, "icon": PixelArt.scaled(t.icon_path),
					"count": 1, "condition": InventoryManager.get_tool_condition(id), "tier": t.tier, "value": t.price, "load": 0.0,
					"accent": Palette.LINE_HI, "search": "%s %s" % [t.display_name, t.category]})
		2:
			out.append(_resource(&"supplies", "Medical supplies", InventoryManager.supplies))
		3:
			out.append(_resource(&"parts", "Salvaged parts", InventoryManager.parts))
	if _filter != "":
		out = out.filter(func(e: Dictionary) -> bool: return str(e["search"]).to_lower().contains(_filter))
	match _sort:
		1: out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
		2: out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tier"]) > int(b["tier"]))
		3: out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["value"]) > int(b["value"]))
		4: out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["condition"]) > float(b["condition"]))
		5: out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["load"]) < float(b["load"]))
	return out


func _resource(kind: StringName, label: String, amount: int) -> Dictionary:
	return {"kind": kind, "key": String(kind), "name": label, "icon": PixelArt.scaled(ICONS[kind]), "count": amount,
		"condition": -1.0, "tier": 0, "value": 0, "load": 0.0, "accent": Palette.LINE_HI, "search": label}


func _rebuild() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_grid)
	var entries := _entries()
	for e in entries:
		var slot := ItemSlot.new().setup(e["kind"], e["key"], e["icon"], int(e["count"]), float(e["condition"]), e["accent"])
		slot.tooltip_text = str(e["name"])
		slot.selected = str(e["key"]) == _selected_key
		slot.hovered.connect(func(s: ItemSlot) -> void: _show(s.kind, s.key))
		slot.clicked.connect(_on_slot_clicked)
		slot.double_clicked.connect(_on_slot_inspect)
		slot.right_clicked.connect(func(s: ItemSlot) -> void: _set_compare(_compare_a, s.kind, s.key))
		slot.dropped.connect(_on_slot_drop)
		_grid.add_child(slot)
	# Pad to full rows so the grid reads as storage, not a list.
	var cells := maxi(COLUMNS * 4, ceili(entries.size() / float(COLUMNS)) * COLUMNS)
	for i in range(entries.size(), cells):
		var empty := ItemSlot.new()
		empty.mouse_default_cursor_shape = Control.CURSOR_ARROW
		empty.focus_mode = Control.FOCUS_NONE
		empty.modulate.a = 0.45
		_grid.add_child(empty)
	var units := InventoryManager.get_instances().size()
	_count.text = "%d implant units · %d tools · supplies %d/%d · parts %d · tokens %d" % [units, InventoryManager.owned_tools.size(),
		InventoryManager.supplies, ClinicManager.get_supplies_capacity(), InventoryManager.parts, InventoryManager.tokens]
	if _selected_key == "" and not entries.is_empty():
		_show(entries[0]["kind"], entries[0]["key"])
	elif entries.is_empty():
		UIKit.clear(_detail)
		_detail.add_child(UIKit.label("Nothing here%s." % (" matching \"%s\"" % _filter if _filter != "" else ""), &"DimLabel", true))
	_refresh_compare()


func _on_slot_clicked(s: ItemSlot) -> void:
	_selected_key = s.key
	for c in _grid.get_children():
		if c is ItemSlot:
			(c as ItemSlot).selected = (c as ItemSlot).key == s.key and not (c as ItemSlot).is_empty()
			(c as ItemSlot).queue_redraw()
	_show(s.kind, s.key)
	AudioManager.play_sfx(&"click", 0.05)


func _on_slot_inspect(s: ItemSlot) -> void:
	var d := _cyberware_of(s.kind, s.key)
	if d:
		UIManager.go_to(UIManager.SCREEN_DATABASE, {"id": d.id, "return_to": UIManager.SCREEN_INVENTORY})
	else:
		_on_slot_clicked(s)


## Drag a slot onto another slot of the same kind: swap their storage order.
func _on_slot_drop(target: ItemSlot, data: Dictionary) -> void:
	var from := str(data["key"])
	if target.is_empty() or from == target.key:
		return
	var kind := StringName(data["slot_kind"])
	if kind == &"implant":
		var list := InventoryManager.instances
		var a := -1
		var b := -1
		for i in list.size():
			if list[i].uid == from:
				a = i
			elif list[i].uid == target.key:
				b = i
		if a >= 0 and b >= 0:
			var tmp := list[a]
			list[a] = list[b]
			list[b] = tmp
	elif kind == &"tool":
		var tools := InventoryManager.owned_tools
		var a := tools.find(StringName(from))
		var b := tools.find(StringName(target.key))
		if a >= 0 and b >= 0:
			var tmp := tools[a]
			tools[a] = tools[b]
			tools[b] = tmp
	_sort = 0
	var sort := find_child("SortBy", true, false) as OptionButton
	if sort:
		sort.select(0)
	AudioManager.play_sfx(&"clamp", 0.05)
	_rebuild()


func _on_compare_drop(zone: ItemSlot, data: Dictionary) -> void:
	_set_compare(zone, StringName(data["slot_kind"]), str(data["key"]))


func _set_compare(zone: ItemSlot, kind: StringName, key: String) -> void:
	if kind != &"implant" and kind != &"tool":
		UIManager.show_toast("Only implants and tools can be compared", &"warn")
		return
	var other := _compare_b if zone == _compare_a else _compare_a
	if not other.is_empty() and other.kind != kind:
		other.setup(&"", "", null)
		other.name = "CompareB" if other == _compare_b else "CompareA"
	var icon: Texture2D
	if kind == &"implant":
		var inst := InventoryManager.get_instance(key)
		icon = PixelArt.scaled(inst.get_data().icon_path) if inst else null
	else:
		var t := InventoryManager.get_tool(StringName(key))
		icon = PixelArt.scaled(t.icon_path) if t else null
	zone.setup(kind, key, icon)
	zone.name = "CompareA" if zone == _compare_a else "CompareB"
	AudioManager.play_sfx(&"confirm", 0.05)
	_refresh_compare()


func _clear_compare() -> void:
	for z in [_compare_a, _compare_b]:
		z.setup(&"", "", null)
	_compare_a.name = "CompareA"
	_compare_b.name = "CompareB"
	_refresh_compare()


func _refresh_compare() -> void:
	while _compare.get_child_count() > 1:
		var c := _compare.get_child(1)
		_compare.remove_child(c)
		c.queue_free()
	if _compare_a.is_empty() or _compare_b.is_empty():
		_compare.add_child(UIKit.label("Right-click an item for CURRENT, drag another onto NEW.", &"DimLabel", true))
		return
	if _compare_a.kind == &"implant":
		var ia := InventoryManager.get_instance(_compare_a.key)
		var ib := InventoryManager.get_instance(_compare_b.key)
		if ia and ib:
			Compare.build_cyberware_table(_compare, ia.get_data(), ib.get_data(), ia, ib)
	else:
		Compare.build_tool_table(_compare, InventoryManager.get_tool(StringName(_compare_a.key)), InventoryManager.get_tool(StringName(_compare_b.key)))


func _cyberware_of(kind: StringName, key: String) -> CyberwareData:
	if kind != &"implant":
		return null
	var inst := InventoryManager.get_instance(key)
	return inst.get_data() if inst else null


# --- Detail panel ---------------------------------------------------------------

func _show(kind: StringName, key: String) -> void:
	UIKit.clear(_detail)
	match kind:
		&"implant":
			var inst := InventoryManager.get_instance(key)
			if inst == null:
				return
			var d := inst.get_data()
			var row := UIKit.hbox(14)
			_detail.add_child(row)
			row.add_child(CyberwareIcon.make(d))
			var v := UIKit.vbox(2)
			UIKit.expand(v)
			row.add_child(v)
			v.add_child(UIKit.label(d.display_name, &"HeaderLabel", true, d.get_rarity_color()))
			v.add_child(UIKit.label("%s · %s · %s" % [d.manufacturer, String(d.category).to_upper(), d.rarity.to_upper()], &"SubHeaderLabel", true))
			_detail.add_child(UIKit.label(d.description, &"DimLabel", true))
			var rows := Compare.cyberware_rows(d, inst)
			var g := GridContainer.new()
			g.columns = 2
			g.add_theme_constant_override(&"h_separation", 18)
			_detail.add_child(g)
			for r: Array in rows:
				g.add_child(UIKit.label(str(r[0]), &"SubHeaderLabel"))
				g.add_child(UIKit.label("??" if bool(r[4]) else str(r[1]), &"MonoLabel", false, Palette.WARN if bool(r[4]) else null))
			g.add_child(UIKit.label("SOURCE", &"SubHeaderLabel"))
			g.add_child(UIKit.label(String(inst.source).to_upper().replace("_", " ") + (" · %s" % d.origin if d.origin != "" else ""), &"MonoLabel", true, Palette.BRAND if inst.source == &"black_market" else null))
			if not d.benefits.is_empty():
				_detail.add_child(UIKit.label("EFFECTS: " + ", ".join(d.benefits), &"", true, Palette.ACCENT))
			if inst.has_unknown_traits():
				_detail.add_child(UIKit.label("%d unknown trait(s). STUDY it at the black market." % (inst.traits.size() - inst.revealed.size()), &"DimLabel", true, Palette.WARN))
			for t in inst.revealed:
				var td := BlackMarketManager.get_trait(t)
				_detail.add_child(UIKit.label("TRAIT: %s · %s" % [str(td.get("name", t)), str(td.get("description", ""))], &"DimLabel", true, Palette.BRAND))
			var actions := UIKit.hbox(10)
			_detail.add_child(actions)
			actions.add_child(UIKit.button("INSPECT  [F]", &"Button", func() -> void:
				UIManager.go_to(UIManager.SCREEN_DATABASE, {"id": d.id, "return_to": UIManager.SCREEN_INVENTORY}), "InspectButton"))
			actions.add_child(UIKit.button("SET AS CURRENT", &"GhostButton", func() -> void: _set_compare(_compare_a, kind, key), "CompareSet"))
		&"tool":
			var t := InventoryManager.get_tool(StringName(key))
			if t == null:
				return
			var row := UIKit.hbox(14)
			_detail.add_child(row)
			row.add_child(UIKit.icon(t.icon_path, 24))
			var v := UIKit.vbox(2)
			UIKit.expand(v)
			row.add_child(v)
			v.add_child(UIKit.label(t.display_name, &"HeaderLabel", true))
			v.add_child(UIKit.label("%s · T%d" % [String(t.category).to_upper(), t.tier], &"SubHeaderLabel"))
			_detail.add_child(UIKit.label(t.description, &"DimLabel", true))
			var cond := InventoryManager.get_tool_condition(t.id)
			var g := GridContainer.new()
			g.columns = 2
			g.add_theme_constant_override(&"h_separation", 18)
			_detail.add_child(g)
			for pair: Array in [["CONDITION", "%d%%" % roundi(cond)], ["PRECISION", "x%.2f (x%.2f now)" % [t.precision, t.precision * InventoryManager.tool_condition_factor(t.id)]],
					["SPEED", "x%.2f" % t.speed], ["RISK", "x%.2f" % t.risk]]:
				g.add_child(UIKit.label(pair[0], &"SubHeaderLabel"))
				g.add_child(UIKit.label(pair[1], &"MonoLabel"))
			if not t.modifiers.is_empty():
				_detail.add_child(UIKit.label(UIKit.describe_modifiers(t.modifiers), &"", true, Palette.ACCENT))
			_detail.add_child(UIKit.label("Service worn instruments at SUPPLY.", &"DimLabel", true))
		&"supplies":
			_detail.add_child(UIKit.label("MEDICAL SUPPLIES", &"HeaderLabel"))
			_detail.add_child(UIKit.label("%d / %d units" % [InventoryManager.supplies, ClinicManager.get_supplies_capacity()], &"BigMonoLabel"))
			_detail.add_child(UIKit.label("Gauze, clamps, synth-plasma. Every operation uses 1-2 units; without them bleeding and complications rise. Buy packs at SUPPLY.", &"DimLabel", true))
		&"parts":
			_detail.add_child(UIKit.label("SALVAGED PARTS", &"HeaderLabel"))
			_detail.add_child(UIKit.label("x%d" % InventoryManager.parts, &"BigMonoLabel"))
			_detail.add_child(UIKit.label("Components stripped from scrapped chrome and odd jobs. Spent on black-market MODIFY and on study.", &"DimLabel", true))
		&"tokens":
			_detail.add_child(UIKit.label("BLACK-MARKET TOKENS", &"HeaderLabel", false, Palette.BRAND))
			_detail.add_child(UIKit.label("x%d" % InventoryManager.tokens, &"BigMonoLabel"))
			_detail.add_child(UIKit.label("Untraceable credit chits. Mystery cases cost tokens; selling black-market chrome earns them.", &"DimLabel", true))
