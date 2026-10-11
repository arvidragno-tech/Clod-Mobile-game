extends Node
## FOLLOW: the game remembers future objectives for the player. Anything
## with a "when" or a "where" can be followed: a quest, a person (cast or
## patient: where they are right now is looked up live from their routine),
## a place with something happening, a patient's return day, a supplier
## delivery, an appointment on the clinic agenda.
##
## Follows read the real state every time they're shown (no copied state):
## a followed person's place changes with the hour, a quest shows its
## progress and days left, and a follow that is over (quest done, person
## dead, event gone, day passed) drops off by itself. Followed items feed
## the clinic's priorities and the journal's MAIN tab.

signal changed()

const MAX_FOLLOWS := 12
const KINDS := ["quest", "person", "cast", "place", "return", "delivery", "appointment"]

## [{id, kind, ref, title, day, minute, since}] in the order followed.
var follows: Array[Dictionary] = []


func reset_state() -> void:
	follows.clear()


## Starts following. `ref` is the quest id / person id / cast id / location
## id / agenda id / supplier id. Returns false if already followed or full.
func follow(kind: String, ref: String, title: String = "", day: int = -1, minute: int = -1) -> bool:
	if not KINDS.has(kind) or ref == "":
		return false
	var id := "%s:%s" % [kind, ref]
	if is_following(id):
		return false
	if follows.size() >= MAX_FOLLOWS:
		follows.pop_front()
	follows.append({"id": id, "kind": kind, "ref": ref, "title": title, "day": day, "minute": minute, "since": BusinessManager.day})
	changed.emit()
	ChangeLog.add("follow", title if title != "" else ref, "Following", ChangeLog.INFO, {"screen": &"dossier", "params": {"tab_name": "MAIN"}})
	return true


func unfollow(id: String) -> void:
	for i in follows.size():
		if str(follows[i]["id"]) == id:
			follows.remove_at(i)
			changed.emit()
			return


func toggle(kind: String, ref: String, title: String = "", day: int = -1, minute: int = -1) -> bool:
	var id := "%s:%s" % [kind, ref]
	if is_following(id):
		unfollow(id)
		return false
	return follow(kind, ref, title, day, minute)


func is_following(id: String) -> bool:
	return follows.any(func(f: Dictionary) -> bool: return str(f["id"]) == id)


static func key(kind: String, ref: String) -> String:
	return "%s:%s" % [kind, ref]


## Live view of every follow that still applies (drops finished ones):
## [{id, kind, title, where (location id or ""), when (text), soon (bool), detail, link}].
func live() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dead: Array[String] = []
	for f in follows:
		var v := resolve(f)
		if v.is_empty():
			dead.append(str(f["id"]))
		else:
			out.append(v)
	for id in dead:
		unfollow(id)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	return out


## One follow resolved against the current game state ({} when it's over).
func resolve(f: Dictionary) -> Dictionary:
	var kind := str(f["kind"])
	var ref := str(f["ref"])
	var v := {"id": f["id"], "kind": kind, "title": str(f["title"]), "where": "", "when": "", "soon": false, "detail": "",
		"link": {}, "order": 500}
	match kind:
		"quest":
			var q := QuestManager.get_quest(StringName(ref))
			if q.is_empty() or not QuestManager.is_active(StringName(ref)):
				return {}
			v["title"] = str(q.get("title", ref))
			v["detail"] = "%s · %s" % [str(q.get("objective", {}).get("text", "")), QuestManager.progress_text(StringName(ref))]
			var dl := int(q.get("deadline_days", 0))
			if dl > 0:
				var left := dl - (BusinessManager.day - int(QuestManager.states[StringName(ref)]["started_day"]))
				v["when"] = "%d day%s left" % [left, "" if left == 1 else "s"]
				v["soon"] = left <= 1
				v["order"] = left * 10
			v["link"] = {"screen": &"dossier", "params": {"tab_name": "MAIN"}}
		"cast":
			var c := CharacterManager.get_character(StringName(ref))
			if c == null or not CharacterManager.has_met(StringName(ref)):
				return {}
			v["title"] = c.display_name
			var at := WorldSimulationManager.where_is_cast(StringName(ref))
			v["where"] = String(at)
			v["when"] = "now" if at != &"" else "not out right now"
			v["detail"] = ("at %s" % LocationManager.location_name(at)) if at != &"" else "check again later (people keep hours)"
			v["soon"] = at != &""
			v["order"] = 100 if at != &"" else 600
			if at != &"":
				v["link"] = {"location": at}
		"person":
			var p := PeopleManager.get_person(StringName(ref))
			if p.is_empty() or str(p.get("status", "")) != "alive":
				return {}
			v["title"] = str(p.get("name", ref))
			var place := WorldSimulationManager.person_place(p)
			v["where"] = String(place)
			v["detail"] = "%s at %s" % [WorldSimulationManager.activity_of(p), LocationManager.location_name(place)]
			v["when"] = "now"
			var nd := int(p.get("next_day", -1))
			if nd >= 0:
				v["detail"] += " · due back day %d" % nd
				v["soon"] = nd <= BusinessManager.day
			v["order"] = 300
			v["link"] = {"location": place}
		"return":
			var p2 := PeopleManager.get_person(StringName(ref))
			var nd2 := int(p2.get("next_day", -1))
			if p2.is_empty() or str(p2.get("status", "")) != "alive" or nd2 < 0 or nd2 < BusinessManager.day:
				return {}
			v["title"] = str(p2.get("name", ref))
			v["when"] = "today" if nd2 == BusinessManager.day else "day %d" % nd2
			v["detail"] = "comes back to the clinic"
			v["soon"] = nd2 <= BusinessManager.day
			v["order"] = (nd2 - BusinessManager.day) * 10
			v["link"] = {"screen": &"dossier", "params": {"tab_name": "PATIENTS"}}
		"place":
			if LocationManager.get_location(StringName(ref)).is_empty():
				return {}
			var ev := WorldSimulationManager.event_at(StringName(ref))
			v["title"] = LocationManager.location_name(StringName(ref))
			v["where"] = ref
			v["detail"] = str(ev.get("title", "")) if not ev.is_empty() else WorldSimulationManager.state_label(StringName(ref))
			v["when"] = "now" if not ev.is_empty() else LocationManager.hours_text(StringName(ref))
			v["soon"] = not ev.is_empty()
			v["order"] = 200 if not ev.is_empty() else 700
			v["link"] = {"location": StringName(ref)}
		"delivery":
			var waiting := SupplierManager.deliveries.any(func(d: Dictionary) -> bool: return str(d["supplier"]) == ref)
			if not waiting:
				return {}
			v["title"] = str(SupplierManager.supplier(ref).get("name", ref))
			v["when"] = "tomorrow morning"
			v["detail"] = "delivery to your clinic"
			v["order"] = 150
			v["link"] = {"screen": &"business"}
		"appointment":
			var a := _agenda(ref)
			if a.is_empty():
				return {}
			v["title"] = str(a.get("label", ref))
			v["when"] = TimeManager.clock_text(int(a["minute"]))
			v["soon"] = int(a["minute"]) - TimeManager.minute <= 120
			v["order"] = int(a["minute"]) - TimeManager.minute
			v["link"] = {"screen": &"clinic"}
	if str(f["title"]) != "" and kind in ["place"]:
		v["title"] = str(f["title"])
	return v


func _agenda(id: String) -> Dictionary:
	for a: Dictionary in TimeManager.upcoming():
		if str(a["id"]) == id:
			return a
	return {}


func get_save_data() -> Dictionary:
	return {"follows": follows.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	follows.clear()
	for f: Variant in d.get("follows", []):
		if f is Dictionary and (f as Dictionary).has("id") and KINDS.has(str(f.get("kind", ""))):
			follows.append(f)
	changed.emit()
