extends Node
## The city moves without you (data/world_events.json).
##
## SITUATIONS last a few days and bend everything: a gang war fills the
## door with gunshot wounds, a manufacturer's recall sends your patients
## back, a MedBoard inquiry brings inspectors, a fixer vanishes and black-
## market prices jump, a port strike makes supplies expensive, a tram
## derails and the wounded line up, a faction takes over the district,
## someone you know gets picked up in a sweep. They start from what's
## true (day, heat, who you know, black-market access) and their effects
## are weights and modifiers, so they colour play rather than script it.
##
## NEWS: every situation makes the wire, and so do you: bodies piling up,
## a clean-handed street doc, a gang-linked clinic, door-to-door sweeps
## when heat is high. Ordinary filler keeps the ticker alive. Stories about
## the clinic get clipped and pinned to the Wall.

const MAX_NEWS := 40

## Situations start on their own at dawn (tests turn this off for determinism).
var auto_roll: bool = true
var data: Dictionary = {}
## [{id, start, days_left, vars: {district, faction, maker, name}}]
var active: Array[Dictionary] = []
var news: Array[Dictionary] = []  # {day, minute, headline, body, about_you}
## reactive id -> day last posted
var _reactive_last: Dictionary = {}
var deaths_today: int = 0
## Last identity the street gave you (news when it changes).
var identity_id: String = "nobody"
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_WORLD_EVENTS)
	if d is Dictionary:
		data = d
	EventBus.day_started.connect(_on_day_started)
	EventBus.day_ended.connect(_on_day_ended)
	PeopleManager.visit_recorded.connect(_on_visit)
	reset_state()


func reset_state() -> void:
	active.clear()
	news.clear()
	_reactive_last.clear()
	deaths_today = 0
	identity_id = "nobody"


# --- Queries ------------------------------------------------------------------------------

func situation(id: StringName) -> Dictionary:
	for s: Dictionary in data.get("situations", []):
		if str(s["id"]) == String(id):
			return s
	return {}


func is_active(id: StringName) -> bool:
	return active.any(func(a: Dictionary) -> bool: return str(a["id"]) == String(id))


func _mult(table: String, key: String) -> float:
	var m := 1.0
	for a in active:
		m *= float(situation(StringName(str(a["id"]))).get(table, {}).get(key, 1.0))
	return m


func archetype_weight(id: String) -> float:
	return _mult("archetypes", id)


func event_weight(id: StringName) -> float:
	return _mult("events", String(id))


## Faction presence at the door (district takeovers).
func faction_weight(f: StringName) -> float:
	var m := 1.0
	for a in active:
		if str(a["id"]) == "district_shift" and str(a["vars"].get("faction_id", "")) == String(f):
			m *= 2.0
	return m


func get_modifiers() -> Dictionary:
	var out := {}
	for a in active:
		var mods: Dictionary = situation(StringName(str(a["id"]))).get("mods", {})
		for k: Variant in mods:
			out[k] = float(out.get(k, 0.0)) + float(mods[k])
	return out


func latest_news(n: int = 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(news.size() - 1, maxi(-1, news.size() - 1 - n), -1):
		out.append(news[i])
	return out


# --- Days ---------------------------------------------------------------------------------

func _on_day_started(_day: int) -> void:
	deaths_today = 0
	# Running situations tick down; finished ones make the news once more.
	for i in range(active.size() - 1, -1, -1):
		active[i]["days_left"] = int(active[i]["days_left"]) - 1
		if int(active[i]["days_left"]) <= 0:
			var s := situation(StringName(str(active[i]["id"])))
			if s.has("end"):
				post(_fill(str(s["end"]), active[i]["vars"]), "")
			active.remove_at(i)
	EventBus.modifiers_changed.emit()
	if auto_roll and active.size() < int(data.get("max_active", 2)) and _rng.randf() < float(data.get("daily_chance", 0.4)):
		roll()
	# Something ordinary on the wire every day.
	var filler: Array = data.get("filler", [])
	if not filler.is_empty():
		post(str(filler[_rng.randi() % filler.size()]), "")


## Starts a fitting situation at random. Returns its id ("" = none).
func roll() -> String:
	var weights := {}
	var list: Array = data.get("situations", [])
	for i in list.size():
		var s: Dictionary = list[i]
		if is_active(StringName(str(s["id"]))) or not _cond_ok(s.get("cond", {})):
			continue
		var w := float(s.get("weight", 1))
		# A gang-linked clinic gets investigated; corporate friends attract recalls' attention less.
		if str(s["id"]) == "investigation":
			w *= 1.0 + maxi(0, ReputationManager.dim(&"criminal")) / 25.0
		weights[i] = w
	if weights.is_empty():
		return ""
	var s: Dictionary = list[int(CustomerGenerator.new(_rng).pick_weighted(weights))]
	start(StringName(str(s["id"])))
	return str(s["id"])


func _cond_ok(c: Dictionary) -> bool:
	if BusinessManager.day < int(c.get("min_day", 0)):
		return false
	if FactionManager.heat < float(c.get("min_heat", -1.0)) or FactionManager.heat > float(c.get("max_heat", 1000.0)):
		return false
	if bool(c.get("bm", false)) and not BlackMarketManager.is_unlocked():
		return false
	if bool(c.get("person", false)) and _known_people().is_empty():
		return false
	return true


func _known_people() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if str(p.get("status", "")) == "alive" and int(p.get("visits", 0)) >= 1 and int(p.get("rel", 0)) >= 0:
			out.append(StringName(k))
	return out


## Starts a situation now (also used by story beats and tests).
func start(id: StringName) -> bool:
	var s := situation(id)
	if s.is_empty():
		return false
	var dr: Array = s.get("days", [2, 3])
	var vars := {"district": WorldManager.district_name(), "name": _fixer_name()}
	var entry := {"id": String(id), "start": BusinessManager.day, "days_left": _rng.randi_range(int(dr[0]), int(dr[1])), "vars": vars}
	match str(s.get("special", "")):
		"recall":
			var makers: Array = s.get("makers", ["Halden Microsystems"])
			vars["maker"] = str(makers[_rng.randi() % makers.size()])
			_recall(str(vars["maker"]))
		"district_shift":
			var fs: Array = FactionManager.order.duplicate()
			var f: StringName = fs[_rng.randi() % fs.size()]
			vars["faction"] = FactionManager.get_name_of(f)
			vars["faction_id"] = String(f)
		"casualties":
			_casualties(int(s.get("casualties", 2)))
		"trouble":
			return _trouble()
	active.append(entry)
	StoryManager.apply_effects(s.get("effects", {}))
	if s.has("headline"):
		post(_fill(str(s["headline"]), vars), _fill(str(s.get("body", "")), vars))
	EventBus.modifiers_changed.emit()
	EventBus.world_event_started.emit(id)
	return true


func _fixer_name() -> String:
	var names: Dictionary = CustomerManager.names
	var al: Array = names.get("alias", ["Ghost"])
	return str(al[_rng.randi() % al.size()])


## Everyone you put that maker's chrome into comes back for a fix.
func _recall(maker: String) -> void:
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if str(p.get("status", "")) != "alive":
			continue
		for cid: Variant in p.get("cyber", []):
			var it := CyberwareManager.get_cyberware(StringName(str(cid)))
			if it and it.manufacturer == maker:
				p["next_day"] = BusinessManager.day + _rng.randi_range(0, 2)
				PeopleManager.note(StringName(k), "Recalled %s. Coming back." % it.display_name)
				break


## The wounded line up at the door.
func _casualties(n: int) -> void:
	for i in n:
		var c := CustomerManager.generator.generate({"archetype": ["civilian", "dock_worker", "elder"][i % 3], "category": "dermal"})
		c.is_emergency = true
		c.bleed_multiplier *= 1.3
		c.dialogue = "Glass in my side from the tram. They said you were open."
		CustomerManager.generator.roll_budget(c)
		CustomerManager.queue.push_front({"customer": c.to_save_dict(), "due_op": 0, "due_day": BusinessManager.day})


## Someone you know needs you. A COMMS message with choices.
func _trouble() -> bool:
	var people := _known_people()
	if people.is_empty():
		return false
	var id: StringName = people[_rng.randi() % people.size()]
	var p := PeopleManager.get_person(id)
	var t: Dictionary = data.get("trouble", {})
	var vars := {"name": str(p["name"])}
	var acts: Array = (t.get("actions", []) as Array).duplicate(true)
	var uid := CommsManager.send_raw("message", "", _fill(str(t.get("subject", "")), vars), _fill(str(t.get("body", "")), vars), acts, "world_trouble")
	CommsManager.get_message(uid)["vars"] = {"kind": "person", "person": String(id)}
	EventBus.world_event_started.emit(&"trouble")
	return true


## A COMMS action about a person (see "trouble").
func apply_person(fx: Dictionary, vars: Dictionary) -> void:
	var id := StringName(str(vars.get("person", "")))
	var p := PeopleManager.get_person(id)
	if p.is_empty():
		return
	if fx.has("memory"):
		MemoryManager.remember(id, StringName(str(fx["memory"])))
	if fx.has("rel"):
		PeopleManager.change_rel(id, int(fx["rel"]))
	if fx.has("return_days"):
		p["next_day"] = BusinessManager.day + int(fx["return_days"])
	if bool(fx.get("emergency", false)):
		var c := PeopleManager.make_customer(id)
		if c:
			c.is_emergency = true
			c.terms = &"free"
			c.dialogue = "They carry %s in between them. \"Security did this. You said you'd help.\"" % c.display_name
			CustomerManager.queue.push_front({"customer": c.to_save_dict(), "due_op": 0, "due_day": BusinessManager.day})


# --- News ---------------------------------------------------------------------------------

func post(headline: String, body: String, about_you: bool = false) -> void:
	var item := {"day": BusinessManager.day, "minute": TimeManager.minute, "headline": headline, "body": body, "about_you": about_you}
	news.append(item)
	while news.size() > MAX_NEWS:
		news.pop_front()
	EventBus.news_posted.emit(item)
	if about_you:
		ClinicLifeManager.pin("clipping", headline, body, "news_%d_%s" % [BusinessManager.day, headline.left(16)])


func _on_visit(_id: StringName, outcome: String) -> void:
	if outcome == "death":
		deaths_today += 1


## At night the wire reacts to what the clinic did.
func _on_day_ended(_day: int, report: Dictionary) -> void:
	var idn := ReputationManager.identity()
	if str(idn["id"]) != identity_id and str(idn["id"]) != "nobody":
		identity_id = str(idn["id"])
		post("The lower city has a name for the doc in %s: %s" % [WorldManager.district_name(), str(idn["title"]).to_lower()], str(idn["text"]), true)
		(report.get("notes", []) as Array).append("The street calls you %s now." % idn["title"])
	for r: Dictionary in data.get("reactive", []):
		var id := str(r["id"])
		if BusinessManager.day - int(_reactive_last.get(id, -1000)) < int(r.get("cooldown", 5)):
			continue
		if _metric(str(r["check"])) < float(r["min"]):
			continue
		_reactive_last[id] = BusinessManager.day
		ReputationManager.change_dims(r.get("dims", {}))
		if r.has("heat"):
			FactionManager.add_heat(float(r["heat"]))
		post(_fill(str(r["headline"]), {"district": WorldManager.district_name()}), "", bool(r.get("clip", false)))


func _metric(check: String) -> float:
	match check:
		"deaths_today":
			return deaths_today
		"dim_medical":
			return ReputationManager.dim(&"medical")
		"dim_criminal":
			return ReputationManager.dim(&"criminal")
		"heat":
			return FactionManager.heat
		"loyal_people":
			return PeopleManager.people.values().filter(func(p: Dictionary) -> bool: return bool(p.get("loyal", false))).size()
		"free_jobs":
			return MemoryManager.who_remembers(&"PLAYER_TREATED_FREE").size()
		"overcharged":
			return MemoryManager.who_remembers(&"PLAYER_OVERCHARGED_ME").size()
	return 0.0


func _fill(s: String, vars: Dictionary) -> String:
	for k: Variant in vars:
		s = s.replace("{%s}" % k, str(vars[k]))
	return s


# --- Save ---------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"active": active.duplicate(true), "news": news.duplicate(true), "reactive": _reactive_last.duplicate(), "deaths_today": deaths_today, "identity": identity_id}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	for a: Variant in d.get("active", []):
		if a is Dictionary and not situation(StringName(str(a.get("id", "")))).is_empty():
			active.append(a)
	for n: Variant in d.get("news", []):
		if n is Dictionary:
			news.append(n)
	var r: Dictionary = d.get("reactive", {})
	for k: Variant in r:
		_reactive_last[str(k)] = int(r[k])
	deaths_today = int(d.get("deaths_today", 0))
	identity_id = str(d.get("identity", "nobody"))
	EventBus.modifiers_changed.emit()
