class_name LocationServices
extends RefCounted
## What you can do at a place (the "services" list in data/locations.json).
## Each service is built from systems that already exist: the supply
## terminal, the Undermarket, staff candidates, suppliers, the customer
## queue, the tool bench. Most can be used once a day per place.
##
## list(loc) -> [{id, label, desc, minutes, cost, block, screen}]
## perform(loc, id) -> {ok, text, screen}

const DEFS := {
	"visit": {"label": "VISIT YOUR PATIENTS", "desc": "Knock on the doors of people you've treated who live here.", "minutes": 30, "daily": true},
	"canvass": {"label": "ASK AROUND", "desc": "Neighbours talk: who's sick, who's missing, where things happen.", "minutes": 20, "daily": true},
	"rumors": {"label": "BUY A ROUND, LISTEN", "desc": "Rumours, places, and who's selling what.", "minutes": 20, "cost": 15, "daily": true},
	"recruit": {"label": "LOOK FOR STAFF", "desc": "Medics drink here between jobs. New names on your candidate list.", "minutes": 30, "daily": true},
	"tout": {"label": "HAND OUT CARDS", "desc": "Tell people where your clinic is. Someone from here will come in.", "minutes": 30, "daily": true},
	"socialize": {"label": "WORK THE ROOM", "desc": "Drinks for the right people: standing with whoever runs the place.", "minutes": 40, "cost": 25, "daily": true},
	"negotiate": {"label": "MEET A FIXER", "desc": "A well-paying client who doesn't want questions.", "minutes": 30, "daily": true},
	"undermarket": {"label": "ENTER THE UNDERMARKET", "desc": "Buy, sell, study and modify chrome in person (10% cheaper than by courier).", "screen": "black_market"},
	"walk_stalls": {"label": "WALK THE STALLS", "desc": "New stock comes out for buyers who show their face. Maybe a new supplier.", "minutes": 30, "daily": true},
	"forged_pass": {"label": "BUY A FORGED LYRA BADGE", "desc": "Gets you past Checkpoint 9. Mostly.", "cost": 450, "once": true},
	"salvage": {"label": "PICK THROUGH THE SALVAGE", "desc": "Parts, supplies, sometimes damaged chrome.", "minutes": 60, "cost": 20, "daily": true},
	"workshop": {"label": "TOOL SERVICE AT THE WORKS", "desc": "The machinists service your tools for 60% of the usual price.", "minutes": 45},
	"market_supplies": {"label": "BROWSE THE STALLS", "desc": "The supply terminal at market prices (cheaper here, cheaper after dark).", "screen": "shop"},
	"sell_scrap": {"label": "FENCE SPARE PARTS", "desc": "Sell up to 3 parts to the scrap stalls.", "minutes": 10},
	"courier": {"label": "TAKE A COURIER JOB", "desc": "Carry a sealed case across the city. Pays; sometimes it's hot.", "minutes": 60, "daily": true},
	"metro_pass": {"label": "BUY A WEEK METRO PASS", "desc": "Free metro rides for seven days.", "cost": 60},
	"contract": {"label": "WORK A LICENSED SHIFT", "desc": "Three hours of clean, licensed clinic work. Good money, good paperwork.", "minutes": 180, "daily": true},
	"licensed_supplies": {"label": "BUY CERTIFIED STOCK", "desc": "Five supply packs with clean paperwork (lowers heat a little).", "cost": 150, "daily": true},
	"zone_pass": {"label": "APPLY FOR A CONTRACTOR PASS", "desc": "Legal access to the Exclusion Zone for approved contractors.", "cost": 300, "once": true},
	"checkpoint": {"label": "TRY THE CHECKPOINT", "desc": "Bribe the guard or try the fence.", "minutes": 20},
	"lab_salvage": {"label": "SEARCH THE COLD STORAGE", "desc": "Prototype chrome nobody logged out. Every minute here is risk.", "minutes": 60, "daily": true},
	"lab_records": {"label": "COPY THE TRIAL RECORDS", "desc": "The logs nobody wiped.", "minutes": 45, "once": true},
}


static func list(loc: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid: Variant in LocationManager.get_location(loc).get("services", []):
		var d: Dictionary = DEFS.get(str(sid), {})
		if d.is_empty():
			continue
		var s := d.duplicate()
		s["id"] = str(sid)
		s["cost"] = cost(loc, str(sid))
		s["block"] = block(loc, str(sid))
		s["desc"] = _desc(loc, str(sid), str(d["desc"]))
		out.append(s)
	return out


static func cost(loc: StringName, sid: String) -> int:
	var base := int(DEFS.get(sid, {}).get("cost", 0))
	if sid == "workshop":
		return int(ceil(InventoryManager.get_service_cost() * 0.6))
	return int(round(base * WorldSimulationManager.price_mult(loc)))


static func _key(loc: StringName, sid: String) -> String:
	return "%s|%s" % [String(loc), sid]


static func used_today(loc: StringName, sid: String) -> bool:
	return int(WorldSimulationManager.used.get(_key(loc, sid), -1)) == BusinessManager.day


static func _desc(loc: StringName, sid: String, d: String) -> String:
	match sid:
		"visit":
			var n := WorldSimulationManager.residents(loc).size()
			return "%s (%d of yours live here)" % [d, n]
		"zone_pass":
			return "%s Needs corporate standing 25+, Lyra on your side, or Glass trusting you (50)." % d
		"checkpoint":
			return "%s Your way in: %s." % [d, LocationManager.zone_access_label()]
	return d


## Why you can't use it right now ("" = you can).
static func block(loc: StringName, sid: String) -> String:
	var d: Dictionary = DEFS.get(sid, {})
	if d.is_empty():
		return "Unknown"
	if LocationManager.player_location != loc:
		return "You're not there"
	if not LocationManager.is_open(loc):
		return "Closed now"
	if WorldSimulationManager.has_flag(loc, &"unwelcome") and sid in ["recruit", "socialize", "negotiate", "tout", "walk_stalls"]:
		return "You're not welcome here (%s)" % FactionManager.get_name_of(WorldSimulationManager.dominant_faction(loc))
	if bool(d.get("daily", false)) and used_today(loc, sid):
		return "Done for today"
	if bool(d.get("once", false)) and WorldSimulationManager.used.has(_key(loc, sid)):
		return "Done"
	var c := cost(loc, sid)
	if c > 0 and not EconomyManager.can_afford(c):
		return "Need %s" % EconomyManager.format_money(c)
	var mins := int(d.get("minutes", 0))
	if mins > 0 and TimeManager.minute + mins > TimeManager.close_minute():
		return "Not enough night left"
	match sid:
		"visit":
			if WorldSimulationManager.residents(loc).is_empty():
				return "None of your patients live here"
		"undermarket":
			if not BlackMarketManager.is_unlocked():
				return "Nobody here will deal with you yet"
		"forged_pass":
			if ReputationManager.dim(&"black_market") < 10 and not StoryManager.has_flag(&"bm_access"):
				return "They don't know you well enough (black market 10)"
			if LocationManager.zone_access in ["forged", "pass"]:
				return "You already have a way in"
		"workshop":
			if c <= 0:
				return "Your tools are in good shape"
		"sell_scrap":
			if InventoryManager.parts <= 0:
				return "No spare parts"
		"metro_pass":
			if LocationManager.has_metro_pass():
				return "Your pass is still good"
		"contract":
			if FactionManager.heat >= 60.0:
				return "Your file is too hot for licensed work"
			if ReputationManager.dim(&"medical") < 0:
				return "Your medical reputation is too poor"
		"zone_pass":
			if LocationManager.zone_access == "pass":
				return "You have a pass"
			if ReputationManager.dim(&"corporate") < 25 and not StoryManager.has_flag(&"joined_lyra") and not (SupplierManager.discovered().has("glass") and int(SupplierManager.st("glass").get("trust", 0)) >= 50):
				return "Not approved: corporate standing 25+ or a Lyra contact"
		"checkpoint":
			if LocationManager.has_zone_access():
				return "You already have a way in"
		"lab_salvage", "lab_records":
			if not LocationManager.has_zone_access():
				return "You shouldn't be here"
		"negotiate":
			if ReputationManager.reputation < 15:
				return "Nobody here takes you seriously yet (REP 15)"
	return ""


static func _done(loc: StringName, sid: String) -> void:
	WorldSimulationManager.used[_key(loc, sid)] = BusinessManager.day


## Does it. {ok, text, screen} (screen: a screen to open, "" = stay).
static func perform(loc: StringName, sid: String, option: int = 0) -> Dictionary:
	var b := block(loc, sid)
	if b != "":
		return {"ok": false, "text": b, "screen": ""}
	var d: Dictionary = DEFS[sid]
	if d.has("screen"):
		return {"ok": true, "text": "", "screen": str(d["screen"])}
	var c := cost(loc, sid)
	if c > 0 and sid != "workshop" and not EconomyManager.spend(c, &"city"):
		return {"ok": false, "text": "Can't afford it", "screen": ""}
	_done(loc, sid)
	var text := _run(loc, sid, option)
	LocationManager.spend_minutes(int(d.get("minutes", 0)))
	WorldSimulationManager.add_feed(loc, text)
	WorldSimulationManager.refresh()
	SaveManager.save_game()
	return {"ok": true, "text": text, "screen": ""}


static func _rng_f() -> float:
	return randf()


static func _population(loc: StringName) -> String:
	var pop: Array = LocationManager.get_location(loc).get("population", ["civilian"])
	return str(pop[randi() % pop.size()]) if not pop.is_empty() else "civilian"


static func _run(loc: StringName, sid: String, option: int) -> String:
	var name := LocationManager.location_name(loc)
	match sid:
		"visit":
			var lines: Array[String] = []
			var asked := 0
			for pid in WorldSimulationManager.residents(loc):
				var p := PeopleManager.get_person(pid)
				PeopleManager.change_rel(pid, 1)
				if int(p.get("dependency", 0)) >= 2 and (int(p.get("next_day", -1)) < 0 or int(p["next_day"]) > BusinessManager.day):
					p["next_day"] = BusinessManager.day
					asked += 1
					lines.append("%s's hands are shaking: you tell them to come in today." % str(p["name"]))
			ReputationManager.change_dims({"civilian": 1})
			return "You do the rounds at %s. %d doors, %d cups of something hot. %s" % [name, WorldSimulationManager.residents(loc).size(), WorldSimulationManager.residents(loc).size(), " ".join(lines) if asked > 0 else "Everyone's holding up."]
		"canvass":
			var mc := WorldSimulationManager.missing_at(loc)
			if not mc.is_empty():
				return "A neighbour points you to %s's door: 'Their family's been asking.'" % str(PeopleManager.get_person(StringName(str(mc["person"]))).get("name", ""))
			var r := _rng_f()
			if r < 0.35:
				var l := LocationManager.reveal_random("A neighbour at %s told you about it." % name)
				if l != &"":
					return "A neighbour tells you about %s." % LocationManager.location_name(l)
			if r < 0.7:
				var c := WorldSimulationManager.send_patient({"archetype": _population(loc), "line": "My neighbour said you came round asking."}, loc)
				if c:
					return "A woman on the third landing says her son needs work done. %s will come to the clinic." % c.display_name
			return "Mostly complaints about the lift. You learn which unit has the good noodles."
		"rumors":
			var before := StoryManager.unlocked_rumors.size()
			StoryManager.update_rumors()
			if StoryManager.unlocked_rumors.size() > before:
				return "Over a round: %s" % StoryManager.get_rumor_text(StoryManager.unlocked_rumors[-1])
			var r := _rng_f()
			if r < 0.4:
				var l := LocationManager.reveal_random("Overheard at %s." % name)
				if l != &"":
					return "Someone mentions %s. You make a note." % LocationManager.location_name(l)
			if r < 0.75:
				var t := SupplierManager.reveal_random_lead("overheard at %s" % name)
				if t != "":
					return "A name comes up twice in one night. You get a number."
			var news := WorldEventManager.latest_news(1)
			if not news.is_empty():
				return "Everyone's talking about it: %s" % str(news[0].get("headline", ""))
			return "Nothing new. The beer is warm."
		"recruit":
			var n := 1 + (1 if _rng_f() < 0.5 else 0)
			for i in n:
				StaffManager.candidates.append(StaffManager.generate_candidate())
			StaffManager.staff_changed.emit()
			return "%d people with medic's hands take your card. They're on your candidate list (STAFF)." % n
		"tout":
			var wealth := float(WorldManager.get_district(LocationManager.district_of(loc)).get("wealth", 1.0))
			var c := WorldSimulationManager.send_patient({"archetype": _population(loc), "pay": wealth, "line": "Got your card at %s." % name}, loc)
			return ("You hand out cards for half an hour. %s takes one seriously: they'll come in." % c.display_name) if c else "Nobody bites."
		"socialize":
			var dom := WorldSimulationManager.dominant_faction(loc)
			if dom != &"":
				FactionManager.change(dom, 3)
				WorldSimulationManager.shift_presence(loc, String(dom), 0.25)
			ReputationManager.change_dims({"criminal" if dom in [&"street_gangs", &"black_market"] else "civilian": 1})
			return "You buy the right people the right drinks. %s like you a little more." % (FactionManager.get_name_of(dom) if dom != &"" else "People")
		"negotiate":
			var c := WorldSimulationManager.send_patient({"archetype": "fixer" if _rng_f() < 0.5 else "executive", "pay": 2.0, "line": "The fixer at %s sent me. No questions." % name}, loc)
			FactionManager.add_heat(3.0)
			ReputationManager.change_dims({"criminal": 1})
			return "The fixer names a price you don't argue with. %s will come to the clinic tonight, paying double." % (c.display_name if c else "A client")
		"walk_stalls":
			BlackMarketManager.refresh_stock()
			var t := ""
			if _rng_f() < 0.4:
				t = SupplierManager.reveal_random_lead("met at %s" % name)
			ReputationManager.change_dims({"black_market": 1})
			return "You walk the stalls. The Undermarket has new stock for buyers who show their face.%s" % (" A seller gives you a number." if t != "" else "")
		"forged_pass":
			LocationManager.grant_zone("forged")
			return "A badge with your face and someone else's name. It'll scan. Mostly."
		"salvage":
			var parts := 1 + randi() % 3
			InventoryManager.add_parts(parts)
			var extra := ""
			if _rng_f() < 0.35:
				InventoryManager.add_supplies(1)
				extra += " A sealed supply pack, somehow."
			if _rng_f() < 0.25:
				EventManager.apply_outcomes({"item": {"random_tier": 1, "condition": [25, 60]}})
				extra += " A damaged implant, still worth fixing."
			return "An hour in the yard: %d parts.%s" % [parts, extra]
		"workshop":
			var c := cost(loc, sid)
			if not EconomyManager.spend(c, &"tools"):
				return "Can't afford it."
			InventoryManager.tool_condition.clear()
			EventBus.inventory_changed.emit()
			return "The machinists strip, clean and true your tools for %s. Good as new." % EconomyManager.format_money(c)
		"sell_scrap":
			var n := mini(3, InventoryManager.parts)
			InventoryManager.add_parts(-n)
			var each := int(round(18.0 / WorldSimulationManager.price_mult(loc)))
			EconomyManager.add_money(n * each, &"city")
			return "%d parts to the scrap stalls at %d each." % [n, each]
		"courier":
			if _rng_f() < 0.25:
				FactionManager.add_heat(5.0)
				EconomyManager.add_money(40, &"city")
				return "The case gets you stopped twice. You deliver it, but someone took your picture. 40 credits."
			EconomyManager.add_money(85, &"city")
			ReputationManager.change_dims({"criminal": 1})
			return "Across the city and back in an hour. 85 credits for not asking."
		"metro_pass":
			LocationManager.metro_pass_until = BusinessManager.day + 6
			return "A week of free metro rides (until day %d)." % LocationManager.metro_pass_until
		"contract":
			var pay := 220 + 20 * ProgressionManager.level
			EconomyManager.add_money(pay, &"city")
			ReputationManager.change_dims({"corporate": 2, "medical": 1})
			FactionManager.change(&"medical_authorities", 1)
			ProgressionManager.add_xp(15)
			return "Three hours of clean, licensed work under fluorescent lights. %s and a signature on your file." % EconomyManager.format_money(pay)
		"licensed_supplies":
			InventoryManager.add_supplies(5)
			FactionManager.add_heat(-2.0)
			return "Five packs, every one with a certificate. Your paperwork looks a little cleaner."
		"zone_pass":
			LocationManager.grant_zone("pass")
			return "A contractor pass with your real name on it. The Zone is open to you, on the record."
		"checkpoint":
			if option == 0 and EconomyManager.can_afford(400):
				EconomyManager.spend(400, &"bribes")
				LocationManager.grant_zone("route")
				return "Four hundred into the heater vent. The guard looks at the ceiling for a while. You know the gap now."
			if _rng_f() < 0.5:
				LocationManager.grant_zone("route")
				return "You go over the fence where the floodlight flickers. You know the way now."
			FactionManager.add_heat(12.0)
			StoryManager.apply_effects({"appearance_player": "injury"})
			return "Wire cuts your palm and a dog finds you. You run. Heat up, hands shaky."
		"lab_salvage":
			var detected := LocationManager.zone_access == "forged" and _rng_f() < 0.2
			EventManager.apply_outcomes({"item": {"black_market": true, "condition": [60, 100]}})
			FactionManager.add_heat(10.0 if detected else 4.0)
			FactionManager.change(&"lyra_biocomp", -2)
			return "A prototype in a cold box, still sealed.%s" % (" The badge reader beeps red on the way out." if detected else "")
		"lab_records":
			StoryManager.apply_effects({"flag": "annex_records", "counters": {"lyra_leads": 2}})
			StoryManager.set_flag(&"lyra_gossip")
			StoryManager.unlock_rumor(&"lyra_trials")
			if CharacterManager.has_met(&"ilse_hartmann"):
				CommsManager.send_raw("message", "Ilse Hartmann", "You went into the annex", "Those are my dosing tables. I know the handwriting on the consent forms because it's mine. Bring me the copies. Please. Before anyone else sees them.", [], "annex_records")
			if not WorldSimulationManager.once_done.has("annex_patient"):
				WorldSimulationManager.start_event(loc, "annex_patient")
			return "Forty minutes at a terminal. Dosing logs, consent forms with Sump addresses, a list of beds. Down the hall, a monitor is still beeping."
	return ""
