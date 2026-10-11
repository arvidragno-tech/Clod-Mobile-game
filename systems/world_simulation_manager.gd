extends Node
## The city between your visits (data/locations.json). Lightweight and
## abstract: nothing walks around frame by frame. Everything is worked out
## from the clock when it's asked for.
##
## - Location state: how busy, how dangerous, how many police, whose turf,
##   monitored, closed, black market active, something happening. Driven by
##   the hour, factions, heat, world events and what you've done there.
## - Who is where: the cast's haunts, your patients' routines (home -> work
##   -> transit -> bar -> home), staff on their break, suppliers at their
##   tables. Rolled once per day and period so nobody flickers.
## - Ambient events at places (bar fights, accidents, raids, deals) and
##   encounters on the way between them.
## - The missing-patient chain: risky chrome -> complication -> they vanish
##   -> a relative asks -> their home -> a clue -> where they ended up.

signal changed()

const FEED_MAX := 30

var auto_roll: bool = true
## loc (String) -> {id, day, period, done, text, vars}
var events: Dictionary = {}
## loc (String) -> {faction: float}: presence you've shifted by your actions.
var shifts: Dictionary = {}
## loc (String) -> day it's closed until (inclusive)
var closures: Dictionary = {}
## person id (String) -> {stage, day, home, place, relative, clue}
var missing: Dictionary = {}
var once_done: Array[String] = []
var feed: Array[Dictionary] = []  # newest last: {day, time, loc, text}
## The travel encounter waiting for a decision ({} = none).
var encounter: Dictionary = {}
## "kind:id" -> day you last talked to them
var talked: Dictionary = {}
## "loc|service" -> day it was last used
var used: Dictionary = {}

var _events_by_id: Dictionary = {}
var _states: Dictionary = {}  # StringName -> state (cache, rebuilt from the clock)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for e: Variant in LocationManager.data.get("events", []):
		_events_by_id[str(e["id"])] = e
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: refresh())
	EventBus.period_changed.connect(_on_period_changed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.world_event_started.connect(func(_id: StringName) -> void: refresh())
	EventBus.faction_changed.connect(func(_f: StringName, _v: int, _d: int) -> void: refresh())
	EventBus.story_flag_changed.connect(_on_flag)
	PeopleManager.visit_recorded.connect(_on_visit_recorded)
	SupplierManager.changed.connect(_on_suppliers_changed)
	reset_state()


func reset_state() -> void:
	events.clear()
	shifts.clear()
	closures.clear()
	missing.clear()
	once_done.clear()
	feed.clear()
	encounter = {}
	talked.clear()
	used.clear()
	_states.clear()


# --- Location state ----------------------------------------------------------------------------

func refresh() -> void:
	_states.clear()
	changed.emit()


func state(id: StringName) -> Dictionary:
	if not _states.has(id):
		_states[id] = _compute(id)
	return _states[id]


func has_flag(id: StringName, flag: StringName) -> bool:
	if flag == &"closed":
		return int(closures.get(String(id), -1)) >= BusinessManager.day
	return (state(id)["flags"] as Array).has(flag)


func _compute(id: StringName) -> Dictionary:
	var l := LocationManager.get_location(id)
	var district := LocationManager.district_of(id)
	var period := String(TimeManager.period())
	var flags: Array[StringName] = []
	var open_hours := LocationManager.is_open(id) or id == LocationManager.CLINIC
	var activity := int(l.get("activity", {}).get(period, 2))
	var danger := int(l.get("danger", 1))
	var authority := int(l.get("authority", 0))
	var dname := WorldManager.district_name(district)
	# World situations reach the street.
	for a: Dictionary in WorldEventManager.active:
		var here := str(a.get("vars", {}).get("district", "")) == dname
		match str(a["id"]):
			"gang_war":
				if here:
					danger += 1
					activity -= 1
			"investigation":
				authority += 1
			"blackout":
				activity -= 1
			"mass_casualty":
				if LocationManager.type_of(id) == "transit":
					activity += 1
	if TimeManager.is_night() and danger >= 1:
		danger += 1
	if FactionManager.heat >= 40.0:
		authority += 1
	if FactionManager.heat >= 70.0 and authority > 0:
		authority += 1
	var facs := faction_presence(id)
	var dom := dominant_faction(id)
	if int(closures.get(String(id), -1)) >= BusinessManager.day:
		flags.append(&"closed")
		activity = 0
	elif not open_hours:
		flags.append(&"after_hours")
		activity = 0
	activity = clampi(activity, 0, 3)
	danger = clampi(danger, 0, 4)
	authority = clampi(authority, 0, 4)
	if activity >= 3:
		flags.append(&"busy")
	elif activity <= 1 and not flags.has(&"after_hours") and not flags.has(&"closed"):
		flags.append(&"quiet")
	if danger >= 3:
		flags.append(&"dangerous")
	if authority >= 3:
		flags.append(&"police")
	if bool(l.get("monitored", false)) or float(facs.get("corporate_security", 0.0)) >= 3.0:
		flags.append(&"monitored")
	if dom != &"" and float(facs.get(String(dom), 0.0)) >= 3.0:
		flags.append(&"controlled")
		if FactionManager.is_hostile(dom):
			flags.append(&"unwelcome")
	if LocationManager.is_restricted(id):
		flags.append(&"restricted")
	if float(facs.get("black_market", 0.0)) >= 2.0 and TimeManager.is_night() and open_hours:
		flags.append(&"bm_active")
	if _live_event(id) != "":
		flags.append(&"event")
	if not missing_at(id).is_empty():
		flags.append(&"lead")
	return {"activity": activity, "danger": danger, "authority": authority, "factions": facs, "dominant": dom, "flags": flags}


## Short label for the most notable thing about a place right now.
func state_label(id: StringName) -> String:
	var f: Array = state(id)["flags"]
	for pair: Array in [[&"closed", "CLOSED"], [&"after_hours", "CLOSED"], [&"lead", "A LEAD"], [&"event", "SOMETHING'S HAPPENING"], [&"police", "POLICE PRESENCE"],
			[&"unwelcome", "UNWELCOME"], [&"dangerous", "DANGEROUS"], [&"bm_active", "BLACK MARKET ACTIVE"], [&"busy", "BUSY"],
			[&"monitored", "MONITORED"], [&"quiet", "QUIET"]]:
		if f.has(pair[0]):
			return pair[1]
	return "NORMAL"


func state_color(id: StringName) -> Color:
	var f: Array = state(id)["flags"]
	if f.has(&"closed") or f.has(&"after_hours"):
		return Palette.TEXT_DIM
	if f.has(&"police") or f.has(&"dangerous") or f.has(&"unwelcome"):
		return Palette.DANGER
	if f.has(&"event") or f.has(&"bm_active") or f.has(&"lead"):
		return Palette.WARN
	return Palette.OK


static func activity_label(a: int) -> String:
	return ["DEAD", "QUIET", "STEADY", "PACKED"][clampi(a, 0, 3)]


## Faction weight at a place: its regulars, plus the district's crews, plus
## takeovers in the news, plus what your choices there have shifted.
func faction_presence(id: StringName) -> Dictionary:
	var out := {}
	var l := LocationManager.get_location(id)
	var base: Dictionary = l.get("factions", {})
	for f: Variant in base:
		out[str(f)] = float(base[f])
	var dname := WorldManager.district_name(LocationManager.district_of(id))
	for a: Dictionary in WorldEventManager.active:
		if str(a["id"]) == "district_shift" and str(a.get("vars", {}).get("district", "")) == dname:
			var fid := str(a["vars"].get("faction_id", ""))
			if fid != "":
				out[fid] = float(out.get(fid, 0.0)) + 2.0
		elif str(a["id"]) == "gang_war" and str(a.get("vars", {}).get("district", "")) == dname:
			out["street_gangs"] = float(out.get("street_gangs", 0.0)) + 1.0
	var sh: Dictionary = shifts.get(String(id), {})
	for f: Variant in sh:
		out[str(f)] = maxf(0.0, float(out.get(str(f), 0.0)) + float(sh[f]))
	return out


func dominant_faction(id: StringName) -> StringName:
	var facs := faction_presence(id)
	var best := ""
	var bw := 0.0
	for f: String in facs:
		if float(facs[f]) > bw:
			bw = float(facs[f])
			best = f
	return StringName(best)


## Your standing with whoever runs the place moves prices there.
func price_mult(id: StringName) -> float:
	var dom := dominant_faction(id)
	if dom == &"":
		return 1.0
	var r := FactionManager.get_rep(dom)
	if r >= 40:
		return 0.85
	if r >= 15:
		return 0.93
	if r <= -40:
		return 1.3
	if r <= -15:
		return 1.12
	return 1.0


func shift_presence(id: StringName, faction: String, delta: float) -> void:
	var sh: Dictionary = shifts.get(String(id), {})
	sh[faction] = clampf(float(sh.get(faction, 0.0)) + delta, -2.0, 2.0)
	shifts[String(id)] = sh
	refresh()


# --- Who is where ----------------------------------------------------------------------------------

func _roll(key: String) -> float:
	return float(hash("%s|%d|%s" % [key, BusinessManager.day, String(TimeManager.period())]) & 0xFFFF) / 65536.0


## The cast members you've met who are here now.
func cast_at(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var haunts: Dictionary = LocationManager.data.get("haunts", {})
	var p := String(TimeManager.period())
	if not LocationManager.is_open(id) and LocationManager.type_of(id) != "residential":
		return out
	for cid: Variant in haunts:
		if str(cid).begins_with("_") or not CharacterManager.has_met(StringName(str(cid))):
			continue
		for h: Dictionary in haunts[cid]:
			if str(h.get("unless", "")) != "" and StoryManager.has_flag(StringName(str(h["unless"]))):
				continue
			if not (h.get("periods", []) as Array).has(p):
				continue
			if str(h["loc"]) == String(id) and _roll(str(cid)) < float(h.get("chance", 0.5)):
				out.append(StringName(str(cid)))
			break
	return out


## Where a cast member is right now (&"" = nowhere you can find them).
func where_is_cast(cid: StringName) -> StringName:
	for id in LocationManager.order:
		if cast_at(id).has(cid):
			return id
	return &""


## Fills in a patient's home, work and favourite bar the first time it's
## needed (stored on the person, so it's saved with them).
func ensure_routine(p: Dictionary) -> Dictionary:
	if p.has("home") and p.has("work") and p.has("social"):
		return p
	var r: Dictionary = LocationManager.data.get("routines", {})
	var home := str(r.get("rich_home", "caldera_stacks")) if int(p.get("wealth", 0)) >= 2 else str(r.get("poor_home", "sump_tenements"))
	var work := str(r.get("work", {}).get(str(p.get("archetype", "")), "home"))
	if work == "home":
		work = home
	var social := str(r.get("social", {}).get(str(p.get("faction", "")), r.get("social", {}).get("", "rusty_valve")))
	p["home"] = home
	p["work"] = work
	p["social"] = social
	return p


## Where someone you treated is at this hour.
func person_place(p: Dictionary) -> StringName:
	if str(p.get("status", "")) != "alive":
		return &""
	ensure_routine(p)
	var r: Dictionary = LocationManager.data.get("routines", {})
	var night := (r.get("night_shift_archetypes", []) as Array).has(str(p.get("archetype", "")))
	var sched: Dictionary = r.get("night_shift" if night else "default", {})
	var slot := str(sched.get(String(TimeManager.period()), "home"))
	# People skip their routine sometimes (sick, broke, hiding).
	if _roll(str(p.get("id", ""))) < 0.15:
		slot = "home"
	var place := &""
	match slot:
		"work":
			place = StringName(str(p["work"]))
		"social":
			place = StringName(str(p["social"]))
		"transit":
			place = &"spindle_interchange"
		_:
			place = StringName(str(p["home"]))
	if not LocationManager.is_open(place) and LocationManager.type_of(place) != "residential":
		place = StringName(str(p["home"]))
	return place


func activity_of(p: Dictionary) -> String:
	var place := person_place(p)
	if place == StringName(str(p.get("home", ""))):
		return "at home"
	if place == StringName(str(p.get("work", ""))):
		return "working"
	if LocationManager.type_of(place) == "transit":
		return "passing through"
	return "out for the night" if TimeManager.is_night() else "out"


## Your patients (people you've treated) who are here now.
func patients_at(id: StringName, limit: int = 8) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if int(p.get("visits", 0)) <= 0 and int(p.get("rel", 0)) == 0:
			continue
		if person_place(p) == id:
			out.append(StringName(k))
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return absi(int(PeopleManager.people[String(a)].get("rel", 0))) > absi(int(PeopleManager.people[String(b)].get("rel", 0))))
	return out.slice(0, limit)


## Patients whose home is here (any time of day).
func residents(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if str(p.get("status", "")) == "alive" and int(p.get("visits", 0)) > 0 and StringName(str(ensure_routine(p)["home"])) == id:
			out.append(StringName(k))
	return out


## Staff on their break: one period a day each, at their bar.
func staff_at(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if LocationManager.type_of(id) != "bar" or not LocationManager.is_open(id):
		return out
	var periods := [&"evening", &"night", &"late_night"]
	for e in StaffManager.employees:
		var brk: StringName = periods[hash("%s|%d" % [str(e["id"]), BusinessManager.day]) % periods.size()]
		if brk == TimeManager.period() and staff_bar(e) == id:
			out.append(StringName(str(e["id"])))
	return out


func staff_bar(e: Dictionary) -> StringName:
	return &"velvet_lounge" if int(e.get("salary", 30)) >= 70 and LocationManager.is_known(&"velvet_lounge") else &"rusty_valve"


## Suppliers at their tables. Unknown ones show up as strangers.
func suppliers_at(id: StringName) -> Array[String]:
	var out: Array[String] = []
	if not LocationManager.is_open(id):
		return out
	var sh: Dictionary = LocationManager.data.get("supplier_haunts", {})
	for sid: Variant in sh:
		if str(sh[sid]) != String(id) or SupplierManager.supplier(str(sid)).is_empty() or SupplierManager.is_cut_off(str(sid)):
			continue
		var known := SupplierManager.discovered().has(str(sid))
		if _roll(str(sid)) < (0.75 if known else 0.35):
			out.append(str(sid))
	return out


## Everyone here, for the location screen.
## [{kind: cast|staff|patient|supplier, id, name, note}]
func people_at(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cid in cast_at(id):
		var c := CharacterManager.get_character(cid)
		out.append({"kind": "cast", "id": String(cid), "name": c.display_name if c else String(cid),
			"note": "%s · %s" % [c.occupation if c else "", CharacterManager.relationship_state(cid)], "talk": _talk_for(cid) != &""})
	for sid in staff_at(id):
		var e := StaffManager.get_employee(sid)
		out.append({"kind": "staff", "id": String(sid), "name": str(e.get("name", sid)), "note": "your staff · on a break (on call)"})
	for pid in patients_at(id):
		var p := PeopleManager.get_person(pid)
		var owes := PeopleManager.owed_by(pid)
		out.append({"kind": "patient", "id": String(pid), "name": str(p.get("name", pid)),
			"note": "%s · %s · %s%s" % [str(p.get("occupation", "")), activity_of(p), PeopleManager.rel_state(pid), (" · owes %d" % owes) if owes > 0 else ""]})
	for sid in suppliers_at(id):
		var known := SupplierManager.discovered().has(sid)
		out.append({"kind": "supplier", "id": sid, "name": str(SupplierManager.supplier(sid).get("name", sid)) if known else "A stranger with a sample case",
			"note": ("supplier · %s" % SupplierManager.standing(sid)) if known else "selling something"})
	return out


## A queued conversation that belongs to this character (talk in person).
func _talk_for(cid: StringName) -> StringName:
	for t: String in StoryManager.talk_queue:
		if StringName(str(DialogueManager.get_dialogue(StringName(t)).get("character", ""))) == cid:
			return StringName(t)
	return &""


func can_talk(kind: String, id: String) -> bool:
	if kind == "cast" and _talk_for(StringName(id)) != &"":
		return true
	return int(talked.get("%s:%s" % [kind, id], -1)) != BusinessManager.day


## Talks to someone here. Returns {text, dialogue} (dialogue: a story
## conversation to open, &"" if none).
## Records why standing changes in here (ChangeLog standing history).
func talk(kind: String, id: String) -> Dictionary:
	ChangeLog.push_cause("Talking around the city")
	var r: Dictionary = _talk_impl(kind, id)
	ChangeLog.pop_cause()
	return r


func _talk_impl(kind: String, id: String) -> Dictionary:
	var here := LocationManager.player_location
	if kind == "cast":
		var d := _talk_for(StringName(id))
		if d != &"":
			StoryManager.talk_queue.erase(String(d))
			return {"text": "", "dialogue": d}
	var key := "%s:%s" % [kind, id]
	if int(talked.get(key, -1)) == BusinessManager.day:
		return {"text": "You've already talked today.", "dialogue": &""}
	talked[key] = BusinessManager.day
	LocationManager.spend_minutes(15)
	var text := ""
	match kind:
		"cast":
			var cid := StringName(id)
			CharacterManager.change_relationship(cid, 1)
			var c := CharacterManager.get_character(cid)
			text = "%s has a few minutes for you. %s" % [c.display_name if c else id, _small_talk(here)]
			# People you know tell you things.
			if _rng.randf() < 0.4:
				var lead := LocationManager.reveal_random("%s told you about it." % (c.display_name if c else "Someone"))
				if lead != &"":
					text += " They mention %s." % LocationManager.location_name(lead)
		"staff":
			var e := StaffManager.get_employee(StringName(id))
			if not e.is_empty():
				e["loyalty"] = clampf(float(e["loyalty"]) + 4.0, 0.0, 100.0)
				e["stress"] = clampf(float(e.get("stress", 0.0)) - 6.0, 0.0, 100.0)
				text = "You buy %s a drink. They talk about %s. Loyalty up, stress down." % [str(e["name"]), StaffLifeManager.family_label(e).to_lower()]
		"patient":
			var pid := StringName(id)
			var p := PeopleManager.get_person(pid)
			PeopleManager.change_rel(pid, 2)
			text = "You check on %s. %s" % [str(p.get("name", id)), _patient_line(p)]
			if int(p.get("dependency", 0)) >= 2 or MemoryManager.of(pid).any(func(m: Dictionary) -> bool: return str(m.get("tag", "")) == "PLAYER_FAILED_OPERATION"):
				if int(p.get("next_day", -1)) < 0 or int(p["next_day"]) > BusinessManager.day:
					p["next_day"] = BusinessManager.day
					text += " You tell them to come by the clinic today. They will."
			# Patients mention where they work.
			var w := StringName(str(ensure_routine(p)["work"]))
			if not LocationManager.is_known(w) and not LocationManager.is_restricted(w):
				LocationManager.discover(w, "%s works there." % str(p.get("name", "")))
		"supplier":
			if SupplierManager.discovered().has(id):
				SupplierManager.change_trust(id, 2)
				text = "%s has a minute. Face to face counts: trust up." % str(SupplierManager.supplier(id).get("name", id))
			else:
				SupplierManager.discover(id, "met in person")
				text = "The stranger is %s. You leave with a number and a price list." % str(SupplierManager.supplier(id).get("name", id))
	add_feed(here, text)
	refresh()
	return {"text": text, "dialogue": &""}


func _small_talk(loc: StringName) -> String:
	var lines := {
		"bar": ["'Drink? No? Then you're working.'", "'The Valve's quiet tonight. I don't like quiet.'", "'Everyone in here owes someone.'"],
		"residential": ["'You came all the way up here? Sit down.'", "'The lift's broken again. Of course.'"],
		"corporate": ["'Careful what you say. The walls file reports.'", "'Clean floors. Dirty money.'"],
		"night_market": ["'Prices are up. Trucks didn't come.'", "'You eat yet? Noodles are on me.'"],
		"black_market": ["'Keep your voice down.'", "'Something big came in last night.'"],
		"industrial": ["'Line 3 took another hand this week.'", "'Shift's a shift.'"],
		"transit": ["'Everyone passes through here. Everyone.'", "'Trains are late. Trains are always late.'"],
		"restricted": ["'You shouldn't be here. Neither should I.'"],
	}
	var pool: Array = lines.get(LocationManager.type_of(loc), ["'Doc.'"])
	return str(pool[_rng.randi() % pool.size()])


func _patient_line(p: Dictionary) -> String:
	var r := int(p.get("rel", 0))
	if r >= 30:
		return "They light up when they see you."
	if r <= -20:
		return "They look at you like you owe them something."
	if int(p.get("dependency", 0)) >= 2:
		return "Their hands won't stop shaking."
	return "The chrome's holding."


## Can't-miss lines for the location screen's street feed.
func add_feed(loc: StringName, text: String) -> void:
	if text == "":
		return
	feed.append({"day": BusinessManager.day, "time": TimeManager.clock_text(), "loc": String(loc), "text": text})
	while feed.size() > FEED_MAX:
		feed.pop_front()


func feed_at(loc: StringName, n: int = 6) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(feed.size() - 1, -1, -1):
		if str(feed[i]["loc"]) == String(loc):
			out.append(feed[i])
			if out.size() >= n:
				break
	return out


# --- Ambient events --------------------------------------------------------------------------------

func _on_period_changed(_p: StringName) -> void:
	for id in LocationManager.known_locations():
		var e: Dictionary = events.get(String(id), {})
		if not e.is_empty() and str(e.get("period", "")) != String(TimeManager.period()):
			events.erase(String(id))
	if auto_roll:
		roll_events()
	refresh()


## Each known place gets a chance at something happening this period.
func roll_events() -> void:
	for id in LocationManager.known_locations():
		if id == LocationManager.CLINIC or events.has(String(id)) or not LocationManager.is_open(id):
			continue
		var act := int(state(id)["activity"])
		if _rng.randf() < 0.2 + 0.12 * act:
			start_event(id)


## The event happening here now ("" = none, or it's been dealt with).
func _live_event(id: StringName) -> String:
	var e: Dictionary = events.get(String(id), {})
	if e.is_empty() or bool(e.get("done", false)) or int(e.get("day", -1)) != BusinessManager.day:
		return ""
	return str(e["id"])


func event_at(id: StringName) -> Dictionary:
	var eid := _live_event(id)
	if eid == "":
		return {}
	var e: Dictionary = (_events_by_id.get(eid, {}) as Dictionary).duplicate(true)
	var live: Dictionary = events[String(id)]
	if str(live.get("text", "")) != "":
		e["text"] = live["text"]
	if live.has("choices"):
		e["choices"] = live["choices"]
	e["vars"] = live.get("vars", {})
	return e


func _eligible(id: StringName, e: Dictionary) -> bool:
	if bool(e.get("once", false)) and once_done.has(str(e["id"])):
		return false
	if FactionManager.heat < float(e.get("min_heat", -1.0)):
		return false
	if ReputationManager.reputation < int(e.get("min_rep", -999)):
		return false
	if bool(e.get("staff", false)) and staff_at(id).is_empty():
		return false
	if bool(e.get("patient_encounter", false)) and patients_at(id).is_empty():
		return false
	return true


## Starts a fitting event at a place (forced id for tests). Returns its id.
func start_event(id: StringName, force: String = "") -> String:
	var pool: Array = LocationManager.get_location(id).get("events", [])
	var eid := force
	if eid == "":
		var weights := {}
		for x: Variant in pool:
			var e: Dictionary = _events_by_id.get(str(x), {})
			if e.is_empty() or not _eligible(id, e):
				continue
			var w := float(e.get("weight", 1))
			if bool(e.get("staff", false)) or bool(e.get("patient_encounter", false)):
				w = 3.0
			weights[str(x)] = w
		if weights.is_empty():
			return ""
		eid = str(CustomerGenerator.new(_rng).pick_weighted(weights))
	var ed: Dictionary = _events_by_id.get(eid, {})
	if ed.is_empty():
		return ""
	var live := {"id": eid, "day": BusinessManager.day, "period": String(TimeManager.period()), "done": false, "vars": {}}
	if bool(ed.get("staff", false)):
		var sid := staff_at(id)
		if sid.is_empty():
			return ""
		var e := StaffManager.get_employee(sid[0])
		live["vars"] = {"staff": String(sid[0])}
		live["text"] = "%s is at the bar after their shift, staring into a drink. They look up when you come in." % str(e.get("name", "Someone"))
		live["choices"] = [
			{"label": "BUY THEM A DRINK (15)", "requires": {"money": 15}, "outcomes": {"money": -15, "staff_loyalty": 6, "text": "Two drinks, an hour of talk. They'll remember you came."}},
			{"label": "TALK SHOP", "minutes": 20, "outcomes": {"staff_loyalty": 2, "text": "You go over last week's cases. They have opinions."}},
			{"label": "LEAVE THEM ALONE", "outcomes": {"text": "Everyone needs a night off from the boss."}}]
	elif bool(ed.get("patient_encounter", false)):
		var ps := patients_at(id)
		if ps.is_empty():
			return ""
		var p := PeopleManager.get_person(ps[0])
		live["vars"] = {"person": String(ps[0])}
		live["text"] = "%s is on the platform. Your work is on them: you can see the port from here. They see you too." % str(p.get("name", "Someone"))
		live["choices"] = [
			{"label": "SAY HELLO", "outcomes": {"person_rel": 4, "person_visit": true, "text": "Five minutes on the platform. They'll drop by the clinic."}},
			{"label": "LOOK AWAY", "outcomes": {"person_rel": -2, "text": "They notice."}}]
	events[String(id)] = live
	var text := str(live.get("text", ed.get("text", "")))
	if (ed.get("choices", []) as Array).is_empty() and not live.has("choices"):
		# Cosmetic: it just happens.
		live["done"] = true
		add_feed(id, "%s: %s" % [str(ed.get("title", "")), text])
	if bool(ed.get("once", false)):
		once_done.append(eid)
	EventBus.location_event.emit(id, StringName(eid))
	refresh()
	return eid


## Chooses an option of the event here. Returns the outcome text.
func resolve_event(id: StringName, index: int) -> String:
	var e := event_at(id)
	var choices: Array = e.get("choices", [])
	if e.is_empty() or index < 0 or index >= choices.size():
		return ""
	var c: Dictionary = choices[index]
	if EventManager.get_choice_block_reason(c) != "":
		return ""
	(events[String(id)] as Dictionary)["done"] = true
	if int(c.get("minutes", 0)) > 0:
		LocationManager.spend_minutes(int(c["minutes"]))
	var text := apply(c.get("outcomes", {}), id, e.get("vars", {}))
	add_feed(id, "%s: %s" % [str(e.get("title", "")), text])
	refresh()
	return text


## Applies an outcome: the incident vocabulary (money, reputation, faction,
## heat, supplies, parts, item, flag, rumor, modifier), story effects, and
## city keys: patient (sent to your clinic), lead (supplier or place),
## candidate (a hire), zone (way into the Zone), close (place shuts for the
## day), staff_loyalty / person_rel / person_visit (with vars).
## Records why standing changes in here (ChangeLog standing history).
func apply(o: Dictionary, loc: StringName = &"", vars: Dictionary = {}) -> String:
	ChangeLog.push_cause(("At %s" % LocationManager.location_name(loc)) if loc != &"" else "In the city")
	var r: String = _apply_impl(o, loc, vars)
	ChangeLog.pop_cause()
	return r


func _apply_impl(o: Dictionary, loc: StringName = &"", vars: Dictionary = {}) -> String:
	if o.has("risk"):
		var risk: Dictionary = o["risk"]
		return apply(risk["success"] if _rng.randf() < float(risk.get("chance", 0.5)) else risk["fail"], loc, vars)
	var extra: Array[String] = []
	var base := o.duplicate()
	for k in ["patient", "lead", "candidate", "zone", "close", "staff_loyalty", "person_rel", "person_visit", "effects"]:
		base.erase(k)
	var text := EventManager.apply_outcomes(base)
	if o.has("effects"):
		StoryManager.apply_effects(o["effects"])
	# What you did here moves who feels at home here.
	var fac: Dictionary = o.get("faction", {})
	for f: Variant in fac:
		if loc != &"" and int(fac[f]) != 0:
			shift_presence(loc, str(f), 0.25 * signf(float(fac[f])))
	if o.has("patient"):
		var c := send_patient(o["patient"], loc)
		if c:
			extra.append("%s is on their way to your clinic." % c.display_name)
	if o.has("lead"):
		var t := SupplierManager.reveal_random_lead("met at %s" % LocationManager.location_name(loc))
		if t == "":
			var l := LocationManager.reveal_random("Someone at %s told you about it." % LocationManager.location_name(loc))
			if l != &"":
				extra.append("New place: %s." % LocationManager.location_name(l))
	if bool(o.get("candidate", false)):
		StaffManager.candidates.append(StaffManager.generate_candidate())
		StaffManager.staff_changed.emit()
	if o.has("zone"):
		LocationManager.grant_zone(str(o["zone"]))
	if bool(o.get("close", false)) and loc != &"":
		closures[String(loc)] = BusinessManager.day
	if o.has("staff_loyalty") and vars.has("staff"):
		var e := StaffManager.get_employee(StringName(str(vars["staff"])))
		if not e.is_empty():
			e["loyalty"] = clampf(float(e["loyalty"]) + float(o["staff_loyalty"]), 0.0, 100.0)
	if vars.has("person"):
		var pid := StringName(str(vars["person"]))
		if o.has("person_rel"):
			PeopleManager.change_rel(pid, int(o["person_rel"]))
		if bool(o.get("person_visit", false)):
			var p := PeopleManager.get_person(pid)
			if not p.is_empty() and str(p.get("status", "")) == "alive":
				p["next_day"] = BusinessManager.day
	if not extra.is_empty():
		text = ("%s %s" % [text, " ".join(extra)]).strip_edges()
	return text


## Someone you met out there walks into your clinic: next through the door.
func send_patient(spec: Dictionary, loc: StringName = &"") -> CustomerData:
	var opts := {"archetype": str(spec.get("archetype", "civilian"))}
	if spec.has("category"):
		opts["category"] = str(spec["category"])
	var c := CustomerManager.generator.generate(opts)
	if c == null:
		return null
	c.is_emergency = bool(spec.get("emergency", false))
	c.pay_multiplier *= float(spec.get("pay", 1.0)) * (1.5 if c.is_emergency else 1.0)
	if spec.has("line"):
		c.dialogue = str(spec["line"])
	CustomerManager.generator.roll_budget(c)
	var entry := {"customer": c.to_save_dict(), "due_op": 0, "due_day": BusinessManager.day}
	if c.is_emergency:
		CustomerManager.queue.push_front(entry)
	else:
		CustomerManager.queue.append(entry)
	ClinicLifeManager.post("%s is coming in: met you at %s." % [c.display_name, LocationManager.location_name(loc) if loc != &"" else "the street"])
	return c


# --- Travel encounters -------------------------------------------------------------------------------

func has_encounter() -> bool:
	return not encounter.is_empty()


## Something on the way. Returns the encounter ({} = an uneventful trip).
func roll_encounter(mode: String, from: StringName, to: StringName, risk: float, force: String = "") -> Dictionary:
	if force == "" and (not auto_roll or from == to):
		return {}
	var danger := maxi(int(WorldManager.get_district(LocationManager.district_of(from)).get("danger", 1)),
		int(WorldManager.get_district(LocationManager.district_of(to)).get("danger", 1)))
	var p := (0.06 + 0.04 * danger + (0.08 if TimeManager.is_night() else 0.0)) * risk
	if force == "" and _rng.randf() >= p:
		return {}
	var weights := {}
	var defs := {}
	for e: Dictionary in LocationManager.data.get("travel", {}).get("encounters", []):
		var id := str(e["id"])
		defs[id] = e
		if force != "":
			continue
		if danger < int(e.get("min_danger", 0)) or FactionManager.heat < float(e.get("min_heat", -1.0)):
			continue
		if bool(e.get("night", false)) and not TimeManager.is_night():
			continue
		if e.has("mode") and str(e["mode"]) != mode:
			continue
		weights[id] = float(e.get("weight", 1))
	var pick := force
	if pick == "":
		if weights.is_empty():
			return {}
		pick = str(CustomerGenerator.new(_rng).pick_weighted(weights))
	var ed: Dictionary = defs.get(pick, {})
	if ed.is_empty():
		return {}
	if bool(ed.get("cosmetic", false)) or (ed.get("choices", []) as Array).is_empty():
		add_feed(to, "On the way: %s" % str(ed.get("text", "")))
		return {}
	encounter = {"id": pick, "text": str(ed.get("text", "")), "choices": (ed.get("choices", []) as Array).duplicate(true), "mode": mode, "from": String(from), "to": String(to)}
	return encounter


func resolve_encounter(index: int) -> String:
	var choices: Array = encounter.get("choices", [])
	if index < 0 or index >= choices.size():
		return ""
	var c: Dictionary = choices[index]
	if EventManager.get_choice_block_reason(c) != "":
		return ""
	var to := StringName(str(encounter.get("to", "")))
	encounter = {}
	var text := apply(c.get("outcomes", {}), to)
	add_feed(to, "On the way: %s" % text)
	refresh()
	return text


# --- The missing-patient chain -------------------------------------------------------------------------

func _missing_cfg() -> Dictionary:
	return LocationManager.data.get("missing", {})


func _at_risk(k: String, p: Dictionary) -> bool:
	if str(p.get("status", "")) != "alive" or int(p.get("visits", 0)) <= 0:
		return false
	if int(p.get("dependency", 0)) >= 2:
		return true
	for m: Dictionary in MemoryManager.of(StringName(k)):
		if str(m.get("tag", "")) == "PLAYER_FAILED_OPERATION":
			return true
	for cid: Variant in p.get("cyber", []):
		var it := CyberwareManager.get_cyberware(StringName(str(cid)))
		if it and it.black_market:
			return true
	return false


## A patient with risky chrome disappears. Returns their id (&"" = nobody).
func start_missing(force_id: StringName = &"") -> StringName:
	var id := force_id
	if id == &"":
		var pool: Array[String] = []
		for k: String in PeopleManager.people:
			if not missing.has(k) and _at_risk(k, PeopleManager.people[k]):
				pool.append(k)
		if pool.is_empty():
			return &""
		id = StringName(pool[_rng.randi() % pool.size()])
	var p := PeopleManager.get_person(id)
	if p.is_empty() or str(p.get("status", "")) != "alive":
		return &""
	ensure_routine(p)
	var places: Array[String] = [str(p["work"]), "furnace_works", "flood_tunnels", "spindle_interchange"]
	places = places.filter(func(x: String) -> bool: return x != str(p["home"]) and LocationManager.has_location(StringName(x)))
	var place := places[_rng.randi() % places.size()]
	var names: Array = CustomerManager.names.get("first", ["Mara"])
	var relative := str(names[_rng.randi() % names.size()])
	var clues: Array = _missing_cfg().get("clues", ["Last seen heading to {place}."])
	missing[String(id)] = {"stage": 0, "day": BusinessManager.day, "home": str(p["home"]), "place": place, "relative": relative,
		"clue": str(clues[_rng.randi() % clues.size()])}
	p["status"] = "missing"
	p["next_day"] = -1
	PeopleManager.note(id, "Went missing.")
	var home := StringName(str(p["home"]))
	LocationManager.discover(home, "%s gave you the address." % relative)
	CommsManager.send_raw("message", relative, "Have you seen %s?" % str(p["name"]),
		"This is %s. %s hasn't come home in two days. They were at your clinic. The chrome you put in... they said it was talking to them. Their place is at %s. Please." % [relative, str(p["name"]), LocationManager.location_name(home)],
		[], "missing")
	add_feed(home, "%s is missing. %s is asking around." % [str(p["name"]), relative])
	refresh()
	return id


## The missing case you can work on here ({} = none): {person, stage, text, choices}.
func missing_at(loc: StringName) -> Dictionary:
	for k: String in missing:
		var m: Dictionary = missing[k]
		var p := PeopleManager.get_person(StringName(k))
		var vars := {"name": str(p.get("name", "")), "relative": str(m["relative"]), "place": LocationManager.location_name(StringName(str(m["place"])))}
		if int(m["stage"]) == 0 and str(m["home"]) == String(loc):
			return {"person": k, "stage": 0, "title": "MISSING: %s" % str(vars["name"]).to_upper(),
				"text": "%s's unit. %s waits by the door, arms crossed." % [vars["name"], vars["relative"]],
				"choices": [{"label": "SEARCH THEIR PLACE (20 min)", "minutes": 20}]}
		if int(m["stage"]) == 1 and str(m["place"]) == String(loc):
			return {"person": k, "stage": 1, "title": "FOUND: %s" % str(vars["name"]).to_upper(),
				"text": _fill(str(_missing_cfg().get("found", "You find {name} at {place}.")), vars),
				"choices": [
					{"label": "GET THEM TO YOUR CLINIC NOW", "requires": {"supplies": 1}},
					{"label": "CALL %s TO COME GET THEM" % str(vars["relative"]).to_upper()},
					{"label": "WALK AWAY"}]}
	return {}


## Records why standing changes in here (ChangeLog standing history).
func act_missing(loc: StringName, index: int) -> String:
	ChangeLog.push_cause("Missing person at %s" % LocationManager.location_name(loc))
	var r: String = _act_missing_impl(loc, index)
	ChangeLog.pop_cause()
	return r


func _act_missing_impl(loc: StringName, index: int) -> String:
	var mc := missing_at(loc)
	if mc.is_empty():
		return ""
	var k := str(mc["person"])
	var m: Dictionary = missing[k]
	var id := StringName(k)
	var p := PeopleManager.get_person(id)
	var vars := {"name": str(p.get("name", "")), "relative": str(m["relative"]), "place": LocationManager.location_name(StringName(str(m["place"])))}
	var text := ""
	if int(mc["stage"]) == 0:
		LocationManager.spend_minutes(20)
		m["stage"] = 1
		text = _fill(str(m["clue"]), vars)
		LocationManager.discover(StringName(str(m["place"])), "A clue in %s's place." % vars["name"])
	else:
		match index:
			0:
				if not InventoryManager.use_supplies(1):
					return ""
				missing.erase(k)
				p["status"] = "alive"
				var c := PeopleManager.make_customer(id)
				if c:
					c.is_emergency = true
					c.dialogue = "I can't... the arm won't stop. You found me."
					CustomerManager.queue.push_front({"customer": c.to_save_dict(), "due_op": 0, "due_day": BusinessManager.day})
				PeopleManager.change_rel(id, 15)
				MemoryManager.remember(id, &"PLAYER_SAVED_ME", "", "found them")
				ReputationManager.change_dims({"civilian": 3})
				PeopleManager.note(id, "You found them and brought them in.")
				text = "You get %s on their feet and into a cab. They'll be on your table tonight." % vars["name"]
			1:
				missing.erase(k)
				p["status"] = "alive"
				p["next_day"] = BusinessManager.day + 1
				PeopleManager.change_rel(id, 6)
				PeopleManager.note(id, "Found; family took them home.")
				text = "%s comes running. They'll bring %s in tomorrow." % [vars["relative"], vars["name"]]
			_:
				missing.erase(k)
				PeopleManager.mark_dead(id, "Left where you found them.")
				ReputationManager.change_dims({"civilian": -3})
				WorldEventManager.post("Body found at %s" % vars["place"], "A resident of %s, recently fitted with cyberware, was found dead. Family say they 'went to a doctor'." % LocationManager.location_name(StringName(str(m["home"]))))
				text = "You walk away. You hear about it on the news two days later."
	add_feed(loc, text)
	refresh()
	return text


func _check_missing_deadlines() -> void:
	var limit := int(_missing_cfg().get("deadline_days", 4))
	for k: String in missing.keys():
		var m: Dictionary = missing[k]
		if BusinessManager.day - int(m["day"]) <= limit:
			continue
		var p := PeopleManager.get_person(StringName(k))
		missing.erase(k)
		if p.is_empty():
			continue
		PeopleManager.mark_dead(StringName(k), "Found dead after going missing.")
		WorldEventManager.post("Missing resident found dead", "%s, missing for %d days, was found at %s. Their cyberware was still running." % [str(p.get("name", "")), limit, LocationManager.location_name(StringName(str(m["place"])))])
		CommsManager.send_raw("message", str(m["relative"]), "They found %s" % str(p.get("name", "")), "Too late. I asked you.", [], "missing_dead")


static func _fill(t: String, vars: Dictionary) -> String:
	for k: Variant in vars:
		t = t.replace("{%s}" % str(k), str(vars[k]))
	return t


# --- Hooks ---------------------------------------------------------------------------------------------

func _on_day_started(_day: int) -> void:
	events.clear()
	encounter = {}
	for k: String in closures.keys():
		if int(closures[k]) < BusinessManager.day:
			closures.erase(k)
	# Shifted presence drifts back.
	for l: String in shifts.keys():
		var sh: Dictionary = shifts[l]
		for f: String in sh.keys():
			var v := float(sh[f])
			v = maxf(0.0, v - 0.1) if v > 0.0 else minf(0.0, v + 0.1)
			if absf(v) < 0.01:
				sh.erase(f)
			else:
				sh[f] = v
		if sh.is_empty():
			shifts.erase(l)
	_check_missing_deadlines()
	if auto_roll and missing.is_empty() and _rng.randf() < float(_missing_cfg().get("daily_chance", 0.08)):
		start_missing()
	_on_suppliers_changed()
	refresh()


func _on_flag(_flag: StringName, _v: bool) -> void:
	if GameManager.is_running:
		LocationManager.check_discovery()


## A patient you helped sometimes tells you about where they work.
func _on_visit_recorded(id: StringName, outcome: String) -> void:
	if not outcome in ["success", "stabilized"] or _rng.randf() >= 0.25:
		return
	var p := PeopleManager.get_person(id)
	if p.is_empty():
		return
	ensure_routine(p)
	for key in ["work", "social"]:
		var l := StringName(str(p[key]))
		if LocationManager.has_location(l) and not LocationManager.is_known(l) and not LocationManager.is_restricted(l):
			LocationManager.discover(l, "%s mentioned it on the table." % str(p.get("name", "A patient")))
			return


## Suppliers you've found deal out of somewhere: you learn where.
func _on_suppliers_changed() -> void:
	var sh: Dictionary = LocationManager.data.get("supplier_haunts", {})
	for sid: String in SupplierManager.discovered():
		var l := StringName(str(sh.get(sid, "")))
		if l != &"" and LocationManager.has_location(l) and not LocationManager.is_known(l) and not LocationManager.is_restricted(l):
			LocationManager.discover(l, "%s deals out of there." % str(SupplierManager.supplier(sid).get("name", sid)))


# --- Save ------------------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"events": events.duplicate(true), "shifts": shifts.duplicate(true), "closures": closures.duplicate(),
		"missing": missing.duplicate(true), "once": once_done.duplicate(), "feed": feed.duplicate(true),
		"encounter": encounter.duplicate(true), "talked": talked.duplicate(), "used": used.duplicate()}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	for key in ["events", "shifts", "closures", "missing", "talked", "used"]:
		var v: Variant = d.get(key, {})
		if v is Dictionary:
			(get(key) as Dictionary).merge(v, true)
	for o: Variant in d.get("once", []):
		once_done.append(str(o))
	for f: Variant in d.get("feed", []):
		if f is Dictionary:
			feed.append(f)
	var enc: Variant = d.get("encounter", {})
	encounter = enc if enc is Dictionary else {}
	# A missing person whose case was lost is home again.
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if str(p.get("status", "")) == "missing" and not missing.has(k):
			p["status"] = "alive"
	refresh()
