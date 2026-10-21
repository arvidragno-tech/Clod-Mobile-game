extends Node
## Street reputation. Gates harder customers and (later) the black market.

const TIERS := [
	[-100, "Butcher"],
	[-19, "Distrusted"],
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
func change_dim(d: StringName, delta: int, reason: String = "") -> void:
	if not dims.has(d) or delta == 0:
		return
	var old := dim(d)
	dims[d] = clampi(old + delta, -100, 100)
	if dim(d) != old:
		EventBus.reputation_dim_changed.emit(d, dim(d), dim(d) - old)
		ChangeLog.record_standing("dim:%s" % d, "%s reputation" % DIMENSION_LABELS.get(d, d), dim(d) - old, dim(d), reason)


func change_dims(deltas: Dictionary, reason: String = "") -> void:
	for k: Variant in deltas:
		change_dim(StringName(str(k)), int(deltas[k]), reason)


## Who the street thinks you are, inferred from what you've done (no class
## picked up front). First match wins; thresholds in order of drama.
const IDENTITIES := [
	{"id": "butcher", "title": "THE BUTCHER", "text": "People die on your table and everybody knows it.", "deaths": 5},
	{"id": "saint", "title": "THE SAINT OF THE SUMP", "text": "You treat the broke and the desperate. They'd hide you if it came to it.", "dims": {"civilian": 20, "medical": 10}},
	{"id": "gang_doc", "title": "THE GANG DOC", "text": "The crews bring you their wounded and their money. Corporate security has a file.", "dims": {"criminal": 20}},
	{"id": "fence", "title": "THE CHROME FENCE", "text": "If it's unregistered, it went through your hands.", "dims": {"black_market": 20}},
	{"id": "contractor", "title": "THE CORPORATE CONTRACTOR", "text": "Suits come down here for discretion, and you give it to them.", "dims": {"corporate": 20}},
	{"id": "shark", "title": "THE CHROME SHARK", "text": "You charge what the desperate can't afford. They pay anyway, and hate you for it.", "overcharged": 4},
	{"id": "surgeon", "title": "THE CLEAN SURGEON", "text": "Licensed or not, your hands are the best in the lower city.", "dims": {"medical": 20}},
]
## How each reputation pulls customers in (archetype weight per point).
const DIM_ARCHETYPES := {
	&"criminal": {"gang_member": 0.02, "criminal": 0.02, "smuggler": 0.015, "corporate": -0.01},
	&"corporate": {"corporate": 0.02, "security_officer": 0.015, "gang_member": -0.01},
	&"civilian": {"civilian": 0.015, "elder": 0.015, "dock_worker": 0.01},
	&"black_market": {"bm_tech": 0.02, "netrunner": 0.015, "smuggler": 0.01},
	&"medical": {"veteran": 0.01, "civilian": 0.01},
}


func identity() -> Dictionary:
	var deaths := 0
	for p: Dictionary in PeopleManager.people.values():
		if str(p.get("status", "")) == "dead":
			deaths += 1
	for i: Dictionary in IDENTITIES:
		if i.has("deaths") and deaths >= int(i["deaths"]):
			return i
		if i.has("overcharged") and MemoryManager.who_remembers(&"PLAYER_OVERCHARGED_ME").size() >= int(i["overcharged"]):
			return i
		if i.has("dims"):
			var ok := true
			for d: Variant in i["dims"]:
				ok = ok and dim(StringName(str(d))) >= int(i["dims"][d])
			if ok:
				return i
	return {"id": "nobody", "title": "NOBODY YET", "text": "The street hasn't decided what you are."}


## Your reputations decide who walks in (with trade-offs: gangs scare off suits).
func archetype_weight(id: String) -> float:
	var m := 1.0
	for d: StringName in DIM_ARCHETYPES:
		m += float(DIM_ARCHETYPES[d].get(id, 0.0)) * dim(d)
	return clampf(m, 0.3, 3.0)


## Criminal work draws attention; corporate friends keep it off you.
func heat_gain_mult() -> float:
	return clampf(1.0 + maxi(0, dim(&"criminal")) / 150.0 - maxi(0, dim(&"corporate")) / 250.0, 0.7, 1.6)


## Highest dimension = what the street thinks you are.
func dominant_dim() -> StringName:
	var best: StringName = &"civilian"
	for d in DIMENSIONS:
		if dim(d) > dim(best):
			best = d
	return best


## What change(delta) does to a reputation of `from` (pure, so previews
## show the same number). Diminishing returns: each point is harder to earn
## the higher you are, so "Legend" stays a long-term goal (losses always hit
## in full); then the -100..100 cap.
func applied_change(delta: int, from: int) -> int:
	if delta > 0 and from > 0:
		delta = maxi(1, roundi(delta * (1.0 - float(from) / (GameConfig.MAX_REPUTATION * 1.4))))
	return clampi(from + delta, GameConfig.MIN_REPUTATION, GameConfig.MAX_REPUTATION) - from


func change(delta: int, reason: String = "") -> void:
	var old := reputation
	reputation = old + applied_change(delta, old)
	if reputation != old:
		EventBus.reputation_changed.emit(reputation, reputation - old)
		ChangeLog.record_standing("rep", "Street reputation", reputation - old, reputation, reason)


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
