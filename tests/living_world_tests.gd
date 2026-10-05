extends RefCounted
## Living-world system tests (no UI): people, memory, psychology, finances,
## payment terms, debts, returning customers. Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	WorldEventManager.auto_roll = false
	_psychology_and_finances()
	_memory()
	_payment_terms()
	_debts()
	_returning_customers()
	_living_save_roundtrip()
	_staff_life()
	_time_of_day()
	_clinic_life()
	_world_events()
	SaveManager.reset_all()
	WorldEventManager.auto_roll = true


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _fresh() -> void:
	SaveManager.reset_all()
	EventManager.operations = 8  # past the learning phase


func _psychology_and_finances() -> void:
	_fresh()
	var seen_traits := {}
	var seen_fin := {}
	var budgets_ok := true
	for i in 120:
		var c := CustomerManager.generator.generate({"full_difficulty": true})
		for tr in c.traits:
			seen_traits[tr] = true
			budgets_ok = budgets_ok and PeopleManager.patients["traits"].has(String(tr))
		seen_fin[c.finance] = true
		budgets_ok = budgets_ok and c.budget > 0 and c.traits.size() in [1, 2]
	check(budgets_ok, "every customer has 1-2 known traits and a budget")
	check(seen_traits.size() >= 8, "trait variety across customers (%d)" % seen_traits.size())
	check(seen_fin.size() >= 5, "finance variety across customers (%d)" % seen_fin.size())
	# Budget is tied to the job: desperate people can't cover it, wealthy can.
	var c2 := CustomerManager.generator.generate({"full_difficulty": true})
	var fee := CustomerGenerator.estimate_fee(c2)
	check(fee > 0, "fee estimate for a generated job (%d)" % fee)
	c2.finance = &"desperate"
	CustomerManager.generator.roll_budget(c2)
	check(c2.budget < fee, "a desperate patient can't cover the fee (%d < %d)" % [c2.budget, fee])
	c2.finance = &"wealthy"
	CustomerManager.generator.roll_budget(c2)
	check(c2.budget >= fee * 2 - 10, "a wealthy patient can (%d vs %d)" % [c2.budget, fee])


func _memory() -> void:
	_fresh()
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(c)
	var rel0 := int(PeopleManager.get_person(c.id)["rel"])
	var civ0 := ReputationManager.dim(&"civilian")
	MemoryManager.remember(c.id, &"PLAYER_SAVED_ME")
	check(MemoryManager.has(c.id, &"PLAYER_SAVED_ME"), "memory recorded")
	check(int(PeopleManager.get_person(c.id)["rel"]) == rel0 + 25, "saving them raises the relationship by the data value")
	check(ReputationManager.dim(&"civilian") == civ0 + 2, "and civilian reputation")
	check(MemoryManager.recall_line(c.id, true) != "", "they bring it up later")
	MemoryManager.remember(c.id, &"NOT_A_TAG")
	check(MemoryManager.of(c.id).size() == 1, "unknown memory tags are ignored")
	# Story cast relationships go through CharacterManager.
	var cast_id: StringName = CharacterManager.cast.keys()[0]
	var r0 := CharacterManager.relationship(cast_id)
	MemoryManager.remember(cast_id, &"PLAYER_KEPT_SECRET")
	check(CharacterManager.relationship(cast_id) == r0 + 15, "cast characters remember too")
	check(MemoryManager.who_remembers(&"PLAYER_KEPT_SECRET").has(cast_id), "who_remembers finds them")
	for i in 40:
		MemoryManager.remember(c.id, &"PLAYER_MADE_ME_WAIT")
	check(MemoryManager.of(c.id).size() == MemoryManager.MAX_PER_OWNER, "memories are capped per person")
	# Death: linked friends remember.
	var friend := PeopleManager.referral(c)
	check(PeopleManager.get_person(c.id)["links"].has(String(friend.id)), "referral links the two people")
	PeopleManager.after_visit(c, "death")
	check(MemoryManager.has(friend.id, &"PLAYER_KILLED_FRIEND"), "a friend remembers you killed them")
	check(str(PeopleManager.get_person(c.id)["status"]) == "dead", "dead people stay dead")
	check(not PeopleManager.due_people().has(c.id), "dead people don't come back")


func _payment_terms() -> void:
	_fresh()
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	c.traits.clear()
	c.budget = 10000
	var s := PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 1000 and int(s["debt"]) == 0, "full price, able to pay")
	c.terms = &"discount"
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 700, "discount pays 70%")
	c.terms = &"free"
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 0 and int(s["debt"]) == 0, "free costs nothing and owes nothing")
	c.terms = &"overcharge"
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 1400, "overcharge +40%")
	c.terms = &"full"
	c.traits.append(&"greedy")
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 850, "greedy patients haggle")
	c.traits.clear()
	# Can't pay: the rest becomes a debt.
	c.budget = 300
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 300 and int(s["debt"]) == 700, "short of money: pays budget, owes the rest")
	check(PeopleManager.owed_by(c.id) == 700, "debt recorded against them")
	c.terms = &"plan"
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 300 and int(s["debt"]) == 700, "pay later: 30% now")
	var plans := PeopleManager.open_debts().filter(func(d: Dictionary) -> bool: return str(d["status"]) == "plan")
	check(plans.size() == 1, "pay later sets up a payment plan")
	# Backer pays.
	c.terms = &"faction"
	c.backer = &"street_gangs"
	var crim0 := ReputationManager.dim(&"criminal")
	s = PeopleManager.settle(c, 1000)
	check(int(s["paid"]) == 1100 and int(s["debt"]) == 0, "a backer pays the bill")
	check(ReputationManager.dim(&"criminal") > crim0, "taking gang money is criminal rep")
	check(PeopleManager.available_terms(c).has(&"faction"), "backer terms offered when backed")
	c.backer = &""
	check(not PeopleManager.available_terms(c).has(&"faction"), "and not otherwise")
	# Terms memories land after the visit.
	c.terms = &"overcharge"
	PeopleManager.after_visit(c, "success", 1400)
	check(MemoryManager.has(c.id, &"PLAYER_OVERCHARGED_ME"), "overcharged patients remember")


func _debts() -> void:
	_fresh()
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(c)
	var d := PeopleManager.add_debt(c.id, 400, "test")
	var m0 := EconomyManager.money
	var got := PeopleManager.demand(int(d["id"]))
	check(got > 0 and EconomyManager.money == m0 + got, "demand collects part of it")
	check(PeopleManager.owed_by(c.id) == 400 - got, "and the rest stays owed")
	PeopleManager.set_plan(int(d["id"]))
	check(str(PeopleManager.get_debt(int(d["id"]))["status"]) == "plan", "payment plan set")
	var before := PeopleManager.owed_by(c.id)
	for i in 12:
		BusinessManager.end_day()
	check(PeopleManager.owed_by(c.id) < before, "instalments come in at night (%d -> %d)" % [before, PeopleManager.owed_by(c.id)])
	var d2 := PeopleManager.add_debt(c.id, 200, "test")
	PeopleManager.write_off(int(d2["id"]))
	check(MemoryManager.has(c.id, &"PLAYER_LET_DEBT_GO"), "writing off is remembered")
	var d3 := PeopleManager.add_debt(c.id, 500, "test")
	var heat0 := FactionManager.heat
	m0 = EconomyManager.money
	check(PeopleManager.send_collector(int(d3["id"])) == 300 and EconomyManager.money == m0 + 300, "a fixer collects 60%")
	check(FactionManager.heat > heat0 and MemoryManager.has(c.id, &"PLAYER_SENT_COLLECTOR"), "collectors bring heat and a grudge")
	var d4 := PeopleManager.add_debt(c.id, 250, "test")
	PeopleManager.favor(int(d4["id"]))
	check(bool(PeopleManager.get_person(c.id)["favor"]) and int(PeopleManager.get_person(c.id)["next_day"]) >= BusinessManager.day, "favour: they'll come back to repay it")
	var s0 := InventoryManager.supplies
	var p0 := InventoryManager.parts
	m0 = EconomyManager.money
	var back := PeopleManager.make_customer(c.id)
	check(back != null and back.changes.any(func(x: String) -> bool: return x.contains("Favour repaid")), "the favour is repaid on arrival")
	check(InventoryManager.supplies > s0 or InventoryManager.parts > p0 or EconomyManager.money > m0, "and it's worth something")


func _returning_customers() -> void:
	_fresh()
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	c.terms = &"discount"
	# Force a return.
	PeopleManager.after_visit(c, "success", 500)
	var p := PeopleManager.get_person(c.id)
	p["next_day"] = BusinessManager.day
	check(PeopleManager.due_people().has(c.id), "a patient is due back")
	CustomerManager.queue.clear()
	var back := CustomerManager._next_customer()
	check(back != null and back.id == c.id, "they walk back in through the normal door")
	check(back.display_name == c.display_name and back.visits == 1, "same person, visit count kept")
	check(back.dialogue.length() > 3, "they have something to say")
	check(MemoryManager.has(c.id, &"PLAYER_GAVE_DISCOUNT") and MemoryManager.has(c.id, &"PLAYER_INSTALLED_CYBERWARE"), "they remember the discount and the chrome")
	check(back.existing_cyberware.has(c.requested_cyberware_id) or CyberwareManager.get_cyberware(c.requested_cyberware_id) == null, "the chrome you installed is still in them")
	check(back.appearance == PeopleManager.get_person(c.id)["appearance"], "their evolving look carries over")
	check(not PeopleManager.due_people().has(c.id), "no longer due once they arrive")
	# Evolution over a long absence produces visible changes.
	var changed := 0
	for i in 30:
		var x := CustomerManager.generator.generate({"full_difficulty": true})
		PeopleManager.after_visit(x, "success", 100)
		PeopleManager.get_person(x.id)["last_day"] = BusinessManager.day - 20
		var y := PeopleManager.make_customer(x.id)
		if not y.changes.is_empty():
			changed += 1
	check(changed >= 10, "people change between visits (%d/30)" % changed)
	# Refusing is remembered; hostile people warn others away.
	var h := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(h)
	PeopleManager.change_rel(h.id, -60)
	var civ0 := ReputationManager.dim(&"civilian")
	PeopleManager.after_visit(h, "refused")
	check(MemoryManager.has(h.id, &"PLAYER_REFUSED_TREATMENT"), "refusals are remembered")
	check(ReputationManager.dim(&"civilian") < civ0, "hostile people warn others away")
	# Loyalty.
	var l := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(l)
	PeopleManager.change_rel(l.id, 70)
	check(PeopleManager.rel_state(l.id) == "loyal", "high regard becomes loyalty")
	# Old copy-return path is gone: record_outcome goes through PeopleManager.
	var r := SurgeryResult.new()
	r.success = true
	r.grade = "S"
	var z := CustomerManager.generator.generate({"full_difficulty": true})
	CustomerManager.record_outcome(z, r)
	check(PeopleManager.has_person(z.id) and int(PeopleManager.get_person(z.id)["visits"]) == 1, "operations register the patient")


func _living_save_roundtrip() -> void:
	_fresh()
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.after_visit(c, "success", 321)
	MemoryManager.remember(c.id, &"PLAYER_KEPT_PROMISE")
	PeopleManager.add_debt(c.id, 123, "test")
	ReputationManager.change_dim(&"medical", 7)
	check(SaveManager.save_game(), "living world saves")
	SaveManager.reset_all()
	check(not PeopleManager.has_person(c.id), "reset clears people")
	check(SaveManager.load_game(), "living world loads")
	check(PeopleManager.has_person(c.id) and int(PeopleManager.get_person(c.id)["paid_total"]) == 321, "people survive save/load")
	check(MemoryManager.has(c.id, &"PLAYER_KEPT_PROMISE"), "memories survive save/load")
	check(PeopleManager.owed_by(c.id) == 123, "debts survive save/load")
	check(ReputationManager.dim(&"medical") == 7, "reputation dimensions survive save/load")
	SaveManager.delete_save()


func _add_staff(spec: String = "") -> Dictionary:
	var e := StaffManager.generate_candidate(spec)
	e["clinic"] = ClinicManager.tier
	for o in StaffManager.employees:
		o["relationships"][str(e["id"])] = 0
		e["relationships"][str(o["id"])] = 0
	StaffManager.employees.append(e)
	StaffManager.staff_changed.emit()
	return e


func _staff_life() -> void:
	_fresh()
	var a := _add_staff()
	var b := _add_staff()
	check(a.has("life") and str(a["life"].get("family", "")) != "" and str(a["life"].get("fear", "")) != "", "new staff get a life (family, money, fear, dream)")
	check(StaffLifeManager.family_label(a) != "" and StaffLifeManager.money_label(a) != "", "life labels resolve")
	StaffLifeManager.change_rel(a, b, 60 - StaffLifeManager.rel(a, b))
	check(StaffLifeManager.bond(a, b) == "loyal" and StaffLifeManager.bond(b, a) == "loyal", "high regard is a loyal bond, both ways")
	check(StaffLifeManager.team_modifier(a) > 0.0, "a loyal colleague steadies the hands")
	var base_chance := EmployeeAI.success_chance(a, CustomerManager.generator.generate({"full_difficulty": true}))
	StaffLifeManager.change_rel(a, b, -110)
	check(StaffLifeManager.bond(a, b) == "resentful", "a grudge becomes resentment")
	check(StaffLifeManager.team_modifier(a) < 0.0, "resentment costs focus")
	check(EmployeeAI.success_chance(a, CustomerManager.generator.generate({"full_difficulty": true})) <= base_chance + 0.2, "team mood feeds job odds")
	# An argument, resolved from COMMS.
	var uid := StaffLifeManager.fire(&"argument", a, b)
	var m := CommsManager.get_message(uid)
	check(uid >= 0 and str(m["subject"]) != "" and (m["actions"] as Array).size() == 3, "argument arrives in COMMS with three choices")
	check(str(m["actions"][0]["label"]).contains(str(a["name"]).to_upper()), "choices name the people involved")
	var r0 := StaffLifeManager.rel(a, b)
	check(CommsManager.act(uid, 2), "choose: both of you, outside")
	check(StaffLifeManager.rel(a, b) == r0 + 12 and StaffLifeManager.bond(a, b) in ["professional", "suspicious", "resentful"], "the choice changes how they get on (%s)" % StaffLifeManager.bond(a, b))
	# Loan shark: paying saves them, and they remember.
	a["life"]["money"] = "debt"
	var m0 := EconomyManager.money
	EconomyManager.add_money(1000)
	var loy := float(a["loyalty"])
	uid = StaffLifeManager.fire(&"loan_shark", a)
	CommsManager.act(uid, 0)
	check(EconomyManager.money == m0 + 1000 - 300, "paying the loan shark costs 300")
	check(float(a["loyalty"]) > loy + 20.0 and MemoryManager.has(StringName(str(a["id"])), &"PLAYER_SAVED_EMPLOYEE"), "they remember you saved them")
	check(str(a["life"]["money"]) == "sending", "and their money situation changes")
	# Family emergency: a day off.
	a["life"]["family"] = "father"
	uid = StaffLifeManager.fire(&"family_emergency", a)
	check(str(CommsManager.get_message(uid)["body"]).contains("father"), "the event knows who their family is")
	CommsManager.act(uid, 0)
	check(str(a["status"]) == "resting", "taking the day means they rest tomorrow")
	# Romance and the work consequences.
	StaffLifeManager.change_rel(a, b, 50 - StaffLifeManager.rel(a, b))
	a["bonds"].erase(str(b["id"]))
	b["bonds"].erase(str(a["id"]))
	uid = StaffLifeManager.fire(&"romance", a, b)
	CommsManager.act(uid, 0)
	check(StaffLifeManager.bond(a, b) == "involved", "two colleagues get together")
	# Reactions.
	loy = float(b["loyalty"])
	StaffLifeManager.on_patient_death(b)
	check(float(b["loyalty"]) > loy, "a partner defends them after a death on the table")
	StaffLifeManager.set_bond(a, b, "competitive")
	StaffLifeManager.change_rel(a, b, -StaffLifeManager.rel(a, b))
	a["raise_pending"] = false
	StaffManager.give_raise(StringName(str(b["id"])), true)
	check(bool(a["raise_pending"]), "a rival wants a raise too")
	# Random life events actually fire.
	StaffLifeManager.last_fired.clear()
	BusinessManager.day = 10
	var fired := StaffLifeManager.roll_event()
	check(fired != "" and StaffLifeManager.last_fired.has(fired), "a fitting life event fires (%s)" % fired)
	check(StaffLifeManager.roll_event() != fired or StaffLifeManager.get_event(StringName(fired)).is_empty(), "the same event has a cooldown")
	# Save/load keeps lives and bonds.
	var fam := str(a["life"]["family"])
	check(SaveManager.save_game(), "staff life saves")
	SaveManager.reset_all()
	check(SaveManager.load_game(), "staff life loads")
	var a2 := StaffManager.get_employee(StringName(str(a["id"])))
	var b2 := StaffManager.get_employee(StringName(str(b["id"])))
	check(not a2.is_empty() and str(a2["life"]["family"]) == fam, "life survives save/load")
	check(StaffLifeManager.bond(a2, b2) == "competitive", "bonds survive save/load")
	check(StaffLifeManager.last_fired.has(fired), "event cooldowns survive save/load")
	SaveManager.delete_save()


func _time_of_day() -> void:
	_fresh()
	check(TimeManager.minute == TimeManager.open_minute() and TimeManager.clock_text() == "09:00", "the clinic opens at 09:00")
	check(TimeManager.period() == &"morning", "it's morning")
	check(TimeManager.period(1200) == &"evening" and TimeManager.period(1380) == &"night" and TimeManager.period(1560) == &"late_night" and TimeManager.period(800) == &"day", "periods follow the clock")
	check(TimeManager.clock_text(1560) == "02:00", "after midnight reads as 02:00")
	check(TimeManager.procedure_minutes(1) == 20 and TimeManager.procedure_minutes(5) == 120, "routine 20 min, complex neural two hours")
	check(TimeManager.procedure_minutes(3, true) < TimeManager.procedure_minutes(3) + 30, "emergencies start immediately")
	var periods_seen := {}
	var changes := [0]
	var cb := func(_p: StringName) -> void: changes[0] += 1
	EventBus.period_changed.connect(cb)
	# A full day of jobs walks through the periods.
	var cap := BusinessManager.capacity()
	for i in cap:
		TimeManager.on_customer_arrived(false)
		periods_seen[TimeManager.period()] = true
		TimeManager.on_operation(3)
		BusinessManager.record_job()
		periods_seen[TimeManager.period()] = true
	EventBus.period_changed.disconnect(cb)
	check(periods_seen.size() >= 2 and changes[0] >= 1 and TimeManager.minute >= 1020, "a day's work spans several periods, into the evening (%s)" % [periods_seen.keys()])
	check(TimeManager.minute <= TimeManager.close_minute() + 120, "the clock stays bounded")
	# Closing time ends the day even with free slots.
	BusinessManager.jobs_today = 0
	TimeManager.minute = TimeManager.close_minute()
	check(BusinessManager.is_day_full(), "past 04:00 the door is locked")
	BusinessManager.end_day()
	check(TimeManager.minute == TimeManager.open_minute() and not BusinessManager.is_day_full(), "a new day opens at 09:00")
	# Night changes who walks in and what happens.
	TimeManager.minute = 1400
	check(TimeManager.archetype_weight("gang_member") > 1.0 and TimeManager.archetype_weight("corporate") < 1.0, "gangs come at night, suits don't")
	check(TimeManager.event_weight(&"bm_deal") > TimeManager.event_weight(&"inspector_visit"), "night favours deals over inspections")
	check(TimeManager.bm_price_mult() < 1.0, "the black market is cheaper after dark")
	var gangs_night := 0
	for i in 200:
		if str(CustomerManager.generator._pick_archetype({})["id"]) in ["gang_member", "criminal", "smuggler"]:
			gangs_night += 1
	TimeManager.minute = 700
	check(TimeManager.event_weight(&"inspector_visit") > 1.0, "inspections happen in business hours")
	var gangs_day := 0
	for i in 200:
		if str(CustomerManager.generator._pick_archetype({})["id"]) in ["gang_member", "criminal", "smuggler"]:
			gangs_day += 1
	check(gangs_night > gangs_day, "more criminals walk in at night (%d vs %d)" % [gangs_night, gangs_day])
	# Late night: supplies cost more, night owls shine.
	TimeManager.minute = 1550
	EventBus.modifiers_changed.emit()
	check(ModifierManager.value(&"price.buy") >= 0.15, "late-night courier fee on supplies")
	var owl := StaffManager.generate_candidate()
	owl["traits"] = ["night_owl"]
	var lark := StaffManager.generate_candidate()
	lark["traits"] = []
	check(TimeManager.staff_modifier(owl) > 0.0 and TimeManager.staff_modifier(lark) < 0.0, "night owls are sharper at 03:00, others slower")
	check(TimeManager.tint().a > 0.2, "the room is dark late at night")
	TimeManager.minute = 700
	EventBus.modifiers_changed.emit()
	check(ModifierManager.value(&"price.buy") <= 0.0, "no courier fee by day")
	# Appointments fire their incident when the clock passes them.
	EventManager.pending_event = &""
	TimeManager.agenda = [{"id": "supplier", "minute": 720, "label": "x", "event": "supply_drop", "hidden": false, "done": false}] as Array[Dictionary]
	check(TimeManager.upcoming().size() == 1, "the supplier is on today's agenda")
	TimeManager.advance(30)
	check(EventManager.pending_event == &"supply_drop" and TimeManager.upcoming().is_empty(), "the supplier's van arrives on time")
	EventManager.pending_event = &""
	# Ambience follows the hour.
	TimeManager.minute = 1380
	TimeManager._apply_ambience()
	AudioManager.set_profile(&"clinic")
	check(AudioManager.layer_level(&"city") > float(AudioManager.PROFILES[&"clinic"]["layers"][&"city"]), "the city is louder at night")
	# Save/load keeps the time.
	TimeManager.minute = 1234
	check(SaveManager.save_game(), "time saves")
	SaveManager.reset_all()
	check(SaveManager.load_game() and TimeManager.minute == 1234, "time survives save/load")
	SaveManager.delete_save()


func _clinic_life() -> void:
	_fresh()
	var was_running := GameManager.is_running
	GameManager.is_running = true
	check(ClinicLifeManager.capacity() >= 1, "the waiting room has a bench")
	var a := CustomerManager.generator.generate({"full_difficulty": true})
	CustomerManager.debug_set_customer(CustomerManager.generator.generate({"full_difficulty": true}))
	check(ClinicLifeManager.seat(a), "someone sits down to wait")
	check(not ClinicLifeManager.can_seat() or ClinicLifeManager.capacity() > 1, "the bench fills up")
	CustomerManager.dismiss_current()
	CustomerManager._on_arrival_timer_timeout()
	check(CustomerManager.current_customer == a and ClinicLifeManager.waiting.is_empty(), "the next customer comes off the bench")
	# Patience runs out.
	var b := CustomerManager.generator.generate({"full_difficulty": true})
	b.patience = 10
	ClinicLifeManager.seat(b)
	TimeManager.advance(ClinicLifeManager.wait_limit(b) + 5)
	check(not ClinicLifeManager.waiting_customers().has(b) and MemoryManager.has(b.id, &"PLAYER_MADE_ME_WAIT"), "they give up, leave and remember")
	ClinicLifeManager.waiting.clear()
	# Rival crews make a scene.
	ClinicManager.upgrades[ClinicManager.clinic_id()] = {"customer": 2}
	BusinessManager.jobs_today = 0
	var g := CustomerManager.generator.generate({"full_difficulty": true, "faction": "street_gangs"})
	var k := CustomerManager.generator.generate({"full_difficulty": true, "faction": "corporate_security"})
	g.faction_id = &"street_gangs"
	k.faction_id = &"corporate_security"
	var civ0 := ReputationManager.dim(&"civilian")
	ClinicLifeManager.seat(g)
	ClinicLifeManager.seat(k)
	check(ClinicLifeManager.waiting.size() == 1 and ReputationManager.dim(&"civilian") < civ0, "gang and corp in one room: someone storms out")
	check(ClinicLifeManager.captions.any(func(c: String) -> bool: return c.contains("square up")), "the scene is described")
	# Overnight the bench empties.
	BusinessManager.end_day()
	check(ClinicLifeManager.waiting.is_empty(), "nobody waits overnight")
	# Vignettes happen and some do things.
	var ids := {}
	TimeManager.minute = 1380
	ClinicLifeManager.waiting.append({"customer": CustomerManager.generator.generate({"full_difficulty": true}), "since": 1380})
	for i in 60:
		ids[ClinicLifeManager.vignette()] = true
	check(ids.size() >= 4, "clinic life has variety (%d kinds)" % ids.size())
	ClinicLifeManager.waiting.clear()
	var s0 := InventoryManager.supplies
	InventoryManager.supplies = 0
	TimeManager.minute = 600
	var delivered := false
	for i in 80:
		if ClinicLifeManager.vignette() == "delivery":
			delivered = true
			break
	check(delivered and InventoryManager.supplies > 0, "a courier's crate adds supplies")
	InventoryManager.supplies = s0
	# The Wall remembers.
	var r := SurgeryResult.new()
	r.success = true
	r.grade = "B"
	r.customer_name = "Test Patient"
	EventBus.surgery_rewarded.emit(r)
	check(ClinicLifeManager.has_pin("first_op"), "the first job goes on the wall")
	EventBus.surgery_rewarded.emit(r)
	check(ClinicLifeManager.wall.size() == 1, "and only once")
	var dead := SurgeryResult.new()
	dead.failure_reason = &"flatline"
	dead.customer_name = "Lost One"
	EventBus.surgery_rewarded.emit(dead)
	check(ClinicLifeManager.wall.any(func(p: Dictionary) -> bool: return str(p["kind"]) == "loss" and str(p["title"]) == "Lost One"), "the dead get their name scratched in")
	FactionManager.add_heat(90.0)
	check(ClinicLifeManager.wall.any(func(p: Dictionary) -> bool: return str(p["kind"]) == "wanted"), "a wanted notice when heat runs high")
	var l := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(l)
	PeopleManager.change_rel(l.id, 80)
	check(ClinicLifeManager.has_pin("patient_%s" % l.id), "loyal regulars get a photo")
	for i in 40:
		ClinicLifeManager.pin("milestone", "n%d" % i)
	check(ClinicLifeManager.wall.size() <= 24 and ClinicLifeManager.wall.any(func(p: Dictionary) -> bool: return str(p["kind"]) == "loss"), "the wall has room limits; losses stay up")
	# Save/load.
	var w0 := ClinicLifeManager.wall.size()
	ClinicLifeManager.seat(CustomerManager.generator.generate({"full_difficulty": true}))
	var n_wait := ClinicLifeManager.waiting.size()
	check(SaveManager.save_game(), "clinic life saves")
	SaveManager.reset_all()
	check(SaveManager.load_game(), "clinic life loads")
	check(ClinicLifeManager.wall.size() == w0 and ClinicLifeManager.waiting.size() == n_wait, "wall and waiting room survive save/load")
	SaveManager.delete_save()
	GameManager.is_running = was_running


func _world_events() -> void:
	_fresh()
	BusinessManager.day = 10
	# Gang war: gunshot wounds and gangs at the door.
	var w0 := WorldEventManager.archetype_weight("gang_member")
	check(WorldEventManager.start(&"gang_war"), "a gang war starts")
	check(WorldEventManager.archetype_weight("gang_member") > w0 and WorldEventManager.event_weight(&"emergency_patient") > 1.0, "it bends who comes and what happens")
	check(WorldEventManager.news.any(func(n: Dictionary) -> bool: return str(n["headline"]).contains("Gang war")), "it makes the news")
	# Shortage: supplies cost more while it lasts.
	WorldEventManager.start(&"shortage")
	check(ModifierManager.value(&"price.buy") >= 0.3, "a port strike raises supply prices")
	for i in 6:
		BusinessManager.end_day()
	check(not WorldEventManager.is_active(&"shortage") and not WorldEventManager.is_active(&"gang_war"), "situations end after a few days")
	check(ModifierManager.value(&"price.buy") < 0.3, "and prices recover")
	check(WorldEventManager.news.any(func(n: Dictionary) -> bool: return str(n["headline"]).contains("Ceasefire")), "the end makes the news too")
	# Recall: your patients with that maker's chrome come back.
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.after_visit(c, "success", 100)
	var p := PeopleManager.get_person(c.id)
	p["cyber"] = ["kevlace_mesh"]
	p["next_day"] = -1
	var s := WorldEventManager.situation(&"recall")
	s["makers"] = ["Halden Microsystems"]
	WorldEventManager.start(&"recall")
	check(int(p["next_day"]) >= BusinessManager.day, "a recall sends your patients back")
	# Mass casualty: emergencies queue at the door.
	CustomerManager.queue.clear()
	WorldEventManager.start(&"mass_casualty")
	check(CustomerManager.queue.size() == 2, "a tram crash queues the wounded")
	var first := CustomerManager._next_customer()
	check(first != null and first.is_emergency, "and they come in as emergencies")
	CustomerManager.queue.clear()
	# Someone you know in trouble: a choice in COMMS.
	var friend := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.after_visit(friend, "success", 100)
	PeopleManager.change_rel(friend.id, 20)
	for k: String in PeopleManager.people.keys():
		if k != String(friend.id):
			PeopleManager.people.erase(k)
	var before := CommsManager.inbox.size()
	check(WorldEventManager.start(&"trouble") and CommsManager.inbox.size() == before + 1, "someone you know gets in trouble")
	var m: Dictionary = CommsManager.inbox[CommsManager.inbox.size() - 1]
	check(str(m["subject"]).contains(friend.display_name), "the message names them")
	CommsManager.act(int(m["uid"]), 1)
	check(not CustomerManager.queue.is_empty() and CustomerManager.queue[0]["customer"]["display_name"] == friend.display_name, "they're brought in as an emergency")
	check(MemoryManager.has(friend.id, &"PLAYER_SAVED_ME"), "and they remember you came through")
	CustomerManager.queue.clear()
	# District takeover favours a faction.
	WorldEventManager.start(&"district_shift")
	var shift: Dictionary = WorldEventManager.active.filter(func(a: Dictionary) -> bool: return str(a["id"]) == "district_shift")[0]
	check(WorldEventManager.faction_weight(StringName(str(shift["vars"]["faction_id"]))) > 1.0, "a takeover brings that faction to your door")
	# The wire reacts to you.
	WorldEventManager.deaths_today = 2
	var civ0 := ReputationManager.dim(&"civilian")
	WorldEventManager._on_day_ended(BusinessManager.day, {})
	check(WorldEventManager.news.any(func(n: Dictionary) -> bool: return bool(n["about_you"]) and str(n["headline"]).contains("Bodies")), "bodies piling up make the news")
	check(ReputationManager.dim(&"civilian") < civ0 and ClinicLifeManager.wall.any(func(x: Dictionary) -> bool: return str(x["kind"]) == "clipping"), "civilians hear, and the clipping goes on the wall")
	var n0 := WorldEventManager.news.size()
	WorldEventManager._on_day_ended(BusinessManager.day, {})
	check(WorldEventManager.news.size() == n0, "the same story doesn't run every night")
	# Random rolls start something real; filler keeps the wire alive.
	var started := ""
	for i in 30:
		WorldEventManager.active.clear()
		started = WorldEventManager.roll()
		if started != "":
			break
	check(started != "", "the city rolls its own situations (%s)" % started)
	var nn := WorldEventManager.news.size()
	BusinessManager.end_day()
	check(WorldEventManager.news.size() > nn or WorldEventManager.news.size() == WorldEventManager.MAX_NEWS, "there's news every day")
	# Save/load.
	var act := WorldEventManager.active.size()
	var nws := WorldEventManager.news.size()
	check(SaveManager.save_game(), "world saves")
	SaveManager.reset_all()
	check(SaveManager.load_game() and WorldEventManager.active.size() == act and WorldEventManager.news.size() == nws, "situations and news survive save/load")
	SaveManager.delete_save()
