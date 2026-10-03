extends BaseScreen
## The player's hub: see who's waiting, restock, check records.

@onready var _view: ClinicView = %ClinicView
@onready var _card: PanelContainer = %CustomerCard
@onready var _portrait: TextureRect = %Portrait
@onready var _name: Label = %CustomerName
@onready var _request: Label = %Request
@onready var _offer: Label = %Offer
@onready var _see_button: Button = %SeeButton
@onready var _waiting: Label = %Waiting
@onready var _supply_button: Button = %SupplyButton
@onready var _records_button: Button = %RecordsButton
@onready var _menu_button: Button = %MenuButton
@onready var _black_market_button: Button = %BlackMarketButton
@onready var _stock_label: Label = %StockLabel

var _waiting_dots: float = 0.0


func on_enter(_params: Dictionary) -> void:
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.inventory_changed.connect(_refresh_stock)
	_see_button.pressed.connect(GameManager.open_customer)
	_view.customer_tapped.connect(GameManager.open_customer)
	_supply_button.pressed.connect(_open_supply)
	_records_button.pressed.connect(_show_records)
	_menu_button.pressed.connect(GameManager.quit_to_menu)
	_black_market_button.pressed.connect(_on_black_market_pressed)
	_black_market_button.text = "BLACK MARKET · REP %d" % GameConfig.BLACK_MARKET_REPUTATION
	_refresh_stock()
	if CustomerManager.has_customer():
		_show_customer(CustomerManager.current_customer, false)
	else:
		_show_waiting()
		CustomerManager.request_next_customer()


func _process(delta: float) -> void:
	if _waiting.visible:
		_waiting_dots += delta * 2.0
		_waiting.text = "Waiting for customers" + ".".repeat(int(_waiting_dots) % 4)


func _on_customer_arrived(customer: CustomerData) -> void:
	AudioManager.play_sfx(&"customer")
	UIManager.haptic()
	UIManager.show_toast("%s is at the door" % customer.display_name, &"info")
	_show_customer(customer, true)


func _show_customer(customer: CustomerData, animate: bool) -> void:
	_view.show_customer(customer, animate)
	var surgery := SurgeryManager.get_surgery(customer.requested_surgery_id)
	var item := CyberwareManager.get_cyberware(surgery.cyberware_id) if surgery else null
	_portrait.texture = load(customer.portrait_path) as Texture2D if ResourceLoader.exists(customer.portrait_path) else null
	_name.text = "%s \"%s\"" % [customer.display_name, customer.alias]
	_request.text = "Wants: %s" % (item.display_name if item else "?")
	var expected := int(round(surgery.base_pay * customer.pay_multiplier)) if surgery else 0
	_offer.text = "Offers %s" % EconomyManager.format_money(expected)
	_waiting.visible = false
	for node: Control in [_portrait, _name, _request, _offer, _see_button]:
		node.visible = true
	if animate:
		_card.modulate.a = 0.0
		create_tween().tween_property(_card, "modulate:a", 1.0, 0.25)


func _show_waiting() -> void:
	_view.hide_customer()
	_waiting.visible = true
	for node: Control in [_portrait, _name, _request, _offer, _see_button]:
		node.visible = false


func _refresh_stock() -> void:
	var parts: Array[String] = []
	for item in CyberwareManager.get_supply_catalog():
		parts.append("%s x%d" % [item.display_name.get_slice(" ", 0), InventoryManager.get_implant_count(item.id)])
	_stock_label.text = "STOCK  " + "  ".join(parts)


func _open_supply() -> void:
	UIManager.show_modal(SupplyPanel.new())


func _show_records() -> void:
	var lines: Array[String] = []
	lines.append("Level %d  (%d XP)" % [ProgressionManager.level, ProgressionManager.total_xp])
	lines.append("Reputation %d · %s" % [ReputationManager.reputation, ReputationManager.get_tier_name()])
	lines.append("Customers served: %d" % ProgressionManager.customers_served)
	for surgery_id: String in ProgressionManager.surgery_records:
		var rec: Dictionary = ProgressionManager.surgery_records[surgery_id]
		var surgery := SurgeryManager.get_surgery(StringName(surgery_id))
		var surgery_name := surgery.display_name if surgery else surgery_id
		lines.append("%s: %d done, %d failed, best %s" % [surgery_name, rec.get("completed", 0), rec.get("failed", 0), str(rec.get("best_grade", "-")) if str(rec.get("best_grade", "")) != "" else "-"])
	var close: Array[Dictionary] = [{"label": "CLOSE", "style": &"GhostButton"}]
	UIManager.show_dialog("CLINIC RECORDS", "\n".join(lines), close)


func _on_black_market_pressed() -> void:
	if ReputationManager.is_black_market_unlocked():
		UIManager.show_toast("The fixer will contact you soon...", &"info")
	else:
		UIManager.show_toast("Locked. Earn %d street rep." % GameConfig.BLACK_MARKET_REPUTATION, &"warn")
