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
var _verdict_box: VBoxContainer
var _rumor: Label
var _stock_label: Label
var _status_box: VBoxContainer
var _factions_box: VBoxContainer
var _matters_box: VBoxContainer
var _changes_button: Button
var _nav: SideNav
var _waiting_dots: float = 0.0
var _panels: Array[Control] = []
var _loc: Label
var _close_button: Button
var _agenda: Label
var _security_button: Button
var _close_row: HBoxContainer


func on_enter(_params: Dictionary) -> void:
	# The clinic screen is the clinic: if you were out, you come back (the
	# trip home takes its time).
	if LocationManager.is_away():
		if not bool(LocationManager.return_to_clinic().get("ok", false)):
			LocationManager.player_location = LocationManager.CLINIC
	_build()
	if EventManager.operations > 0:
		(func() -> void: Hints.first("priorities")).call_deferred()
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
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective.mouse_filter = Control.MOUSE_FILTER_STOP
	_objective.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_objective.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Nav.open(Guidance.top().get("link", {})))
	UIKit.expand(_objective)
	strip.add_child(_objective)
	_changes_button = UIKit.button("", &"GhostButton", ChangesPanel.open, "ChangesButton", 36)
	_changes_button.tooltip_text = "What changed while you were busy (money, standing, heat, supplies, staff, people, places)."
	strip.add_child(_changes_button)
	strip.add_child(UIKit.label("[%s] customer  [%s] inventory  [%s] journal  [%s] map" % [Controls.key_name("customer_info"), Controls.key_name("inventory"), Controls.key_name("journal"), Controls.key_name("map")], &"SubHeaderLabel"))
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
	cv.add_child(UIKit.section_head("AT THE DOOR", "", "loop"))
	# The details scroll if they're long; SEE CUSTOMER always stays visible.
	var isc := UIKit.scroll()
	isc.name = "DoorScroll"
	UIKit.expand(isc, true, true)
	cv.add_child(isc)
	_info_box = UIKit.vbox(10)
	UIKit.expand(_info_box, true, false)
	isc.add_child(_info_box)
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
	_verdict_box = UIKit.vbox(4)
	_verdict_box.name = "DoorVerdict"
	_info_box.add_child(_verdict_box)
	_waiting = UIKit.label("Nobody at the door yet.\n\nWhile you wait: restock in SUPPLY, spend skill points, check the JOURNAL, or go out into the city (CITY MAP, %s)." % Controls.key_name("map"), &"DimLabel", true)
	_waiting.name = "WaitingLabel"
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.custom_minimum_size.y = 120
	UIKit.expand(_waiting, true, true)
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cv.add_child(_waiting)
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
	_view.custom_minimum_size = Vector2(1100, 580)
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
	UIKit.expand(cards, true, false)
	cards.size_flags_vertical = Control.SIZE_SHRINK_END
	centre.add_child(cards)
	_status_box = UIKit.section(cards, "TODAY", &"CardPanel", "", "time")
	(_status_box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(_status_box.get_parent())
	_stock_label = UIKit.label("", &"MonoLabel")
	_stock_label.visible = false
	_status_box.add_child(_stock_label)
	_close_button = UIKit.button("CLOSE FOR THE NIGHT", &"GhostButton", _close_day, "CloseDayButton", 40)
	_close_button.tooltip_text = "End the business day: pay rent, running costs and salaries, see the ledger."
	UIKit.expand(_close_button)
	_close_row = UIKit.hbox(8)
	_status_box.add_child(_close_row)
	_close_row.add_child(_close_button)
	_security_button = UIKit.button("SECURITY", &"GhostButton", _open_security, "SecurityButton", 40)
	_security_button.tooltip_text = "Heat level, break-ins and investigations."
	_close_row.add_child(_security_button)
	_matters_box = UIKit.section(cards, "WHAT MATTERS NOW", &"CardPanel", "click to go there")
	_matters_box.add_theme_constant_override(&"separation", 4)
	_matters_box.name = "WhatMatters"
	(_matters_box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(_matters_box.get_parent() as Control).size_flags_stretch_ratio = 1.4
	_panels.append(_matters_box.get_parent())
	_factions_box = UIKit.section(cards, "CLINIC STATUS", &"CardPanel", "", "")
	_factions_box.name = "ClinicStatus"
	(_factions_box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panels.append(_factions_box.get_parent())


func _process(delta: float) -> void:
	_objective_timer -= delta
	if _objective_timer <= 0.0:
		_objective_timer = 0.5
		_refresh_objective()
	if _waiting and _waiting.visible:
		_waiting_dots += delta * 2.0
		if BusinessManager.is_day_full():
			_waiting.text = "It's %s. The day's work is done.\n\nPress CLOSE FOR THE NIGHT (below the room) to pay the bills and start tomorrow." % TimeManager.clock_text()
		else:
			_waiting.text = "Waiting for the next customer" + ".".repeat(int(_waiting_dots) % 4) + "\n\nWhile you wait: restock in SUPPLY, spend skill points, read the JOURNAL, or go out into the city (CITY MAP, %s)." % Controls.key_name("map")


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
	# Same numbers as the customer file (one source of truth).
	var expected := CustomerGenerator.estimate_fee(customer) if surgery and item else 0
	_offer.text = "PAYS ≈ %s" % EconomyManager.format_money(expected)
	_risk.text = "Patience %d · known conditions %d" % [customer.patience, customer.revealed_conditions.size()]
	UIKit.clear(_verdict_box)
	JobVerdict.build(_verdict_box, customer, true)
	_load_meter.set_load(NeuralLoad.compute(customer), NeuralLoad.projected(customer, ImplantInstance.create(item.id)) if item else NeuralLoad.compute(customer))
	_waiting.visible = false
	_info_box.visible = true
	(_info_box.get_parent() as Control).visible = true
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
	(_info_box.get_parent() as Control).visible = false
	_see_button.visible = false


func _refresh_status() -> void:
	if _stock_label == null:
		return
	_stock_label.text = "CHROME IN STOCK: %d" % InventoryManager.get_instances().size()
	for c in _status_box.get_children():
		if c != _stock_label and c != _close_row and c.get_index() > 2:
			c.queue_free()
	var full := BusinessManager.is_day_full()
	_close_button.disabled = CustomerManager.has_customer() or SurgeryManager.is_active
	_close_button.theme_type_variation = &"AccentButton" if full else &"GhostButton"
	if _loc:
		_loc.text = "%s · %s · %s" % [ClinicManager.get_tier_name().to_upper(), WorldManager.district_name().to_upper(), TimeManager.stamp()]
	# Four meters: how much night is left, the day's jobs, supplies, heat.
	var span := float(TimeManager.close_minute() - TimeManager.open_minute())
	_meter_row("NIGHT LEFT", 1.0 - clampf(float(TimeManager.minute - TimeManager.open_minute()) / span, 0.0, 1.0),
		Palette.WARN if TimeManager.minutes_left() < 120 else Palette.ACCENT, "%s · doors lock 04:00" % TimeManager.duration_text(TimeManager.minutes_left()), "time")
	var cap := maxi(1, BusinessManager.capacity())
	_meter_row("JOBS", float(BusinessManager.jobs_today) / cap, Palette.OK if full else Palette.ACCENT, "%d / %d · bill %s%s" % [BusinessManager.jobs_today, cap,
		EconomyManager.format_money(BusinessManager.projected_total()), (" · DEBT %d" % BusinessManager.debt) if BusinessManager.debt > 0 else ""], "jobs")
	var scap := maxi(1, ClinicManager.get_supplies_capacity())
	_meter_row("SUPPLIES", float(InventoryManager.supplies) / scap, Palette.WARN if InventoryManager.supplies < 2 else Palette.OK, "%d / %d · %d implants" % [InventoryManager.supplies, scap, InventoryManager.get_instances().size()], "supplies")
	_meter_row("HEAT", FactionManager.heat / 100.0, Palette.DANGER if FactionManager.heat >= 35.0 else Palette.TEXT_DIM, "%d · %s" % [roundi(FactionManager.heat), SecurityManager.level_label()], "heat")
	var open := SecurityManager.open_cases().size()
	_security_button.text = "SECURITY" if open == 0 else "%d OPEN CASE%s" % [open, "S" if open > 1 else ""]
	_security_button.theme_type_variation = &"DangerButton" if open > 0 else &"GhostButton"
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
	_refresh_status_card()
	_refresh_matters(true)


## CLINIC STATUS: six one-word summaries (✓ ! ✕) and the one thing to do.
func _refresh_status_card() -> void:
	UIKit.clear_after(_factions_box, 1)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override(&"v_separation", 0)
	_factions_box.add_child(grid)
	for r: Dictionary in ClinicStatus.rows():
		var line := UIKit.hbox(6)
		line.name = "Status_%s" % r["key"]
		UIKit.expand(line)
		line.add_child(UIKit.label(ClinicStatus.mark(r["level"]), &"MonoLabel", false, ClinicStatus.color(r["level"]), 17))
		var cap := UIKit.caption(str(r["label"]))
		cap.add_theme_font_size_override(&"font_size", 15)
		cap.custom_minimum_size.x = 160
		line.add_child(cap)
		var v := UIKit.label(str(r["state"]), &"", false, ClinicStatus.color(r["level"]), 15)
		v.tooltip_text = "%s: %s\n%s" % [r["label"], r["state"], r["detail"]]
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		v.clip_text = true
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UIKit.expand(v)
		line.add_child(v)
		grid.add_child(line)
	var top := ClinicStatus.most_important()
	var tip := UIKit.label(("▲ " if top["level"] != ClinicStatus.GOOD else "✓ ") + str(top["text"]), &"DimLabel", true, ClinicStatus.color(top["level"]) if top["level"] != ClinicStatus.GOOD else Palette.TEXT_DIM, 14)
	tip.name = "StatusAdvice"
	tip.max_lines_visible = 2
	_factions_box.add_child(tip)


var _matters_sig: String = ""


## WHAT MATTERS NOW: the prioritised, clickable list (Guidance).
func _refresh_matters(force: bool = false) -> void:
	if _matters_box == null:
		return
	var its := Guidance.items(4)
	var sig := ""
	for it in its:
		sig += str(it["text"]) + "|"
	if _changes_button:
		var n := ChangeLog.unread_count()
		_changes_button.text = ("◷ CHANGES %d  [%s]" % [n, Controls.key_name("changes")]) if n > 0 else ("◷ CHANGES  [%s]" % Controls.key_name("changes"))
		_changes_button.theme_type_variation = &"Button" if n > 0 else &"GhostButton"
	if ChangeLog.unread_count() >= 4 and EventManager.operations > 0:
		Hints.first("changes")
	if sig == _matters_sig and not force:
		return
	_matters_sig = sig
	UIKit.clear_after(_matters_box, 1)
	if its.is_empty():
		_matters_box.add_child(UIKit.label("Nothing urgent.", &"DimLabel"))
		return
	for i in its.size():
		var it: Dictionary = its[i]
		var lv: StringName = it["level"]
		var txt := "%s %s  %s" % [Guidance.MARKS[lv], str(it["icon"]), str(it["text"])]
		var link: Dictionary = it["link"]
		var b := UIKit.button(txt, &"GhostButton", func() -> void: Nav.open(link), "Matter_%d" % i, 32)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = str(it["text"])
		b.add_theme_color_override(&"font_color", Guidance.color(lv))
		b.disabled = not Nav.can_open(link)
		_matters_box.add_child(b)


## One labelled meter in the TODAY card (hover/click the caption to learn more).
func _meter_row(caption: String, ratio: float, color: Color, text: String, term: String) -> void:
	var row := UIKit.hbox(8)
	row.name = "Today_%s" % caption.replace(" ", "_")
	var cap := UIKit.label(caption, &"SubHeaderLabel")
	cap.custom_minimum_size.x = 104
	cap.mouse_filter = Control.MOUSE_FILTER_STOP
	cap.mouse_default_cursor_shape = Control.CURSOR_HELP
	cap.tooltip_text = Glossary.short(term)
	cap.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Glossary.show(term))
	row.add_child(cap)
	var m := UIKit.meter(clampf(ratio, 0.0, 1.0), color, 10)
	m.custom_minimum_size.x = 120
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(m)
	var v := UIKit.label(text, &"DimLabel", false, null, 15)
	v.clip_text = true
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIKit.expand(v)
	row.add_child(v)
	_status_box.add_child(row)


func _refresh_rumor() -> void:
	pass  # rumours live in the journal (DISCOVERIES) and on the wire ticker


func _refresh_objective() -> void:
	if _objective == null:
		return
	var o := GameManager.get_next_objective()
	_objective.text = "NEXT > " + str(o["text"]).to_upper()
	_objective.add_theme_color_override(&"font_color", Palette.WARN if o["kind"] == &"warn" else Palette.ACCENT)
	_refresh_matters()


func _open_security() -> void:
	var panel := SecurityPanel.new()
	panel.name = "SecurityPanel"
	UIManager.show_modal(panel)
	panel.closed.connect(_refresh_status)
