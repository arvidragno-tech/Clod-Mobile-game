extends Node
## Places in Caldera (data/locations.json): DISTRICT -> LOCATION. Keeps the
## registry, what the player has discovered, where the player is, opening
## hours, access to the Exclusion Zone and travel (time, cost, risk). What
## a place is like right now, who is there and what happens there is
## WorldSimulationManager's job; what you can do there is LocationServices.
##
## Being away from the clinic is real: the clock moves with every trip,
## nobody new walks in while you're out (people sit on the bench if
## there's room), and the clinic is easier to rob at night.

signal moved(id: StringName)
signal discovered(id: StringName)

const CLINIC := &"clinic"

var data: Dictionary = {}
var types: Dictionary = {}
var locations: Dictionary = {}  # StringName -> Dictionary
var order: Array[StringName] = []
var modes: Array = []

var known: Array[StringName] = []
var player_location: StringName = CLINIC
## How you get into the Exclusion Zone: "" none, "route" (a gap in the
## fence), "forged" (a fake badge), "pass" (a real contractor pass).
var zone_access: String = ""
var metro_pass_until: int = 0
var visits: Dictionary = {}  # StringName -> int
## Minutes spent away from the clinic tonight (theft risk).
var away_minutes_night: int = 0
var last_trip: Dictionary = {}


func _ready() -> void:
	var d: Variant = DataLoader.load_json(GameConfig.DATA_LOCATIONS)
	if d is Dictionary:
		data = d
		types = d.get("types", {})
		modes = d.get("travel", {}).get("modes", [])
		for e: Variant in d.get("locations", []):
			var id := StringName(str(e["id"]))
			locations[id] = e
			order.append(id)
	EventBus.day_started.connect(_on_day_started)
	reset_state()


func reset_state() -> void:
	known.clear()
	player_location = CLINIC
	zone_access = ""
	metro_pass_until = 0
	visits.clear()
	away_minutes_night = 0
	last_trip = {}
	for id in order:
		if bool(get_location(id).get("discover", {}).get("start", false)):
			known.append(id)


# --- Registry ------------------------------------------------------------------------------------

func get_location(id: StringName) -> Dictionary:
	return locations.get(id, {})


func has_location(id: StringName) -> bool:
	return locations.has(id)


func location_name(id: StringName) -> String:
	if id == CLINIC:
		return ClinicManager.get_tier_name()
	return str(get_location(id).get("name", id))


func type_of(id: StringName) -> String:
	return str(get_location(id).get("type", ""))


func type_label(id: StringName) -> String:
	return str(types.get(type_of(id), {}).get("label", type_of(id).to_upper()))


## The clinic moves with your practice; everything else stays put.
func district_of(id: StringName) -> StringName:
	if id == CLINIC:
		return WorldManager.current_district_id()
	return StringName(str(get_location(id).get("district", "")))


## Marker position on the city map (fractions of the map art).
func map_pos(id: StringName) -> Vector2:
	var m: Array = get_location(id).get("map", [])
	if id == CLINIC or m.size() < 2:
		var dm: Array = WorldManager.get_district(district_of(id)).get("map", [0.5, 0.5])
		return Vector2(float(dm[0]), float(dm[1]))
	return Vector2(float(m[0]), float(m[1]))


func in_district(district: StringName, only_known: bool = true) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if district_of(id) == district and (not only_known or is_known(id)):
			out.append(id)
	return out


func known_locations() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if is_known(id):
			out.append(id)
	return out


func of_type(t: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if type_of(id) == t:
			out.append(id)
	return out


# --- Discovery -----------------------------------------------------------------------------------

func is_known(id: StringName) -> bool:
	return known.has(id)


## Reveals a place. `how` is told to the player ("Rook mentioned it").
func discover(id: StringName, how: String = "") -> bool:
	if not locations.has(id) or known.has(id):
		return false
	known.append(id)
	var l := get_location(id)
	var body := str(l.get("description", ""))
	if how != "":
		body = "%s\n\n%s" % [how, body]
	CommsManager.send_raw("message", "", "New place: %s (%s)" % [location_name(id), WorldManager.district_name(district_of(id))], body, [], "location_found")
	discovered.emit(id)
	EventBus.location_discovered.emit(id)
	return true


## Places whose own conditions now hold reveal themselves (word gets around).
func check_discovery() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if known.has(id):
			continue
		if _discover_cond(get_location(id).get("discover", {})):
			discover(id, "Word gets around.")
			out.append(id)
	return out


func _discover_cond(c: Dictionary) -> bool:
	if c.is_empty() or bool(c.get("hidden", false)):
		return false
	if bool(c.get("start", false)):
		return true
	if bool(c.get("bm", false)):
		return BlackMarketManager.is_unlocked()
	var any: Array = c.get("any_flag", [])
	for f: Variant in any:
		if StoryManager.has_flag(StringName(str(f))):
			return true
	if c.has("flag"):
		return StoryManager.has_flag(StringName(str(c["flag"])))
	if c.has("level"):
		return ProgressionManager.level >= int(c["level"])
	return false


## A place nobody has told you about yet (rumours, fixers): reveals one.
func reveal_random(how: String = "A rumour.") -> StringName:
	var pool: Array[StringName] = []
	for id in order:
		if not known.has(id) and not bool(get_location(id).get("discover", {}).get("hidden", false)):
			pool.append(id)
	if pool.is_empty():
		return &""
	var id: StringName = pool[randi() % pool.size()]
	discover(id, how)
	return id


# --- Hours and access ----------------------------------------------------------------------------

## Clock minutes on the 06:00..30:00 dial (after midnight = +1440).
static func dial(m: int) -> int:
	var t := m % TimeManager.MINUTES_PER_DAY
	return t + TimeManager.MINUTES_PER_DAY if t < 360 else t


func is_open(id: StringName, m: int = -1) -> bool:
	if id == CLINIC:
		return true
	var h: Array = get_location(id).get("hours", [0, 1800])
	var t := dial(TimeManager.minute if m < 0 else m)
	if not (t >= int(h[0]) and t < int(h[1])):
		return false
	return not WorldSimulationManager.has_flag(id, &"closed")


func hours_text(id: StringName) -> String:
	var h: Array = get_location(id).get("hours", [0, 1800])
	if int(h[0]) <= 360 and int(h[1]) >= 1800:
		return "always open"
	return "%s-%s" % [TimeManager.clock_text(int(h[0])), TimeManager.clock_text(int(h[1]))]


func is_restricted(id: StringName) -> bool:
	return type_of(id) == "restricted"


func zone_access_label() -> String:
	match zone_access:
		"route":
			return "a gap in the fence"
		"forged":
			return "a forged badge"
		"pass":
			return "a contractor pass"
	return "none"


## A way in, or a practice inside the Zone already.
func has_zone_access() -> bool:
	return zone_access != "" or WorldManager.current_district_id() == &"restricted"


func grant_zone(kind: String) -> void:
	var rank := {"": 0, "route": 1, "forged": 2, "pass": 3}
	if int(rank.get(kind, 0)) > int(rank.get(zone_access, 0)):
		zone_access = kind
	if kind != "":
		discover(&"lyra_checkpoint", "You have a way past the fence now.")
		discover(&"lyra_annex", "Past Checkpoint 9: the research annex.")


## Why you can't go there right now ("" = you can).
func access_block(id: StringName) -> String:
	if not locations.has(id):
		return "Unknown place"
	if not is_known(id):
		return "You don't know where that is"
	if id == CLINIC:
		return ""
	if str(get_location(id).get("access", "")) == "zone" and not has_zone_access():
		return "Restricted: you need a way past Checkpoint 9"
	if not is_open(id):
		if WorldSimulationManager.has_flag(id, &"closed"):
			return "Closed today (%s)" % WorldSimulationManager.state_label(id).to_lower()
		return "Closed now (open %s)" % hours_text(id)
	return ""


# --- Travel ----------------------------------------------------------------------------------------

func is_away() -> bool:
	return player_location != CLINIC


func distance(a: StringName, b: StringName) -> float:
	return map_pos(a).distance_to(map_pos(b))


func mode_def(mode: String) -> Dictionary:
	for m: Dictionary in modes:
		if str(m["id"]) == mode:
			return m
	return {}


func has_metro_pass() -> bool:
	return metro_pass_until >= BusinessManager.day


## {mode, label, minutes, cost, risk, block}. `block` != "" = unavailable.
func trip(to: StringName, mode: String, from: StringName = &"") -> Dictionary:
	var src := from if from != &"" else player_location
	var m := mode_def(mode)
	var out := {"mode": mode, "label": str(m.get("label", mode.to_upper())), "minutes": 0, "cost": 0, "risk": 0.0, "block": ""}
	if m.is_empty():
		out["block"] = "No such way to travel"
		return out
	var same := district_of(src) == district_of(to)
	var dist := distance(src, to)
	if same:
		if mode != "walk":
			out["block"] = "Same district: walk it"
		out["minutes"] = int(data.get("travel", {}).get("local_minutes", 12)) + int(dist * 60.0)
	else:
		out["minutes"] = int(m.get("base", 10)) + int(float(m.get("per_unit", 60)) * dist)
	var cost := int(m.get("cost", 0)) + int(float(m.get("cost_per_unit", 0)) * dist)
	if TimeManager.is_night():
		cost = int(cost * float(m.get("night_mult", 1.0)))
	if mode == "metro" and has_metro_pass():
		cost = 0
	out["cost"] = 0 if same else cost
	out["risk"] = float(m.get("risk", 1.0))
	if out["block"] != "":
		return out
	if bool(m.get("no_restricted", false)) and (is_restricted(to) or is_restricted(src)):
		out["block"] = "Doesn't go into the Exclusion Zone"
	elif m.has("hours"):
		var h: Array = m["hours"]
		var t := dial(TimeManager.minute)
		if t < int(h[0]) or t >= int(h[1]):
			out["block"] = "Not running now (%s-%s)" % [TimeManager.clock_text(int(h[0])), TimeManager.clock_text(int(h[1]))]
	if out["block"] == "" and mode == "metro" and WorldEventManager.is_active(&"blackout"):
		out["block"] = "Blackout: the lines are down"
	if out["block"] == "" and int(out["cost"]) > 0 and not EconomyManager.can_afford(int(out["cost"])):
		out["block"] = "Need %s" % EconomyManager.format_money(int(out["cost"]))
	return out


## Every way to get there from where you are.
func trips(to: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in modes:
		out.append(trip(to, str(m["id"])))
	return out


## The sensible default: the fastest way you can afford that's running.
func best_trip(to: StringName) -> Dictionary:
	var best: Dictionary = {}
	for t in trips(to):
		if t["block"] != "":
			continue
		# Cabs only when they save real time.
		if t["mode"] == "taxi" and not best.is_empty() and int(best["minutes"]) - int(t["minutes"]) < 30:
			continue
		if best.is_empty() or int(t["minutes"]) < int(best["minutes"]):
			best = t
	return best


## Why you can't leave right now ("" = you can).
func leave_block(to: StringName) -> String:
	if SurgeryManager.is_active:
		return "You're in the middle of an operation"
	if to == player_location:
		return "You're already here"
	if DialogueManager.is_active():
		return "You're in a conversation"
	if not is_away() and CustomerManager.has_customer() and CustomerManager.current_customer.is_emergency:
		return "There's an emergency at your door"
	if WorldSimulationManager.has_encounter():
		return "Something is in your way"
	if to != CLINIC and TimeManager.minute >= TimeManager.close_minute() - 15:
		return "It's nearly four. The night is over: go home."
	return access_block(to)


## Goes somewhere. Returns {ok, reason, minutes, cost, encounter}.
func travel(to: StringName, mode: String = "") -> Dictionary:
	var block := leave_block(to)
	if block != "":
		return {"ok": false, "reason": block}
	var t := best_trip(to) if mode == "" else trip(to, mode)
	if t.is_empty():
		return {"ok": false, "reason": "No way to get there right now"}
	if str(t["block"]) != "":
		return {"ok": false, "reason": str(t["block"])}
	var from := player_location
	if from == CLINIC:
		_leave_clinic()
	if int(t["cost"]) > 0:
		EconomyManager.spend(int(t["cost"]), &"travel")
	player_location = to
	if to != CLINIC:
		visits[to] = int(visits.get(to, 0)) + 1
		WorldManager.visit(district_of(to))
	var mins := int(t["minutes"])
	_count_away(mins, from)
	TimeManager.advance(mins)
	last_trip = {"from": String(from), "to": String(to), "mode": str(t["mode"]), "minutes": mins, "cost": int(t["cost"]), "day": BusinessManager.day}
	var enc := WorldSimulationManager.roll_encounter(str(t["mode"]), from, to, float(t["risk"]))
	if to == CLINIC:
		_arrive_clinic()
	EventBus.modifiers_changed.emit()
	moved.emit(to)
	EventBus.location_changed.emit(to)
	return {"ok": true, "reason": "", "minutes": mins, "cost": int(t["cost"]), "mode": str(t["mode"]), "encounter": enc}


## Spends time where you are (services, events). Away from the clinic the
## minutes count toward the night's break-in risk.
func spend_minutes(mins: int) -> void:
	if mins <= 0:
		return
	_count_away(mins, player_location)
	TimeManager.advance(mins)


func _count_away(mins: int, from: StringName) -> void:
	if from != CLINIC or player_location != CLINIC:
		if TimeManager.is_night() or TimeManager.period(TimeManager.minute + mins) in [&"night", &"late_night"]:
			away_minutes_night += mins


## Whoever is at the door when you go out: they sit and wait if there's
## room on the bench, otherwise they leave.
func _leave_clinic() -> void:
	CustomerManager.stop_arrivals()
	var c := CustomerManager.current_customer
	if c == null:
		return
	CustomerManager.current_customer = null
	if ClinicLifeManager.can_seat():
		ClinicLifeManager.seat(c)
	else:
		PeopleManager.after_visit(c, "left")
		ClinicLifeManager.post("%s gave up when you walked out." % c.display_name)
		EventBus.customer_left.emit(c)


func _arrive_clinic() -> void:
	if not ClinicLifeManager.waiting.is_empty():
		ClinicLifeManager.post("You're back. %d waiting." % ClinicLifeManager.waiting.size())


## Goes back to the clinic the sensible way (used by the CLINIC button).
func return_to_clinic() -> Dictionary:
	if not is_away():
		return {"ok": true, "minutes": 0}
	return travel(CLINIC)


## While you're somewhere, that place's prices apply (night markets are
## cheaper after dark).
func get_modifiers() -> Dictionary:
	if not is_away():
		return {}
	var l := get_location(player_location)
	var out: Dictionary = (l.get("mods", {}) as Dictionary).duplicate()
	if TimeManager.is_night():
		var nm: Dictionary = l.get("night_mods", {})
		for k: Variant in nm:
			out[k] = nm[k]
	return out


# --- Days --------------------------------------------------------------------------------------------

func _on_day_started(_day: int) -> void:
	# A new business day starts at the clinic.
	player_location = CLINIC
	away_minutes_night = 0
	EventBus.modifiers_changed.emit()
	check_discovery()


# --- Save ----------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var v := {}
	for k: StringName in visits:
		v[String(k)] = visits[k]
	return {"known": known.map(func(x: StringName) -> String: return String(x)), "at": String(player_location),
		"zone": zone_access, "metro_pass": metro_pass_until, "visits": v, "away_night": away_minutes_night, "last_trip": last_trip.duplicate()}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	for v: Variant in d.get("known", []):
		var id := StringName(str(v))
		if locations.has(id) and not known.has(id):
			known.append(id)
	var at := StringName(str(d.get("at", "clinic")))
	player_location = at if locations.has(at) else CLINIC
	zone_access = str(d.get("zone", ""))
	metro_pass_until = int(d.get("metro_pass", 0))
	var vs: Dictionary = d.get("visits", {})
	for k: Variant in vs:
		visits[StringName(str(k))] = int(vs[k])
	away_minutes_night = int(d.get("away_night", 0))
	var lt: Variant = d.get("last_trip", {})
	last_trip = lt if lt is Dictionary else {}
	# Anything that should be known by now (older saves) is.
	check_discovery_silent()


func check_discovery_silent() -> void:
	for id in order:
		if not known.has(id) and _discover_cond(get_location(id).get("discover", {})):
			known.append(id)
