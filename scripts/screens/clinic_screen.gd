extends BaseScreen
## PC hub: the clinic room (1200x672, 3x pixel art) in the centre, the
## customer at the door on the left with everything needed to decide at a
## glance, live clinic status underneath, the workstation status bar on top
## and section navigation on the left. Double-click the room to zoom.

var _objective: Label
var _objective_timer: float = 0.0
var _view: ClinicView
var _card: PanelContainer
var _portrait: PixelPortrait
var _name: Label
var _faction_tag: Label
var _occupation: Label
var _request_box: HBoxContainer
var _offer: Label
var _risk: Label
var _load_meter: NeuralLoadMeter
var _see_button: Button
var _waiting: Label
var _info_box: VBoxContainer
var _rumor: Label
var _stock_label: Label
var _status_box: VBoxContainer
var _factions_box: VBoxContainer
var _nav: SideNav
var _waiting_dots: float = 0.0
var _panels: Array[Control] = []
var _loc: Label
var _close_button: Button
var _agenda: Label


func on_enter(_params: Dictionary) -> void:
	_build()
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.inventory_changed.connect(_refresh_status)
	EventBus.resources_changed.connect(_refresh_status)
	EventBus.day_started.connect(func(_d: int) -> void: _refresh_status())
	EventBus.rumor_unlocked.connect(func(_id: StringName) -> void: _refresh_rumor())
	StoryManager.update_rumors()
	_refresh_status()
	_refresh_rumor()
	if CustomerManager.has_customer():
		_show_customer(CustomerManager.current_customer, false)
	else:
		_show_waiting()
	StoryManager.talk_queued.connect(func(_id: StringName) -> void: _show_talk.call_deferred())
	# Something scheduled for this hour (the supplier, a midnight deal...).
	EventBus.event_queued.connect(func(_id: StringName) -> void:
		if is_inside_tree():
			_show_event.call_deferred())
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: _refresh_status())
	if EventManager.has_pending():
		_show_event.call_deferred()
	elif StoryManager.has_talk():
		_show_talk.call_deferred()
	elif not CustomerManager.has_customer():
		CustomerManager.request_next_customer()


func get_panels() -> Array:
	return _panels


func _build() -> void:
	var content := UIKit.workstation(self, &"clinic")
	_nav = find_child("SideNav", true, false) as SideNav
	# NEXT objective strip
	var strip := UIKit.hbox(16)
	content.add_child(strip)
	_objective = UIKit.label("", &"MonoLabel", false, Palette.ACCENT)
	_objective.name = "Objective"
	_objective.clip_text = true
	UIKit.expand(_objective)
	strip.add_child(_objective)
	strip.add_child(UIKit.label("[%s] customer  [%s] inventory  [%s] journal  [%s] quick save" % [Controls.key_name("customer_info"), Controls.key_name("inventory"), Controls.key_name("journal"), Controls.key_name("quicksave")], &"SubHeaderLabel"))
	_refresh_objective()
	var row := UIKit.hbox(16)
	UIKit.expand(row, true, true)
	content.add_child(row)
	# --- Left: who's at the door
	var left := UIKit.vbox(14)
	left.custom_minimum_size.x = 420
	row.add_child(left)
	_card = UIKit.panel(&"AccentPanel")
	_card.name = "CustomerCard"
	UIKit.expand(_card, true, true)
	left.add_child(_card)
	_panels.append(_card)
	var cv := UIKit.vbox(12)
	_card.add_child(cv)
	cv.add_child(UIKit.label("AT THE DOOR", &"SubHeaderLabel"))
	_info_box = UIKit.vbox(10)
	cv.add_child(_info_box)
	var who := UIKit.hbox(14)
	_info_box.add_child(who)
	_portrait = PixelPortrait.new()
	_portrait.framing = PixelPortrait.Framing.FACE
	who.add_child(_portrait)
	var text := UIKit.vbox(4)
	UIKit.expand(text)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(text)
	_name = UIKit.label("", &"HeaderLabel", true)
	text.add_child(_name)
	_faction_tag = UIKit.label("", &"SubHeaderLabel", true)
	text.add_child(_faction_tag)
	_occupation = UIKit.label("", &"DimLabel", true)
	text.add_child(_occupation)
	_request_box = UIKit.hbox(12)
	_info_box.add_child(_request_box)
	_offer = UIKit.label("", &"MonoLabel", false, Palette.WARN)
	_info_box.add_child(_offer)
	_risk = UIKit.label("", &"DimLabel", true)
	_info_box.add_child(_risk)
	_load_meter = NeuralLoadMeter.new()
	_info_box.add_child(_load_meter)
	_waiting = UIKit.label("Waiting for customers...", &"DimLabel")
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.custom_minimum_size.y = 120
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cv.add_child(_waiting)
	cv.add_child(UIKit.expand(Control.new(), false, true))
	_see_button = UIKit.button("SEE CUSTOMER  [%s]" % Controls.key_name("customer_info"), &"AccentButton", GameManager.open_customer, "SeeButton", 56)
	_see_button.set_meta(&"default", true)
	cv.add_child(_see_button)
	# --- Centre: the room + status cards
	var centre := UIKit.vbox(14)
	UIKit.expand(centre, true, true)
	row.add_child(centre)
	var frame := UIKit.panel(&"HudPanel")
	frame.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(frame)
	_view = ClinicView.new()
	_view.name = "ClinicView"
	_view.custom_minimum_size = Vector2(1100, 640)
	_view.tooltip_text = "Click the customer or a lit prop · wheel / double-click to zoom · drag to look around"
	_view._base_tooltip = _view.tooltip_text
	_view.hotspot_clicked.connect(GameManager.navigate)
	frame.add_child(_view)
	_view.customer_tapped.connect(GameManager.open_customer)
	var overlay := UIKit.vbox(2)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	overlay.offset_left = 12
	overlay.offset_right = -12
	overlay.offset_top = 10
	_view.add_child(overlay)
	var loc := UIKit.label("", &"SubHeaderLabel", false, Palette.TEXT)
	loc.name = "ClockLabel"
	_loc = loc
	loc.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	loc.add_theme_constant_override(&"outline_size", 4)
	overlay.add_child(loc)
	_agenda = UIKit.label("", &"DimLabel", false, Palette.ACCENT, 14)
	_agenda.name = "AgendaLabel"
	_agenda.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_agenda.add_theme_constant_override(&"outline_size", 4)
	overlay.add_child(_agenda)
	var cards := UIKit.hbox(14)
	UIKit.expand(cards, true, true)
	centre.add_child(cards)
	_status_box = UIKit.section(cards, "CLINIC STATUS")
	(_status_box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(_status_box.get_parent())
	_stock_label = UIKit.label("", &"MonoLabel")
	_status_box.add_child(_stock_label)
	_close_button = UIKit.button("CLOSE FOR THE NIGHT", &"GhostButton", _close_day, "CloseDayButton", 40)
	_close_button.tooltip_text = "End the business day: pay rent, running costs and salaries, see the ledger."
	_status_box.add_child(_close_button)
	var rumors := UIKit.section(cards, "STREET RUMOURS", &"CardPanel", "[%s] journal" % Controls.key_name("journal"))
	(rumors.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(rumors.get_parent() as Control).size_flags_stretch_ratio = 1.4
	_rumor = UIKit.label("", &"DimLabel", true, Palette.ACCENT)
	rumors.add_child(_rumor)
	_factions_box = UIKit.section(cards, "FACTIONS")
	(_factions_box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(_factions_box.get_parent())


func _process(delta: float) -> void:
	_objective_timer -= delta
	if _objective_timer <= 0.0:
		_objective_timer = 0.5
		_refresh_objective()
	if _waiting and _waiting.visible:
		_waiting_dots += delta * 2.0
		_waiting.text = (("It's %s. Door's locked. Close up for the night." % TimeManager.clock_text()) if BusinessManager.is_day_full() else "Waiting for customers") + ".".repeat(int(_waiting_dots) % 4)


func _show_event() -> void:
	if not EventManager.has_pending() or UIManager.has_modal():
		return
	var panel := EventPanel.new()
	panel.name = "EventPanel"
	panel.event_id = EventManager.pending_event
	AudioManager.play_sfx(&"event", 0.0)
	UIManager.show_modal(panel)
	panel.closed.connect(_after_event)


## Someone from the story wants a word (conversation modal).
func _show_talk() -> void:
	if not is_inside_tree() or not StoryManager.has_talk() or UIManager.has_modal() or EventManager.has_pending():
		return
	var panel := DialoguePanel.new()
	panel.name = "DialoguePanel"
	panel.dialogue_id = StoryManager.pop_talk()
	AudioManager.play_sfx(&"customer", 0.0)
	UIManager.show_modal(panel)
	panel.closed.connect(_after_event)


func _after_event() -> void:
	if _nav:
		_nav.refresh()
	if StoryManager.ending != &"" and not StoryManager.has_flag(&"ending_shown") and is_inside_tree():
		StoryManager.set_flag(&"ending_shown")
		var e := StoryManager.ending_text()
		var ok: Array[Dictionary] = [{"label": "KEEP THE CLINIC OPEN", "style": &"AccentButton", "name": "EndingClose"}]
		UIManager.show_dialog.call_deferred("ENDING · %s" % str(e.get("title", "")), str(e.get("text", "")), ok)
		return
	_refresh_status()
	if not is_inside_tree():
		return
	if StoryManager.has_talk():
		_show_talk.call_deferred()
		return
	if CustomerManager.has_customer():
		_show_customer(CustomerManager.current_customer, false)
	else:
		CustomerManager.request_next_customer()


func _on_customer_arrived(customer: CustomerData) -> void:
	_objective_timer = 0.0
	_refresh_status()
	AudioManager.play_sfx(&"customer")
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
	_occupation.text = "%d yrs · %s" % [customer.age, customer.occupation.capitalize()]
	UIKit.clear(_request_box)
	if item:
		_request_box.add_child(CyberwareIcon.make(item))
		var rv := UIKit.vbox(2)
		UIKit.expand(rv)
		rv.add_child(UIKit.label("WANTS", &"SubHeaderLabel"))
		rv.add_child(UIKit.label(item.display_name, &"", true))
		rv.add_child(UIKit.label("T%d %s · difficulty %d/5" % [item.tier, item.category.to_upper(), item.install_difficulty], &"DimLabel", true))
		_request_box.add_child(rv)
	var expected := 0
	if surgery and item:
		expected = int(round((surgery.base_pay + item.price * GameConfig.IMPLANT_PRICE_MARKUP) * customer.pay_multiplier))
	_offer.text = "OFFERS %s" % EconomyManager.format_money(expected)
	var risk_word := "LOW" if customer.complication_risk < 0.95 else ("HIGH" if customer.complication_risk > 1.1 else "MEDIUM")
	_risk.text = "Risk: %s · patience %d · %s" % [risk_word, customer.patience, "known conditions: %d" % customer.revealed_conditions.size()]
	_load_meter.set_load(NeuralLoad.compute(customer), NeuralLoad.projected(customer, ImplantInstance.create(item.id)) if item else NeuralLoad.compute(customer))
	_waiting.visible = false
	_info_box.visible = true
	_see_button.visible = true
	if animate:
		_card.modulate.a = 0.0
		create_tween().tween_property(_card, "modulate:a", 1.0, 0.25)


func _close_day() -> void:
	GameManager.close_for_the_night()
	_refresh_status()


func _show_waiting() -> void:
	_view.hide_customer()
	_waiting.visible = true
	_info_box.visible = false
	_see_button.visible = false


func _refresh_status() -> void:
	if _stock_label == null:
		return
	_stock_label.text = "CHROME IN STOCK: %d" % InventoryManager.get_instances().size()
	for c in _status_box.get_children():
		if c != _stock_label and c != _close_button and c.get_index() > 2:
			c.queue_free()
	var full := BusinessManager.is_day_full()
	_close_button.disabled = CustomerManager.has_customer() or SurgeryManager.is_active
	_close_button.theme_type_variation = &"AccentButton" if full else &"GhostButton"
	_status_box.add_child(UIKit.label("DAY %d · jobs %d/%d · tonight's bill %d%s" % [BusinessManager.day, BusinessManager.jobs_today, BusinessManager.capacity(),
		BusinessManager.projected_total(), ("  · DEBT %d" % BusinessManager.debt) if BusinessManager.debt > 0 else ""], &"DimLabel", true, Palette.WARN if BusinessManager.debt > 0 else null))
	if _loc:
		_loc.text = "%s · %s · %s" % [ClinicManager.get_tier_name().to_upper(), WorldManager.district_name().to_upper(), TimeManager.stamp()]
	_status_box.add_child(UIKit.label("Supplies %d / %d · Parts %d · Tokens %d" % [InventoryManager.supplies, ClinicManager.get_supplies_capacity(), InventoryManager.parts, InventoryManager.tokens], &"DimLabel", true))
	_status_box.add_child(UIKit.label("Heat %d%s" % [roundi(FactionManager.heat), "  · inspections likely" if FactionManager.heat >= 35.0 else ""], &"DimLabel", true, Palette.DANGER if FactionManager.heat >= 35.0 else null))
	# Today's agenda: what's due and when the door locks.
	var agenda: Array[String] = []
	for a in TimeManager.upcoming():
		agenda.append("%s  %s" % [TimeManager.clock_text(int(a["minute"])), str(a["label"])])
	var due := PeopleManager.due_people().size()
	if due > 0:
		agenda.append("%d patient%s due back today" % [due, "s" if due > 1 else ""])
	agenda.append("%s  doors lock (%s left)" % [TimeManager.clock_text(TimeManager.close_minute()), TimeManager.duration_text(TimeManager.minutes_left())])
	if _agenda:
		_agenda.text = "\n".join(agenda)
	UIKit.clear_after(_factions_box, 1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	_factions_box.add_child(grid)
	for id: StringName in FactionManager.order:
		var line := UIKit.hbox(6)
		UIKit.expand(line)
		var n := UIKit.label(str(FactionManager.factions[id].get("short", id)), &"DimLabel")
		n.tooltip_text = FactionManager.get_name_of(id)
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		UIKit.expand(n)
		line.add_child(n)
		var rep := FactionManager.get_rep(id)
		line.add_child(UIKit.label("%+d" % rep, &"MonoLabel", false, Palette.OK if rep > 5 else (Palette.DANGER if rep < -5 else Palette.TEXT_DIM)))
		grid.add_child(line)


func _refresh_rumor() -> void:
	var r := StoryManager.get_latest_rumor()
	_rumor.text = r if r != "" else "Quiet night. Nothing on the wire."


func _refresh_objective() -> void:
	if _objective == null:
		return
	var o := GameManager.get_next_objective()
	_objective.text = "NEXT > " + str(o["text"]).to_upper()
	_objective.add_theme_color_override(&"font_color", Palette.WARN if o["kind"] == &"warn" else Palette.ACCENT)
