extends BaseScreen
## Supply terminal: licensed implants (by unlocked tier), surgical tools and
## consumable supplies. PC layout: a grid of item cards (hover or click to
## inspect) and a detail panel with the CURRENT vs NEW comparison.

const TABS := ["IMPLANTS", "TOOLS", "SUPPLIES"]
const COLUMNS := 2

var _list: GridContainer
var _detail: VBoxContainer
var _balance: Label
var _tab: int = 0
var _panels: Array[Control] = []
## The implant / tool the detail panel shows (kept across rebuilds).
var _shown: StringName = &""
var _rebuild_queued: bool = false


func on_enter(params: Dictionary) -> void:
	_tab = int(params.get("tab", 0))
	var col := UIKit.workstation(self, &"supply")
	var head := UIKit.header("CLINIC · SUPPLY", "SUPPLY TERMINAL", GameManager.go_to_clinic)
	col.add_child(head)
	_balance = UIKit.label("", &"MonoLabel", true, Palette.WARN)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIKit.expand(_balance)
	head.add_child(_balance)
	var tabs := UIKit.tabs(TABS, _on_tab, "ShopTab")
	tabs.custom_minimum_size.x = 720
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tabs)
	(tabs.get_child(_tab) as Button).button_pressed = true
	var row := UIKit.hbox(18)
	UIKit.expand(row, true, true)
	col.add_child(row)
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	row.add_child(sc)
	_panels.append(sc)
	_list = GridContainer.new()
	_list.columns = COLUMNS
	_list.add_theme_constant_override(&"h_separation", 12)
	_list.add_theme_constant_override(&"v_separation", 12)
	UIKit.expand(_list)
	sc.add_child(_list)
	# A fixed-width detail panel: its content must never resize the card grid
	# (a reflow on hover would move BUY buttons under the cursor).
	var dp := UIKit.panel(&"AccentPanel")
	dp.custom_minimum_size.x = 540
	dp.size_flags_horizontal = Control.SIZE_SHRINK_END
	dp.clip_contents = true
	row.add_child(dp)
	_panels.append(dp)
	var dsc := UIKit.scroll()
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dp.add_child(dsc)
	_detail = UIKit.vbox(10)
	_detail.name = "Detail"
	UIKit.expand(_detail)
	dsc.add_child(_detail)
	# One purchase emits several signals: rebuild once, after them all.
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _queue_rebuild())
	EventBus.inventory_changed.connect(_queue_rebuild)
	EventBus.resources_changed.connect(_queue_rebuild)
	_rebuild()


func get_panels() -> Array[Control]:
	return _panels


func _on_tab(i: int) -> void:
	_tab = i
	_shown = &""
	_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var scroll := _list.get_parent() as ScrollContainer
	var keep_scroll := scroll.scroll_vertical if scroll else 0
	_balance.text = ""  # your cash is in the status bar (and in BEFORE YOU PAY)
	UIKit.clear(_list)
	UIKit.clear(_detail)
	_list.columns = COLUMNS
	match _tab:
		0:
			var items := CyberwareManager.get_supply_catalog()  # what you can buy now
			var shown: CyberwareData = items[0] if not items.is_empty() else null
			for item in items:
				_list.add_child(_implant_card(item))
				if item.id == _shown:
					shown = item
			if shown:
				_show_implant(shown)
		1:
			var tools := InventoryManager.get_purchasable_tools()
			var shown_tool: ToolData = null
			for t in tools:
				_list.add_child(_tool_card(t))
				if t.id == _shown:
					shown_tool = t
			if shown_tool:
				_show_tool(shown_tool)
			else:
				_show_owned_tools()
		2:
			_list.columns = 1
			_list.add_child(_supplies_card())
			_show_owned_tools()
	if scroll:
		scroll.set_deferred(&"scroll_vertical", keep_scroll)


## Card behaviour: hover or click shows the item in the detail panel.
func _inspectable(card: Control, show: Callable) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(show)
	card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			show.call())


func _show_implant(item: CyberwareData) -> void:
	_shown = item.id
	UIKit.clear(_detail)
	var row := UIKit.hbox(14)
	_detail.add_child(row)
	row.add_child(CyberwareIcon.make(item))
	var v := UIKit.vbox(2)
	UIKit.expand(v)
	row.add_child(v)
	v.add_child(UIKit.label(item.display_name, &"HeaderLabel", true, item.get_rarity_color()))
	v.add_child(UIKit.label("%s · %s · %s" % [item.manufacturer, String(item.category).to_upper(), item.rarity.to_upper()], &"SubHeaderLabel", true))
	if not item.benefits.is_empty():
		_detail.add_child(UIKit.label("EFFECTS: " + ", ".join(item.benefits), &"", true, Palette.ACCENT))
	# Before you pay: the real price and what it leaves you (DecisionPreview).
	var have := InventoryManager.get_implant_count(item.id)
	var limits: Array[String] = []
	if not CyberwareManager.is_tier_available(item.tier):
		limits.append("Locked: needs LV %d and a clinic rated for T%d." % [GameConfig.CYBERWARE_TIER_LEVEL.get(item.tier, 99), item.tier])
	if not item.required_tools.is_empty():
		limits.append("Fitting it needs: %s." % ", ".join(item.required_tools).to_lower())
	DecisionPreview.build(_detail, InventoryManager.implant_price(item), {"stock": "%d → %d" % [have, have + 1],
		"purpose": "A patient who asks for it pays for the part when you fit it.", "limits": limits})
	# Specs and the comparison: one click away.
	var more := UIKit.collapsible(_detail, "SPECS & COMPARE", false, &"CardPanel")
	more.add_child(UIKit.label(item.description, &"DimLabel", true, null, 14))
	more.add_child(UIKit.label("T%d %s · %s · load +%d%% · difficulty %d/5" % [item.tier, item.get_tier_name(), String(item.category).to_upper(), roundi(item.neural_load), item.install_difficulty], &"MonoLabel", true, Palette.TEXT_DIM, 15))
	Compare.build_cyberware_table(more, _current_for(item), item)


func _current_for(item: CyberwareData) -> CyberwareData:
	var c := CustomerManager.current_customer
	if c:
		for id in c.existing_cyberware:
			var e := CyberwareManager.get_cyberware(id)
			if e and e.category == item.category:
				return e
	for inst in InventoryManager.get_instances():
		var d := inst.get_data()
		if d and d.category == item.category and d.id != item.id:
			return d
	return null


func _show_tool(t: ToolData) -> void:
	_shown = t.id
	UIKit.clear(_detail)
	var row := UIKit.hbox(14)
	_detail.add_child(row)
	row.add_child(UIKit.icon(t.icon_path, 24))
	var v := UIKit.vbox(2)
	UIKit.expand(v)
	row.add_child(v)
	v.add_child(UIKit.label(t.display_name, &"HeaderLabel", true))
	v.add_child(UIKit.label("%s · T%d" % [String(t.category).to_upper(), t.tier], &"SubHeaderLabel"))
	if not t.modifiers.is_empty():
		_detail.add_child(UIKit.label(UIKit.describe_modifiers(t.modifiers), &"", true, Palette.ACCENT))
	var best := InventoryManager.get_best_tool(t.category)
	var tl: Array[String] = []
	if t.unlock_level > ProgressionManager.level:
		tl.append("Unlocks at LV %d." % t.unlock_level)
	DecisionPreview.build(_detail, InventoryManager.tool_price(t), {"stock": "best %s now: %s" % [String(t.category).to_lower(), best.display_name if best else "none"],
		"purpose": "Used whenever a step needs a %s. Better instruments lower the risk; they wear %d%% per operation." % [String(t.category).to_lower(), roundi(InventoryManager.WEAR_PER_OP)],
		"limits": tl})
	var more := UIKit.collapsible(_detail, "SPECS & COMPARE", false, &"CardPanel")
	more.add_child(UIKit.label(t.description, &"DimLabel", true, null, 14))
	Compare.build_tool_table(more, InventoryManager.get_best_tool(t.category), t)


## Owned instruments with condition, plus SERVICE (restores 100%).
func _show_owned_tools() -> void:
	UIKit.clear(_detail)
	_detail.add_child(UIKit.section_head("YOUR INSTRUMENTS"))
	for id in InventoryManager.owned_tools:
		var t := InventoryManager.get_tool(id)
		if t == null:
			continue
		var r := UIKit.hbox(10)
		r.add_child(UIKit.icon(t.icon_path, 24))
		var name_l := UIKit.label(t.display_name, &"", true)
		UIKit.expand(name_l)
		r.add_child(name_l)
		var cond := InventoryManager.get_tool_condition(id)
		r.add_child(UIKit.label("%d%%" % roundi(cond), &"MonoLabel", false, Palette.OK if cond >= 60.0 else (Palette.WARN if cond >= 25.0 else Palette.DANGER)))
		_detail.add_child(r)
	var cost := InventoryManager.get_service_cost()
	_detail.add_child(UIKit.label("Instruments wear %d%% per operation and lose up to %d%% precision when worn out." % [roundi(InventoryManager.WEAR_PER_OP), roundi((1.0 - InventoryManager.WORN_PRECISION) * 100.0)], &"DimLabel", true))
	var b := UIKit.button("SERVICE ALL  %s" % EconomyManager.format_money(cost) if cost > 0 else "ALL INSTRUMENTS AT 100%", &"AccentButton", _service, "ServiceTools", 56)
	b.disabled = cost <= 0 or not EconomyManager.can_afford(cost)
	_detail.add_child(b)


func _service() -> void:
	if not UIKit.debounce("service_tools"):
		return
	if InventoryManager.service_tools():
		UIManager.celebrate(&"tool", "Instruments serviced")
		SaveManager.save_game()


func _implant_card(item: CyberwareData) -> Control:
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card)
	_inspectable(card, _show_implant.bind(item))
	var row := UIKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := CyberwareIcon.make(item)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the whole card inspects
	row.add_child(icon)
	var info := UIKit.vbox(2)
	UIKit.expand(info)
	row.add_child(info)
	# Name, what it does, and why it matters now; specs are in the detail panel.
	info.add_child(UIKit.label(item.display_name, &"", true))
	if not item.benefits.is_empty():
		info.add_child(UIKit.label(item.benefits[0], &"DimLabel", true, null, 14))
	var c := CustomerManager.current_customer
	if c and c.requested_cyberware_id == item.id:
		info.add_child(UIKit.label("★ for the patient at the door", &"", true, Palette.ACCENT, 14))
	var have := InventoryManager.get_implant_count(item.id)
	if have > 0:
		info.add_child(UIKit.label("%d in stock" % have, &"DimLabel", false, Palette.OK, 14))
	var price := InventoryManager.implant_price(item)
	var b := UIKit.button(EconomyManager.format_money(price), &"AccentButton", func() -> void: _buy_implant(item.id), "BuyImplant_%s" % item.id)
	b.custom_minimum_size.x = 130
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not CyberwareManager.is_tier_available(item.tier):
		b.text = "LOCKED"
		b.disabled = true
		b.tooltip_text = "Needs LV %d and a clinic rated for T%d" % [GameConfig.CYBERWARE_TIER_LEVEL.get(item.tier, 99), item.tier]
	elif not EconomyManager.can_afford(price):
		b.disabled = true
	row.add_child(b)
	return card


## The instrument the patient at the door is missing (or &"").
func _needed_tool_category() -> StringName:
	var c := CustomerManager.current_customer
	if c == null:
		return &""
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item == null:
		return &""
	for req in item.get_tool_requirements():
		if not InventoryManager.has_tool_category(StringName(str(req["category"])), int(req["tier"])):
			return StringName(str(req["category"]))
	return &""


func _tool_card(t: ToolData) -> Control:
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card)
	_inspectable(card, _show_tool.bind(t))
	var row := UIKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(UIKit.icon(t.icon_path, 24))
	var info := UIKit.vbox(2)
	UIKit.expand(info)
	row.add_child(info)
	info.add_child(UIKit.label(t.display_name, &"", true))
	info.add_child(UIKit.label("%s, tier %d" % [String(t.category).capitalize(), t.tier], &"DimLabel", true, null, 14))
	if _needed_tool_category() == t.category:
		info.add_child(UIKit.label("★ the patient at the door needs one", &"", true, Palette.ACCENT, 14))
	var price := InventoryManager.tool_price(t)
	var b := UIKit.button(EconomyManager.format_money(price), &"AccentButton", func() -> void: _buy_tool(t.id), "BuyTool_%s" % t.id)
	b.custom_minimum_size.x = 130
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if t.unlock_level > ProgressionManager.level:
		b.text = "LV %d" % t.unlock_level
		b.disabled = true
	elif not EconomyManager.can_afford(price):
		b.disabled = true
	row.add_child(b)
	return card


func _supplies_card() -> Control:
	var card := UIKit.panel(&"CardPanel")
	var v := UIKit.vbox(8)
	card.add_child(v)
	var row := UIKit.hbox(10)
	v.add_child(row)
	row.add_child(UIKit.icon("res://assets/sprites/ui/icons/supplies.png", 12))
	row.add_child(UIKit.label("MEDICAL SUPPLIES  %d / %d" % [InventoryManager.supplies, ClinicManager.get_supplies_capacity()], &"HeaderLabel"))
	v.add_child(UIKit.label("Every operation uses 1-2 units. Operating without supplies raises bleeding and complications.", &"DimLabel", true))
	var price := int(round(GameConfig.SUPPLY_PACK_PRICE * ModifierManager.mult(&"price.buy")))
	var b := UIKit.button("BUY %d FOR %s" % [GameConfig.SUPPLY_PACK_SIZE, EconomyManager.format_money(price)], &"AccentButton", _buy_supplies, "BuySupplies")
	b.tooltip_text = DecisionPreview.summary(price) + " · supplies %d → %d" % [InventoryManager.supplies, mini(InventoryManager.supplies + GameConfig.SUPPLY_PACK_SIZE, ClinicManager.get_supplies_capacity())]
	b.disabled = not EconomyManager.can_afford(price) or InventoryManager.supplies >= ClinicManager.get_supplies_capacity()
	v.add_child(b)
	v.add_child(UIKit.label("PARTS %d  ·  TOKENS %d" % [InventoryManager.parts, InventoryManager.tokens], &"MonoLabel", false, Palette.TEXT_DIM))
	v.add_child(UIKit.label("Parts come from scrapping chrome and odd jobs. Tokens are black-market currency.", &"DimLabel", true, null, 13))
	return card


func _buy_implant(id: StringName) -> void:
	if not UIKit.debounce("buy_implant_%s" % id):
		return  # a double-click is one purchase
	_shown = id
	if InventoryManager.buy_implant(id):
		UIManager.celebrate(&"purchase", "%s stocked" % CyberwareManager.get_cyberware(id).display_name)
		SaveManager.save_game()
	else:
		AudioManager.play_sfx(&"denied")
		UIManager.show_toast("Purchase failed: insufficient credits", &"danger")


func _buy_tool(id: StringName) -> void:
	if not UIKit.debounce("buy_tool_%s" % id):
		return
	_shown = id
	if InventoryManager.buy_tool(id):
		UIManager.celebrate(&"tool", "%s acquired" % InventoryManager.get_tool(id).display_name)
		SaveManager.save_game()
	else:
		UIManager.show_toast("Purchase failed", &"danger")


func _buy_supplies() -> void:
	if not UIKit.debounce("buy_supplies"):
		return
	if InventoryManager.buy_supply_pack():
		UIManager.celebrate(&"purchase")
		SaveManager.save_game()
