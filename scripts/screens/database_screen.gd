extends BaseScreen
## Cyberware database (PC). Left: searchable, filterable list of every
## model the clinic knows about. Centre: the full spec sheet (rarity,
## price, neural load, compatibility, difficulty, effects, risks,
## manufacturer, origin, condition of stocked units). Right: CURRENT vs NEW
## comparison (Better / Worse / Unknown / Incompatible).
## Click a row = NEW; right-click a row (or SET AS CURRENT) = CURRENT.

const CATEGORY_ALL := "ALL SLOTS"
const SORTS := ["TIER", "NAME", "PRICE", "NEURAL LOAD", "DIFFICULTY"]

var _return_to: StringName = UIManager.SCREEN_CLINIC
var _list: VBoxContainer
var _spec: VBoxContainer
var _compare: VBoxContainer
var _filter: String = ""
var _category: String = CATEGORY_ALL
var _sort: int = 0
var _show_bm: bool = true
var _current: CyberwareData
var _new: CyberwareData
var _panels: Array[Control] = []


func on_enter(params: Dictionary) -> void:
	_return_to = StringName(str(params.get("return_to", UIManager.SCREEN_CLINIC)))
	var col := UIKit.workstation(self, &"database")
	var head := UIKit.header("CLINIC · REFERENCE", "CYBERWARE DATABASE", _back)
	col.add_child(head)
	var bar := UIKit.hbox(12)
	col.add_child(bar)
	bar.add_child(UIKit.label("SEARCH", &"SubHeaderLabel"))
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "name, maker, effect..."
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(360, GameConfig.MIN_CONTROL)
	search.text_changed.connect(func(t: String) -> void:
		_filter = t.strip_edges().to_lower()
		_rebuild_list())
	bar.add_child(search)
	var cat := OptionButton.new()
	cat.name = "SlotFilter"
	cat.add_item(CATEGORY_ALL)
	for c in CyberwareData.CATEGORIES:
		cat.add_item(String(c).to_upper())
	cat.custom_minimum_size = Vector2(240, GameConfig.MIN_CONTROL)
	cat.item_selected.connect(func(i: int) -> void:
		_category = cat.get_item_text(i)
		_rebuild_list())
	bar.add_child(cat)
	var sort := OptionButton.new()
	sort.name = "SortBy"
	for s in SORTS:
		sort.add_item("SORT: " + s)
	sort.custom_minimum_size = Vector2(260, GameConfig.MIN_CONTROL)
	sort.item_selected.connect(func(i: int) -> void:
		_sort = i
		_rebuild_list())
	bar.add_child(sort)
	var bm := CheckButton.new()
	bm.name = "ShowBlackMarket"
	bm.text = "BLACK-MARKET MODELS"
	bm.button_pressed = true
	bm.toggled.connect(func(on: bool) -> void:
		_show_bm = on
		_rebuild_list())
	bar.add_child(bm)
	var row := UIKit.hbox(18)
	UIKit.expand(row, true, true)
	col.add_child(row)
	var lp := UIKit.panel(&"CardPanel")
	lp.custom_minimum_size.x = 470
	row.add_child(lp)
	_panels.append(lp)
	var lsc := UIKit.scroll()
	lp.add_child(lsc)
	_list = UIKit.vbox(4)
	_list.name = "List"
	UIKit.expand(_list)
	lsc.add_child(_list)
	var sp := UIKit.panel(&"AccentPanel")
	UIKit.expand(sp, true, true)
	row.add_child(sp)
	_panels.append(sp)
	var ssc := UIKit.scroll()
	sp.add_child(ssc)
	_spec = UIKit.vbox(10)
	_spec.name = "Spec"
	UIKit.expand(_spec)
	ssc.add_child(_spec)
	var cp := UIKit.panel(&"CardPanel")
	cp.custom_minimum_size.x = 560
	row.add_child(cp)
	_panels.append(cp)
	cp.clip_contents = true
	var csc := UIKit.scroll()
	# Wide comparisons scroll sideways inside the panel instead of widening
	# the screen past the canvas.
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cp.add_child(csc)
	_compare = UIKit.vbox(10)
	_compare.name = "Compare"
	UIKit.expand(_compare)
	csc.add_child(_compare)
	# Defaults: NEW = the requested / given model, CURRENT = what the
	# customer already has in that slot.
	var start := CyberwareManager.get_cyberware(StringName(str(params.get("id", ""))))
	if start == null:
		start = GameManager.get_requested_item() if CustomerManager.has_customer() else null
	if start == null:
		var all := _models()
		start = all[0] if not all.is_empty() else null
	_rebuild_list()
	if start:
		_select(start)
		_current = _default_current(start)
		_refresh_compare()


func get_panels() -> Array[Control]:
	return _panels


func _back() -> void:
	UIManager.go_to(_return_to)


## Models the player has seen: supply catalogue, unlocked black-market
## models, anything in stock or installed in the current customer.
func _models() -> Array[CyberwareData]:
	var known := {}
	for c: CyberwareData in CyberwareManager.catalog.values():
		if not c.black_market or CyberwareManager.unlocked.has(c.id) or BlackMarketManager.is_unlocked():
			known[c.id] = c
	var out: Array[CyberwareData] = []
	for c: CyberwareData in known.values():
		if c.black_market and not _show_bm:
			continue
		if _category != CATEGORY_ALL and String(c.category).to_upper() != _category:
			continue
		if _filter != "" and not ("%s %s %s %s %s" % [c.display_name, c.manufacturer, c.category, ", ".join(c.benefits), c.origin]).to_lower().contains(_filter):
			continue
		out.append(c)
	match _sort:
		0: out.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.tier < b.tier or (a.tier == b.tier and a.display_name < b.display_name))
		1: out.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.display_name < b.display_name)
		2: out.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.price < b.price)
		3: out.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.neural_load < b.neural_load)
		4: out.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.install_difficulty < b.install_difficulty)
	return out


func _rebuild_list() -> void:
	UIKit.clear(_list)
	var models := _models()
	if models.is_empty():
		_list.add_child(UIKit.label("No models match.", &"DimLabel"))
	for c in models:
		var b := Button.new()
		b.name = "Model_%s" % c.id
		b.theme_type_variation = &"ToolButton"
		b.toggle_mode = true
		b.button_pressed = _new == c
		b.custom_minimum_size.y = 78
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s\nClick: inspect (NEW) · Right-click: set as CURRENT" % c.display_name
		var m := UIKit.full_rect(UIKit.margin(8, 4, 10, 4))
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var r := UIKit.hbox(10)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(r)
		var icon := CyberwareIcon.make(c)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(icon)
		var v := UIKit.vbox(0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIKit.expand(v)
		r.add_child(v)
		var n := UIKit.label(c.display_name, &"", false, c.get_rarity_color(), 15)
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(n)
		v.add_child(UIKit.label("T%d · %s%s · %d in stock" % [c.tier, String(c.category).to_upper(), " · BLACK MKT" if c.black_market else "", InventoryManager.get_implant_count(c.id)], &"SubHeaderLabel", false, Palette.BRAND if c.black_market else null))
		b.pressed.connect(_select.bind(c))
		b.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_current = c
				AudioManager.play_sfx(&"confirm", 0.05)
				_refresh_compare())
		_list.add_child(b)


func _default_current(c: CyberwareData) -> CyberwareData:
	var cust := CustomerManager.current_customer
	if cust:
		for id in cust.existing_cyberware:
			var e := CyberwareManager.get_cyberware(id)
			if e and e.category == c.category and e != c:
				return e
	return null


func _select(c: CyberwareData) -> void:
	_new = c
	for b in _list.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(b.name == "Model_%s" % c.id)
	_build_spec(c)
	_refresh_compare()


func _build_spec(c: CyberwareData) -> void:
	UIKit.clear(_spec)
	var row := UIKit.hbox(16)
	_spec.add_child(row)
	row.add_child(CyberwareIcon.make(c))
	var v := UIKit.vbox(2)
	UIKit.expand(v)
	row.add_child(v)
	v.add_child(UIKit.label(c.display_name, &"HeaderLabel", true, c.get_rarity_color()))
	v.add_child(UIKit.label("%s · %s" % [c.rarity.to_upper(), "BLACK-MARKET MODEL" if c.black_market else "LICENSED"], &"SubHeaderLabel", false, Palette.BRAND if c.black_market else c.get_rarity_color()))
	_spec.add_child(UIKit.label(c.description, &"DimLabel", true))
	var surgery := SurgeryManager.get_surgery(c.install_surgery_id)
	var tools: Array[String] = []
	for req in c.get_tool_requirements():
		var have := InventoryManager.has_tool_category(StringName(str(req["category"])), int(req["tier"]))
		tools.append("%s T%d%s" % [String(req["category"]).to_upper(), int(req["tier"]), "" if have else " ✕"])
	var risks: Array[String] = []
	for cid in c.complication_ids:
		var comp: ComplicationData = SurgeryManager.complications.get(cid)
		risks.append(comp.title if comp else String(cid))
	var stock := InventoryManager.get_instances().filter(func(i: ImplantInstance) -> bool: return i.cyberware_id == c.id)
	var conds: Array[String] = []
	for i: ImplantInstance in stock:
		conds.append("%d%%" % roundi(i.condition))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override(&"h_separation", 22)
	g.add_theme_constant_override(&"v_separation", 6)
	_spec.add_child(g)
	var unknown := c.unknown_traits > 0
	for pair: Array in [
		["MANUFACTURER", c.manufacturer if c.manufacturer != "" else "unknown"],
		["ORIGIN", c.origin if c.origin != "" else ("street salvage" if c.black_market else "licensed supply")],
		["SLOT", String(c.category).to_upper()],
		["TIER", "T%d %s" % [c.tier, c.get_tier_name()]],
		["RARITY", c.rarity.to_upper()],
		["PRICE", EconomyManager.format_money(c.price)],
		["NEURAL LOAD", "+%d%%%s" % [roundi(c.neural_load), "  (± unknown traits)" if unknown else ""]],
		["PERFORMANCE", "%d%%" % roundi(c.base_performance * 100.0)],
		["DIFFICULTY", "%s  %d/5" % [UIKit.pips(c.install_difficulty, 5), c.install_difficulty]],
		["PROCEDURE", "%s (%d steps)" % [surgery.display_name, surgery.stages.size()] if surgery else "-"],
		["COMPATIBILITY", "%s · tools: %s" % ["available now" if CyberwareManager.is_unlocked(c.id) else "locked (tier / level)", ", ".join(tools) if not tools.is_empty() else "standard kit"]],
		["FAILURE RISK", "%d%%" % roundi(c.failure_risk * 100.0)],
		["RISKS", ", ".join(risks) if not risks.is_empty() else "standard"],
		["HIDDEN TRAITS", "%d unknown" % c.unknown_traits if unknown else "none"],
		["IN STOCK", "%d unit(s)%s" % [stock.size(), (" · condition " + ", ".join(conds)) if not conds.is_empty() else ""]],
	]:
		g.add_child(UIKit.caption(pair[0]))
		var vl := UIKit.label(str(pair[1]), &"", true, Palette.WARN if str(pair[1]).contains("✕") or str(pair[1]).begins_with("locked") else null)
		UIKit.expand(vl)
		g.add_child(vl)
	if not c.benefits.is_empty():
		_spec.add_child(UIKit.section_head("EFFECTS"))
		for e in c.benefits:
			_spec.add_child(UIKit.label("+ " + e, &"", true, Palette.OK))
	var actions := UIKit.hbox(10)
	_spec.add_child(actions)
	actions.add_child(UIKit.button("SET AS CURRENT", &"GhostButton", func() -> void:
		_current = c
		_refresh_compare(), "SetCurrent"))


func _refresh_compare() -> void:
	UIKit.clear(_compare)
	_compare.add_child(UIKit.section_head("COMPARISON", "", "performance"))
	if _new == null:
		return
	if _current == null:
		_compare.add_child(UIKit.label("Right-click a model (or SET AS CURRENT) to compare against it. Defaults to the customer's chrome in the same slot.", &"DimLabel", true))
	Compare.build_cyberware_table(_compare, _current, _new)
	var legend := UIKit.label("▲ BETTER   ▼ WORSE   ? UNKNOWN   ✕ INCOMPATIBLE", &"SubHeaderLabel", true)
	_compare.add_child(legend)
