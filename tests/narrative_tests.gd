extends RefCounted
## 3.11 tests: the day's patient schedule (visits, quiet days, breathers,
## the incident cap, walk-ins, old saves), story cases (order, gaps, the
## patient, the clue, the decision that follows, consequences days later,
## declines, missed cases, dialogue that remembers), cutscenes (data,
## queue, once per save, the setting, act changes, saves) and seasons
## (calendar, gradual blends, weather, the wire, the mix, no rule
## changes). Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	var cs_was := CutscenePlayer.enabled
	GameManager.is_running = true
	SaveManager.reset_all()
	_seasons_calendar()
	_seasons_presentation()
	_schedule_visits()
	_schedule_quiet_day()
	_schedule_walk_ins_and_breathers()
	_incident_cap()
	_schedule_saves()
	_cases_data()
	_cases_order_and_patient()
	_case_decision_and_echoes()
	_case_decline_and_missed()
	_case_dialogue_variants()
	_cutscenes()
	SaveManager.reset_all()
	CutscenePlayer.enabled = cs_was
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _new_day(day: int) -> void:
	BusinessManager.day = day
	BusinessManager.jobs_today = 0
	EventBus.day_started.emit(day)


# --- Seasons ---------------------------------------------------------------------------------

func _seasons_calendar() -> void:
	var len := TimeManager.season_length()
	check(TimeManager.season(1) == &"autumn" and TimeManager.season(1 + len) == &"winter" and TimeManager.season(1 + 2 * len) == &"spring"
		and TimeManager.season(1 + 3 * len) == &"summer" and TimeManager.season(1 + 4 * len) == &"autumn", "seasons: autumn from day 1, then winter, spring, summer and round again")
	check(TimeManager.day_in_season(1) == 1 and TimeManager.day_in_season(len) == len and TimeManager.day_in_season(len + 1) == 1, "seasons: days count within a season")
	# Gradual: the last days fade toward the next season; nothing jumps overnight.
	var flat := true
	for d in range(1, len - 1):
		flat = flat and float(TimeManager.season_blend(d)["t"]) == 0.0
	var b6: Dictionary = TimeManager.season_blend(len - 1)
	var b7: Dictionary = TimeManager.season_blend(len)
	check(flat and b6["to"] == &"winter" and float(b6["t"]) > 0.0 and float(b7["t"]) > float(b6["t"]) and float(b7["t"]) < 1.0, "seasons: the last days of autumn blend toward winter (%.2f, %.2f)" % [float(b6["t"]), float(b7["t"])])
	var max_step := 0.0
	for d in range(1, 4 * len + 1):
		var a := TimeManager.season_tint(d)
		var z := TimeManager.season_tint(d + 1)
		max_step = maxf(max_step, absf(a.r - z.r) + absf(a.g - z.g) + absf(a.b - z.b) + absf(a.a - z.a))
	var hard := TimeManager.season_tint(4) - TimeManager.season_tint(4 + len)
	var hard_step := absf(hard.r) + absf(hard.g) + absf(hard.b) + absf(hard.a)
	check(max_step < hard_step * 0.6, "seasons: light changes a step at a time (largest daily step %.2f vs %.2f season to season)" % [max_step, hard_step])
	check(TimeManager.weather(5) == TimeManager.weather(5), "seasons: a day's weather is fixed (every street agrees, reloads match)")
	var kinds := {}
	for d in range(1, 4 * len + 1):
		kinds[TimeManager.weather(d)["kind"]] = true
	check(kinds.has("rain") and kinds.has("sleet") and kinds.has("haze"), "seasons: rain, sleet and summer haze all occur (%s)" % str(kinds.keys()))
	# Atmosphere only: no season carries rule modifiers, and the hour's
	# modifiers are the same in every season.
	var mods_free := true
	for id: Variant in TimeManager._seasons().get("list", {}):
		mods_free = mods_free and not (TimeManager.season_def(StringName(str(id))) as Dictionary).has("mods")
	BusinessManager.day = 1
	var m1 := TimeManager.get_modifiers().duplicate()
	var p1 := ModifierManager.value(&"price.buy")
	BusinessManager.day = 1 + 3 * len
	ModifierManager.invalidate()
	check(mods_free and TimeManager.get_modifiers() == m1 and is_equal_approx(ModifierManager.value(&"price.buy"), p1), "seasons: no prices, odds or rules change with the season")
	BusinessManager.day = 1
	ModifierManager.invalidate()


func _seasons_presentation() -> void:
	SaveManager.reset_all()
	var len := TimeManager.season_length()
	BusinessManager.day = 1
	check(TimeManager.stamp().contains("AUTUMN"), "seasons: the clock stamp names the season (%s)" % TimeManager.stamp())
	var news_before := WorldEventManager.news.size()
	var fired: Array = []
	var cb := func(s: StringName) -> void: fired.append(s)
	EventBus.season_changed.connect(cb)
	_new_day(len + 1)
	EventBus.season_changed.disconnect(cb)
	var start_line := str(TimeManager.season_def(&"winter").get("start", ""))
	var on_wire := false
	for i in range(news_before, WorldEventManager.news.size()):
		on_wire = on_wire or str(WorldEventManager.news[i].get("headline", "")) == start_line
	check(fired == [&"winter"] and on_wire, "seasons: winter's first day is announced once, on the news wire")
	check(AudioManager._mix_mods.has(&"season") and float((AudioManager._mix_mods[&"season"] as Dictionary).get("vent", 1.0)) > 1.0, "seasons: the ambience mix follows the season (winter vents)")
	var ok_lines := true
	for id: Variant in TimeManager._seasons().get("list", {}):
		var sd: Dictionary = TimeManager.season_def(StringName(str(id)))
		ok_lines = ok_lines and not (sd.get("lines", []) as Array).is_empty() and not (sd.get("news", []) as Array).is_empty() and str(sd.get("start", "")) != ""
	check(ok_lines, "seasons: every season has its own lines, headlines and opening line")
	SaveManager.reset_all()


# --- The day's schedule ------------------------------------------------------------------------

func _schedule_visits() -> void:
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 5
	var budget := CustomerManager.visit_budget()
	check(budget == BusinessManager.capacity() + int(CustomerManager.pacing().get("spare_visits", 2)), "schedule: visits a day = jobs a day + spare (%d)" % budget)
	check(CustomerManager.visits_left() == budget and CustomerManager.story_slot >= 1, "schedule: a fresh day has every visit, and a story case never opens it")
	CustomerManager.story_slot = 99  # a stranger, not today's story case
	var c := CustomerManager.next_visit()
	check(c != null and CustomerManager.visits_today == 1 and CustomerManager.visits_left() == budget - 1, "schedule: a knock uses one visit")
	var s := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(s)
	check(CustomerManager.kind_of(s) == &"routine", "schedule: a stranger is a routine visit")
	CustomerManager.dismiss_current()
	check(CustomerManager.last_kind == &"routine", "schedule: the last visit's kind is remembered for the breather")
	_new_day(3)
	check(CustomerManager.visits_today == 0, "schedule: a new day, a new schedule")


func _schedule_quiet_day() -> void:
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 5
	CustomerManager.visits_today = CustomerManager.visit_budget()
	StoryManager.talk_queue.clear()
	SkillManager.points = 0
	CustomerManager.request_next_customer(0.0)
	check(not CustomerManager.has_customer() and not CustomerManager.is_customer_pending(), "schedule: nobody new once today's visits are used")
	check(CustomerManager.day_is_quiet() and BusinessManager.is_day_full(), "schedule: a spent schedule is a quiet day")
	var obj := GameManager.get_next_objective()
	check(str(obj["text"]).begins_with("Nobody else is expected today"), "schedule: the clinic says nobody else is expected (%s)" % obj["text"])
	# Someone you sent for still comes.
	var friend := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.queue.append({"customer": friend.to_save_dict(), "due_op": 0})
	check(CustomerManager.has_due_queue() and not CustomerManager.day_is_quiet(), "schedule: someone due back still comes on a quiet day")
	CustomerManager.request_next_customer(0.0)
	check(CustomerManager.has_customer() and CustomerManager.current_customer.display_name == friend.display_name, "schedule: and knocks")
	CustomerManager.dismiss_current()
	SaveManager.reset_all()


func _schedule_walk_ins_and_breathers() -> void:
	SaveManager.reset_all()
	_new_day(2)
	TimeManager.minute = 700
	check(CustomerManager.walk_ins_allowed(), "walk-ins: allowed while the schedule has room")
	CustomerManager.quiet_until = 760
	check(not CustomerManager.walk_ins_allowed(), "walk-ins: nobody new walks in during a quiet stretch")
	CustomerManager.quiet_until = -1
	CustomerManager.visits_today = CustomerManager.visit_budget()
	check(not CustomerManager.walk_ins_allowed(), "walk-ins: the bench shares the day's visits")
	# Five busy hours with the day's visits spent: nobody new sits down.
	var was_open := BusinessManager.doors_open
	var was_running := GameManager.is_running
	BusinessManager.doors_open = true
	GameManager.is_running = true
	CustomerManager.debug_set_customer(CustomerManager.generator.generate({}))
	ClinicLifeManager.waiting.clear()
	ClinicLifeManager._last_minute = -1
	ClinicLifeManager._on_time_changed(600, &"day")
	for h in 10:
		ClinicLifeManager._on_time_changed(600 + (h + 1) * 30, &"day")
	check(ClinicLifeManager.waiting.is_empty(), "walk-ins: the hourly walk-in roll respects the day's visits")
	# Someone already at the door can still take a seat when you go out.
	check(ClinicLifeManager.can_seat(), "walk-ins: the person at the door can still wait on the bench")
	CustomerManager.dismiss_current()
	BusinessManager.doors_open = was_open
	GameManager.is_running = was_running
	var scale := CustomerManager.breather_scale
	CustomerManager.breather_scale = 1.0
	var b: Dictionary = CustomerManager.pacing().get("breather_sec", {})
	CustomerManager.last_kind = &"routine"
	var routine := CustomerManager.breather()
	CustomerManager.last_kind = &"story"
	var story := CustomerManager.breather()
	CustomerManager.last_kind = &"character"
	var character := CustomerManager.breather()
	check(is_equal_approx(routine, float(b["routine"])) and story > character and character > routine and routine > GameConfig.CUSTOMER_ARRIVAL_DELAY_SEC,
		"breathers: longer after someone you know, longest after a story case (%.1f / %.1f / %.1f s)" % [routine, character, story])
	CustomerManager.breather_scale = scale
	SaveManager.reset_all()


func _incident_cap() -> void:
	SaveManager.reset_all()
	_new_day(4)
	EventManager.operations = 30
	var cap := int(CustomerManager.pacing().get("max_incidents_per_day", 2))
	var fired := 0
	for i in 60:
		var id := EventManager.roll_random_event()
		if id != &"":
			fired += 1
			EventManager.pending_event = &""
	check(fired == cap, "incidents: at most %d random incidents a day (%d)" % [cap, fired])
	_new_day(5)
	var again := 0
	for i in 60:
		if EventManager.roll_random_event() != &"":
			again += 1
			EventManager.pending_event = &""
	check(again == cap, "incidents: the cap resets each day")
	check(EventManager.roll_random_event(true) != &"", "incidents: forced (scheduled) incidents still happen")
	EventManager.pending_event = &""
	SaveManager.reset_all()


func _schedule_saves() -> void:
	SaveManager.reset_all()
	_new_day(3)
	CustomerManager.count_visit()
	CustomerManager.count_visit()
	CustomerManager.last_kind = &"story"
	CustomerManager.quiet_until = 800
	var slot := CustomerManager.story_slot
	var d := CustomerManager.get_save_data()
	CustomerManager.load_save_data(d)
	check(CustomerManager.visits_today == 2 and CustomerManager.last_kind == &"story" and CustomerManager.quiet_until == 800 and CustomerManager.story_slot == slot, "schedule: saved and loaded")
	# A 3.10 save has no schedule: today's finished jobs count as visits.
	var old := d.duplicate(true)
	old.erase("schedule")
	BusinessManager.jobs_today = 2
	CustomerManager.load_save_data(old)
	check(CustomerManager.visits_left() == CustomerManager.visit_budget() - 2, "schedule: an old save gets a schedule for today (2 jobs done = 2 visits used)")
	var ev := EventManager.get_save_data()
	ev.erase("incidents_today")
	ev.erase("incident_day")
	EventManager.load_save_data(ev)
	check(EventManager.incidents_today == 0, "incidents: old saves load with no incidents counted")
	SaveManager.reset_all()


# --- Story cases -------------------------------------------------------------------------------

func _cases_data() -> void:
	var ok := true
	var why := ""
	var archetypes := {}
	for a: Dictionary in CustomerManager.archetypes:
		archetypes[str(a["id"])] = true
	for c: Dictionary in StoryManager.cases:
		var id := str(c["id"])
		for k in ["after", "after_failed"]:
			if c.has(k) and not EventManager.events.has(StringName(str(c[k]))):
				ok = false
				why += " %s.%s" % [id, k]
		var p: Dictionary = c.get("patient", {})
		if not archetypes.has(str(p.get("archetype", ""))) or str(p.get("name", "")) == "" or str(c.get("line", "")) == "" or str(c.get("clue", "")) == "":
			ok = false
			why += " %s.patient" % id
		if p.has("faction") and not FactionManager.factions.has(StringName(str(p["faction"]))):
			ok = false
			why += " %s.faction" % id
	check(ok and StoryManager.cases.size() >= 6, "cases: %d cases, each with a patient, words, a clue and a decision that exists%s" % [StoryManager.cases.size(), why])
	# Every consequence and cutscene a case decision names exists.
	var refs_ok := true
	for c: Dictionary in StoryManager.cases:
		var ev := EventManager.get_event(StringName(str(c.get("after", ""))))
		for ch: Dictionary in ev.get("choices", []):
			for o: Dictionary in _outcome_branches(ch.get("outcomes", {})):
				var e: Dictionary = o.get("effects", {})
				if e.has("consequence"):
					var cid := str(e["consequence"]["id"])
					refs_ok = refs_ok and (CommsManager.templates.has(cid) or EventManager.events.has(StringName(cid)) or DialogueManager.has_dialogue(StringName(cid)))
				if e.has("cutscene"):
					refs_ok = refs_ok and StoryManager.cutscenes.has(str(e["cutscene"]))
	check(refs_ok, "cases: every echo (comms, cutscene) a decision schedules exists")


func _outcome_branches(o: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = [o]
	if o.has("risk"):
		out.append(o["risk"]["success"])
		out.append(o["risk"]["fail"])
	return out


func _cases_order_and_patient() -> void:
	SaveManager.reset_all()
	_new_day(1)
	EventManager.operations = 0
	check(StoryManager.due_case().is_empty(), "cases: none on the first day")
	_new_day(2)
	EventManager.operations = 3
	var first := StoryManager.due_case()
	check(str(first.get("id", "")) == "case_crane_hands", "cases: the first case comes on day 2 after a few jobs (%s)" % str(first.get("id", "")))
	# It takes a routine patient's place in the schedule.
	CustomerManager.story_slot = 1
	CustomerManager.count_visit()
	var before := CustomerManager.visits_today
	var c := CustomerManager.next_visit()
	check(c != null and c.case_id == &"case_crane_hands" and CustomerManager.visits_today == before + 1, "cases: a story case replaces a routine visit (one visit, not an extra)")
	check(c.display_name == "Bram Okoye" and c.alias == "Crane" and c.id == &"case_bram_okoye", "cases: the patient is Bram Okoye, the same person every visit")
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	check(surgery != null and str(c.scan_findings.get(String(surgery.scan_region), "")).contains("silver filaments"), "cases: the scan of the operated region holds the clue")
	check(not c.medical_history.is_empty() and c.medical_history[0].contains("tonic"), "cases: the file's history carries the case's line")
	check(c.dialogue.contains("Nerve tonic"), "cases: they say the case's words at the door")
	check(str(StoryManager.case_state.get("case_crane_hands", "")) == "arrived" and StoryManager.last_case_day == 2, "cases: the case is marked as arrived")
	check(StoryManager.due_case().is_empty(), "cases: no second case the same day")
	_new_day(3)
	check(StoryManager.due_case().is_empty(), "cases: and none the next day either (a gap between cases)")
	CustomerManager.debug_set_customer(c)
	_new_day(4)
	EventManager.operations = 6
	check(StoryManager.due_case().get("id", "") == "case_too_calm", "cases: the next case follows a few days later")
	CustomerManager.dismiss_current()
	SaveManager.reset_all()


func _case_decision_and_echoes() -> void:
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 3
	CustomerManager.story_slot = 0
	var c := CustomerManager.next_visit()
	CustomerManager.debug_set_customer(c)
	TimeManager.minute = 700
	CustomerManager.dismiss_current()
	StoryManager.case_finished(c, "success")
	check(EventManager.pending_event == &"case_crane_after", "case decision: THE FILAMENT follows the operation")
	check(CustomerManager.quiet_until > TimeManager.minute and CustomerManager.last_kind == &"story", "case decision: the room stays quiet after it, and the next knock waits longer")
	check(StoryManager.has_flag(&"met_bram") and str(StoryManager.case_state["case_crane_hands"]) == "done", "case decision: the case is done")
	var inv := StoryManager.path_score(&"investigator")
	EventManager.resolve(0)
	check(StoryManager.has_flag(&"thread_sample") and StoryManager.path_score(&"investigator") == inv + 1, "case decision: KEEP A SAMPLE sets the flag and walks the investigator path")
	check(ClinicLifeManager.has_pin("case_sample"), "case decision: the vial goes up on the Wall (a visible consequence)")
	# A second finish never repeats the decision.
	StoryManager.case_finished(c, "success")
	check(not EventManager.has_pending(), "case decision: once only")
	# Telling him schedules a letter three days later.
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 3
	CustomerManager.story_slot = 0
	var c2 := CustomerManager.next_visit()
	StoryManager.case_finished(c2, "success")
	EventManager.resolve(1)
	check(StoryManager.has_flag(&"crane_told"), "case decision: TELL BRAM sets crane_told")
	var inbox := CommsManager.inbox.size()
	_new_day(4)
	check(CommsManager.inbox.size() == inbox, "case echo: nothing yet two days later")
	_new_day(5)
	var got := false
	for m: Dictionary in CommsManager.inbox:
		got = got or str(m.get("template", "")) == "c_crane_letter"
	check(got, "case echo: Bram's letter arrives three days later")
	# His return in act IV remembers what you told him.
	StoryManager.act = 4
	StoryManager.act_started_day = 3
	StoryManager.last_case_day = -99
	for sc: Dictionary in StoryManager.cases:
		if str(sc["id"]) != "case_crane_returns" and not StoryManager.case_state.has(str(sc["id"])):
			StoryManager.case_state[str(sc["id"])] = "missed"
	var back := StoryManager.due_case()
	check(str(back.get("id", "")) == "case_crane_returns" and StoryManager.case_text(back, "line").begins_with("You told me"), "case echo: Bram comes back in act IV, and remembers you told him")
	# Something already waiting: the decision comes tomorrow instead.
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 3
	CustomerManager.story_slot = 0
	var c3 := CustomerManager.next_visit()
	EventManager.queue_event(&"post_op_return")
	StoryManager.case_finished(c3, "success")
	check(EventManager.pending_event == &"post_op_return", "case decision: never replaces an incident that's already waiting")
	EventManager.pending_event = &""
	_new_day(3)
	check(EventManager.pending_event == &"case_crane_after", "case decision: it comes the next morning instead")
	SaveManager.reset_all()


func _case_decline_and_missed() -> void:
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 3
	CustomerManager.story_slot = 0
	var c := CustomerManager.next_visit()
	CustomerManager.debug_set_customer(c)
	# (GameManager.decline_customer calls this; the screen change is the E2E's.)
	StoryManager.case_declined(c)
	CustomerManager.dismiss_current()
	check(str(StoryManager.case_state.get("case_crane_hands", "")) == "declined" and StoryManager.has_flag(&"case_crane_hands_declined"), "cases: turning a case away is remembered")
	check(not EventManager.has_pending(), "cases: a declined case has no decision to make")
	_new_day(4)
	EventManager.operations = 6
	check(StoryManager.due_case().get("id", "") == "case_too_calm", "cases: the story goes on without it")
	# A case patient nobody saw by morning is missed, not stuck.
	CustomerManager.story_slot = 0
	var c2 := CustomerManager.next_visit()
	check(c2 != null and c2.case_id == &"case_too_calm", "cases: the second case walks in")
	_new_day(5)
	check(str(StoryManager.case_state.get("case_too_calm", "")) == "missed", "cases: a case patient gone overnight is marked missed")
	# Saves keep case state; old saves start with none.
	var d := StoryManager.get_save_data()
	StoryManager.load_save_data(d)
	check(str(StoryManager.case_state.get("case_crane_hands", "")) == "declined" and StoryManager.last_case_day == 4, "cases: saved and loaded")
	var old := d.duplicate(true)
	for k in ["cases", "last_case_day", "cutscenes", "seen_cutscenes"]:
		old.erase(k)
	StoryManager.load_save_data(old)
	check(StoryManager.case_state.is_empty() and StoryManager.cutscene_queue.is_empty() and StoryManager.act == int(d["act"]), "cases: a 3.10 save loads with no cases or scenes seen and its story intact")
	# A dead patient never comes back for their case.
	SaveManager.reset_all()
	_new_day(2)
	EventManager.operations = 3
	var bram := CustomerManager.make_case_customer(StoryManager.get_case(&"case_crane_hands"))
	PeopleManager.after_visit(bram, "success", 100)
	PeopleManager.mark_dead(bram.id, "Test.")
	StoryManager.set_flag(&"met_bram")
	StoryManager.act = 4
	StoryManager.last_case_day = -99
	for sc: Dictionary in StoryManager.cases:
		if str(sc["id"]) != "case_crane_returns":
			StoryManager.case_state[str(sc["id"])] = "done"
	check(StoryManager.due_case().is_empty() and str(StoryManager.case_state.get("case_crane_returns", "")) == "missed", "cases: someone who died can't walk in for their case")
	SaveManager.reset_all()


func _case_dialogue_variants() -> void:
	SaveManager.reset_all()
	var moor: Dictionary = DialogueManager.get_dialogue(&"d_moor_evidence")
	var start: Dictionary = moor["nodes"][moor["start"]]
	var plain := DialogueManager.node_text(start)
	StoryManager.set_flag(&"board_files")
	var with_files := DialogueManager.node_text(start)
	check(plain != with_files and with_files.contains("clerk"), "dialogue: Moor remembers the clerk's files you asked for")
	var ilse: Dictionary = DialogueManager.get_dialogue(&"d_ilse_truth")
	var istart: Dictionary = ilse["nodes"][ilse["start"]]
	StoryManager.set_flag(&"thread_sample")
	check(DialogueManager.node_text(istart).contains("filament"), "dialogue: Ilse knows about the sample in your cold box")
	SaveManager.reset_all()


# --- Cutscenes ---------------------------------------------------------------------------------

func _cutscenes() -> void:
	SaveManager.reset_all()
	var valid := true
	var why := ""
	for id: String in StoryManager.cutscenes:
		var shots: Array = StoryManager.cutscenes[id].get("shots", [])
		if shots.is_empty() or shots.size() > 5:
			valid = false
			why += " %s:length" % id
		for s: Dictionary in shots:
			var bd := str(s.get("backdrop", "black"))
			if bd.begins_with("street:"):
				var loc := StringName(bd.trim_prefix("street:"))
				if not LocationManager.locations.has(loc) or not ResourceLoader.exists("res://assets/sprites/streets/%s_night.png" % loc):
					valid = false
					why += " %s:%s" % [id, bd]
			elif not bd in ["keyart", "clinic", "black"]:
				valid = false
				why += " %s:%s" % [id, bd]
			if s.has("portrait") and not CharacterManager.has_character(StringName(str(s["portrait"]))):
				valid = false
				why += " %s:%s" % [id, s["portrait"]]
			if str(s.get("text", "")) == "" or str(s.get("text", "")).length() > 140:
				valid = false
				why += " %s:text" % id
	check(valid, "cutscenes: short (5 shots at most), one line each, made from existing art and cast%s" % why)
	var acts_ok := true
	for n in range(2, 6):
		acts_ok = acts_ok and StoryManager.cutscenes.has("cs_act_%d" % n)
	check(acts_ok and StoryManager.cutscenes.has("cs_opening"), "cutscenes: an opening and a card for every new act")
	CutscenePlayer.enabled = true
	Settings.story_cutscenes = true
	StoryManager.queue_cutscene(&"cs_act_2")
	StoryManager.queue_cutscene(&"cs_act_2")
	check(StoryManager.cutscene_queue == ["cs_act_2"], "cutscenes: queued once")
	check(StoryManager.pop_cutscene() == &"cs_act_2" and not StoryManager.has_cutscene() and StoryManager.seen_cutscenes.has("cs_act_2"), "cutscenes: playing one marks it seen")
	StoryManager.queue_cutscene(&"cs_act_2")
	check(not StoryManager.has_cutscene(), "cutscenes: each plays at most once per save")
	StoryManager.queue_cutscene(&"nope")
	check(not StoryManager.has_cutscene(), "cutscenes: unknown ids are ignored")
	# Turning them off in the settings skips them entirely.
	Settings.story_cutscenes = false
	StoryManager.queue_cutscene(&"cs_act_3")
	check(not StoryManager.has_cutscene() and StoryManager.seen_cutscenes.has("cs_act_3"), "cutscenes: STORY CUTSCENES off skips them")
	Settings.story_cutscenes = true
	# A new act queues its card.
	SaveManager.reset_all()
	StoryManager.advance_act()
	check(StoryManager.act == 2 and StoryManager.cutscene_queue.has("cs_act_2"), "cutscenes: a new act queues its chapter card")
	# A beat can queue one before its conversation (Mother's arrival).
	SaveManager.reset_all()
	StoryManager._do({"cutscene": "cs_mother"})
	check(StoryManager.cutscene_queue == ["cs_mother"], "cutscenes: a story beat can queue a scene")
	var d := StoryManager.get_save_data()
	StoryManager.load_save_data(d)
	check(StoryManager.cutscene_queue == ["cs_mother"], "cutscenes: the queue survives save and load")
	CutscenePlayer.enabled = false
	SaveManager.reset_all()
