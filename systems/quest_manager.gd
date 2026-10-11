extends Node
## Quests (data/quests.json): main, side, staff, customer, faction, black
## market and clinic. Each has a title, description, objective, reward and
## consequence, and a state: inactive, active, completed or failed. The
## story starts them (beats, dialogue choices); objectives are checked
## against the world whenever StoryManager.check() runs.

signal quest_started(id: StringName)
signal quest_completed(id: StringName)
signal quest_failed(id: StringName)

const TYPES := ["main", "side", "staff", "customer", "faction", "black_market", "clinic"]
const TYPE_LABELS := {"main": "MAIN", "side": "SIDE", "staff": "STAFF", "customer": "CUSTOMER", "faction": "FACTION",
	"black_market": "BLACK MARKET", "clinic": "CLINIC"}

var quests: Dictionary = {}  # id -> data
var order: Array[StringName] = []
var states: Dictionary = {}  # id -> {state, started_day, ended_day}


func _ready() -> void:
	for q: Variant in DataLoader.load_entries(GameConfig.DATA_QUESTS, "quests"):
		var id := StringName(str(q["id"]))
		quests[id] = q
		order.append(id)
	reset_state()


func reset_state() -> void:
	states.clear()


func get_quest(id: StringName) -> Dictionary:
	return quests.get(id, {})


func state_of(id: StringName) -> String:
	return str(states.get(id, {}).get("state", "inactive"))


func is_active(id: StringName) -> bool:
	return state_of(id) == "active"


func start(id: StringName) -> bool:
	if not quests.has(id) or state_of(id) != "inactive":
		return false
	states[id] = {"state": "active", "started_day": BusinessManager.day, "ended_day": 0}
	quest_started.emit(id)
	CommsManager.notify("New %s quest: %s" % [str(TYPE_LABELS.get(str(quests[id]["type"]), "")).to_lower(), str(quests[id]["title"])])
	check(id)
	return true


func by_state(state: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if state_of(id) == state:
			out.append(id)
	return out


func check_all() -> void:
	for id in order:
		if is_active(id):
			check(id)


func check(id: StringName) -> void:
	var q := get_quest(id)
	if q.is_empty() or not is_active(id):
		return
	if met(q.get("objective", {})):
		complete(id)
		return
	var dl := int(q.get("deadline_days", 0))
	if dl > 0 and BusinessManager.day - int(states[id]["started_day"]) > dl:
		fail(id)


func complete(id: StringName) -> void:
	states[id]["state"] = "completed"
	states[id]["ended_day"] = BusinessManager.day
	var r: Dictionary = get_quest(id).get("reward", {})
	if r.has("money"):
		EconomyManager.add_money(int(r["money"]), &"events")
	if r.has("rep"):
		ReputationManager.change(int(r["rep"]))
	if r.has("xp"):
		ProgressionManager.add_xp(int(r["xp"]))
	var fa: Dictionary = r.get("faction", {})
	for f: Variant in fa:
		FactionManager.change(StringName(str(f)), int(fa[f]))
	var rel: Dictionary = r.get("rel", {})
	for c: Variant in rel:
		CharacterManager.change_relationship(StringName(str(c)), int(rel[c]))
	quest_completed.emit(id)
	CommsManager.notify("Quest complete: %s" % str(get_quest(id)["title"]))


func fail(id: StringName) -> void:
	states[id]["state"] = "failed"
	states[id]["ended_day"] = BusinessManager.day
	quest_failed.emit(id)
	CommsManager.notify("Quest failed: %s" % str(get_quest(id)["title"]))


func reward_text(id: StringName) -> String:
	var r: Dictionary = get_quest(id).get("reward", {})
	var parts: Array[String] = []
	if r.has("money"):
		parts.append("%d cr" % int(r["money"]))
	if r.has("rep"):
		parts.append("+%d rep" % int(r["rep"]))
	if r.has("xp"):
		parts.append("+%d XP" % int(r["xp"]))
	var fa: Dictionary = r.get("faction", {})
	for f: Variant in fa:
		parts.append("%s %+d" % [FactionManager.get_name_of(StringName(str(f))), int(fa[f])])
	var rel: Dictionary = r.get("rel", {})
	for c: Variant in rel:
		var cd := CharacterManager.get_character(StringName(str(c)))
		parts.append("%s %+d" % [cd.display_name if cd else str(c), int(rel[c])])
	return ", ".join(parts) if not parts.is_empty() else "-"


## "2 / 3" style progress where it makes sense.
func progress_text(id: StringName) -> String:
	var o: Dictionary = get_quest(id).get("objective", {})
	var cur := _value(o)
	if cur < 0:
		return ""
	return "%d / %d" % [mini(cur, int(o.get("n", 0))), int(o.get("n", 0))]


func met(o: Dictionary) -> bool:
	if o.is_empty():
		return false
	if o.has("and") and not met(o["and"]):
		return false
	match str(o.get("type", "")):
		"flag":
			return StoryManager.has_flag(StringName(str(o["flag"])))
		"flag_any":
			for f: Variant in o["flags"]:
				if StoryManager.has_flag(StringName(str(f))):
					return true
			return false
		"debt_max":
			return BusinessManager.debt <= int(o["n"])
		"faction":
			return FactionManager.get_rep(StringName(str(o["id"]))) >= int(o["n"])
		"staff_skill":
			var e := StaffManager.get_employee(StringName(str(o["id"])))
			return not e.is_empty() and int(e.get("skill", 0)) >= int(o["n"])
	var v := _value(o)
	return v >= 0 and v >= int(o.get("n", 0))


## Numeric progress for counting objectives (-1 = not a counter).
func _value(o: Dictionary) -> int:
	match str(o.get("type", "")):
		"day":
			return BusinessManager.day
		"ops":
			return EventManager.operations
		"rep":
			return ReputationManager.reputation
		"staff":
			return StaffManager.count()
		"clinics":
			return ClinicManager.owned.size()
		"security":
			return ClinicManager.security_rating()
		"counter":
			return StoryManager.counter(StringName(str(o["id"])))
		"upgrades":
			var n := 0
			for i in ClinicManager.owned:
				n += ClinicManager.used_slots(i)
			return n
		"regulars":
			var seen := {}
			for h: Dictionary in CustomerManager.history:
				if bool(h.get("regular", false)):
					seen[str(h["uid"])] = true
			return seen.size()
		"faction":
			return FactionManager.get_rep(StringName(str(o["id"])))
	return -1


func get_save_data() -> Dictionary:
	var s := {}
	for id: Variant in states:
		s[String(id)] = states[id].duplicate()
	return {"states": s}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var s: Dictionary = data.get("states", {})
	for id: Variant in s:
		if quests.has(StringName(str(id))) and s[id] is Dictionary:
			states[StringName(str(id))] = (s[id] as Dictionary).duplicate()
