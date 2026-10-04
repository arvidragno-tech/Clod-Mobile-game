extends BaseScreen
## Supply terminal: licensed implants (by unlocked tier), surgical tools and
## consumable supplies.

const TABS := ["IMPLANTS", "TOOLS", "SUPPLIES"]

var _list: VBoxContainer
var _balance: Label
var _tab: int = 0


func on_enter(params: Dictionary) -> void:
	_tab = int(params.get("tab", 0))
	var m := UIKit.full_rect(UIKit.margin(10, 8, 10, 10))
	add_child(m)
	var col := UIKit.vbox(8)
	m.add_child(col)
	col.add_child(UIKit.header("CLINIC · SUPPLY", "SUPPLY TERMINAL", GameManager.go_to_clinic))
	_balance = UIKit.label("", &"MonoLabel", true, Palette.WARN, 18)
	col.add_child(_balance)
	var tabs := UIKit.tabs(TABS, _on_tab, "ShopTab")
	col.add_child(tabs)
	(tabs.get_child(_tab) as Button).button_pressed = true
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = UIKit.vbox(8)
	UIKit.expand(_list)
	sc.add_child(_list)
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild())
	EventBus.inventory_changed.connect(_rebuild)
	EventBus.resources_changed.connect(_rebuild)
	_rebuild()


func _on_tab(i: int) -> void:
	_tab = i
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_balance.text = "BALANCE %s  ·  TIER T%d ACCESS" % [EconomyManager.format_money(EconomyManager.money), CyberwareManager.get_available_tier()]
	UIKit.clear(_list)
	match _tab:
		0:
			for item in CyberwareManager.get_supply_catalog(true):
				_list.add_child(_implant_card(item))
		1:
			for t in InventoryManager.get_purchasable_tools(true):
				_list.add_child(_tool_card(t))
			_list.add_child(UIKit.label("OWNED", &"SubHeaderLabel"))
			var owned := HFlowContainer.new()
			owned.add_theme_constant_override(&"h_separation", 4)
			owned.add_theme_constant_override(&"v_separation", 4)
			for id in InventoryManager.owned_tools:
				var t := InventoryManager.get_tool(id)
				if t:
					var ic := UIKit.icon(t.icon_path, 24)
					ic.tooltip_text = t.display_name
					owned.add_child(ic)
			_list.add_child(owned)
		2:
			_list.add_child(_supplies_card())


func _implant_card(item: CyberwareData) -> Control:
	var card := UIKit.panel(&"CardPanel")
	var row := UIKit.hbox(10)
	card.add_child(row)
	row.add_child(CyberwareIcon.make(item))
	var info := UIKit.vbox(2)
	UIKit.expand(info)
	row.add_child(info)
	info.add_child(UIKit.label(item.display_name, &"", true))
	info.add_child(UIKit.label("T%d %s · %s" % [item.tier, item.get_tier_name(), item.category.to_upper()], &"SubHeaderLabel", true, item.get_rarity_color()))
	info.add_child(UIKit.label("LOAD +%d%%  ·  DIFF %d/5  ·  IN STOCK %d" % [roundi(item.neural_load), item.install_difficulty, InventoryManager.get_implant_count(item.id)], &"MonoLabel", true, Palette.TEXT_DIM, 17))
	info.add_child(UIKit.label(", ".join(item.benefits), &"DimLabel", true, null, 13))
	if not item.required_tools.is_empty():
		info.add_child(UIKit.label("Needs: " + ", ".join(item.required_tools).to_upper(), &"DimLabel", true, Palette.WARN, 13))
	var price := InventoryManager.implant_price(item)
	var b := UIKit.button(EconomyManager.format_money(price), &"AccentButton", func() -> void: _buy_implant(item.id), "BuyImplant_%s" % item.id)
	b.custom_minimum_size.x = 92
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not CyberwareManager.is_tier_available(item.tier):
		b.text = "LOCKED"
		b.disabled = true
		b.tooltip_text = "Needs LV %d and a clinic rated for T%d" % [GameConfig.CYBERWARE_TIER_LEVEL.get(item.tier, 99), item.tier]
	elif not EconomyManager.can_afford(price):
		b.disabled = true
	row.add_child(b)
	return card


func _tool_card(t: ToolData) -> Control:
	var card := UIKit.panel(&"CardPanel")
	var row := UIKit.hbox(10)
	card.add_child(row)
	row.add_child(UIKit.icon(t.icon_path, 24))
	var info := UIKit.vbox(2)
	UIKit.expand(info)
	row.add_child(info)
	info.add_child(UIKit.label(t.display_name, &"", true))
	info.add_child(UIKit.label("%s T%d · PREC x%.1f · SPEED x%.1f · RISK x%.2f" % [String(t.category).to_upper(), t.tier, t.precision, t.speed, t.risk], &"SubHeaderLabel", true))
	info.add_child(UIKit.label(t.description, &"DimLabel", true, null, 13))
	if not t.modifiers.is_empty():
		info.add_child(UIKit.label(UIKit.describe_modifiers(t.modifiers), &"DimLabel", true, Palette.ACCENT, 13))
	var price := InventoryManager.tool_price(t)
	var b := UIKit.button(EconomyManager.format_money(price), &"AccentButton", func() -> void: _buy_tool(t.id), "BuyTool_%s" % t.id)
	b.custom_minimum_size.x = 92
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
	b.disabled = not EconomyManager.can_afford(price) or InventoryManager.supplies >= ClinicManager.get_supplies_capacity()
	v.add_child(b)
	v.add_child(UIKit.label("PARTS %d  ·  TOKENS %d" % [InventoryManager.parts, InventoryManager.tokens], &"MonoLabel", false, Palette.TEXT_DIM))
	v.add_child(UIKit.label("Parts come from scrapping chrome and odd jobs. Tokens are black-market currency.", &"DimLabel", true, null, 13))
	return card


func _buy_implant(id: StringName) -> void:
	if InventoryManager.buy_implant(id):
		UIManager.celebrate(&"purchase", "%s stocked" % CyberwareManager.get_cyberware(id).display_name)
		SaveManager.save_game()
	else:
		AudioManager.play_sfx(&"denied")
		UIManager.show_toast("Purchase failed: insufficient credits", &"danger")


func _buy_tool(id: StringName) -> void:
	if InventoryManager.buy_tool(id):
		UIManager.celebrate(&"tool", "%s acquired" % InventoryManager.get_tool(id).display_name)
		SaveManager.save_game()
	else:
		UIManager.show_toast("Purchase failed", &"danger")


func _buy_supplies() -> void:
	if InventoryManager.buy_supply_pack():
		UIManager.celebrate(&"purchase")
		SaveManager.save_game()
