extends Node
## Lightweight narrative state: story flags, unlocked rumors and which
## recurring characters the player has met.

var flags: Dictionary = {}  # StringName -> bool
var rumors: Dictionary = {}  # StringName -> Dictionary (data)
var rumor_order: Array[StringName] = []
var unlocked_rumors: Array[StringName] = []
var met_characters: Array[StringName] = []
## Story act (1 SURVIVAL .. 5 CONSEQUENCE), see the acts in data/story.json.
var act: int = 1
## Delayed consequences: [{id, due_day, data}] fired at the start of a day.
var pending: Array[Dictionary] = []


func _ready() -> void:
	for r: Variant in DataLoader.load_entries(GameConfig.DATA_RUMORS, "rumors"):
		var id := StringName(str(r["id"]))
		rumors[id] = r
		rumor_order.append(id)
	reset_state()


func reset_state() -> void:
	act = 1
	pending.clear()
	flags.clear()
	unlocked_rumors.clear()
	met_characters.clear()


func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: StringName, value: bool = true) -> void:
	if has_flag(flag) == value:
		return
	flags[flag] = value
	EventBus.story_flag_changed.emit(flag, value)


## Something the player did comes back `days` later (choices echo).
func schedule_consequence(id: StringName, days: int, data: Dictionary = {}) -> void:
	pending.append({"id": String(id), "due_day": BusinessManager.day + maxi(1, days), "data": data})


## Consequences due today (removed from the queue).
func take_due(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(pending.size() - 1, -1, -1):
		if int(pending[i]["due_day"]) <= day:
			out.push_front(pending[i])
			pending.remove_at(i)
	return out


func meet(character_id: StringName) -> void:
	if character_id != &"" and not met_characters.has(character_id):
		met_characters.append(character_id)


func unlock_rumor(id: StringName) -> void:
	if rumors.has(id) and not unlocked_rumors.has(id):
		unlocked_rumors.append(id)
		EventBus.rumor_unlocked.emit(id)


## Unlocks every rumor whose conditions are now met.
func update_rumors() -> void:
	for id in rumor_order:
		if not unlocked_rumors.has(id) and EventManager.conditions_met(rumors[id].get("conditions", {})):
			unlock_rumor(id)


func get_rumor_text(id: StringName) -> String:
	return str(rumors.get(id, {}).get("text", ""))


func get_latest_rumor() -> String:
	return get_rumor_text(unlocked_rumors[unlocked_rumors.size() - 1]) if not unlocked_rumors.is_empty() else ""


func get_save_data() -> Dictionary:
	var f := {}
	for k: StringName in flags:
		f[String(k)] = flags[k]
	return {"flags": f, "rumors": unlocked_rumors.map(func(x: StringName) -> String: return String(x)),
			"met": met_characters.map(func(x: StringName) -> String: return String(x)), "act": act, "pending": pending.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var f: Dictionary = data.get("flags", {})
	for k: Variant in f:
		flags[StringName(str(k))] = bool(f[k])
	for r: Variant in data.get("rumors", []):
		if rumors.has(StringName(str(r))):
			unlocked_rumors.append(StringName(str(r)))
	for m: Variant in data.get("met", []):
		met_characters.append(StringName(str(m)))
	act = clampi(int(data.get("act", 1)), 1, 5)
	for p: Variant in data.get("pending", []):
		if p is Dictionary:
			pending.append(p)
