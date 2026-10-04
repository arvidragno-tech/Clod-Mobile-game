extends BaseScreen
## The player's hub: who's waiting, the clinic itself, rumors, incidents and
## navigation to the shop, skills, clinic upgrades, dossier and black market.

const PlayerHudScene := preload("res://ui/components/player_hud.tscn")

var _objective: Label
var _objective_timer: float = 0.0
var _view: ClinicView
var _card: PanelContainer
var _portrait: PixelPortrait
var _name: Label
var _request: Label
var _offer: Label
var _faction_tag: Label
var _see_button: Button
var _waiting: Label
var _info_box: HBoxContainer
var _rumor: Label
var _stock_label: Label
var _nav: NavBar
var _waiting_dots: float = 0.0
var _rumor_scroll: float = 0.0


func on_enter(_params: Dictionary) -> void:
	_build()
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.inventory_changed.connect(_refresh_stock)
	EventBus.rumor_unlocked.connect(func(_id: StringName) -> void: _refresh_rumor())
	StoryManager.update_rumors()
	_refresh_stock()
	_refresh_rumor()
	_nav.set_locked(&"blackmarket", not BlackMarketManager.is_unlocked())
	_nav.set_badge(&"skills", SkillManager.points > 0)
	_nav.set_badge(&"upgrades", ClinicManager.get_upgrade_block_reason() == "")
	if CustomerManager.has_customer():
		_show_customer(CustomerManager.current_customer, false)
	else:
		_show_waiting()
	if EventManager.has_pending():
		_show_event.call_deferred()
	elif not CustomerManager.has_customer():
		CustomerManager.request_next_customer()


func _build() -> void:
	var m := UIKit.full_rect(UIKit.margin(10, 8, 10, 10))
	add_child(m)
	var col := UIKit.vbox(6)
	m.add_child(col)
	var top := UIKit.hbox(6)
	col.add_child(top)
	var hud := PlayerHudScene.instantiate()
	UIKit.expand(hud)
	top.add_child(hud)
	var menu := UIKit.button("", &"GhostButton", _open_pause_menu, "MenuButton")
	menu.icon = PixelArt.scaled("res://assets/sprites/ui/icons/menu.png")
	menu.custom_minimum_size = Vector2(GameConfig.MIN_TOUCH, GameConfig.MIN_TOUCH)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(menu)
	# Clinic view
	var frame := UIKit.panel(&"HudPanel")
	UIKit.expand(frame, true, true)
	col.add_child(frame)
	_view = ClinicView.new()
	_view.name = "ClinicView"
	frame.add_child(_view)
	_view.customer_tapped.connect(GameManager.open_customer)
	var overlay := UIKit.vbox(2)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	overlay.offset_left = 6
	overlay.offset_right = -6
	overlay.offset_top = 6
	_view.add_child(overlay)
	var loc := UIKit.label("%s · SUBLEVEL 3" % ClinicManager.get_tier_name().to_upper(), &"SubHeaderLabel", false, Palette.TEXT)
	loc.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	loc.add_theme_constant_override(&"outline_size", 4)
	overlay.add_child(loc)
	_rumor = UIKit.label("", &"MonoLabel", true, Palette.ACCENT, 17)
	_rumor.clip_text = true
	_rumor.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_rumor.add_theme_constant_override(&"outline_size", 4)
	overlay.add_child(_rumor)
	_stock_label = UIKit.label("", &"MonoLabel", true, Palette.TEXT_DIM, 17)
	_stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stock_label.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_stock_label.add_theme_constant_override(&"outline_size", 4)
	_stock_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_stock_label.offset_top = -26
	_stock_label.offset_left = 6
	_stock_label.offset_right = -6
	_view.add_child(_stock_label)
	# "NEXT" objective: always answers "what should I do now?"
	_objective = UIKit.label("", &"MonoLabel", false, Palette.ACCENT, 18)
	_objective.name = "Objective"
	_objective.clip_text = true
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_objective)
	_refresh_objective()
	# Customer card
	_card = UIKit.panel(&"AccentPanel")
	_card.name = "CustomerCard"
	col.add_child(_card)
	var cv := UIKit.vbox(8)
	_card.add_child(cv)
	_info_box = UIKit.hbox(10)
	cv.add_child(_info_box)
	_portrait = PixelPortrait.new()
	_portrait.crop = Rect2i(14, 6, 36, 36)
	_info_box.add_child(_portrait)
	var text := UIKit.vbox(1)
	UIKit.expand(text)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_info_box.add_child(text)
	_name = UIKit.label("", &"HeaderLabel", true)
	_name.clip_text = true
	text.add_child(_name)
	_faction_tag = UIKit.label("", &"SubHeaderLabel")
	text.add_child(_faction_tag)
	_request = UIKit.label("", &"", false, null, 15)
	_request.clip_text = true
	text.add_child(_request)
	_offer = UIKit.label("", &"MonoLabel", true, Palette.WARN, 20)
	text.add_child(_offer)
	_waiting = UIKit.label("Waiting for customers...", &"DimLabel")
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.custom_minimum_size.y = 72
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cv.add_child(_waiting)
	_see_button = UIKit.button("SEE CUSTOMER", &"AccentButton", GameManager.open_customer, "SeeButton", 54)
	cv.add_child(_see_button)
	_nav = NavBar.new()
	_nav.name = "NavBar"
	col.add_child(_nav)
	_nav.nav_pressed.connect(_on_nav)


func _process(delta: float) -> void:
	_objective_timer -= delta
	if _objective_timer <= 0.0:
		_objective_timer = 0.5
		_refresh_objective()
	if _waiting and _waiting.visible:
		_waiting_dots += delta * 2.0
		_waiting.text = "Waiting for customers" + ".".repeat(int(_waiting_dots) % 4)


func _on_nav(id: StringName) -> void:
	match id:
		&"supply":
			GameManager.open_screen(UIManager.SCREEN_SHOP)
		&"skills":
			GameManager.open_screen(UIManager.SCREEN_SKILLS)
		&"upgrades":
			GameManager.open_screen(UIManager.SCREEN_UPGRADES)
		&"dossier":
			GameManager.open_screen(UIManager.SCREEN_DOSSIER)
		&"blackmarket":
			if BlackMarketManager.is_unlocked():
				GameManager.open_screen(UIManager.SCREEN_BLACK_MARKET)
			else:
				UIManager.show_toast("No contact yet. Build street rep (%d) or find a fixer." % GameConfig.BLACK_MARKET_REPUTATION, &"warn")


func _show_event() -> void:
	if not EventManager.has_pending() or UIManager.has_modal():
		return
	var panel := EventPanel.new()
	panel.name = "EventPanel"
	panel.event_id = EventManager.pending_event
	AudioManager.play_sfx(&"event", 0.0)
	UIManager.show_modal(panel)
	panel.closed.connect(_after_event)


func _after_event() -> void:
	_nav.set_locked(&"blackmarket", not BlackMarketManager.is_unlocked())
	if CustomerManager.has_customer():
		_show_customer(CustomerManager.current_customer, false)
	else:
		CustomerManager.request_next_customer()


func _on_customer_arrived(customer: CustomerData) -> void:
	_objective_timer = 0.0
	AudioManager.play_sfx(&"customer")
	UIManager.haptic(&"ui")
	UIManager.show_toast("%s is at the door" % customer.display_name, &"danger" if customer.is_emergency else &"info")
	_show_customer(customer, true)


func _show_customer(customer: CustomerData, animate: bool) -> void:
	_view.show_customer(customer, animate)
	var item := CyberwareManager.get_cyberware(customer.requested_cyberware_id)
	var surgery := SurgeryManager.get_surgery(item.install_surgery_id) if item else null
	_portrait.set_appearance(customer.appearance, FactionManager.get_color(customer.faction_id))
	_name.text = customer.get_display_title()
	_faction_tag.text = "%s%s" % ["EMERGENCY · " if customer.is_emergency else "", FactionManager.get_name_of(customer.faction_id).to_upper()]
	_faction_tag.add_theme_color_override(&"font_color", Palette.DANGER if customer.is_emergency else FactionManager.get_color(customer.faction_id))
	_request.text = "Wants: %s" % (item.display_name if item else "?")
	var expected := 0
	if surgery and item:
		expected = int(round((surgery.base_pay + item.price * GameConfig.IMPLANT_PRICE_MARKUP) * customer.pay_multiplier))
	_offer.text = "Offers %s" % EconomyManager.format_money(expected)
	_waiting.visible = false
	_info_box.visible = true
	_see_button.visible = true
	if animate:
		_card.modulate.a = 0.0
		create_tween().tween_property(_card, "modulate:a", 1.0, 0.25)


func _show_waiting() -> void:
	_view.hide_customer()
	_waiting.visible = true
	_info_box.visible = false
	_see_button.visible = false


func _refresh_stock() -> void:
	var n := InventoryManager.get_instances().size()
	_stock_label.text = "CHROME IN STOCK: %d" % n


func _refresh_rumor() -> void:
	var r := StoryManager.get_latest_rumor()
	_rumor.text = ("RUMOR: " + r) if r != "" else ""
	_rumor.tooltip_text = r


## Pause menu: settings, a short how-to-play recap, or save & quit.
func _open_pause_menu() -> void:
	var buttons: Array[Dictionary] = [
		{"label": "RESUME", "style": &"AccentButton", "name": "PauseResume"},
		{"label": "SETTINGS", "style": &"", "name": "PauseSettings", "callback": func() -> void:
			UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.SCREEN_CLINIC})},
		{"label": "HOW TO PLAY", "style": &"", "name": "PauseHelp", "callback": _show_help},
		{"label": "SAVE & QUIT", "style": &"GhostButton", "name": "PauseQuit", "callback": GameManager.quit_to_menu},
	]
	UIManager.show_dialog("CLINIC PAUSED", "Progress is saved automatically after every job, purchase and upgrade.", buttons)


func _show_help() -> void:
	var buttons: Array[Dictionary] = [{"label": "GOT IT", "style": &"AccentButton", "name": "HelpClose"}]
	UIManager.show_dialog("HOW TO PLAY", TutorialManager.HELP_TEXT, buttons)


func _refresh_objective() -> void:
	if _objective == null:
		return
	var o := GameManager.get_next_objective()
	_objective.text = "NEXT > " + str(o["text"]).to_upper()
	_objective.add_theme_color_override(&"font_color", Palette.WARN if o["kind"] == &"warn" else Palette.ACCENT)
