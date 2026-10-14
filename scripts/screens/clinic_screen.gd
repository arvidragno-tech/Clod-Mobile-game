extends BaseScreen
## PC hub: the clinic room (1200x672, 3x pixel art) in the centre, the
## customer at the door on the left with everything needed to decide at a
## glance, live clinic status underneath, the workstation status bar on top
## and section navigation on the left. Double-click the room to zoom.

var _objective: Label
var _objective_why: Label
var _waiting_tail: String = ""
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
var _changes_button: Button
var _nav: SideNav
var _waiting_dots: float = 0.0
var _panels: Array[Control] = []
var _loc: Label
var _close_button: Button
var _security_button: Button
var _close_row: HBoxContainer
var _doors_row: HFlowContainer
var _status_line: Button
var _status_link: Dictionary = {}


func on_enter(_params: Dictionary) -> void:
	# The clinic screen is the clinic: if you were out, you come back (the
	# trip home takes its time).
	if LocationManager.is_away():
		if not bool(LocationManager.return_to_clinic().get("ok", false)):
			LocationManager.player_location = LocationManager.CLINIC
	_build()
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.inventory_changed.connect(_refresh_status)
	EventBus.resources_changed.connect(_refresh_status)
	EventBus.day_started.connect(func(_d: int) -> void: _refresh_status())
	BusinessManager.doors_changed.connect(func(_open: bool) -> void:
		_refresh_doors()
		_refresh_matters(true))
	EventBus.rumor_unlocked.connect(func(_id: StringName) -> void: _refresh_rumor())
	StoryManager.update_rumors()
	_refresh_status()
	_refresh_rumor()
	if CustomerManager.has_customer():
		_show_customer(CustomerManager.current_customer, false)
	else:
		_show_waiting()
	StoryManager.talk_queued.connect(func(_id: StringName) -> void: _show_talk.call_deferred())
	StoryManager.cutscene_queued.connect(func(_id: StringName) -> void: _show_cutscene.call_deferred())
	# Something scheduled for this hour (the supplier, a midnight deal...).
	EventBus.event_queued.connect(func(_id: StringName) -> void:
		if is_inside_tree():
			_show_event.call_deferred())
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: _refresh_status())
	if EventManager.has_pending():
		_show_event.call_deferred()
	elif StoryManager.has_cutscene():
		_show_cutscene.call_deferred()
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
	var obj_col := UIKit.vbox(0)
	UIKit.expand(obj_col)
	strip.add_child(obj_col)
	obj_col.add_child(_objective)
	# Why it matters, in one short line under it.
	_objective_why = UIKit.label("", &"DimLabel", false, Palette.TEXT_DIM, 14)
	_objective_why.name = "ObjectiveWhy"
	_objective_why.clip_text = true
	_objective_why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	obj_col.add_child(_objective_why)
	_changes_button = UIKit.button("", &"GhostButton", ChangesPanel.open, "ChangesButton", 36)
	_changes_button.tooltip_text = "What changed while you were busy (money, standing, heat, supplies, staff, people, places)."
	strip.add_child(_changes_button)
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
	cv.add_child(UIKit.section_head("AT THE DOOR"))
	# The details scroll if they're long; SEE PATIENT always stays visible.
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
	_occupation.name = "DoorSentBy"
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
	_see_button = UIKit.button("SEE PATIENT  [%s]" % Controls.key_name("customer_info"), &"AccentButton", GameManager.show_patient_summary, "SeeButton", 56)
	_see_button.set_meta(&"default", true)
	cv.add_child(_see_button)
	# --- Centre: the room + status cards
	var centre := UIKit.vbox(14)
	UIKit.expand(centre, true, true)
	row.add_child(centre)
	var frame := UIKit.panel(&"HudPanel")
	frame.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	# The room crops its art to whatever space it gets, so it flexes: with
	# big text the cards below and the door card keep their room instead of
	# the whole screen growing past the canvas.
	UIKit.expand(frame, true, true)
	centre.add_child(frame)
	_view = ClinicView.new()
	_view.name = "ClinicView"
	_view.custom_minimum_size = Vector2(760, 400)
	UIKit.expand(_view, true, true)
	_view.tooltip_text = "Click the customer or a lit prop · wheel / double-click to zoom · drag to look around"
	_view._base_tooltip = _view.tooltip_text
	_view.hotspot_clicked.connect(GameManager.navigate)
	frame.add_child(_view)
	_view.customer_tapped.connect(GameManager.show_patient_summary)
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
	loc.clip_text = true
	loc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	overlay.add_child(loc)
	# ONE bar under the room: one sentence (what needs you, else today's
	# progress) and the clinic's own controls. It replaces the TODAY meters,
	# WHAT MATTERS NOW and CLINIC STATUS cards (3.9): the NEXT line above is
	# the one objective; people, messages and quests live in the journal.
	var bar := UIKit.panel(&"CardPanel")
	bar.name = "TodayBar"
	UIKit.expand(bar, true, false)
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	centre.add_child(bar)
	_panels.append(bar)
	_status_box = UIKit.vbox(0)
	bar.add_child(_status_box)
	_stock_label = UIKit.label("", &"MonoLabel")
	_stock_label.visible = false
	_status_box.add_child(_stock_label)
	_close_row = UIKit.hbox(10)
	_status_box.add_child(_close_row)
	_status_line = UIKit.button("", &"GhostButton", func() -> void: Nav.open(_status_link), "StatusHeadline", 44)
	_status_line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_line.clip_text = true
	_status_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIKit.expand(_status_line)
	_close_row.add_child(_status_line)
	_close_button = UIKit.button("CLOSE FOR THE NIGHT", &"GhostButton", _close_day, "CloseDayButton", 44)
	_close_button.tooltip_text = "End the business day: pay rent, running costs and salaries, see the ledger."
	_close_row.add_child(_close_button)
	_doors_button = UIKit.button("", &"GhostButton", func() -> void:
		BusinessManager.set_doors_open(not BusinessManager.doors_open)
		_refresh_doors(), "DoorsButton", 44)
	_close_row.add_child(_doors_button)
	_security_button = UIKit.button("SECURITY", &"GhostButton", _open_security, "SecurityButton", 44)
	_security_button.tooltip_text = "Heat level, break-ins and investigations."
	_close_row.add_child(_security_button)
	_doors_row = null
	_refresh_doors()


func _process(delta: float) -> void:
	_objective_timer -= delta
	if _objective_timer <= 0.0:
		_objective_timer = 0.5
		_refresh_objective()
	if _waiting and _waiting.visible:
		_waiting_dots += delta * 2.0
		if BusinessManager.is_day_full() and BusinessManager.jobs_today < BusinessManager.capacity() and not TimeManager.is_closing_time():
			_waiting.text = "It's %s. Nobody else is expected today.\n\nThe room is yours: read, restock, walk the city. Press CLOSE FOR THE NIGHT (below the room) when you're ready." % TimeManager.clock_text()
		elif BusinessManager.is_day_full():
			_waiting.text = "It's %s. The day's work is done.\n\nPress CLOSE FOR THE NIGHT (below the room) to pay the bills and start tomorrow." % TimeManager.clock_text()
		elif not BusinessManager.doors_open:
			_waiting.text = "ARRIVALS PAUSED\n\nNobody new comes in. Take your time: restock in SUPPLY, spend skill points, read the JOURNAL. Press LET PATIENTS IN (below the room) when you're ready."
		else:
			_waiting.text = "Waiting for the next patient" + ".".repeat(int(_waiting_dots) % 4) + _waiting_tail


func _show_event() -> void:
	if not EventManager.has_pending() or UIManager.has_modal():
		return
	var panel := EventPanel.new()
	panel.name = "EventPanel"
	panel.event_id = EventManager.pending_event
	AudioManager.play_sfx(&"event", 0.0)
	UIManager.show_modal(panel)
	panel.closed.connect(_after_event)


## A short story scene (opening, a new chapter, a revelation). It plays
## before any conversation it leads into; never over a decision or a patient
## being worked on.
func _show_cutscene() -> void:
	if not is_inside_tree() or not StoryManager.has_cutscene() or UIManager.has_modal() or EventManager.has_pending():
		return
	var panel := CutscenePlayer.new()
	panel.name = "CutscenePlayer"
	panel.cutscene_id = StoryManager.pop_cutscene()
	UIManager.show_modal(panel)
	panel.closed.connect(_after_event)


## Someone from the story wants a word (conversation modal).
func _show_talk() -> void:
	if not is_inside_tree() or not StoryManager.has_talk() or UIManager.has_modal() or EventManager.has_pending():
		return
	if StoryManager.has_cutscene():
		_show_cutscene()
		return
	var panel := DialoguePanel.new()
	panel.name = "DialoguePanel"
	panel.dialogue_id = StoryManager.pop_talk()
	AudioManager.play_sfx(&"customer", 0.0)
	UIManager.show_modal(panel)
	panel.closed.connect(_after_event)


## Shows what's waiting for an answer (a decision, a scene, a conversation)
## if nothing is on screen: the NEXT line's link.
func resume_story() -> void:
	if UIManager.has_modal():
		return
	if EventManager.has_pending():
		_show_event()
	elif StoryManager.has_cutscene():
		_show_cutscene()
	elif StoryManager.has_talk():
		_show_talk()


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
	if EventManager.has_pending():
		_show_event.call_deferred()
		return
	if StoryManager.has_cutscene():
		_show_cutscene.call_deferred()
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
	# The room, the door card and the NEXT line already say who's here;
	# only an emergency also interrupts.
	if customer.is_emergency:
		UIManager.show_toast("EMERGENCY: %s is bleeding at the door" % customer.display_name, &"danger")
	_show_customer(customer, true)


func _show_customer(customer: CustomerData, animate: bool) -> void:
	_view.show_customer(customer, animate)
	var item := CyberwareManager.get_cyberware(customer.requested_cyberware_id)
	var surgery := SurgeryManager.get_surgery(item.install_surgery_id) if item else null
	_portrait.set_appearance(customer.appearance, FactionManager.get_color(customer.faction_id))
	_name.text = customer.get_display_title()
	# The door card is a teaser: who and what. Their background is in the
	# patient view (DETAILS / INTAKE FORM).
	_faction_tag.text = "EMERGENCY" if customer.is_emergency else ""
	_faction_tag.visible = customer.is_emergency
	_faction_tag.add_theme_color_override(&"font_color", Palette.DANGER)
	# Who sent them, when someone did: the street answering your standing.
	_occupation.text = "Sent by %s" % customer.referred_by if customer.referred_by != "" else ""
	_occupation.visible = customer.referred_by != ""
	UIKit.clear(_request_box)
	if item:
		_request_box.add_child(CyberwareIcon.make(item))
		var rv := UIKit.vbox(2)
		UIKit.expand(rv)
		rv.add_child(UIKit.label("WANTS", &"SubHeaderLabel"))
		rv.add_child(UIKit.label(item.display_name, &"", true))
		_request_box.add_child(rv)
	# Same numbers as the customer file (one source of truth).
	var expected := CustomerGenerator.estimate_fee(customer) if surgery and item else 0
	_offer.text = "PAYS ≈ %s" % EconomyManager.format_money(expected)
	# The door card is a teaser: who, what, roughly what it pays and one line
	# of advice. Everything else is one click away in the PATIENT SUMMARY.
	_risk.visible = false
	_load_meter.visible = false
	UIKit.clear(_verdict_box)
	var adv := PatientBrief.recommendation(customer, PatientBrief.build(customer))
	var a := UIKit.label(str(adv["text"]), &"", true, JobVerdict.color(adv["level"]))
	a.name = "VerdictAdvice"
	_verdict_box.add_child(a)
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


var _doors_button: Button


## PAUSE ARRIVALS / LET PATIENTS IN (the doors): pauses walk-ins. Named
## so it can't be mistaken for CLOSE FOR THE NIGHT, which ends the day.
func _refresh_doors() -> void:
	if _doors_button == null:
		return
	var open := BusinessManager.doors_open
	_doors_button.text = "PAUSE ARRIVALS" if open else "LET PATIENTS IN"
	_doors_button.theme_type_variation = &"GhostButton" if open else &"AccentButton"
	_doors_button.tooltip_text = ("Stop new patients for a while, so you can read, shop and level up in peace. Someone already at the door stays. This doesn't end the day." if open
		else "Let patients in again.")
	if open and not CustomerManager.has_customer():
		CustomerManager.request_next_customer()


func _show_waiting() -> void:
	_view.hide_customer()
	# Only suggest what the player has been introduced to.
	var ideas: Array[String] = []
	for pair: Array in [[&"supply", "restock in SUPPLY"], [&"skills", "spend skill points"], [&"dossier", "read the JOURNAL"],
			[&"map", "go out into the city (CITY MAP, %s)" % Controls.key_name("map")]]:
		if Features.is_on(pair[0]):
			ideas.append(str(pair[1]))
	_waiting_tail = ("\n\nWhile you wait: " + ", ".join(ideas) + ".") if not ideas.is_empty() else "\n\nSomeone will knock soon."
	_waiting.text = "Nobody at the door yet." + _waiting_tail
	_waiting.visible = true
	_info_box.visible = false
	(_info_box.get_parent() as Control).visible = false
	_see_button.visible = false


func _refresh_status() -> void:
	if _stock_label == null:
		return
	_stock_label.text = "CHROME IN STOCK: %d" % InventoryManager.get_instances().size()
	var full := BusinessManager.is_day_full()
	_close_button.disabled = CustomerManager.has_customer() or SurgeryManager.is_active
	_close_button.theme_type_variation = &"AccentButton" if full else &"GhostButton"
	# The clinic's controls appear once the first job has taught the day.
	var after_first := Difficulty.ops() >= 1 or not Features.progressive()
	_close_button.visible = after_first or full
	_doors_button.visible = after_first
	var open := SecurityManager.open_cases().size()
	_security_button.visible = open > 0 or Features.is_on(&"upgrades") or FactionManager.heat >= 25.0
	_security_button.text = "SECURITY" if open == 0 else "%d OPEN CASE%s" % [open, "S" if open > 1 else ""]
	_security_button.theme_type_variation = &"DangerButton" if open > 0 else &"GhostButton"
	if _loc:
		# Where you are; the status bar above has the day and the time.
		_loc.text = "%s · %s" % [ClinicManager.get_tier_name().to_upper(), WorldManager.district_name().to_upper()]
	_refresh_status_card()
	_refresh_matters(true)
	# New sections become available as they become relevant (Features).
	Features.refresh()
	(func() -> void:
		if is_inside_tree() and UIManager.current_screen == self:
			Features.show_next_intro()).call_deferred()


## The bar's one sentence: what needs you (ClinicStatus.dashboard: the
## headline, else the most serious issue), otherwise today's progress.
func _refresh_status_card() -> void:
	if _status_line == null:
		return
	var d := ClinicStatus.dashboard(1)
	var head: Dictionary = d["headline"]
	var issues: Array = d["issues"]
	var level: StringName = ClinicStatus.GOOD
	var text := ""
	_status_link = {}
	# A decision that's waiting is already the NEXT line above: the bar
	# doesn't say it twice.
	if str(head["key"]) not in ["ready", "action"]:
		level = head["level"]
		text = "%s %s · %s" % [ClinicStatus.mark(level), str(head["text"]), str(head["why"])]
		_status_link = head["link"]
	elif not issues.is_empty():
		var it: Dictionary = issues[0]
		level = it["level"]
		text = "%s %s · %s" % [ClinicStatus.mark(level), str(it["text"]), str(it["why"])]
		_status_link = it["link"]
	else:
		var cap := maxi(1, BusinessManager.capacity())
		text = "Jobs %d / %d today · %s of the night left" % [BusinessManager.jobs_today, cap, TimeManager.duration_text(TimeManager.minutes_left())]
	_status_line.text = text
	_status_line.tooltip_text = text
	var col := Palette.TEXT_DIM if level == ClinicStatus.GOOD else ClinicStatus.color(level)
	_status_line.add_theme_color_override(&"font_color", col)
	_status_line.add_theme_color_override(&"font_disabled_color", col)
	_status_line.disabled = not Nav.can_open(_status_link)


func _open_link(link: Dictionary) -> void:
	Nav.open(link)


## The CHANGES button (shown once the journal is introduced: it's where
## changes are read in full).
func _refresh_matters(_force: bool = false) -> void:
	if _changes_button == null:
		return
	_changes_button.visible = Features.is_on(&"dossier")
	var n := ChangeLog.unread_count()
	_changes_button.text = ("◷ CHANGES %d  [%s]" % [n, Controls.key_name("changes")]) if n > 0 else ("◷ CHANGES  [%s]" % Controls.key_name("changes"))
	_changes_button.theme_type_variation = &"Button" if n > 0 else &"GhostButton"
	if n >= 4 and EventManager.operations > 0 and _changes_button.visible:
		Hints.first("changes")


func _refresh_rumor() -> void:
	pass  # rumours live in the journal (DISCOVERIES) and on the wire ticker


func _refresh_objective() -> void:
	if _objective == null:
		return
	var o := GameManager.get_next_objective()
	_objective.text = ("WHEN YOU'RE READY > " if bool(o.get("optional", false)) else "NEXT > ") + str(o["text"]).to_upper()
	_objective.add_theme_color_override(&"font_color", Palette.WARN if o["kind"] == &"warn" else Palette.ACCENT)
	_objective.tooltip_text = str(o.get("why", ""))
	if _objective_why:
		_objective_why.text = str(o.get("why", ""))
	_refresh_matters()


func _open_security() -> void:
	var panel := SecurityPanel.new()
	panel.name = "SecurityPanel"
	UIManager.show_modal(panel)
	panel.closed.connect(_refresh_status)
