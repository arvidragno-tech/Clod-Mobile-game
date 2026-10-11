extends Node
## Reputation with each faction, plus "heat": attention from the authorities.

var factions: Dictionary = {}  # StringName -> Dictionary (data)
var order: Array[StringName] = []
var rep: Dictionary = {}  # StringName -> int
var heat: float = 0.0


func _ready() -> void:
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_FACTIONS, "factions"):
		var id := StringName(str(entry["id"]))
		factions[id] = entry
		order.append(id)
	reset_state()


func reset_state() -> void:
	rep.clear()
	for id in order:
		rep[id] = int(factions[id].get("starting_rep", 0))
	heat = 0.0


func get_faction(id: StringName) -> Dictionary:
	return factions.get(id, {})


func get_name_of(id: StringName) -> String:
	return str(get_faction(id).get("name", id))


func get_color(id: StringName) -> Color:
	return Color(str(get_faction(id).get("color", "8e9aa8")))


func get_rep(id: StringName) -> int:
	return int(rep.get(id, 0))


func change(id: StringName, delta: int) -> int:
	if not factions.has(id) or delta == 0:
		return 0
	var scaled := delta
	if delta > 0:
		scaled = int(round(delta * ModifierManager.mult(&"faction.gain")))
	var old := get_rep(id)
	rep[id] = clampi(old + scaled, -100, 100)
	var actual := get_rep(id) - old
	if actual != 0:
		EventBus.faction_changed.emit(id, get_rep(id), actual)
	return actual


func get_standing(id: StringName) -> String:
	var r := get_rep(id)
	for s: Array in GameConfig.FACTION_STANDINGS:
		if r < int(s[0]):
			return String(s[1])
	return "ALLIED"


func is_hostile(id: StringName) -> bool:
	return get_rep(id) <= -50


## Price multiplier for goods tied to a faction (friends give discounts).
func price_multiplier(id: StringName) -> float:
	return clampf(1.0 - get_rep(id) / 400.0, 0.75, 1.3)


## How often customers of this faction show up.
func customer_weight(id: StringName) -> float:
	return clampf(1.0 + get_rep(id) / 50.0, 0.15, 3.0)


func add_heat(amount: float) -> void:
	var scaled := amount * (ModifierManager.mult(&"heat.gain") * ReputationManager.heat_gain_mult() if amount > 0.0 else 1.0)
	var old := heat
	heat = clampf(heat + scaled, 0.0, GameConfig.MAX_HEAT)
	if not is_equal_approx(old, heat):
		EventBus.heat_changed.emit(heat, heat - old)


func get_save_data() -> Dictionary:
	var r := {}
	for id: StringName in rep:
		r[String(id)] = rep[id]
	return {"rep": r, "heat": heat}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var r: Dictionary = data.get("rep", {})
	for key: Variant in r:
		var id := StringName(str(key))
		if factions.has(id):
			rep[id] = int(r[key])
	heat = float(data.get("heat", 0.0))
