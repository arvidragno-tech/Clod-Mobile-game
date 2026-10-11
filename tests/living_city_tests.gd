extends RefCounted
## Living city tests (no UI): locations, discovery, hours, travel, NPC
## routines, day/night states, ambient events, factions, black-market
## integration, services, the missing-patient chain, encounters, save/load.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	WorldSimulationManager.auto_roll = false
	_registry()
	_discovery()
	_hours_and_states()
	_travel()
	_away_from_clinic()
	_routines()
	_cast_and_staff()
	_events()
	_factions()
	_black_market()
	_services()
	_restricted()
	_missing_chain()
	_encounters()
	_talk()
	_save_roundtrip()
	_soak()
	SaveManager.reset_all()
	WorldEventManager.auto_roll = true
	SecurityManager.auto_roll = true
	WorldSimulationManager.auto_roll = true


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _fresh() -> void:
	SaveManager.reset_all()
	EventManager.operations = 8
	TimeManager.minute = 600
	WorldSimulationManager.refresh()


func _at(m: int) -> void:
	TimeManager.minute = m
	WorldSimulationManager.refresh()


## A treated patient with a given archetype/faction/wealth.
func _patient(archetype: String, faction: String = "street_gangs", wealth: int = 0) -> StringName:
	var c := CustomerManager.generator.generate({"archetype": archetype, "faction": faction})
	c.wealth = wealth
	PeopleManager.after_visit(c, "success", 100)
	return c.id


func _registry() -> void:
	_fresh()
	check(LocationManager.order.size() >= 10 and LocationManager.order.size() <= 18, "a handful of places, not dozens (%d)" % LocationManager.order.size())
	var types := {}
	var ok := true
	var bad: Array[String] = []
	for id in LocationManager.order:
		var l := LocationManager.get_location(id)
		types[str(l["type"])] = true
		if id != LocationManager.CLINIC and not WorldManager.districts.has(StringName(str(l["district"]))):
			bad.append("%s district" % id)
		for s: Variant in l.get("services", []):
			if not LocationServices.DEFS.has(str(s)):
				bad.append("%s service %s" % [id, s])
		for e: Variant in l.get("events", []):
			if not WorldSimulationManager._events_by_id.has(str(e)):
				bad.append("%s event %s" % [id, e])
		var m := LocationManager.map_pos(id)
		if m.x < 0.0 or m.x > 1.0 or m.y < 0.0 or m.y > 1.0:
			bad.append("%s map" % id)
		for k in ["description", "hours", "activity"]:
			if not l.has(k):
				bad.append("%s missing %s" % [id, k])
	check(bad.is_empty(), "every place is complete and points at real districts/services/events %s" % str(bad))
	for ty in ["clinic", "night_market", "black_market", "bar", "industrial", "corporate", "residential", "transit", "restricted"]:
		ok = ok and types.has(ty)
	check(ok, "all nine kinds of place exist")
	var haunts: Dictionary = LocationManager.data["haunts"]
	var hbad: Array[String] = []
	for cid: Variant in haunts:
		if str(cid).begins_with("_"):
			continue
		if not CharacterManager.has_character(StringName(str(cid))):
			hbad.append(str(cid))
		for h: Dictionary in haunts[cid]:
			if not LocationManager.has_location(StringName(str(h["loc"]))):
				hbad.append("%s@%s" % [cid, h["loc"]])
	for sid: Variant in LocationManager.data["supplier_haunts"]:
		if SupplierManager.supplier(str(sid)).is_empty():
			hbad.append("supplier %s" % sid)
	check(hbad.is_empty(), "cast and supplier haunts are real people at real places %s" % str(hbad))
	var districts_with_places := {}
	for id in LocationManager.order:
		districts_with_places[LocationManager.district_of(id)] = true
	check(districts_with_places.size() == WorldManager.order.size(), "every district has at least one place")


func _discovery() -> void:
	_fresh()
	check(LocationManager.is_known(&"clinic") and LocationManager.is_known(&"rusty_valve") and LocationManager.is_known(&"sump_tenements"), "the clinic and the nearby places are known from the start")
	check(not LocationManager.is_known(&"meridian_plaza") and not LocationManager.is_known(&"lyra_annex"), "far and hidden places start unknown")
	ProgressionManager.level = 5
	var found := LocationManager.check_discovery()
	check(found.has(&"furnace_works") and found.has(&"meridian_plaza") and found.has(&"velvet_lounge"), "levelling up reveals more of the city (%s)" % str(found))
	check(not LocationManager.is_known(&"lyra_checkpoint"), "the checkpoint stays hidden at level 5")
	StoryManager.set_flag(&"static_seen")
	LocationManager.check_discovery()
	check(LocationManager.is_known(&"lyra_checkpoint"), "a story flag reveals the checkpoint")
	check(not LocationManager.is_known(&"lyra_annex"), "the annex is only revealed by people")
	check(not LocationManager.is_known(&"flood_tunnels"), "the flood tunnels need a black-market contact")
	StoryManager.set_flag(&"bm_access")
	LocationManager.check_discovery()
	check(LocationManager.is_known(&"flood_tunnels"), "a black-market contact reveals the flood tunnels")
	_fresh()
	var n := CommsManager.inbox.size()
	var r := LocationManager.reveal_random("test")
	check(r != &"" and LocationManager.is_known(r) and not bool(LocationManager.get_location(r)["discover"].get("hidden", false)), "rumours reveal ordinary places, never hidden ones")
	check(CommsManager.inbox.size() == n + 1, "discovering a place sends a message")
	# Patients mention where they work.
	_fresh()
	var pid := _patient("corporate", "corporate_security", 3)
	var p := PeopleManager.get_person(pid)
	WorldSimulationManager.ensure_routine(p)
	check(str(p["work"]) == "meridian_plaza" and str(p["home"]) == "caldera_stacks", "a corporate patient works at the plaza and lives in the stacks")
	_at(1260)
	var res := WorldSimulationManager.talk("patient", String(pid))
	check(str(res["text"]) != "", "you can talk to a patient")
	check(LocationManager.is_known(&"meridian_plaza"), "a patient tells you where they work")
	# Suppliers' haunts become known.
	_fresh()
	SupplierManager.discover("magpie", "test")
	check(LocationManager.is_known(&"furnace_works"), "finding a supplier reveals where they deal")


func _hours_and_states() -> void:
	_fresh()
	_at(600)
	check(not LocationManager.is_open(&"rusty_valve"), "the bar is closed at 10:00")
	check(LocationManager.access_block(&"rusty_valve").begins_with("Closed now"), "and says when it opens")
	_at(1320)
	check(LocationManager.is_open(&"rusty_valve"), "the bar is open at 22:00")
	check(WorldSimulationManager.state(&"rusty_valve")["flags"].has(&"busy"), "and busy at night")
	_at(660)
	check(WorldSimulationManager.state(&"rusty_valve")["flags"].has(&"after_hours"), "after hours shows as closed")
	_at(1500)
	check(not LocationManager.is_open(&"meridian_plaza"), "the plaza closes at night")
	_at(700)
	check(LocationManager.is_open(&"meridian_plaza") and int(WorldSimulationManager.state(&"meridian_plaza")["activity"]) == 3, "the plaza is packed by day")
	check(WorldSimulationManager.state(&"meridian_plaza")["flags"].has(&"monitored"), "the plaza is monitored")
	_at(1400)
	StoryManager.set_flag(&"bm_access")
	check(WorldSimulationManager.state(&"flood_tunnels")["flags"].has(&"bm_active"), "the black market is active in the tunnels at night")
	var d0 := int(WorldSimulationManager.state(&"sump_tenements")["danger"])
	_at(700)
	var d1 := int(WorldSimulationManager.state(&"sump_tenements")["danger"])
	check(d0 > d1, "the Sump is more dangerous at night (%d > %d)" % [d0, d1])
	FactionManager.heat = 80.0
	WorldSimulationManager.refresh()
	check(int(WorldSimulationManager.state(&"spindle_interchange")["authority"]) >= 3 and WorldSimulationManager.has_flag(&"spindle_interchange", &"police"), "high heat brings police to the interchange")
	check(WorldSimulationManager.state_label(&"spindle_interchange") != "", "every place has a state label")
	FactionManager.heat = 0.0
	WorldSimulationManager.closures["glow_night_market"] = BusinessManager.day
	WorldSimulationManager.refresh()
	check(not LocationManager.is_open(&"glow_night_market") and LocationManager.access_block(&"glow_night_market").begins_with("Closed today"), "a place can close for the day")
	BusinessManager.day += 1
	WorldSimulationManager._on_day_started(BusinessManager.day)
	check(not WorldSimulationManager.closures.has("glow_night_market"), "closures lift the next day")


func _travel() -> void:
	_fresh()
	_at(1320)
	EconomyManager.money = 500
	var w := LocationManager.trip(&"rusty_valve", "walk")
	check(w["block"] == "" and int(w["minutes"]) > 0 and int(w["cost"]) == 0, "walking to the bar next door is free and takes minutes")
	check(LocationManager.trip(&"rusty_valve", "metro")["block"] != "", "no metro inside a district")
	var before := TimeManager.minute
	var r := LocationManager.travel(&"rusty_valve")
	check(bool(r["ok"]) and LocationManager.player_location == &"rusty_valve", "travel moves you")
	check(TimeManager.minute == before + int(r["minutes"]), "travel takes time on the clock (%d min)" % int(r["minutes"]))
	check(int(LocationManager.visits.get(&"rusty_valve", 0)) == 1, "visits are counted")
	var m := LocationManager.trip(&"glow_night_market", "metro")
	var tx := LocationManager.trip(&"glow_night_market", "taxi")
	var wk := LocationManager.trip(&"glow_night_market", "walk")
	check(m["block"] == "" and int(m["cost"]) == 6, "the metro costs 6")
	check(int(tx["minutes"]) < int(wk["minutes"]) and int(tx["cost"]) > int(m["cost"]), "cabs are faster and dearer than walking")
	check(float(wk["risk"]) > float(tx["risk"]), "walking is riskier than a cab")
	var money := EconomyManager.money
	r = LocationManager.travel(&"glow_night_market", "metro")
	check(bool(r["ok"]) and EconomyManager.money == money - 6, "the fare is paid")
	_at(1520)
	check(LocationManager.trip(&"rusty_valve", "metro")["block"] != "" or LocationManager.district_of(&"rusty_valve") == LocationManager.district_of(LocationManager.player_location), "the metro stops after 01:00")
	check(LocationManager.trip(&"sump_tenements", "metro")["block"].begins_with("Not running"), "the metro says when it runs")
	var night_cab := int(LocationManager.trip(&"sump_tenements", "taxi")["cost"])
	_at(700)
	var day_cab := int(LocationManager.trip(&"sump_tenements", "taxi")["cost"])
	check(night_cab > day_cab, "cabs cost more at night (%d > %d)" % [night_cab, day_cab])
	WorldEventManager.active.append({"id": "blackout", "start": BusinessManager.day, "days_left": 1, "vars": {}})
	check(LocationManager.trip(&"sump_tenements", "metro")["block"].begins_with("Blackout"), "a blackout stops the metro")
	WorldEventManager.active.clear()
	EconomyManager.money = 3
	check(LocationManager.trip(&"sump_tenements", "taxi")["block"].begins_with("Need"), "you can't take a cab you can't pay for")
	check(bool(LocationManager.travel(&"sump_tenements")["ok"]), "you can always walk")
	EconomyManager.money = 500
	check(not LocationManager.travel(&"meridian_plaza")["ok"], "you can't travel to a place you don't know")
	check(not LocationManager.travel(&"sump_tenements")["ok"], "or to where you already are")
	_at(1670)
	check(LocationManager.leave_block(&"rusty_valve") != "", "near four you can only go home")
	check(LocationManager.leave_block(LocationManager.CLINIC) == "", "home is always allowed")
	r = LocationManager.return_to_clinic()
	check(bool(r["ok"]) and not LocationManager.is_away(), "you can always get home")
	check(TimeManager.minute <= TimeManager.close_minute() + 120, "the clock never runs past its cap")
	# Metro pass.
	_fresh()
	_at(700)
	LocationManager.metro_pass_until = BusinessManager.day + 3
	check(int(LocationManager.trip(&"glow_night_market", "metro")["cost"]) == 0, "a metro pass makes rides free")
	# Same-district auto route and fastest pick.
	var best := LocationManager.best_trip(&"glow_night_market")
	check(best["block"] == "" and best["mode"] in ["metro", "walk"], "the default trip is the sensible one (%s)" % str(best["mode"]))


func _away_from_clinic() -> void:
	_fresh()
	_at(1200)
	var c := CustomerManager.generator.generate({})
	CustomerManager.debug_set_customer(c)
	var waiting := ClinicLifeManager.waiting.size()
	LocationManager.travel(&"rusty_valve")
	check(not CustomerManager.has_customer(), "going out: nobody is left standing at the door")
	check(ClinicLifeManager.waiting.size() == waiting + 1, "they sit on the bench instead")
	CustomerManager.request_next_customer(0.0)
	check(not CustomerManager.has_customer(), "nobody new walks in while you're out")
	check(GameManager.get_next_objective()["text"].contains("RETURN TO CLINIC"), "the objective line says you're out")
	var em := CustomerManager.generator.generate({})
	LocationManager.return_to_clinic()
	em.is_emergency = true
	CustomerManager.debug_set_customer(em)
	check(LocationManager.leave_block(&"rusty_valve").contains("emergency"), "you can't walk out on an emergency")
	CustomerManager.dismiss_current()
	CustomerManager.request_next_customer(0.0)
	check(CustomerManager.has_customer(), "back at the clinic, people walk in again")
	CustomerManager.dismiss_current()
	# Nights away make break-ins likelier.
	_fresh()
	var p0 := SecurityManager.theft_chance()
	LocationManager.away_minutes_night = 240
	check(SecurityManager.theft_chance() > p0, "a night out raises the break-in risk")
	SurgeryManager.is_active = true
	check(LocationManager.leave_block(&"rusty_valve") != "", "you can't leave mid-operation")
	SurgeryManager.is_active = false
	# The day starts at the clinic.
	_at(1300)
	LocationManager.travel(&"rusty_valve")
	EventBus.day_started.emit(BusinessManager.day + 1)
	check(not LocationManager.is_away(), "a new day starts at the clinic")


func _routines() -> void:
	_fresh()
	var workers: Array[StringName] = []
	for i in 30:
		workers.append(_patient("dock_worker", "independent_mercs", 1))
	_at(700)
	var at_work := 0
	for id in workers:
		if WorldSimulationManager.person_place(PeopleManager.get_person(id)) == &"furnace_works":
			at_work += 1
	check(at_work >= 18, "dock workers are at the works by day (%d/30)" % at_work)
	_at(1560)
	var home := 0
	for id in workers:
		if WorldSimulationManager.person_place(PeopleManager.get_person(id)) == &"sump_tenements":
			home += 1
	check(home >= 24, "and home in the tenements late at night (%d/30)" % home)
	_at(1080)
	var transit := 0
	for id in workers:
		if WorldSimulationManager.person_place(PeopleManager.get_person(id)) == &"spindle_interchange":
			transit += 1
	check(transit >= 15, "commuting through the interchange in the evening (%d/30)" % transit)
	var gang: Array[StringName] = []
	for i in 20:
		gang.append(_patient("gang_member", "street_gangs", 0))
	_at(1320)
	var at_valve := 0
	for id in gang:
		if WorldSimulationManager.person_place(PeopleManager.get_person(id)) == &"rusty_valve":
			at_valve += 1
	check(at_valve >= 12, "gang members work the Valve at night (%d/20)" % at_valve)
	check(not WorldSimulationManager.patients_at(&"rusty_valve").is_empty(), "patients show up in the people at a place")
	check(WorldSimulationManager.people_at(&"rusty_valve").any(func(p: Dictionary) -> bool: return p["kind"] == "patient"), "and in the location's people list")
	# The dead and the missing are nowhere.
	var dead := gang[0]
	PeopleManager.mark_dead(dead, "test")
	check(WorldSimulationManager.person_place(PeopleManager.get_person(dead)) == &"", "the dead are nowhere")
	check(PeopleManager.get_person(dead)["status"] == "dead", "mark_dead marks them dead")
	# Routines are stable within a period (no flicker).
	var p := PeopleManager.get_person(workers[0])
	var a := WorldSimulationManager.person_place(p)
	var same := true
	for i in 10:
		same = same and WorldSimulationManager.person_place(p) == a
	check(same, "where someone is doesn't flicker")
	var ab := WorldSimulationManager.activity_of(p)
	check(ab != "", "people have a current activity (%s)" % ab)
	# Everyone gets home/work/social, and they're real places.
	var ok := true
	for k: String in PeopleManager.people:
		var pp := WorldSimulationManager.ensure_routine(PeopleManager.people[k])
		for key in ["home", "work", "social"]:
			ok = ok and LocationManager.has_location(StringName(str(pp[key])))
	check(ok, "every routine points at real places")


func _cast_and_staff() -> void:
	_fresh()
	_at(1320)
	var unmet := true
	for cid in WorldSimulationManager.cast_at(&"rusty_valve"):
		unmet = unmet and CharacterManager.has_met(cid)
	check(unmet and not WorldSimulationManager.cast_at(&"rusty_valve").has(&"rook_varga"), "unmet cast stay off the map")
	var found := false
	CharacterManager.mark_met(&"rook_varga")
	var start_day := BusinessManager.day
	for d in 20:
		BusinessManager.day = start_day + d
		WorldSimulationManager.refresh()
		if WorldSimulationManager.cast_at(&"rusty_valve").has(&"rook_varga"):
			found = true
			break
	check(found, "Rook is at the Valve some nights")
	check(WorldSimulationManager.where_is_cast(&"rook_varga") in [&"rusty_valve", &""], "where_is_cast agrees")
	var never_closed := true
	for d in 20:
		BusinessManager.day = start_day + d
		_at(600)
		never_closed = never_closed and not WorldSimulationManager.cast_at(&"rusty_valve").has(&"rook_varga")
	check(never_closed, "nobody's at the bar when it's closed")
	BusinessManager.day = start_day
	# Teo stops haunting once he's gone.
	CharacterManager.mark_met(&"teo_marr")
	StoryManager.set_flag(&"teo_gone")
	var teo := false
	for d in 20:
		BusinessManager.day = start_day + d
		_at(1320)
		teo = teo or WorldSimulationManager.where_is_cast(&"teo_marr") != &""
	check(not teo, "a cast member who's gone is nowhere")
	BusinessManager.day = start_day
	# Staff on their break.
	_fresh()
	StaffManager.employees.append(StaffManager.generate_candidate())
	var e: Dictionary = StaffManager.employees[0]
	var seen := false
	for p in [1080, 1320, 1560]:
		_at(p)
		if WorldSimulationManager.staff_at(&"rusty_valve").has(StringName(str(e["id"]))):
			seen = true
	check(seen, "staff spend one break a night at their bar")
	var loyal := float(e["loyalty"])
	for p in [1080, 1320, 1560]:
		_at(p)
		if WorldSimulationManager.staff_at(&"rusty_valve").has(StringName(str(e["id"]))):
			WorldSimulationManager.talk("staff", str(e["id"]))
	check(float(e["loyalty"]) > loyal, "a drink with staff raises loyalty")


func _events() -> void:
	_fresh()
	_at(1320)
	var eid := WorldSimulationManager.start_event(&"rusty_valve", "bar_fight")
	check(eid == "bar_fight" and not WorldSimulationManager.event_at(&"rusty_valve").is_empty(), "an event happens at a place")
	check(WorldSimulationManager.has_flag(&"rusty_valve", &"event"), "and shows in its state")
	var txt := WorldSimulationManager.resolve_event(&"rusty_valve", 2)
	check(txt != "" and WorldSimulationManager.event_at(&"rusty_valve").is_empty(), "choosing resolves it")
	check(not WorldSimulationManager.feed_at(&"rusty_valve").is_empty(), "and it goes in the street feed")
	# Quest-generating: an accident sends a patient to your clinic.
	ProgressionManager.level = 3
	LocationManager.check_discovery()
	_at(700)
	InventoryManager.supplies = 3
	var q := CustomerManager.queue.size()
	WorldSimulationManager.start_event(&"furnace_works", "works_accident")
	var before := TimeManager.minute
	WorldSimulationManager.resolve_event(&"furnace_works", 0)
	check(CustomerManager.queue.size() == q + 1, "the injured worker is on their way to your clinic")
	var c := CustomerData.from_save_dict(CustomerManager.queue[0]["customer"])
	check(c.is_emergency and String(c.archetype_id) == "dock_worker", "as an emergency")
	check(TimeManager.minute == before + 25, "helping takes time")
	check(InventoryManager.supplies == 2, "and a supply")
	# Gated choices.
	InventoryManager.supplies = 0
	WorldSimulationManager.events.erase("furnace_works")
	WorldSimulationManager.start_event(&"furnace_works", "works_accident")
	check(WorldSimulationManager.resolve_event(&"furnace_works", 0) == "", "a choice you can't afford does nothing")
	# Cosmetic events just happen.
	WorldSimulationManager.events.erase("furnace_works")
	WorldSimulationManager.start_event(&"furnace_works", "works_scrap")
	check(WorldSimulationManager.event_at(&"furnace_works").is_empty() and not WorldSimulationManager.feed_at(&"furnace_works").is_empty(), "cosmetic events go straight to the feed")
	# Rolling: over many periods, places get events, never closed ones.
	WorldSimulationManager.events.clear()
	_at(600)
	WorldSimulationManager.roll_events()
	check(not WorldSimulationManager.events.has("rusty_valve"), "closed places don't roll events")
	var any := 0
	for i in 10:
		WorldSimulationManager.events.clear()
		_at(1320)
		WorldSimulationManager.roll_events()
		any += WorldSimulationManager.events.size()
	check(any > 0, "open places roll events (%d)" % any)
	# Period change clears stale events.
	WorldSimulationManager.events.clear()
	_at(1320)
	WorldSimulationManager.start_event(&"rusty_valve", "bar_recruit")
	_at(1560)
	WorldSimulationManager._on_period_changed(TimeManager.period())
	check(WorldSimulationManager.event_at(&"rusty_valve").is_empty() or str(WorldSimulationManager.events.get("rusty_valve", {}).get("period", "")) == "late_night", "events don't outlive their period")
	# Candidate / lead / zone outcomes.
	var cand := StaffManager.candidates.size()
	WorldSimulationManager.apply({"candidate": true})
	check(StaffManager.candidates.size() == cand + 1, "a recruit outcome adds a candidate")
	var known := SupplierManager.discovered().size() + LocationManager.known_locations().size()
	WorldSimulationManager.apply({"lead": "supplier"}, &"rusty_valve")
	check(SupplierManager.discovered().size() + LocationManager.known_locations().size() > known, "a lead outcome finds a supplier or a place")
	# Every authored event is valid: choices resolve without errors.
	var bad: Array[String] = []
	for id: String in WorldSimulationManager._events_by_id:
		var ed: Dictionary = WorldSimulationManager._events_by_id[id]
		for ch: Variant in ed.get("choices", []):
			if not (ch as Dictionary).has("label") or not (ch as Dictionary).has("outcomes"):
				bad.append(id)
	check(bad.is_empty(), "every event choice has a label and outcomes %s" % str(bad))


func _factions() -> void:
	_fresh()
	_at(1320)
	var base := float(WorldSimulationManager.faction_presence(&"rusty_valve").get("street_gangs", 0.0))
	check(WorldSimulationManager.dominant_faction(&"rusty_valve") == &"street_gangs", "the Valve is Saints turf")
	check(WorldSimulationManager.has_flag(&"rusty_valve", &"controlled"), "and shows as controlled")
	WorldEventManager.active.append({"id": "district_shift", "start": 1, "days_left": 3, "vars": {"district": "The Sump", "faction_id": "independent_mercs", "faction": "Mercs"}})
	WorldSimulationManager.refresh()
	check(float(WorldSimulationManager.faction_presence(&"rusty_valve").get("independent_mercs", 0.0)) >= 3.0, "a district takeover in the news puts the faction on the street")
	WorldEventManager.active.clear()
	WorldEventManager.active.append({"id": "gang_war", "start": 1, "days_left": 3, "vars": {"district": "The Sump"}})
	WorldSimulationManager.refresh()
	check(float(WorldSimulationManager.faction_presence(&"rusty_valve").get("street_gangs", 0.0)) > base, "a gang war brings more gangs")
	check(int(WorldSimulationManager.state(&"sump_tenements")["danger"]) >= 3, "and danger")
	WorldEventManager.active.clear()
	WorldSimulationManager.refresh()
	# Hostile to whoever runs the place: unwelcome, services closed, prices up.
	FactionManager.rep[&"street_gangs"] = -80
	WorldSimulationManager.refresh()
	LocationManager.travel(&"rusty_valve")
	check(WorldSimulationManager.has_flag(&"rusty_valve", &"unwelcome"), "hostile gangs make the Valve unwelcome")
	check(LocationServices.block(&"rusty_valve", "recruit").begins_with("You're not welcome"), "and close its services to you")
	check(WorldSimulationManager.price_mult(&"rusty_valve") > 1.0, "and its prices go up")
	FactionManager.rep[&"street_gangs"] = 60
	WorldSimulationManager.refresh()
	check(WorldSimulationManager.price_mult(&"rusty_valve") < 1.0, "friends get a discount")
	# What you do there shifts presence, and it drifts back.
	var p0 := float(WorldSimulationManager.faction_presence(&"rusty_valve").get("independent_mercs", 0.0))
	WorldSimulationManager.apply({"faction": {"independent_mercs": 2}}, &"rusty_valve")
	var p1 := float(WorldSimulationManager.faction_presence(&"rusty_valve").get("independent_mercs", 0.0))
	check(p1 > p0, "helping a faction somewhere makes them more present there")
	for i in 5:
		WorldSimulationManager._on_day_started(BusinessManager.day)
	check(float(WorldSimulationManager.faction_presence(&"rusty_valve").get("independent_mercs", 0.0)) < p1, "and it drifts back over days")


func _black_market() -> void:
	_fresh()
	_at(1380)
	StoryManager.set_flag(&"bm_access")
	LocationManager.check_discovery()
	var bm0 := ModifierManager.value(&"bm.price")
	LocationManager.travel(&"flood_tunnels")
	check(LocationManager.player_location == &"flood_tunnels", "you can go to the Undermarket in person")
	check(ModifierManager.value(&"bm.price") < bm0, "and it's cheaper in person")
	var r := LocationServices.perform(&"flood_tunnels", "undermarket")
	check(str(r["screen"]) == "black_market", "the Undermarket opens from the tunnels")
	BlackMarketManager.stock.clear()
	r = LocationServices.perform(&"flood_tunnels", "walk_stalls")
	check(bool(r["ok"]) and not BlackMarketManager.stock.is_empty(), "walking the stalls brings out new stock")
	check(LocationServices.block(&"flood_tunnels", "walk_stalls") == "Done for today", "once a day")
	LocationManager.return_to_clinic()
	check(is_equal_approx(ModifierManager.value(&"bm.price"), bm0), "the discount stays in the tunnels")
	# The night market's prices.
	_at(1320)
	var pb := ModifierManager.value(&"price.buy")
	LocationManager.travel(&"glow_night_market")
	check(ModifierManager.value(&"price.buy") < pb, "the night market is cheaper after dark")
	LocationManager.return_to_clinic()
	# Suppliers: met in person.
	_fresh()
	_at(1380)
	StoryManager.set_flag(&"bm_access")
	LocationManager.check_discovery()
	SupplierManager.discover("curator", "test")
	var seen := false
	var start_day := BusinessManager.day
	for d in 15:
		BusinessManager.day = start_day + d
		WorldSimulationManager.refresh()
		if WorldSimulationManager.suppliers_at(&"flood_tunnels").has("curator"):
			seen = true
			break
	check(seen, "suppliers keep tables at their haunt")
	var tr := int(SupplierManager.st("curator").get("trust", 0))
	LocationManager.travel(&"flood_tunnels")
	WorldSimulationManager.talk("supplier", "curator")
	check(int(SupplierManager.st("curator").get("trust", 0)) > tr, "face to face builds trust")
	WorldSimulationManager.talk("supplier", "okafor")
	check(SupplierManager.discovered().has("okafor"), "a stranger with a sample case becomes a contact")
	BusinessManager.day = start_day


func _services() -> void:
	_fresh()
	_at(1320)
	EconomyManager.money = 2000
	LocationManager.travel(&"rusty_valve")
	check(LocationServices.block(&"glow_night_market", "tout") == "You're not there", "services only where you are")
	var q := CustomerManager.queue.size()
	var r := LocationServices.perform(&"rusty_valve", "tout")
	check(bool(r["ok"]) and CustomerManager.queue.size() == q + 1, "handing out cards sends someone to your clinic")
	check(not bool(LocationServices.perform(&"rusty_valve", "tout")["ok"]), "once a day per place")
	var cand := StaffManager.candidates.size()
	LocationServices.perform(&"rusty_valve", "recruit")
	check(StaffManager.candidates.size() > cand, "recruiting at the bar adds candidates")
	var m := EconomyManager.money
	r = LocationServices.perform(&"rusty_valve", "rumors")
	check(bool(r["ok"]) and EconomyManager.money < m and str(r["text"]) != "", "a round buys you something to hear")
	r = LocationServices.perform(&"rusty_valve", "socialize")
	check(bool(r["ok"]), "working the room")
	# Industrial.
	ProgressionManager.level = 3
	LocationManager.check_discovery()
	_at(700)
	LocationManager.travel(&"furnace_works")
	var parts := InventoryManager.parts
	LocationServices.perform(&"furnace_works", "salvage")
	check(InventoryManager.parts > parts, "salvage gives parts")
	check(LocationServices.block(&"furnace_works", "workshop") != "" or InventoryManager.get_service_cost() > 0, "the workshop only works on worn tools")
	if not InventoryManager.owned_tools.is_empty():
		InventoryManager.tool_condition[InventoryManager.owned_tools[0]] = 40.0
		var cost := LocationServices.cost(&"furnace_works", "workshop")
		check(cost > 0 and cost < InventoryManager.get_service_cost(), "the works service is cheaper than the usual")
		LocationServices.perform(&"furnace_works", "workshop")
		check(InventoryManager.get_tool_condition(InventoryManager.owned_tools[0]) >= 99.0, "and fixes your tools")
	# Transit.
	LocationManager.travel(&"spindle_interchange")
	m = EconomyManager.money
	LocationServices.perform(&"spindle_interchange", "courier")
	check(EconomyManager.money > m, "a courier job pays")
	LocationServices.perform(&"spindle_interchange", "metro_pass")
	check(LocationManager.has_metro_pass(), "a metro pass")
	# Corporate.
	ProgressionManager.level = 5
	LocationManager.check_discovery()
	_at(700)
	LocationManager.travel(&"meridian_plaza")
	m = EconomyManager.money
	var before := TimeManager.minute
	LocationServices.perform(&"meridian_plaza", "contract")
	check(EconomyManager.money > m and TimeManager.minute == before + 180, "a licensed shift pays and takes three hours")
	FactionManager.heat = 70.0
	check(LocationServices.block(&"meridian_plaza", "licensed_supplies") == "", "certified stock is always for sale")
	check(LocationServices.block(&"meridian_plaza", "contract") != "", "a hot file blocks licensed work (or it's done today)")
	FactionManager.heat = 0.0
	# Residential.
	LocationManager.return_to_clinic()
	var pid := _patient("addict", "street_gangs", 0)
	PeopleManager.get_person(pid)["dependency"] = 3
	_at(800)
	LocationManager.travel(&"sump_tenements")
	r = LocationServices.perform(&"sump_tenements", "visit")
	check(bool(r["ok"]) and int(PeopleManager.get_person(pid)["next_day"]) == BusinessManager.day, "visiting patients at home brings the shaky ones in")
	# Night market.
	ProgressionManager.level = 1
	LocationManager.return_to_clinic()
	_at(1320)
	LocationManager.travel(&"glow_night_market")
	r = LocationServices.perform(&"glow_night_market", "market_supplies")
	check(str(r["screen"]) == "shop", "the market opens the supply terminal at market prices")
	InventoryManager.parts = 5
	m = EconomyManager.money
	LocationServices.perform(&"glow_night_market", "sell_scrap")
	check(InventoryManager.parts == 2 and EconomyManager.money > m, "fencing parts")
	# Everything listed everywhere returns a definite answer.
	var undefined: Array[String] = []
	for id in LocationManager.order:
		for s in LocationServices.list(id):
			if not s.has("block") or not s.has("label"):
				undefined.append("%s/%s" % [id, s.get("id", "")])
	check(undefined.is_empty(), "every service lists cleanly %s" % str(undefined))
	LocationManager.return_to_clinic()


func _restricted() -> void:
	_fresh()
	ProgressionManager.level = 6
	EconomyManager.money = 3000
	LocationManager.check_discovery()
	check(LocationManager.is_known(&"lyra_checkpoint"), "the checkpoint is found by level 6")
	_at(1320)
	check(LocationManager.trip(&"lyra_checkpoint", "metro")["block"].contains("Zone") or LocationManager.trip(&"lyra_checkpoint", "metro")["block"] != "", "no metro into the Zone")
	check(LocationManager.trip(&"lyra_checkpoint", "taxi")["block"] != "", "no cab into the Zone")
	var r := LocationManager.travel(&"lyra_checkpoint")
	check(bool(r["ok"]) and r["mode"] == "walk", "you walk to the checkpoint")
	check(not LocationManager.is_known(&"lyra_annex") and LocationManager.access_block(&"lyra_annex") != "", "the annex is off limits")
	r = LocationServices.perform(&"lyra_checkpoint", "checkpoint", 0)
	check(bool(r["ok"]) and LocationManager.zone_access == "route", "bribing the guard gets you a way in")
	check(LocationManager.is_known(&"lyra_annex") and LocationManager.access_block(&"lyra_annex") == "", "and the annex opens up")
	LocationManager.travel(&"lyra_annex")
	var n := InventoryManager.get_instances().size()
	LocationServices.perform(&"lyra_annex", "lab_salvage")
	check(InventoryManager.get_instances().size() == n + 1, "the cold storage has prototype chrome")
	LocationServices.perform(&"lyra_annex", "lab_records")
	check(StoryManager.has_flag(&"annex_records") and StoryManager.counter(&"lyra_leads") >= 2, "the records feed the story")
	check(WorldSimulationManager.event_at(&"lyra_annex").get("id", "") == "annex_patient", "and lead to bed 14")
	InventoryManager.supplies = 3
	var q := CustomerManager.queue.size()
	WorldSimulationManager.resolve_event(&"lyra_annex", 0)
	check(StoryManager.has_flag(&"annex_rescue") and CustomerManager.queue.size() == q + 1, "you can carry the survivor out to your clinic")
	LocationManager.return_to_clinic()
	# Other ways in.
	_fresh()
	ReputationManager.dims[&"corporate"] = 30
	LocationManager.grant_zone("")
	check(LocationServices.block(&"meridian_plaza", "zone_pass") == "You're not there", "the pass is applied for at the plaza")
	ProgressionManager.level = 5
	LocationManager.check_discovery()
	EconomyManager.money = 1000
	_at(700)
	LocationManager.travel(&"meridian_plaza")
	r = LocationServices.perform(&"meridian_plaza", "zone_pass")
	check(bool(r["ok"]) and LocationManager.zone_access == "pass", "corporate standing gets you a contractor pass")
	LocationManager.return_to_clinic()
	_fresh()
	ReputationManager.dims[&"black_market"] = 15
	StoryManager.set_flag(&"bm_access")
	LocationManager.check_discovery()
	EconomyManager.money = 1000
	_at(1380)
	LocationManager.travel(&"flood_tunnels")
	LocationServices.perform(&"flood_tunnels", "forged_pass")
	check(LocationManager.zone_access == "forged", "or a forged badge from the tunnels")
	check(not LocationServices.list(&"flood_tunnels").is_empty(), "the tunnels list their services")
	LocationManager.return_to_clinic()
	# An elite practice inside the Zone needs no pass.
	_fresh()
	ClinicManager.tier = 6
	check(LocationManager.has_zone_access(), "a practice in the Zone is its own way in")
	ClinicManager.tier = 0


func _missing_chain() -> void:
	_fresh()
	var pid := _patient("addict", "street_gangs", 0)
	var p := PeopleManager.get_person(pid)
	p["dependency"] = 2
	var inbox := CommsManager.inbox.size()
	check(WorldSimulationManager.start_missing() == pid, "a patient with risky chrome goes missing")
	check(p["status"] == "missing" and CommsManager.inbox.size() > inbox, "their family writes to you")
	check(WorldSimulationManager.person_place(p) == &"", "the missing aren't at their usual places")
	check(not PeopleManager.due_people().has(pid), "and don't walk into the clinic")
	var m: Dictionary = WorldSimulationManager.missing[String(pid)]
	var home := StringName(str(m["home"]))
	var place := StringName(str(m["place"]))
	check(LocationManager.is_known(home), "you know where they live")
	check(not WorldSimulationManager.missing_at(home).is_empty(), "their home has a lead")
	_at(800)
	if home != LocationManager.player_location:
		LocationManager.travel(home)
	var txt := WorldSimulationManager.act_missing(home, 0)
	check(txt != "" and int(m["stage"]) == 1 and LocationManager.is_known(place), "searching their place points to where they went (%s)" % place)
	check(WorldSimulationManager.missing_at(place).get("stage", -1) == 1, "and they're there")
	InventoryManager.supplies = 2
	var q := CustomerManager.queue.size()
	WorldSimulationManager.act_missing(place, 0)
	check(p["status"] == "alive" and CustomerManager.queue.size() == q + 1, "you bring them in as an emergency")
	check(CustomerManager.queue[0]["customer"]["id"] == String(pid), "it's them, first in line")
	check(not WorldSimulationManager.missing.has(String(pid)), "the case closes")
	LocationManager.return_to_clinic()
	# Too late.
	_fresh()
	var pid2 := _patient("addict", "street_gangs", 0)
	PeopleManager.get_person(pid2)["dependency"] = 2
	WorldSimulationManager.start_missing(pid2)
	var news := WorldEventManager.news.size()
	BusinessManager.day += 6
	WorldSimulationManager._on_day_started(BusinessManager.day)
	check(PeopleManager.get_person(pid2)["status"] == "dead" and WorldEventManager.news.size() > news, "after the deadline they're found dead, in the news")
	# Walking away.
	_fresh()
	var pid3 := _patient("addict", "street_gangs", 0)
	WorldSimulationManager.start_missing(pid3)
	var m3: Dictionary = WorldSimulationManager.missing[String(pid3)]
	m3["stage"] = 1
	WorldSimulationManager.act_missing(StringName(str(m3["place"])), 2)
	check(PeopleManager.get_person(pid3)["status"] == "dead", "walking away has a price")
	# Nobody at risk: nobody vanishes; cast never.
	_fresh()
	check(WorldSimulationManager.start_missing() == &"", "nobody at risk, nobody missing")


func _encounters() -> void:
	_fresh()
	_at(1320)
	EconomyManager.money = 200
	var e := WorldSimulationManager.roll_encounter("walk", &"clinic", &"rusty_valve", 1.0, "mugging")
	check(not e.is_empty() and WorldSimulationManager.has_encounter(), "something can happen on the way")
	check(LocationManager.leave_block(&"sump_tenements") != "", "you deal with it before moving on")
	var txt := WorldSimulationManager.resolve_encounter(0)
	check(txt != "" and EconomyManager.money == 140 and not WorldSimulationManager.has_encounter(), "handing over the wallet costs 60")
	e = WorldSimulationManager.roll_encounter("walk", &"clinic", &"rusty_valve", 1.0, "street_preacher")
	check(e.is_empty() and not WorldSimulationManager.has_encounter(), "cosmetic encounters just happen")
	e = WorldSimulationManager.roll_encounter("walk", &"clinic", &"rusty_valve", 1.0, "wounded_stranger")
	var q := CustomerManager.queue.size()
	WorldSimulationManager.resolve_encounter(1)
	check(CustomerManager.queue.size() == q + 1, "a stranger you help ends up at your clinic")
	# Risk scales with mode and night: many trips, cabs see fewer.
	WorldSimulationManager.auto_roll = true
	var walk_hits := 0
	var cab_hits := 0
	for i in 300:
		if not WorldSimulationManager.roll_encounter("walk", &"clinic", &"glow_night_market", 1.0).is_empty():
			walk_hits += 1
		WorldSimulationManager.encounter = {}
		if not WorldSimulationManager.roll_encounter("taxi", &"clinic", &"glow_night_market", 0.15).is_empty():
			cab_hits += 1
		WorldSimulationManager.encounter = {}
	WorldSimulationManager.auto_roll = false
	check(walk_hits > cab_hits, "walking at night meets more trouble than a cab (%d vs %d)" % [walk_hits, cab_hits])


func _talk() -> void:
	_fresh()
	_at(1320)
	CharacterManager.mark_met(&"rook_varga")
	var did := &""
	for d: String in DialogueManager.dialogues:
		if str(DialogueManager.dialogues[d].get("character", "")) == "rook_varga":
			did = StringName(d)
			break
	if did != &"":
		StoryManager.queue_talk(did)
		var r := WorldSimulationManager.talk("cast", "rook_varga")
		check(StringName(str(r["dialogue"])) == did and not StoryManager.talk_queue.has(String(did)), "a waiting conversation can happen where you find them")
	var rel := CharacterManager.relationship(&"rook_varga")
	var r2 := WorldSimulationManager.talk("cast", "rook_varga")
	check(str(r2["text"]) != "" and CharacterManager.relationship(&"rook_varga") == rel + 1, "small talk builds the relationship")
	check(not WorldSimulationManager.can_talk("cast", "rook_varga"), "once a day")


func _save_roundtrip() -> void:
	_fresh()
	ProgressionManager.level = 6
	LocationManager.check_discovery()
	_at(1320)
	EconomyManager.money = 1000
	LocationManager.travel(&"rusty_valve")
	LocationManager.metro_pass_until = BusinessManager.day + 4
	LocationManager.grant_zone("route")
	WorldSimulationManager.start_event(&"rusty_valve", "bar_recruit")
	var pid := _patient("addict", "street_gangs", 0)
	WorldSimulationManager.start_missing(pid)
	WorldSimulationManager.shift_presence(&"rusty_valve", "independent_mercs", 0.5)
	WorldSimulationManager.closures["glow_night_market"] = BusinessManager.day
	WorldSimulationManager.roll_encounter("walk", &"clinic", &"rusty_valve", 1.0, "mugging")
	var known := LocationManager.known_locations().size()
	var minute := TimeManager.minute
	check(SaveManager.save_game(&"manual"), "save with the city in it")
	SaveManager.reset_all()
	check(not LocationManager.is_away() and WorldSimulationManager.missing.is_empty(), "reset clears the city")
	check(SaveManager.load_game(), "load")
	check(LocationManager.player_location == &"rusty_valve", "you're still where you were")
	check(LocationManager.known_locations().size() == known, "known places survive")
	check(LocationManager.zone_access == "route" and LocationManager.has_metro_pass(), "zone access and metro pass survive")
	check(not WorldSimulationManager.event_at(&"rusty_valve").is_empty(), "the event in progress survives")
	check(WorldSimulationManager.missing.has(String(pid)) and PeopleManager.get_person(pid)["status"] == "missing", "the missing case survives")
	check(float(WorldSimulationManager.shifts.get("rusty_valve", {}).get("independent_mercs", 0.0)) > 0.0, "faction shifts survive")
	check(WorldSimulationManager.has_flag(&"glow_night_market", &"closed"), "closures survive")
	check(WorldSimulationManager.has_encounter(), "a pending encounter survives")
	check(TimeManager.minute == minute, "the clock survives")
	WorldSimulationManager.resolve_encounter(0)
	# An old save without the city still loads, with sensible defaults.
	var data := {"known": ["rusty_valve", "bogus_place"], "at": "nowhere"}
	LocationManager.load_save_data(data)
	check(not LocationManager.is_away() and LocationManager.is_known(&"rusty_valve") and not LocationManager.has_location(&"bogus_place"), "bad save data falls back safely")
	LocationManager.load_save_data({})
	check(LocationManager.is_known(&"clinic") and LocationManager.is_known(&"furnace_works"), "an old save gets the places it should know")
	PeopleManager.get_person(pid)["status"] = "missing"
	WorldSimulationManager.load_save_data({})
	check(PeopleManager.get_person(pid)["status"] == "alive", "a missing person without a case comes home")


## A week of city life with everything rolling: no errors, no stuck states,
## the clinic always reachable.
func _soak() -> void:
	_fresh()
	WorldSimulationManager.auto_roll = true
	EconomyManager.money = 5000
	ProgressionManager.level = 6
	StoryManager.set_flag(&"bm_access")
	LocationManager.check_discovery()
	for i in 12:
		_patient(["dock_worker", "gang_member", "corporate", "addict", "club_performer"][i % 5], ["independent_mercs", "street_gangs", "corporate_security"][i % 3], i % 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var stuck := false
	var trips := 0
	for day in 7:
		EventBus.day_started.emit(BusinessManager.day)
		for hop in 8:
			var known := LocationManager.known_locations()
			var to: StringName = known[rng.randi() % known.size()]
			var r := LocationManager.travel(to)
			if bool(r.get("ok", false)):
				trips += 1
			if WorldSimulationManager.has_encounter():
				WorldSimulationManager.resolve_encounter(rng.randi() % (WorldSimulationManager.encounter["choices"] as Array).size())
				if WorldSimulationManager.has_encounter():
					WorldSimulationManager.encounter = {}
			var here := LocationManager.player_location
			var ev := WorldSimulationManager.event_at(here)
			if not ev.is_empty():
				WorldSimulationManager.resolve_event(here, rng.randi() % maxi(1, (ev.get("choices", []) as Array).size()))
			for s in LocationServices.list(here):
				if s["block"] == "" and not s.has("screen") and rng.randf() < 0.4:
					LocationServices.perform(here, str(s["id"]))
			for p in WorldSimulationManager.people_at(here):
				if rng.randf() < 0.3:
					var res := WorldSimulationManager.talk(str(p["kind"]), str(p["id"]))
					if StringName(str(res.get("dialogue", ""))) != &"":
						pass
		var home := LocationManager.return_to_clinic()
		stuck = stuck or not bool(home.get("ok", false)) or LocationManager.is_away()
		BusinessManager.day += 1
		TimeManager.minute = TimeManager.open_minute()
		CustomerManager.queue.clear()
	WorldSimulationManager.auto_roll = false
	check(trips > 20, "a week of trips around the city (%d)" % trips)
	check(not stuck, "the clinic was reachable every night")
	check(WorldSimulationManager.feed.size() <= WorldSimulationManager.FEED_MAX, "the street feed stays bounded")
