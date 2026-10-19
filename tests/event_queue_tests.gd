extends RefCounted
## Events that come while another is waiting for an answer wait behind it
## instead of replacing it: delayed consequences due the same morning, a
## story case's decision deferred to a morning that has other news, and the
## incidents an operation queues on top of one that came during surgery
## (post-op return, angry relative, static fever). Every one is answered in
## the order it came, once, and the line survives a save and reload. The
## day's appointments (the supplier's van, an inspection, the midnight
## deal, the late emergency) come at their time even when a decision is
## waiting, once each, and their decision waits in line.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	var cs_was := CutscenePlayer.enabled
	GameManager.is_running = true
	CutscenePlayer.enabled = false
	SaveManager.reset_all()
	_same_day_consequences()
	_case_decision_and_event_same_day()
	_operation_collisions()
	_repeats_and_duplicates()
	_save_and_reload()
	_agenda_while_waiting()
	_agenda_save_and_duplicates()
	_old_saves_load()
	SaveManager.reset_all()
	CutscenePlayer.enabled = cs_was
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _new_day(day: int) -> void:
	BusinessManager.day = day
	BusinessManager.jobs_today = 0
	EventBus.day_started.emit(day)


## Answers what's pending (first choice that isn't blocked) and returns its id.
func _answer() -> StringName:
	var id := EventManager.pending_event
	var choices: Array = EventManager.get_event(id).get("choices", [])
	for i in choices.size():
		if EventManager.get_choice_block_reason(choices[i]) == "":
			EventManager.resolve(i)
			return id
	return &""


## Answers everything in line; returns the ids in the order they came up.
func _answer_all() -> Array[StringName]:
	var out: Array[StringName] = []
	for guard in 20:
		if not EventManager.has_pending():
			break
		out.append(_answer())
	return out


func _same_day_consequences() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(5000)
	_new_day(5)
	StoryManager.schedule_consequence(&"ev_crew_reprisal", 2)
	StoryManager.schedule_consequence(&"ev_aegis_audit", 2)
	StoryManager.schedule_consequence(&"angry_relative", 2)
	_new_day(6)
	check(not EventManager.has_pending(), "event queue: nothing is due a day early")
	_new_day(7)
	check(EventManager.pending_event == &"ev_crew_reprisal", "event queue: the first consequence due today is up (%s)" % EventManager.pending_event)
	check(EventManager.waiting == [&"ev_aegis_audit", &"angry_relative"], "event queue: the other two due the same day wait behind it, in order (%s)" % [EventManager.waiting])
	var answered := _answer_all()
	check(answered == [&"ev_crew_reprisal", &"ev_aegis_audit", &"angry_relative"], "event queue: all three are answered, in the order they were scheduled (%s)" % [answered])
	check(int(EventManager.history.get(&"ev_aegis_audit", {}).get("count", 0)) == 1, "event queue: each one is answered once")
	var still := StoryManager.pending.filter(func(x: Dictionary) -> bool: return str(x["id"]) in ["ev_crew_reprisal", "ev_aegis_audit", "angry_relative"])
	check(not EventManager.has_pending() and EventManager.waiting.is_empty() and still.is_empty(), "event queue: nothing is left over (%s)" % [StoryManager.pending])
	_new_day(8)
	check(not EventManager.has_pending(), "event queue: nothing comes back the next day")


## A story case finishes while an incident waits: its decision is deferred
## to the next morning, and that morning has another consequence due too.
func _case_decision_and_event_same_day() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(5000)
	_new_day(9)
	StoryManager.schedule_consequence(&"angry_relative", 1)
	EventManager.queue_event(&"supply_drop")
	var sc := StoryManager.get_case(&"case_crew_lieutenant")
	var c := CustomerManager.make_case_customer(sc)
	CustomerManager.debug_set_customer(c)
	CustomerManager.dismiss_current()
	StoryManager.case_finished(c, "success")
	check(EventManager.pending_event == &"supply_drop" and EventManager.waiting.is_empty(), "event queue: a case decision never replaces an incident that's waiting")
	_answer()
	_new_day(10)
	var up := [EventManager.pending_event] + EventManager.waiting
	check(up == [&"angry_relative", &"case_lieutenant_after"], "event queue: the next morning both the consequence and THE BOUNTY are there (%s)" % [up])
	var answered := _answer_all()
	check(answered == [&"angry_relative", &"case_lieutenant_after"], "event queue: both are answered, in the order they were scheduled (%s)" % [answered])
	check(int(EventManager.history.get(&"case_lieutenant_after", {}).get("count", 0)) == 1, "event queue: the case decision is answered exactly once")
	_new_day(11)
	check(not EventManager.has_pending(), "event queue: the decision doesn't come back")


## What GameManager._on_surgery_finished queues, in its order, on top of an
## appointment that came up while the patient was on the table.
func _operation_collisions() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(5000)
	InventoryManager.supplies = 10
	_new_day(12)
	# The supplier's van, due at 10:00, arrives mid-operation.
	TimeManager.agenda = [{"id": "supplier", "minute": 0, "label": "", "event": "supply_drop", "hidden": false, "done": false}]
	TimeManager._run_agenda()
	check(EventManager.pending_event == &"supply_drop", "event queue: the van arrives during the operation")
	# The operation ends: the patient comes back with a failing wound...
	EventManager.operations = 6
	var risky := CustomerManager.generator.generate({"category": "neural"})
	risky.post_op_risk = 1.0
	var ok := SurgeryResult.new()
	ok.success = true
	ok.grade = "C"
	var notes := {}
	for attempt in 20:  # the risk is capped below 100%
		notes = CustomerManager.record_outcome(risky, ok)
		if bool(notes["post_op"]):
			break
	check(bool(notes["post_op"]), "event queue: the post-op complication happened")
	# ...and the implant broke their mind (game_manager.gd: neural_break).
	EventManager.queue_event(&"static_fever")
	# A random incident never piles on top.
	EventManager.roll_random_event(true)
	check(EventManager.pending_event == &"supply_drop", "event queue: the post-op return and static fever don't replace the van")
	var up := [EventManager.pending_event] + EventManager.waiting
	var post_ops := up.count(&"post_op_return")
	check(post_ops >= 1 and up.back() == &"static_fever" and up.size() == 2 + post_ops, "event queue: van, post-op return, static fever, in that order (%s)" % [up])
	var answered := _answer_all()
	check(answered == up, "event queue: all of them are answered, in order (%s)" % [answered])
	# A failed operation: the angry relative waits behind what's there.
	EventManager.queue_event(&"supply_drop")
	var bad := SurgeryResult.new()
	bad.success = false
	bad.failure_reason = &"failed"
	var angry := false
	for attempt in 50:  # complaints are a roll
		CustomerManager.record_outcome(CustomerManager.generator.generate({}), bad)
		if EventManager.waiting.has(&"angry_relative"):
			angry = true
			break
	check(angry and EventManager.pending_event == &"supply_drop", "event queue: an angry relative waits behind the van instead of replacing it")
	_answer_all()
	check(not EventManager.has_pending() and EventManager.waiting.is_empty(), "event queue: the line empties")


func _repeats_and_duplicates() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(5000)
	EventManager.queue_event(&"supply_drop")
	EventManager.queue_event(&"ev_aegis_audit")
	EventManager.queue_event(&"ev_aegis_audit")
	EventManager.queue_event(&"supply_drop")
	check(EventManager.waiting == [&"ev_aegis_audit", &"supply_drop"], "event queue: a one-time decision is never queued twice; a repeatable incident can be (%s)" % [EventManager.waiting])
	EventManager.queue_event(&"no_such_event")
	check(EventManager.waiting.size() == 2, "event queue: an unknown event is ignored")
	var answered := _answer_all()
	check(answered == [&"supply_drop", &"ev_aegis_audit", &"supply_drop"], "event queue: answered in the order they came (%s)" % [answered])
	# Two failed patients, two families at the door.
	EventManager.queue_event(&"angry_relative")
	EventManager.queue_event(&"angry_relative")
	check(EventManager.pending_event == &"angry_relative" and EventManager.waiting == [&"angry_relative"], "event queue: two angry families are two visits")
	_answer_all()
	check(int(EventManager.history.get(&"angry_relative", {}).get("count", 0)) == 2, "event queue: both visits are answered")


func _save_and_reload() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(5000)
	_new_day(14)
	StoryManager.schedule_consequence(&"ev_crew_reprisal", 1)
	StoryManager.schedule_consequence(&"angry_relative", 1)
	EventManager.queue_event(&"supply_drop")
	EventManager.queue_event(&"post_op_return")
	var money := EconomyManager.money
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	check(EventManager.pending_event == &"supply_drop" and EventManager.waiting == [&"post_op_return"], "event queue: a reload keeps what's pending and what waits behind it (%s / %s)" % [EventManager.pending_event, EventManager.waiting])
	check(StoryManager.pending.size() == 2, "event queue: and tomorrow's consequences")
	check(EconomyManager.money == money, "event queue: the reload changes no money")
	check(_answer() == &"supply_drop", "event queue: after the reload the van is answered first")
	# Saved between two queued events.
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	check(EventManager.pending_event == &"post_op_return" and EventManager.waiting.is_empty(), "event queue: saved between two events, the second is up after the reload")
	_new_day(15)
	var up := [EventManager.pending_event] + EventManager.waiting
	check(up == [&"post_op_return", &"ev_crew_reprisal", &"angry_relative"], "event queue: the morning's consequences join the line behind it (%s)" % [up])
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	var answered := _answer_all()
	check(answered == [&"post_op_return", &"ev_crew_reprisal", &"angry_relative"], "event queue: after another reload all three are answered once, in order (%s)" % [answered])
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	check(not EventManager.has_pending() and EventManager.waiting.is_empty(), "event queue: answered events don't come back after a reload")


## Today's appointments from data/time.json, all of them (no chance roll).
func _full_agenda() -> void:
	var out: Array[Dictionary] = []
	for a: Dictionary in TimeManager.data.get("appointments", []):
		out.append({"id": str(a["id"]), "minute": int(a["minute"]), "label": str(a.get("label", "")),
			"event": str(a["event"]), "hidden": bool(a.get("hidden", false)), "done": false})
	TimeManager.agenda = out
	TimeManager.minute = TimeManager.open_minute()


func _agenda_done() -> Array[String]:
	var out: Array[String] = []
	for a: Dictionary in TimeManager.agenda:
		if bool(a["done"]):
			out.append(str(a["id"]))
	return out


## Heat over the inspection's 35, Wire met (the midnight deal), past the
## learning phase (the late emergency), a decision on the table.
func _busy_day() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(5000)
	InventoryManager.add_tokens(2)
	FactionManager.add_heat(45)
	StoryManager.set_flag(&"bm_access")
	EventManager.operations = 10
	_new_day(20)
	_full_agenda()
	EventManager.queue_event(&"angry_relative")


func _agenda_while_waiting() -> void:
	_busy_day()
	TimeManager.advance(600 - TimeManager.minute)  # 10:00, the van
	check(_agenda_done() == ["supplier"], "agenda: at 10:00 only the van has come (%s)" % [_agenda_done()])
	check(EventManager.pending_event == &"angry_relative" and EventManager.waiting == [&"supply_drop"], "agenda: the van comes while a decision waits, and waits behind it (%s)" % [EventManager.waiting])
	TimeManager.advance(60)  # 11:00: nothing new is due
	check(EventManager.waiting == [&"supply_drop"], "agenda: nothing comes before its time")
	TimeManager.advance(780 - TimeManager.minute)  # 13:00, the inspection
	check(EventManager.waiting == [&"supply_drop", &"inspector_visit"], "agenda: the inspection comes at 13:00 and waits behind the van (%s)" % [EventManager.waiting])
	TimeManager.advance(1440 - TimeManager.minute)  # midnight
	TimeManager.advance(1560 - TimeManager.minute)  # 02:00, the late emergency
	var up := [EventManager.pending_event] + EventManager.waiting
	check(up == [&"angry_relative", &"supply_drop", &"inspector_visit", &"bm_deal", &"emergency_patient"],
		"agenda: every appointment came at its time and waits in the order it came (%s)" % [up])
	check(_agenda_done().size() == 4 and TimeManager.upcoming().is_empty(), "agenda: all four are marked as come, none still upcoming")
	TimeManager._run_agenda()
	TimeManager.advance(30)
	check(EventManager.waiting.size() == 4, "agenda: the clock moving on doesn't bring any of them twice")
	var heat := FactionManager.heat
	var answered := _answer_all()
	check(answered == up, "agenda: each is answered once, in order (%s)" % [answered])
	check(FactionManager.heat < heat, "agenda: the inspection's answer still applies (heat %.0f -> %.0f)" % [heat, FactionManager.heat])
	check(CustomerManager.has_customer() and CustomerManager.current_customer.is_emergency, "agenda: treating the late emergency still brings the patient in")
	CustomerManager.reset_state()
	TimeManager._run_agenda()
	check(not EventManager.has_pending(), "agenda: answered appointments never come back")
	# Prerequisites are read at the appointment's time: no midnight deal
	# without Wire, even if you meet Wire later that night.
	_busy_day()
	StoryManager.set_flag(&"bm_access", false)
	TimeManager.advance(1440 - TimeManager.minute)
	check(not EventManager.waiting.has(&"bm_deal"), "agenda: the midnight deal doesn't come without Wire")
	StoryManager.set_flag(&"bm_access")
	TimeManager.advance(60)
	check(not EventManager.waiting.has(&"bm_deal"), "agenda: and doesn't come late once Wire is met")
	# Nothing waiting: the van is up straight away, as before.
	SaveManager.reset_all()
	_full_agenda()
	TimeManager.advance(600 - TimeManager.minute)
	check(EventManager.pending_event == &"supply_drop" and EventManager.waiting.is_empty(), "agenda: with nothing waiting, the van is up at once")


func _agenda_save_and_duplicates() -> void:
	_busy_day()
	TimeManager.advance(800 - TimeManager.minute)  # the van and the inspection have come
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	check(EventManager.pending_event == &"angry_relative" and EventManager.waiting == [&"supply_drop", &"inspector_visit"], "agenda save: a reload keeps the waiting appointments (%s)" % [EventManager.waiting])
	check(_agenda_done() == ["supplier", "inspection"], "agenda save: and which appointments have come (%s)" % [_agenda_done()])
	TimeManager._run_agenda()
	TimeManager.advance(10)
	check(EventManager.waiting == [&"supply_drop", &"inspector_visit"], "agenda save: after the reload neither comes again")
	check(_answer() == &"angry_relative" and _answer() == &"supply_drop", "agenda save: answering the first two")
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	check(EventManager.pending_event == &"inspector_visit" and EventManager.waiting.is_empty(), "agenda save: saved between two, the inspection is up after the reload")
	TimeManager.advance(1440 - TimeManager.minute)
	check(EventManager.waiting == [&"bm_deal"], "agenda save: the midnight deal still comes at its time after the reload (%s)" % [EventManager.waiting])
	var answered := _answer_all()
	check(answered == [&"inspector_visit", &"bm_deal"], "agenda save: the rest answered once, in order (%s)" % [answered])
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	TimeManager._run_agenda()
	check(not EventManager.has_pending() and EventManager.waiting.is_empty(), "agenda save: answered appointments don't come back after a reload")
	CustomerManager.reset_state()


func _old_saves_load() -> void:
	SaveManager.reset_all()
	EventManager.load_save_data({"pending": "supply_drop", "operations": 3})
	check(EventManager.pending_event == &"supply_drop" and EventManager.waiting.is_empty(), "event queue: a save from before the queue loads its one pending event")
	EventManager.load_save_data({"pending": "", "waiting": ["no_such_event", "angry_relative"]})
	check(EventManager.pending_event == &"angry_relative" and EventManager.waiting.is_empty(), "event queue: an unknown waiting event is dropped, the next one comes up")
	SaveManager.reset_all()
