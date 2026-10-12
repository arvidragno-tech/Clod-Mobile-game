extends Node
## What people remember about you. A light, data-driven tag store
## (data/memories.json): any person or story character can remember
## PLAYER_SAVED_ME, PLAYER_OVERCHARGED_ME, PLAYER_KILLED_FRIEND... Each tag
## shifts the relationship and reputation dimensions once, and gives them
## something to say later. Dialogue, story beats, customer behaviour and
## staff opinions all read these tags.

const MAX_PER_OWNER := 24
## Chance a returning person brings up a memory unprompted.
const RECALL_CHANCE := 0.6

var defs: Dictionary = {}  # tag -> {label, rel, rep, lines}
var memories: Dictionary = {}  # owner id (String) -> Array[{tag, day, about, note}]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_MEMORIES)
	if d is Dictionary:
		defs = d.get("memories", {})
	reset_state()


func reset_state() -> void:
	memories.clear()


## Records a memory and applies its relationship / reputation effect.
## about: who/what it concerns (another person's id, an item...).
## Records why standing changes in here (ChangeLog standing history).
func remember(owner: StringName, tag: StringName, about: String = "", note: String = "") -> void:
	ChangeLog.push_cause("Remembered: %s" % String(tag).replace("_", " ").to_lower())
	_remember_impl(owner, tag, about, note)
	ChangeLog.pop_cause()


func _remember_impl(owner: StringName, tag: StringName, about: String = "", note: String = "") -> void:
	if owner == &"" or not defs.has(String(tag)):
		return
	var key := String(owner)
	if not memories.has(key):
		memories[key] = []
	var list: Array = memories[key]
	list.append({"tag": String(tag), "day": BusinessManager.day, "about": about, "note": note})
	while list.size() > MAX_PER_OWNER:
		list.pop_front()
	var d: Dictionary = defs[String(tag)]
	var rel := int(d.get("rel", 0))
	if CharacterManager.has_character(owner):
		CharacterManager.change_relationship(owner, rel)
	elif PeopleManager.has_person(owner):
		PeopleManager.change_rel(owner, rel)
	elif not StaffManager.get_employee(owner).is_empty():
		var e := StaffManager.get_employee(owner)
		e["loyalty"] = clampf(float(e["loyalty"]) + rel / 2.0, 0.0, 100.0)
	ReputationManager.change_dims(d.get("rep", {}))
	EventBus.memory_added.emit(owner, tag)


func has(owner: StringName, tag: StringName) -> bool:
	return count(owner, tag) > 0


func count(owner: StringName, tag: StringName) -> int:
	var n := 0
	for m: Dictionary in memories.get(String(owner), []):
		if str(m["tag"]) == String(tag):
			n += 1
	return n


func of(owner: StringName) -> Array:
	return memories.get(String(owner), [])


func label(tag: StringName) -> String:
	return str(defs.get(String(tag), {}).get("label", String(tag).capitalize()))


## Anyone who remembers `tag` (e.g. everyone you ever overcharged).
func who_remembers(tag: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: String in memories:
		for m: Dictionary in memories[k]:
			if str(m["tag"]) == String(tag):
				out.append(StringName(k))
				break
	return out


## Something they might say about the past: the strongest recent memory,
## only some of the time (people don't bring it up every visit).
func recall_line(owner: StringName, force: bool = false) -> String:
	var list: Array = of(owner)
	if list.is_empty() or (not force and _rng.randf() > RECALL_CHANCE):
		return ""
	var best: Dictionary = {}
	var best_w := -1.0
	for i in list.size():
		var m: Dictionary = list[i]
		var w := absf(float(defs.get(str(m["tag"]), {}).get("rel", 0))) + i * 2.0
		if w > best_w:
			best_w = w
			best = m
	var lines: Array = defs.get(str(best.get("tag", "")), {}).get("lines", [])
	return str(lines[_rng.randi() % lines.size()]) if not lines.is_empty() else ""


func get_save_data() -> Dictionary:
	return {"memories": memories.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var m: Dictionary = data.get("memories", {})
	for k: Variant in m:
		if m[k] is Array:
			memories[str(k)] = (m[k] as Array).duplicate(true)
