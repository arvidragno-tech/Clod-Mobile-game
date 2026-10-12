extends RefCounted
## Living-world system tests (no UI): people, memory, psychology, finances,
## payment terms, debts, returning customers. Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
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
	_high_stakes()
	_suppliers()
	_threats()
	_narrative()
	_save_v5_migration()
	_followups()
	_audit_fixes()
	SaveManager.reset_all()
	WorldEventManager.auto_roll = true
	SecurityManager.auto_roll = true


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
	# A fixed seed: "variety" over 120 random patients sat right at the
	# threshold now and then. The generator's own state is restored after.
	var rng: RandomNumberGenerator = CustomerManager.generator.rng
	var rng_state := rng.state
	rng.seed = 3901
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
	rng.state = rng_state
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
	# 3.6: a shortfall goes on instalments automatically too.
	check(plans.size() == 2, "pay later sets up a payment plan (and so does a shortfall)")
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
	check(InventoryManager.supplies > s0 or s0 >= ClinicManager.get_supplies_capacity() or InventoryManager.parts > p0 or EconomyManager.money > m0 or not SupplierManager.discovered().is_empty(), "and it's worth something (supplies, parts, cash or a supplier lead)")


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
	var job := CustomerManager.generator.generate({"full_difficulty": true})
	var base_chance := EmployeeAI.success_chance(a, job)
	StaffLifeManager.change_rel(a, b, -110)
	check(StaffLifeManager.bond(a, b) == "resentful", "a grudge becomes resentment")
	check(StaffLifeManager.team_modifier(a) < 0.0, "resentment costs focus")
	check(EmployeeAI.success_chance(a, job) < base_chance or base_chance >= 0.97 or EmployeeAI.success_chance(a, job) <= 0.05, "team mood feeds job odds")
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


func _start_op(c: CustomerData) -> void:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	SurgeryManager.start_session(SurgeryManager.get_surgery(item.install_surgery_id), c, true, 1.0, 7, ImplantInstance.create(item.id))
	SurgeryManager.resume()


func _high_stakes() -> void:
	_fresh()
	EventManager.operations = 12
	# --- Surgical dilemmas -------------------------------------------------
	var c := CustomerManager.generator.generate({"full_difficulty": true, "category": "neural"})
	_start_op(c)
	check(SurgicalDilemmas.chance(SurgeryManager) > 0.0, "dilemmas can happen once you're past the basics")
	c.hidden_conditions.clear()
	c.is_emergency = false
	var calm_chance := SurgicalDilemmas.chance(SurgeryManager)
	c.is_emergency = true
	c.hidden_conditions.append(CustomerManager.conditions.keys()[0])
	check(SurgicalDilemmas.chance(SurgeryManager) > calm_chance, "riskier patients make dilemmas likelier")
	c.is_emergency = false
	check(SurgicalDilemmas.data()["dilemmas"].size() == 6, "six kinds of surgical dilemma")
	SurgeryManager.debug_trigger_dilemma(&"internal_bleeding")
	check(not SurgeryManager.active_dilemma.is_empty() and not SurgeryManager.is_running, "a dilemma stops the operation")
	SurgeryManager.resume()
	check(not SurgeryManager.is_running, "and nothing resumes it until you decide")
	InventoryManager.supplies = 0
	var pack: Dictionary = SurgeryManager.active_dilemma["choices"][1]
	check(SurgicalDilemmas.block_reason(pack) != "", "options you can't afford are blocked")
	check(SurgeryManager.resolve_dilemma(1).is_empty(), "and can't be chosen")
	InventoryManager.supplies = 10
	var r := SurgeryManager.resolve_dilemma(0)
	check(not r.is_empty() and SurgeryManager.active_dilemma.is_empty() and not SurgeryManager.is_running, "deciding keeps the patient frozen while you read the outcome")
	SurgeryManager.resume()
	check(SurgeryManager.is_running, "dismissing it resumes the operation")
	check(SurgeryManager.dilemma_notes.size() == 1, "the outcome is recorded for the report")
	# Stop safely.
	SurgeryManager.debug_trigger_dilemma(&"cyberware_instability")
	var finished := [null]
	var cb := func(res: SurgeryResult) -> void: finished[0] = res
	SurgeryManager.session_finished.connect(cb)
	SurgeryManager.resolve_dilemma(2)
	SurgeryManager.session_finished.disconnect(cb)
	check(finished[0] != null and (finished[0] as SurgeryResult).failure_reason == &"aborted" and not SurgeryManager.is_active, "STOP ends the operation with the patient alive")
	# Foreign device: what you pull out is yours.
	_start_op(CustomerManager.generator.generate({"full_difficulty": true, "category": "neural"}))
	SurgeryManager.debug_trigger_dilemma(&"foreign_device")
	var units := InventoryManager.get_instances().size()
	var choice: Dictionary = SurgeryManager.active_dilemma["choices"][0]
	choice["odds"] = 1.0
	SurgeryManager.resolve_dilemma(0)
	choice["odds"] = 0.55
	check(InventoryManager.get_instances().size() == units + 1, "extracting a foreign device puts it in your stash")
	# Calling an employee needs one on shift.
	SurgeryManager.debug_trigger_dilemma(&"nerve_damage")
	check(SurgicalDilemmas.block_reason(SurgeryManager.active_dilemma["choices"][1]) != "", "no ripperdoc on shift, no help")
	var e := StaffManager.generate_candidate()
	e["clinic"] = ClinicManager.tier
	StaffManager.employees.append(e)
	check(SurgicalDilemmas.block_reason(SurgeryManager.active_dilemma["choices"][1]) == "" and SurgicalDilemmas.odds(SurgeryManager, SurgeryManager.active_dilemma["choices"][1]) > 0.0, "with one on shift you can call them in")
	SurgeryManager.resolve_dilemma(1)
	SurgeryManager.abort()
	StaffManager.employees.clear()
	# Learning players never see them.
	EventManager.operations = 1
	check(SurgicalDilemmas.chance(SurgeryManager) == 0.0, "no dilemmas while learning")
	EventManager.operations = 12
	# --- Emergency triage --------------------------------------------------
	var em := CustomerManager.spawn_emergency()
	InventoryManager.supplies = 10
	var m0 := EconomyManager.money
	var jobs := BusinessManager.jobs_today
	var t0 := TimeManager.minute
	var st := GameManager.triage_stabilize()
	check(not st.is_empty() and EconomyManager.money > m0 and BusinessManager.jobs_today == jobs + 1 and TimeManager.minute > t0, "STABILISE: paid a little, a job done, time passes")
	check(MemoryManager.has(em.id, &"PLAYER_STABILIZED_ME") and int(PeopleManager.get_person(em.id)["next_day"]) > BusinessManager.day, "and they come back for the real job")
	check(not CustomerManager.has_customer(), "the door is free again")
	em = CustomerManager.spawn_emergency()
	EconomyManager.add_money(5000)
	var sp := GameManager.triage_specialist()
	check(not sp.is_empty() and (MemoryManager.has(em.id, &"PLAYER_SAVED_ME") or str(PeopleManager.get_person(em.id)["status"]) == "dead"), "a specialist saves them (or doesn't)")
	em = CustomerManager.spawn_emergency()
	InventoryManager.parts = 5
	var bleed := em.bleed_multiplier
	check(GameManager.triage_experimental() and em.bleed_multiplier < bleed and InventoryManager.parts == 2, "the experimental rig slows bleeding for parts")
	check(not GameManager.triage_experimental(), "only once")
	var prem := GameManager.premium_option(em)
	if prem:
		check(GameManager.triage_premium() and em.requested_cyberware_id == prem.id, "premium chrome swaps in the expensive unit")
	check(not GameManager.emergency_crash() and em.crashes == 1, "waiting too long: they crash")
	check(GameManager.emergency_crash() and str(PeopleManager.get_person(em.id)["status"]) == "dead" and not CustomerManager.has_customer(), "waiting longer: they die")
	# --- Dependency --------------------------------------------------------
	var d := CustomerManager.generator.generate({"full_difficulty": true, "category": "arms"})
	d.dependency = 2
	PeopleManager.register(d)
	PeopleManager.get_person(d.id)["dependency"] = 2
	CustomerManager.debug_set_customer(d)
	check(GameManager.set_care(&"profit") and d.care == &"feed" and d.terms == &"overcharge", "PROFIT: overcharge and feed it")
	var safer := GameManager.dependency_safer_option(d)
	if safer:
		check(GameManager.set_care(&"safer") and d.requested_cyberware_id == safer.id, "SAFER swaps to a lower-load unit")
	PeopleManager.dependency_choice(d, true)
	PeopleManager.dependency_choice(d, true)
	check(int(PeopleManager.get_person(d.id)["dependency"]) == 4 and StoryManager.pending.any(func(x: Dictionary) -> bool: return str(x["id"]) == "c_dependency_crisis"), "feeding it to the limit schedules a crisis")
	var dep := GameManager.dependency_stabilize()
	check(not dep.is_empty() and int(PeopleManager.get_person(d.id)["dependency"]) == 2 and MemoryManager.has(d.id, &"PLAYER_STABILIZED_ME"), "STABILISE eases the dependency")
	check(int(PeopleManager.get_person(d.id)["dependency"]) < 4, "dependency can be walked back")


func _suppliers() -> void:
	_fresh()
	StoryManager.set_flag(&"bm_access")
	check(SupplierManager.ids().size() == 6 and SupplierManager.discovered().is_empty(), "six contacts, none known at first")
	check(SupplierManager.data["categories"].size() == 10 and SupplierManager.data["grades"].size() == 7, "ten categories, seven grades")
	# Discovery through a customer of the right kind.
	var found := false
	for i in 80:
		var c := CustomerManager.generator.generate({"archetype": "scavenger", "full_difficulty": true})
		SupplierManager._on_customer_left(c)
		if bool(SupplierManager.st("magpie")["discovered"]):
			found = true
			break
	check(found and str(SupplierManager.st("magpie")["lead_from"]).begins_with("customer"), "a scavenger tells you about Magpie")
	check(not (SupplierManager.st("magpie")["stock"] as Array).is_empty(), "a new contact has stock")
	# Quest flag and faction standing open doors.
	SupplierManager._check_discovery()
	check(bool(SupplierManager.st("juno")["discovered"]), "black-market access brings the fixer")
	FactionManager.change(&"independent_mercs", 30)
	for i in 3:
		SupplierManager._check_discovery()
	check(bool(SupplierManager.st("okafor")["discovered"]), "merc standing gets you the quartermaster")
	check(SupplierManager.reveal_random_supplier_lead_text() != "" or SupplierManager.discovered().size() == 6, "favours can be repaid with a lead")
	# Buying: heat, trust, stock shrinks.
	var id := "magpie"
	SupplierManager._refresh(id)
	EconomyManager.add_money(20000)
	var n := (SupplierManager.st(id)["stock"] as Array).size()
	var t0 := int(SupplierManager.st(id)["trust"])
	var h0 := FactionManager.heat
	check(SupplierManager.buy(id, 0) != "", "buy from a supplier")
	check((SupplierManager.st(id)["stock"] as Array).size() == n - 1 and int(SupplierManager.st(id)["trust"]) > t0, "stock shrinks, trust grows")
	check(FactionManager.heat >= h0, "black-market buys carry heat")
	# Unlocks by trust: credit and rush.
	check(SupplierManager.buy_block_reason(id, 0, "credit") == "Needs more trust" or (SupplierManager.st(id)["stock"] as Array).is_empty(), "no credit for strangers")
	SupplierManager.change_trust(id, 60)
	SupplierManager._refresh(id)
	check(SupplierManager.has_unlock(id, "credit") and SupplierManager.has_unlock(id, "rush") and SupplierManager.has_unlock(id, "discount"), "trust unlocks credit, rush delivery and discounts")
	var price := SupplierManager.price_for(id, 0, "credit")
	var m0 := EconomyManager.money
	check(SupplierManager.buy(id, 0, "credit") != "" and EconomyManager.money == m0 and int(SupplierManager.st(id)["debt"]) == price, "buy on credit: nothing paid now")
	for i in 3:
		BusinessManager.record_job()
	check(int(SupplierManager.st(id)["debt"]) == 0 and EconomyManager.money == m0 - price, "credit is paid after three jobs")
	# Can't pay: suspicion, then cut off.
	SupplierManager._refresh(id)
	if not (SupplierManager.st(id)["stock"] as Array).is_empty():
		SupplierManager.buy(id, 0, "credit")
		EconomyManager.spend(EconomyManager.money)
		for i in 12:
			BusinessManager.record_job()
		check(SupplierManager.is_cut_off(id) or int(SupplierManager.st(id)["suspicion"]) >= 25, "unpaid credit makes them suspicious, then they cut you off")
	SupplierManager.cut_off(id, 3)
	check(SupplierManager.buy_block_reason(id, 0) != "" and (SupplierManager.st(id)["stock"] as Array).is_empty(), "cut off: no stock, no sales")
	# Grades and tools.
	var inst := ImplantInstance.create(&"kevlace_mesh", 90.0, &"black_market")
	inst.grade = &"military"
	var plain := ImplantInstance.create(&"kevlace_mesh", 90.0, &"black_market")
	check(inst.get_quality() > plain.get_quality(), "military grade performs better")
	var okafor := "okafor"
	EconomyManager.add_money(20000)
	var got_tool := false
	for i in 20:
		SupplierManager._refresh(okafor)
		var st: Array = SupplierManager.st(okafor)["stock"]
		for j in st.size():
			if str(st[j]["kind"]) == "tool" and SupplierManager.buy_block_reason(okafor, j) == "":
				var tid := StringName(str(st[j]["tool"]))
				SupplierManager.buy(okafor, j)
				check(not InventoryManager.owns_tool(tid), "a cash order isn't here yet")
				SupplierManager._on_day_started(BusinessManager.day)
				got_tool = InventoryManager.owns_tool(tid)
				break
		if got_tool:
			break
	check(got_tool, "restricted tools can be bought off the books")
	# Unknown tech: partial info, analyse, give to the specialist.
	var u := ImplantInstance.create(&"ghostlink_eye", 60.0, &"black_market")
	u.identified = false
	InventoryManager.add_instance(u)
	check(u.display_name() == "Unidentified device", "unidentified devices hide what they are")
	InventoryManager.parts = 5
	check(SupplierManager.identify(u.uid) and u.identified and InventoryManager.parts == 3, "ANALYSE identifies it")
	var u2 := ImplantInstance.create(&"ghostlink_eye", 60.0, &"black_market")
	u2.identified = false
	InventoryManager.add_instance(u2)
	SupplierManager.st("curator")["discovered"] = false
	check(SupplierManager.give_to_specialist(u2.uid) == 0, "no specialist until you know the Curator")
	SupplierManager.discover("curator", "test")
	var ct := int(SupplierManager.st("curator")["trust"])
	check(SupplierManager.give_to_specialist(u2.uid) > 0 and int(SupplierManager.st("curator")["trust"]) > ct, "the Curator pays and trusts you more")
	# Favours through COMMS.
	var uid := SupplierManager.ask_favor("juno", "store")
	var tj := int(SupplierManager.st("juno")["trust"])
	check(uid >= 0 and CommsManager.act(uid, 0), "a favour request can be accepted from COMMS")
	check(int(SupplierManager.st("juno")["trust"]) > tj and SupplierManager.contraband.size() == 1, "storing their crate builds trust (and keeps contraband in your stash)")
	for i in 5:
		BusinessManager.end_day()
	check(SupplierManager.contraband.is_empty(), "they collect it after a few days")
	uid = SupplierManager.ask_favor("juno", "secret")
	var sj := int(SupplierManager.st("juno")["suspicion"])
	CommsManager.act(uid, 1)
	check(int(SupplierManager.st("juno")["suspicion"]) > sj, "refusing some favours makes them suspicious")
	# Dynamic: prices drift, night and heat change stock.
	var d0 := float(SupplierManager.st("juno")["price_drift"])
	BusinessManager.end_day()
	check(float(SupplierManager.st("juno")["price_drift"]) != d0, "prices drift day to day")
	# Save/load.
	check(SaveManager.save_game(), "suppliers save")
	var trust_j := int(SupplierManager.st("juno")["trust"])
	SaveManager.reset_all()
	check(SaveManager.load_game() and int(SupplierManager.st("juno")["trust"]) == trust_j and bool(SupplierManager.st("curator")["discovered"]), "supplier relationships survive save/load")
	var back := InventoryManager.get_instance(u.uid)
	check(back != null and back.identified, "implant identity survives save/load")
	SaveManager.delete_save()


func _threats() -> void:
	_fresh()
	# Heat levels.
	check(SecurityManager.level(0.0)["label"] == "LOW", "heat 0 is LOW")
	check(SecurityManager.level(30.0)["label"] == "MEDIUM" and SecurityManager.level(60.0)["label"] == "HIGH" and SecurityManager.level(80.0)["label"] == "CRITICAL", "MEDIUM, HIGH, CRITICAL")
	# Theft takes something real and opens a case.
	EconomyManager.add_money(2000)
	var m0 := EconomyManager.money
	var units := InventoryManager.get_instances().size()
	var sup := InventoryManager.supplies
	var parts := InventoryManager.parts
	var c := SecurityManager.roll_theft(true)
	check(not c.is_empty() and str(c["status"]) == "open", "a break-in opens a case")
	var lost := EconomyManager.money < m0 or InventoryManager.get_instances().size() < units or InventoryManager.supplies < sup or InventoryManager.parts < parts or str(c["loot"]["kind"]) in ["data", "belongings", "equipment"]
	check(lost, "something is actually gone (%s)" % c["loot_text"])
	check(CommsManager.inbox.any(func(m: Dictionary) -> bool: return str(m["template"]) == "theft"), "you're told")
	# Security makes it rarer.
	var risk0 := SecurityManager.theft_chance()
	ClinicManager.upgrades[ClinicManager.clinic_id()] = {"security": 2}
	check(SecurityManager.theft_chance() < risk0, "security upgrades lower the risk")
	# Investigation tools.
	var id := int(c["id"])
	check(SecurityManager.can_use(id, "cameras") == "", "cameras need security (installed)")
	var clue := SecurityManager.investigate(id, "cameras")
	check(clue.begins_with("Footage"), "cameras give a clue")
	check(SecurityManager.investigate(id, "cameras") == "", "once per case")
	EconomyManager.add_money(500)
	check(SecurityManager.investigate(id, "ask") != "", "asking around gives a clue (for a price)")
	var sus := SecurityManager.suspects(id)
	check(sus.size() >= 2, "there are suspects to confront")
	var right := SecurityManager._culprit_key(c)
	check(sus.any(func(s: Dictionary) -> bool: return str(s["key"]) == right), "the real culprit is among them")
	var r := SecurityManager.confront(id, right)
	check(bool(r["right"]) and str(SecurityManager.get_case(id)["status"]) == "solved", "confronting the right one solves it")
	# Accusing an innocent employee costs loyalty.
	var e := StaffManager.generate_candidate()
	e["clinic"] = ClinicManager.tier
	e["loyalty"] = 60.0
	StaffManager.employees.append(e)
	var c2 := SecurityManager.roll_theft(true)
	if not c2.is_empty() and SecurityManager._culprit_key(c2) != "staff:%s" % e["id"]:
		SecurityManager.confront(int(c2["id"]), "staff:%s" % e["id"])
		check(float(e["loyalty"]) <= 45.0 and MemoryManager.has(StringName(str(e["id"])), &"PLAYER_LIED"), "a false accusation hurts an innocent employee")
	# A desperate employee is a likely thief.
	StaffManager.employees.clear()
	var d := StaffManager.generate_candidate()
	d["clinic"] = ClinicManager.tier
	StaffLifeManager.ensure_life(d)
	d["life"]["desperate"] = true
	StaffManager.employees.append(d)
	var by_staff := 0
	for i in 30:
		EconomyManager.add_money(500)
		var cc := SecurityManager.roll_theft(true)
		if not cc.is_empty() and str(cc["culprit"]["kind"]) == "employee":
			by_staff += 1
	check(by_staff >= 4, "desperate staff steal (%d/30)" % by_staff)
	StaffManager.employees.clear()
	# Pressure at HIGH: cooperating names names.
	var person := CustomerManager.generator.generate({"full_difficulty": true, "faction": "street_gangs"})
	person.faction_id = &"street_gangs"
	PeopleManager.after_visit(person, "success", 100)
	SupplierManager.discover("magpie", "test")
	var susp0 := int(SupplierManager.st("magpie")["suspicion"])
	SecurityManager.roll_pressure("high")
	var msg: Dictionary = CommsManager.inbox[CommsManager.inbox.size() - 1]
	check(str(msg["template"]) == "heat_high" and (msg["actions"] as Array).size() == 3, "HIGH heat: an interrogation with three answers")
	FactionManager.heat = 55.0
	CommsManager.act(int(msg["uid"]), 0)
	check(FactionManager.heat < 55.0 and int(SupplierManager.st("magpie")["suspicion"]) > susp0, "cooperating cools heat; suppliers hear about it")
	check(MemoryManager.has(person.id, &"PLAYER_BETRAYED_FACTION"), "the crews you named remember")
	# CRITICAL: confiscation.
	var bm := ImplantInstance.create(&"ghostlink_eye", 70.0, &"black_market")
	InventoryManager.add_instance(bm)
	SupplierManager.contraband.append({"supplier": "magpie", "days_left": 3})
	SecurityManager.roll_pressure("critical")
	msg = CommsManager.inbox[CommsManager.inbox.size() - 1]
	CommsManager.act(int(msg["uid"]), 0)
	check(InventoryManager.get_instance(bm.uid) == null and SupplierManager.contraband.is_empty(), "handing it over: black-market stock and contraband are seized")
	# Nightly notes reach the day report.
	var report := {"notes": []}
	EconomyManager.add_money(500)
	var forced := false
	SecurityManager.auto_roll = true
	for i in 40:
		SecurityManager._on_day_ended(BusinessManager.day, report)
		if (report["notes"] as Array).any(func(n: String) -> bool: return n.begins_with("Break-in")):
			forced = true
			break
	SecurityManager.auto_roll = false
	check(forced, "break-ins show up in the night's report")
	# Save/load.
	var n_cases := SecurityManager.cases.size()
	check(SaveManager.save_game(), "security saves")
	SaveManager.reset_all()
	check(SaveManager.load_game() and SecurityManager.cases.size() == n_cases, "cases survive save/load")
	SaveManager.delete_save()


func _narrative() -> void:
	_fresh()
	# Identity from behaviour, not a class pick.
	check(ReputationManager.identity()["id"] == "nobody", "nobody yet at the start")
	ReputationManager.change_dim(&"criminal", 25)
	check(ReputationManager.identity()["id"] == "gang_doc", "crew work makes you the gang doc")
	check(ReputationManager.archetype_weight("gang_member") > 1.0 and ReputationManager.archetype_weight("corporate") < 1.0, "gangs come, suits stay away")
	check(ReputationManager.heat_gain_mult() > 1.0, "and you draw more heat")
	var h0 := FactionManager.heat
	FactionManager.add_heat(10.0)
	check(FactionManager.heat - h0 > 10.0, "heat gain is scaled by your reputation")
	var report := {"notes": []}
	WorldEventManager._on_day_ended(BusinessManager.day, report)
	check((report["notes"] as Array).any(func(n: String) -> bool: return n.contains("GANG DOC")), "the street's new name for you is in the night report")
	check(WorldEventManager.news.any(func(n: Dictionary) -> bool: return bool(n["about_you"]) and str(n["headline"]).contains("gang doc")), "and in the news")
	ReputationManager.change_dim(&"criminal", -25)
	ReputationManager.change_dim(&"civilian", 25)
	ReputationManager.change_dim(&"medical", 12)
	check(ReputationManager.identity()["id"] == "saint", "charity and care make you the saint of the Sump")
	# The emergent chain: grateful patient -> gang-linked referral.
	var c := CustomerManager.generator.generate({"full_difficulty": true, "faction": "independent_mercs"})
	c.faction_id = &"independent_mercs"
	PeopleManager.register(c)
	PeopleManager.change_rel(c.id, 50)
	var gang := 0
	for i in 30:
		if PeopleManager.referral(c).faction_id == &"street_gangs":
			gang += 1
	check(gang >= 3, "grateful patients sometimes send friends who run with a crew (%d/30)" % gang)
	# Staff react to a gang clientele.
	ReputationManager.change_dim(&"criminal", 20)
	var e := StaffManager.generate_candidate()
	e["clinic"] = ClinicManager.tier
	e["ethics"] = ["no_harvest"]
	StaffManager.employees.append(e)
	StaffLifeManager.ensure_life(e)
	var ev := StaffLifeManager.get_event(&"gang_clients")
	check(StaffLifeManager._single_ok(e, ev["cond"]), "staff with principles notice the crew colours")
	var uid := StaffLifeManager.fire(&"gang_clients", e)
	CommsManager.act(uid, 2)
	check(ReputationManager.dim(&"criminal") < 20 + 0 or ReputationManager.dim(&"criminal") <= 15, "turning the crews away costs criminal standing")
	# Investigation becomes likelier when you're gang-linked.
	ReputationManager.change_dim(&"criminal", 40)
	FactionManager.heat = 40.0
	var inv := 0
	for i in 60:
		WorldEventManager.active.clear()
		if WorldEventManager.roll() == "investigation":
			inv += 1
	check(inv >= 10, "a gang-linked clinic draws MedBoard inquiries (%d/60)" % inv)
	WorldEventManager.active.clear()
	# Military chrome stolen by staff -> a quest, solved by confronting them.
	StaffManager.employees.clear()
	var thief := StaffManager.generate_candidate()
	thief["clinic"] = ClinicManager.tier
	thief["loyalty"] = 10.0
	StaffManager.employees.append(thief)
	for x in InventoryManager.get_instances():
		InventoryManager.remove_instance(x.uid)
	InventoryManager.add_instance(ImplantInstance.create(&"unknown_military_core", 80.0, &"black_market"))
	EconomyManager.spend(maxi(0, EconomyManager.money - 30))
	InventoryManager.supplies = 0
	InventoryManager.parts = 0
	var cs := {}
	for i in 40:
		cs = SecurityManager.roll_theft(true)
		if not cs.is_empty() and str(cs["culprit"]["kind"]) == "employee" and str(cs["loot"]["kind"]) == "cyberware":
			break
		if not cs.is_empty() and str(cs["loot"]["kind"]) == "cyberware":
			SecurityManager._recover(cs)
		cs = {}
	if not cs.is_empty():
		check(QuestManager.is_active(&"q_inside_job"), "chrome walking out with staff starts INSIDE JOB")
		SecurityManager.confront(int(cs["id"]), SecurityManager._culprit_key(cs))
		check(QuestManager.state_of(&"q_inside_job") == "completed", "confronting the thief completes it")
		check(InventoryManager.get_instances().any(func(x: ImplantInstance) -> bool: return x.cyberware_id == &"unknown_military_core"), "and the chrome comes back")
	else:
		check(false, "could not stage an inside theft")
	# Reactive audio: calm late night is muffled; danger opens it up.
	FactionManager.heat = 0.0
	SecurityManager.cases.clear()
	CustomerManager.dismiss_current()
	TimeManager.minute = 1560
	AudioManager.update_tension()
	var calm := AudioManager.music_cutoff()
	check(calm < 5000.0, "the small hours are muffled (%d Hz)" % roundi(calm))
	FactionManager.heat = 80.0
	CustomerManager.spawn_emergency()
	AudioManager.update_tension()
	check(AudioManager.tension > 0.5 and AudioManager.music_cutoff() > calm, "danger raises tension and opens the music")
	check(float(AudioManager._mix_mods[&"tension"]["pump"]) > 1.3, "the machinery pushes forward")
	FactionManager.heat = 0.0
	CustomerManager.dismiss_current()


## A v4 save (before the living world) loads: new systems start fresh and
## the old clinic log becomes people you've met.
func _save_v5_migration() -> void:
	_fresh()
	var r := SurgeryResult.new()
	r.success = true
	r.grade = "B"
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	CustomerManager.record_outcome(c, r)
	EconomyManager.add_money(777)
	var money := EconomyManager.money
	check(SaveManager.save_game(), "save for migration")
	var data: Dictionary = SaveManager._read_save(SaveManager.save_path)
	check(not data.is_empty(), "save readable")
	data["version"] = 4
	for k: String in ["MemoryManager", "PeopleManager", "StaffLifeManager", "TimeManager", "ClinicLifeManager", "WorldEventManager", "SupplierManager", "SecurityManager"]:
		(data["systems"] as Dictionary).erase(k)
	var migrated := SaveManager._migrate(data)
	check(int(migrated["version"]) == 5, "v4 migrates to v5")
	check((migrated["systems"] as Dictionary).has("PeopleManager") and (migrated["systems"]["PeopleManager"]["people"] as Dictionary).has(String(c.id)), "old patients become people you've met")
	SaveManager.reset_all()
	for name in SaveManager.SAVEABLE_SYSTEMS:
		var node := SaveManager._get_system(name)
		node.call("load_save_data", (migrated["systems"] as Dictionary).get(name, {}))
	check(EconomyManager.money == money and TimeManager.minute == TimeManager.open_minute(), "old progress kept; the clock starts at opening")
	check(PeopleManager.has_person(c.id), "the old patient is known")
	PeopleManager.get_person(c.id)["next_day"] = BusinessManager.day
	var back := PeopleManager.make_customer(c.id)
	check(back != null and not back.appearance.is_empty(), "and can walk back in with a face")
	SaveManager.delete_save()


func _followups() -> void:
	_fresh()
	# 1. Unidentified devices stay unknown until analysed or installed.
	var c := CustomerManager.generator.generate({"full_difficulty": true, "category": "eyes"})
	c.risk_tolerance = 0.5
	CustomerManager.debug_set_customer(c)
	var u := ImplantInstance.create(c.requested_cyberware_id, 70.0, &"black_market")
	u.identified = false
	check(not GameManager.customer_accepts(u), "a cautious patient won't take an unidentified device")
	c.risk_tolerance = 0.9
	check(GameManager.customer_accepts(u), "a reckless one will")
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	SurgeryManager.start_session(SurgeryManager.get_surgery(item.install_surgery_id), c, true, 1.0, 3, u)
	var res := [null]
	var cb := func(r: SurgeryResult) -> void: res[0] = r
	SurgeryManager.session_finished.connect(cb)
	SurgeryManager.abort()
	SurgeryManager.session_finished.disconnect(cb)
	check(u.identified and (res[0] as SurgeryResult).implant_name.contains("blind"), "installing blind reveals what it was")
	CustomerManager.dismiss_current()
	# 2. Every clinic has its own wall space and waiting spots, inside the room.
	var ok := true
	for i in ClinicManager.tiers.size():
		var t := ClinicManager.get_tier_data(i)
		var w: Dictionary = t.get("wall", {})
		var bg := load(str(t.get("background", ""))) as Texture2D
		var room := Vector2(bg.get_size()) if bg else Vector2(600, 336)
		ok = ok and w.has("x") and int(w["x"]) + int(w["cols"]) * ClinicView.WALL_CELL.x <= room.x and int(w["y"]) + ClinicView.WALL_CELL.y * 3 <= room.y
		ok = ok and (t.get("waiting_feet", []) as Array).size() >= 2
		for f: Array in t.get("waiting_feet", []):
			ok = ok and float(f[0]) < room.x and float(f[1]) < room.y
	check(ok, "all seven clinics define wall space and waiting spots inside the room")
	# 3. Time pressure setting.
	var tp0 := Settings.time_pressure
	Settings.time_pressure = 1
	check(Settings.time_pressure_mult() == 2.0, "RELAXED doubles the emergency countdown")
	Settings.time_pressure = 2
	check(Settings.time_pressure_mult() == 0.0, "OFF removes it")
	Settings.time_pressure = tp0
	# 5. The clinic score follows the night and the tension.
	AudioManager.set_profile(&"menu")
	FactionManager.heat = 0.0
	SecurityManager.cases.clear()
	TimeManager.minute = 700
	AudioManager.update_tension()
	AudioManager.set_profile(&"clinic")
	check(AudioManager.current_music() == &"clinic", "daytime clinic score")
	TimeManager.minute = 1400
	AudioManager.update_tension()
	check(AudioManager.current_music() == &"clinic_night", "a sparser score at night")
	FactionManager.heat = 80.0
	CustomerManager.spawn_emergency()
	AudioManager.update_tension()
	check(AudioManager.current_music() == &"clinic_tension", "the tense score when things go wrong")
	FactionManager.heat = 50.0
	CustomerManager.dismiss_current()
	AudioManager.update_tension()
	check(AudioManager.current_music() == &"clinic_tension" or AudioManager.tension < 0.3, "it doesn't flap at the threshold (hysteresis)")
	FactionManager.heat = 0.0
	AudioManager.update_tension()
	check(AudioManager.current_music() == &"clinic_night", "and calms down again")
	for id: StringName in [&"clinic_night", &"clinic_tension"]:
		check(ResourceLoader.exists(AudioManager.MUSIC_PATHS[id]), "%s track exists" % id)
	AudioManager.set_profile(&"menu")
	# 6. Conversations know who you've become and what they remember.
	ReputationManager.reset_state()
	DialogueManager.start(&"d_mother_protection")
	var plain := DialogueManager.node_text(DialogueManager.current_node())
	ReputationManager.change_dim(&"criminal", 25)
	check(DialogueManager.node_text(DialogueManager.current_node()) != plain and DialogueManager.node_text(DialogueManager.current_node()).contains("crews already call you"), "Mother greets the gang doc differently")
	DialogueManager.choose(0)
	check(DialogueManager.options().any(func(o: Dictionary) -> bool: return str(o["text"]).contains("colours")), "and a gang doc gets a new option")
	DialogueManager.end()
	ReputationManager.change_dim(&"criminal", -25)
	DialogueManager.start(&"d_mother_protection")
	DialogueManager.choose(0)
	check(not DialogueManager.options().any(func(o: Dictionary) -> bool: return str(o["text"]).contains("colours")), "which is hidden otherwise")
	DialogueManager.end()
	# Memories change odds and lines.
	DialogueManager.start(&"d_teo_crossroads")
	var lie := {"kind": "lie"}
	var p0 := DialogueManager.chance(lie)
	MemoryManager.remember(&"teo_marr", &"PLAYER_LIED")
	check(DialogueManager.chance(lie) < p0, "a remembered lie makes the next one harder")
	MemoryManager.remember(&"teo_marr", &"PLAYER_SAVED_EMPLOYEE")
	check(DialogueManager.node_text(DialogueManager.current_node()).contains("paid"), "Teo remembers you paid his debt")
	DialogueManager.end()
	# Every authored option points at a node that exists.
	var broken: Array[String] = []
	for did: Variant in DialogueManager.dialogues:
		var nodes: Dictionary = DialogueManager.dialogues[did].get("nodes", {})
		for nid: Variant in nodes:
			var n: Dictionary = nodes[nid]
			for key: String in ["next"]:
				if n.has(key) and not nodes.has(str(n[key])):
					broken.append("%s/%s" % [did, nid])
			for o: Variant in n.get("options", []):
				for key: String in ["next", "fail_next"]:
					if (o as Dictionary).has(key) and not nodes.has(str(o[key])):
						broken.append("%s/%s->%s" % [did, nid, o[key]])
	check(broken.is_empty(), "dialogue graphs are intact %s" % [broken])


## Regression tests for the bugs found in the code audit.
func _audit_fixes() -> void:
	_fresh()
	# Terms memories only when paid treatment happened.
	var c := CustomerManager.generator.generate({"full_difficulty": true})
	c.terms = &"free"
	PeopleManager.after_visit(c, "refused")
	check(not MemoryManager.has(c.id, &"PLAYER_TREATED_FREE"), "refusing a FREE patient isn't remembered as free treatment")
	PeopleManager.after_visit(c, "deferred")
	check(not MemoryManager.has(c.id, &"PLAYER_TREATED_FREE"), "nor is deferring them")
	PeopleManager.after_visit(c, "success", 0)
	check(MemoryManager.has(c.id, &"PLAYER_TREATED_FREE"), "treating them is")
	# The dead don't pay.
	var d := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(d)
	var debt := PeopleManager.add_debt(d.id, 400, "test")
	PeopleManager.set_plan(int(debt["id"]))
	PeopleManager.after_visit(d, "death")
	var m0 := EconomyManager.money
	for i in 4:
		BusinessManager.end_day()
	check(PeopleManager.owed_by(d.id) == 0 and str(PeopleManager.get_debt(int(debt["id"]))["status"]) == "deceased" and EconomyManager.money <= m0, "a dead patient's debt closes and stops paying")
	check(PeopleManager.demand(int(debt["id"])) == 0, "and can't be demanded")
	# Specialist: one PLAYER_SAVED_ME, not two.
	var em := CustomerManager.spawn_emergency()
	EconomyManager.add_money(5000)
	var saved := false
	for i in 20:
		var r := GameManager.triage_specialist()
		if bool(r.get("success", false)):
			saved = true
			break
		em = CustomerManager.spawn_emergency()
	if saved:
		check(MemoryManager.count(em.id, &"PLAYER_SAVED_ME") == 1, "the specialist save is remembered once")
	# First-time patients: dilemma memories move the relationship.
	var f := CustomerManager.generator.generate({"full_difficulty": true, "category": "neural"})
	var item := CyberwareManager.get_cyberware(f.requested_cyberware_id)
	SurgeryManager.start_session(SurgeryManager.get_surgery(item.install_surgery_id), f, true, 1.0, 5, ImplantInstance.create(item.id))
	SurgeryManager.debug_trigger_dilemma(&"foreign_device")
	var ch: Dictionary = SurgeryManager.active_dilemma["choices"][0]
	ch["odds"] = 1.0
	SurgeryManager.resolve_dilemma(0)
	ch["odds"] = 0.55
	check(PeopleManager.has_person(f.id) and int(PeopleManager.get_person(f.id)["rel"]) < 0, "a first-timer you robbed on the table resents it")
	# A choice with no failure outcome always succeeds.
	SurgeryManager.resume()
	SurgeryManager.debug_trigger_dilemma(&"nerve_damage")
	var lower: Dictionary = SurgeryManager.active_dilemma["choices"][2]
	lower["odds"] = 0.0
	check(bool(SurgeryManager.resolve_dilemma(2)["success"]), "a safe choice can't 'go wrong'")
	lower["odds"] = 0.95
	SurgeryManager.resume()
	# Stopping before the implant goes in returns it to stock.
	var stop_c := CustomerManager.generator.generate({"full_difficulty": true, "category": "dermal"})
	SurgeryManager.abort()
	CustomerManager.debug_set_customer(stop_c)
	var it2 := CyberwareManager.get_cyberware(stop_c.requested_cyberware_id)
	InventoryManager.add_instance(ImplantInstance.create(it2.id))
	GameManager.chosen_diagnosis_id = stop_c.true_diagnosis_id
	GameManager.diagnosis_correct = true
	for t in it2.get_tool_requirements():
		for tool: ToolData in InventoryManager.tool_catalog.values():
			if tool.category == StringName(str(t["category"])) and tool.tier >= int(t["tier"]) and not InventoryManager.owns_tool(tool.id):
				InventoryManager.owned_tools.append(tool.id)
				break
	for cat in SurgeryManager.get_surgery(it2.install_surgery_id).get_required_tool_categories():
		if not InventoryManager.has_tool_category(cat):
			for tool: ToolData in InventoryManager.tool_catalog.values():
				if tool.category == cat:
					InventoryManager.owned_tools.append(tool.id)
					break
	stop_c.risk_tolerance = 1.0
	var units := InventoryManager.get_instances().filter(func(x: ImplantInstance) -> bool: return x.cyberware_id == it2.id).size()
	GameManager.begin_surgery()
	check(SurgeryManager.is_active, "operation starts for the stop test %s" % [GameManager.get_surgery_readiness()])
	SurgeryManager.debug_trigger_dilemma(&"cyberware_instability")
	SurgeryManager.resolve_dilemma(2)
	await_free()
	check(InventoryManager.get_instances().filter(func(x: ImplantInstance) -> bool: return x.cyberware_id == it2.id).size() == units, "stopping before the implant goes in returns it to stock")
	CustomerManager.dismiss_current()
	# Waiting-room complaint makes people leave sooner, not later.
	ClinicLifeManager.waiting.clear()
	var w := CustomerManager.generator.generate({"full_difficulty": true})
	ClinicLifeManager.waiting.append({"customer": w, "since": 600})
	ClinicLifeManager._apply({"patience": -10})
	check(int(ClinicLifeManager.waiting[0]["since"]) < 600, "a complaint eats patience")
	ClinicLifeManager.waiting.clear()
	# Rivalry XP.
	var a := StaffManager.generate_candidate()
	var b := StaffManager.generate_candidate()
	a["clinic"] = ClinicManager.tier
	b["clinic"] = ClinicManager.tier
	a["relationships"][str(b["id"])] = 0
	b["relationships"][str(a["id"])] = 0
	StaffManager.employees.append(a)
	StaffManager.employees.append(b)
	var xp0 := int(a["xp"]) + int(a["skill"]) * 1000
	StaffLifeManager.apply_staff({"bond": "competitive", "xp": 30}, {"a": str(a["id"]), "b": str(b["id"])})
	check(int(a["xp"]) + int(a["skill"]) * 1000 > xp0, "a rivalry sharpens both of them")
	StaffManager.employees.clear()
	check(CommsManager.templates.has("fired_grudge"), "a fired employee's grudge has somewhere to land")
	# Trimming keeps favours and returns; memories go with the person.
	var fav := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.register(fav)
	PeopleManager.get_person(fav.id)["favor"] = true
	PeopleManager.get_person(fav.id)["rel"] = 0
	for i in PeopleManager.MAX_PEOPLE + 5:
		var x := CustomerManager.generator.generate({"full_difficulty": true})
		PeopleManager.register(x)
		MemoryManager.remember(x.id, &"PLAYER_MADE_ME_WAIT")
	check(PeopleManager.has_person(fav.id), "someone who owes you a favour is never forgotten")
	check(MemoryManager.memories.size() <= PeopleManager.people.size() + 30, "forgotten people take their memories with them")
	# Backers survive a change in wealth.
	var cr := CustomerManager.generator.generate({"full_difficulty": true})
	PeopleManager.after_visit(cr, "success", 10)
	var pc := PeopleManager.get_person(cr.id)
	pc["finance"] = "criminal"
	for i in 30:
		pc["last_day"] = BusinessManager.day - 30
		PeopleManager.make_customer(cr.id)
	check(str(pc["finance"]) == "criminal", "crew money stays crew money")
	# Confiscation takes all the black-market chrome.
	for x in InventoryManager.get_instances().duplicate():
		InventoryManager.remove_instance(x.uid)
	for i in 3:
		InventoryManager.add_instance(ImplantInstance.create(&"ghostlink_eye", 60.0, &"black_market"))
	InventoryManager.add_instance(ImplantInstance.create(&"kevlace_mesh"))
	SecurityManager.confiscate()
	check(InventoryManager.get_instances().size() == 1 and InventoryManager.get_instances()[0].source != &"black_market", "confiscation takes every unregistered unit, nothing else")
	# No paying twice for a tool you own.
	StoryManager.set_flag(&"bm_access")
	SupplierManager.discover("okafor", "test")
	var stock: Array = SupplierManager.st("okafor")["stock"]
	stock.clear()
	var owned_id: StringName = InventoryManager.owned_tools[0]
	stock.append({"kind": "tool", "tool": String(owned_id), "category": "rare_tools", "grade": "professional", "price": 100})
	check(SupplierManager.buy_block_reason("okafor", 0) == "You already have one", "you can't buy a tool you already own")
	# Night brings more stock.
	SupplierManager.st("okafor")["stock"] = []
	SupplierManager.st("sallow")["discovered"] = true
	SupplierManager.st("sallow")["stock"] = []
	SupplierManager._on_period_changed(&"night")
	check((SupplierManager.st("sallow")["stock"] as Array).size() >= 2, "night contacts bring out more")
	# Rush is now; cash is tomorrow.
	EconomyManager.add_money(50000)
	SupplierManager.st("sallow")["trust"] = 60
	var n_sup := InventoryManager.supplies
	InventoryManager.supplies = 0
	(SupplierManager.st("sallow")["stock"] as Array).insert(0, {"kind": "supplies", "amount": 4, "category": "illegal_pharma", "grade": "used", "price": 50})
	SupplierManager.buy("sallow", 0, "rush")
	check(InventoryManager.supplies == 4, "RUSH delivers right away")
	(SupplierManager.st("sallow")["stock"] as Array).insert(0, {"kind": "supplies", "amount": 3, "category": "illegal_pharma", "grade": "used", "price": 50})
	SupplierManager.buy("sallow", 0, "cash")
	check(InventoryManager.supplies == 4 and SupplierManager.deliveries.size() == 1, "a cash order waits for the morning run")
	SupplierManager._on_day_started(BusinessManager.day)
	check(InventoryManager.supplies == 7 and SupplierManager.deliveries.is_empty(), "and arrives at opening")
	InventoryManager.supplies = n_sup
	# Getting hurt in a fight costs you steady hands.
	var prec := ModifierManager.value(&"surgery.precision")
	StoryManager.apply_effects({"appearance_player": "injury"})
	check(ModifierManager.value(&"surgery.precision") < prec, "an injury really makes your hands worse")
	# Teo caught stealing is gone for good.
	var teo := StaffManager.cast_candidate(StaffManager.TEO)
	if not teo.is_empty():
		teo["clinic"] = ClinicManager.tier
		StaffManager.employees.append(teo)
		var cs := {"id": 999, "day": BusinessManager.day, "loot": {"kind": "belongings", "text": "x"}, "loot_text": "x",
			"culprit": {"kind": "employee", "id": str(teo["id"]), "name": str(teo["name"])}, "clues": [], "used": [], "status": "open", "outcome": ""}
		SecurityManager.cases.append(cs)
		SecurityManager.confront(999, "staff:%s" % teo["id"])
		check(StoryManager.has_flag(&"teo_gone"), "Teo caught stealing is gone from the story")
	# The emergency countdown lives on the patient, not the screen.
	var e2 := CustomerManager.spawn_emergency()
	var left := CustomerManager.emergency_seconds_left()
	e2.emergency_deadline -= 30000
	check(absf(CustomerManager.emergency_seconds_left() - (left - 30.0)) < 0.01, "time spent away from the file still counts")


func await_free() -> void:
	pass
