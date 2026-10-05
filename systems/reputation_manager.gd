extends Node
## Street reputation. Gates harder customers and (later) the black market.

const TIERS := [
	[-100, "Butcher"],
	[0, "Unknown"],
	[10, "Back-alley"],
	[25, "Known Cutter"],
	[50, "Trusted Ripper"],
	[80, "Legend"],
]

var reputation: int = 0
## Reputation dimensions (-100..100): who trusts you for what. They decide
## which customers and opportunities come; raising one often costs another.
const DIMENSIONS: Array[StringName] = [&"civilian", &"criminal", &"medical", &"corporate", &"black_market"]
const DIMENSION_LABELS := {&"civilian": "Civilian", &"criminal": "Criminal", &"medical": "Medical", &"corporate": "Corporate", &"black_market": "Black market"}
var dims: Dictionary = {}


func _ready() -> void:
	reset_state()


func reset_state() -> void:
	reputation = GameConfig.STARTING_REPUTATION
	dims.clear()
	for d in DIMENSIONS:
		dims[d] = 0


func dim(d: StringName) -> int:
	return int(dims.get(d, 0))


## Changes one reputation dimension (trade-offs are applied by the caller's
## data, e.g. criminal work costs corporate standing).
func change_dim(d: StringName, delta: int) -> void:
	if not dims.has(d) or delta == 0:
		return
	var old := dim(d)
	dims[d] = clampi(old + delta, -100, 100)
	if dim(d) != old:
		EventBus.reputation_dim_changed.emit(d, dim(d), dim(d) - old)


func change_dims(deltas: Dictionary) -> void:
	for k: Variant in deltas:
		change_dim(StringName(str(k)), int(deltas[k]))


## Highest dimension = what the street thinks you are.
func dominant_dim() -> StringName:
	var best: StringName = &"civilian"
	for d in DIMENSIONS:
		if dim(d) > dim(best):
			best = d
	return best


func change(delta: int) -> void:
	var old := reputation
	# Diminishing returns: each point is harder to earn the higher you are,
	# so "Legend" stays a long-term goal (losses always hit in full).
	if delta > 0 and reputation > 0:
		delta = maxi(1, roundi(delta * (1.0 - float(reputation) / (GameConfig.MAX_REPUTATION * 1.4))))
	reputation = clampi(reputation + delta, GameConfig.MIN_REPUTATION, GameConfig.MAX_REPUTATION)
	if reputation != old:
		EventBus.reputation_changed.emit(reputation, reputation - old)


func get_tier_name() -> String:
	var tier_name := String(TIERS[0][1])
	for tier: Array in TIERS:
		if reputation >= int(tier[0]):
			tier_name = String(tier[1])
	return tier_name


func is_black_market_unlocked() -> bool:
	return reputation >= GameConfig.BLACK_MARKET_REPUTATION


func get_save_data() -> Dictionary:
	var d := {}
	for k: StringName in dims:
		d[String(k)] = dims[k]
	return {"reputation": reputation, "dims": d}


func load_save_data(data: Dictionary) -> void:
	reputation = int(data.get("reputation", GameConfig.STARTING_REPUTATION))
	var d: Dictionary = data.get("dims", {})
	for k: Variant in d:
		if dims.has(StringName(str(k))):
			dims[StringName(str(k))] = clampi(int(d[k]), -100, 100)
	EventBus.reputation_changed.emit(reputation, 0)
