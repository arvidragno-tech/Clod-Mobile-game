extends Node
## The city of Caldera: seven districts (data/districts.json), each with
## its own architecture, light, palette, population, factions, customer
## mix and events. The active clinic's district shapes who walks in and
## which incidents happen; working in a district builds influence there.

var districts: Dictionary = {}  # StringName -> Dictionary
var order: Array[StringName] = []
var city_name: String = "Caldera"
var visited: Array[StringName] = []
var influence: Dictionary = {}  # StringName -> int


func _ready() -> void:
	var d: Variant = DataLoader.load_json(GameConfig.DATA_DISTRICTS)
	if d is Dictionary:
		city_name = str(d.get("city", city_name))
		for e: Variant in d.get("districts", []):
			var id := StringName(str(e["id"]))
			districts[id] = e
			order.append(id)
	reset_state()


func reset_state() -> void:
	visited = [&"undercity"]
	influence.clear()


func get_district(id: StringName) -> Dictionary:
	return districts.get(id, {})


func current_district_id() -> StringName:
	return ClinicManager.district_id()


func current_district() -> Dictionary:
	return get_district(current_district_id())


func district_name(id: StringName = &"") -> String:
	return str(get_district(id if id != &"" else current_district_id()).get("name", "Caldera"))


func is_district_unlocked(id: StringName) -> bool:
	var u: Dictionary = get_district(id).get("unlock", {})
	if u.is_empty():
		return true
	return ProgressionManager.level >= int(u.get("level", 1)) and ReputationManager.reputation >= int(u.get("reputation", -100))


func unlock_reason(id: StringName) -> String:
	var u: Dictionary = get_district(id).get("unlock", {})
	if ProgressionManager.level < int(u.get("level", 1)):
		return "Requires LV %d" % int(u["level"])
	if ReputationManager.reputation < int(u.get("reputation", -100)):
		return "Requires REP %d" % int(u["reputation"])
	return ""


func visit(id: StringName) -> void:
	if id == &"" or not districts.has(id):
		return
	if not visited.has(id):
		visited.append(id)
	EventBus.district_changed.emit(id)


## Events native to the current district are twice as likely.
func event_weight(event_id: StringName) -> float:
	var evs: Array = current_district().get("events", [])
	return 2.0 if evs.has(String(event_id)) else 1.0


## Archetype weight multiplier for walk-ins at the current clinic.
func customer_weight(archetype_id: String) -> float:
	var pool: Dictionary = current_district().get("customers", {})
	return 0.25 + float(pool.get(archetype_id, 0.0))


func faction_weight(faction_id: StringName) -> float:
	var f: Dictionary = current_district().get("factions", {})
	return 1.0 + 0.25 * float(f.get(String(faction_id), 0.0))


func pay_mult() -> float:
	return float(current_district().get("wealth", 1.0))


func heat_mult() -> float:
	return float(current_district().get("heat_mult", 1.0))


func add_influence(id: StringName = &"", n: int = 1) -> void:
	var d := id if id != &"" else current_district_id()
	influence[d] = int(influence.get(d, 0)) + n


func get_influence(id: StringName) -> int:
	return int(influence.get(id, 0))


## Which district owns the most of the player's work.
func stronghold() -> StringName:
	var best: StringName = &"undercity"
	var n := -1
	for id: StringName in influence:
		if int(influence[id]) > n:
			n = int(influence[id])
			best = id
	return best


func get_save_data() -> Dictionary:
	var inf := {}
	for k: StringName in influence:
		inf[String(k)] = influence[k]
	return {"visited": visited.map(func(x: StringName) -> String: return String(x)), "influence": inf}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for v: Variant in data.get("visited", []):
		var id := StringName(str(v))
		if districts.has(id) and not visited.has(id):
			visited.append(id)
	var inf: Dictionary = data.get("influence", {})
	for k: Variant in inf:
		influence[StringName(str(k))] = int(inf[k])
