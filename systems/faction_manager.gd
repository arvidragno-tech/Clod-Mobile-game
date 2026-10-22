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


## The change a delta really makes before the -100..100 cap: gains are
## scaled by faction.gain (Faction Relations), losses hit in full.
func scaled_change(delta: int) -> int:
	return int(round(delta * ModifierManager.mult(&"faction.gain"))) if delta > 0 else delta


func change(id: StringName, delta: int, reason: String = "") -> int:
	if not factions.has(id) or delta == 0:
		return 0
	var old := get_rep(id)
	rep[id] = clampi(old + scaled_change(delta), -100, 100)
	var actual := get_rep(id) - old
	if actual != 0:
		EventBus.faction_changed.emit(id, get_rep(id), actual)
		ChangeLog.record_standing("faction:%s" % id, get_name_of(id), actual, get_rep(id), reason)
	return actual


## Taking a side has a price. When a DECISION (an event choice, a
## conversation, a reply) wins you standing with a faction, its rivals
## (factions.json `rivals`) hear about it and lose some: a share of the
## gain, at least 1 and at most RIVAL_MAX_LOSS each. Routine work (paid
## operations, quest rewards) uses change() and stays neutral.
const RIVAL_SHARE := 0.4
const RIVAL_MIN_GAIN := 3
const RIVAL_MAX_LOSS := 5


## What the rivals would lose if `id` gained `delta` by a decision:
## {rival_id: -n}. Pure, so previews show the same numbers.
func rival_losses(id: StringName, delta: int) -> Dictionary:
	var out := {}
	if delta < RIVAL_MIN_GAIN:
		return out
	for r: Variant in get_faction(id).get("rivals", []):
		var rid := StringName(str(r))
		if factions.has(rid) and rid != id:
			out[rid] = -clampi(roundi(delta * RIVAL_SHARE), 1, RIVAL_MAX_LOSS)
	return out


## A faction change that comes from a choice the player made (rivals react).
func change_by_choice(id: StringName, delta: int, reason: String = "") -> int:
	var actual := change(id, delta, reason)
	var losses := rival_losses(id, actual)
	for rid: StringName in losses:
		change(rid, int(losses[rid]), "%s: you sided with %s" % [reason if reason != "" else "Word gets around", get_name_of(id)])
	return actual


## What change_by_choice(id, delta) would change, without changing it:
## {faction_id: change}, by the same rules (scaling, cap, rivals). `reps`
## holds standings already previewed (faction_id -> standing) and is
## updated, so several changes in a row add up as they would in play.
func preview_by_choice(id: StringName, delta: int, reps: Dictionary) -> Dictionary:
	var out := {}
	var actual := _preview_change(id, delta, reps)
	out[id] = actual
	var losses := rival_losses(id, actual)
	for rid: StringName in losses:
		out[rid] = int(out.get(rid, 0)) + _preview_change(rid, int(losses[rid]), reps)
	return out


func _preview_change(id: StringName, delta: int, reps: Dictionary) -> int:
	if not factions.has(id) or delta == 0:
		return 0
	var old := int(reps.get(id, get_rep(id)))
	reps[id] = clampi(old + scaled_change(delta), -100, 100)
	return int(reps[id]) - old


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


## The heat an amount really adds before the 0..MAX_HEAT cap: gains are
## scaled by heat.gain and by who the street thinks you are; cooling down
## is never scaled.
func scaled_heat(amount: float) -> float:
	return amount * (ModifierManager.mult(&"heat.gain") * ReputationManager.heat_gain_mult() if amount > 0.0 else 1.0)


## What add_heat(amount) would change, starting from heat `from`.
func preview_heat(amount: float, from: float) -> float:
	return clampf(from + scaled_heat(amount), 0.0, GameConfig.MAX_HEAT) - from


func add_heat(amount: float, reason: String = "") -> void:
	var old := heat
	heat = clampf(heat + scaled_heat(amount), 0.0, GameConfig.MAX_HEAT)
	if not is_equal_approx(old, heat):
		EventBus.heat_changed.emit(heat, heat - old)
		ChangeLog.record_standing("heat", "Authority attention (heat)", heat - old, heat, reason)


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
