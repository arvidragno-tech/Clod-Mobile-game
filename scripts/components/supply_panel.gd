class_name SupplyPanel
extends Control
## Modal "supply terminal": restock implants and buy tool upgrades.
## The item list is built from CyberwareManager / InventoryManager data.

const ICON_SIZE := Vector2(44, 44)
const BUY_BUTTON_SIZE := Vector2(84, 48)

var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_theme_constant_override(&"margin_top", 40)
	margin.add_theme_constant_override(&"margin_bottom", 40)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AccentPanel"
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override(&"separation", 0)
	header.add_child(title_box)
	var title := Label.new()
	title.text = "SUPPLY TERMINAL"
	title.theme_type_variation = &"HeaderLabel"
	title_box.add_child(title)
	_money = Label.new()
	_money.theme_type_variation = &"MonoLabel"
	_money.add_theme_color_override(&"font_color", Palette.WARN)
	title_box.add_child(_money)
	var close := Button.new()
	close.text = "X"
	close.name = "CloseButton"
	close.theme_type_variation = &"GhostButton"
	close.custom_minimum_size = Vector2(GameConfig.MIN_TOUCH, GameConfig.MIN_TOUCH)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(UIManager.close_modal)
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 260
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var note := Label.new()
	note.text = "Black-market chrome unlocks at REP %d." % GameConfig.BLACK_MARKET_REPUTATION
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild())
	EventBus.inventory_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_money.text = "Balance %s" % EconomyManager.format_money(EconomyManager.money)
	for child in _list.get_children():
		child.queue_free()
	for item in CyberwareManager.get_supply_catalog():
		var stock := InventoryManager.get_implant_count(item.id)
		_add_row(item.icon_path, item.display_name, "%s · In stock: %d" % [item.manufacturer, stock], item.price,
				func() -> void: _buy_implant(item.id), "BuyImplant_%s" % item.id)
	for t in InventoryManager.get_purchasable_tools():
		_add_row(t.icon_path, t.display_name, t.description, t.price,
				func() -> void: _buy_tool(t.id), "BuyTool_%s" % t.id)


func _add_row(icon_path: String, title: String, desc: String, price: int, on_buy: Callable, button_name: String) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	_list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = title
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.theme_type_variation = &"DimLabel"
	desc_label.add_theme_font_size_override(&"font_size", 13)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)
	var buy := Button.new()
	buy.name = button_name
	buy.text = EconomyManager.format_money(price)
	buy.theme_type_variation = &"AccentButton"
	buy.custom_minimum_size = BUY_BUTTON_SIZE
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.focus_mode = Control.FOCUS_NONE
	buy.disabled = not EconomyManager.can_afford(price)
	buy.pressed.connect(on_buy)
	row.add_child(buy)


func _buy_implant(id: StringName) -> void:
	if InventoryManager.buy_implant(id):
		AudioManager.play_sfx(&"cash")
		UIManager.show_toast("Implant restocked", &"success")
		SaveManager.save_game()


func _buy_tool(id: StringName) -> void:
	if InventoryManager.buy_tool(id):
		AudioManager.play_sfx(&"cash")
		UIManager.show_toast("%s acquired" % InventoryManager.get_tool(id).display_name, &"success")
		SaveManager.save_game()
