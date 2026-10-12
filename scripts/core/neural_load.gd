class_name NeuralLoad
extends RefCounted
## Neural load: how much synthetic signal a nervous system is carrying.
## Every implant adds load; past 50% the patient starts paying for it.

const BANDS := [
	{"max": 50.0, "id": &"stable", "name": "STABLE", "color": Color("6dff8a")},
	{"max": 70.0, "id": &"minor", "name": "MINOR SYMPTOMS", "color": Color("c8e86a")},
	{"max": 85.0, "id": &"unstable", "name": "INSTABILITY", "color": Color("ffb43d")},
	{"max": 95.0, "id": &"severe", "name": "SEVERE INSTABILITY", "color": Color("ff4d4d")},
	{"max": 99999.0, "id": &"critical", "name": "CRITICAL", "color": Color("ff2a5a")},
]


## Current load of a customer from existing chrome and hidden conditions.
static func compute(customer: CustomerData) -> float:
	if customer == null:
		return 0.0
	var load := 0.0
	for id in customer.existing_cyberware:
		var item := CyberwareManager.get_cyberware(id)
		if item:
			load += item.neural_load
	for cid in customer.hidden_conditions:
		var cond := CustomerManager.get_condition(cid)
		load += float(cond.get("modifiers", {}).get("neural_load", 0.0))
	return load


## Load the doctor can see: installed chrome + revealed conditions.
static func compute_visible(customer: CustomerData) -> float:
	if customer == null:
		return 0.0
	var load := 0.0
	for id in customer.existing_cyberware:
		var item := CyberwareManager.get_cyberware(id)
		if item:
			load += item.neural_load
	for cid in customer.revealed_conditions:
		load += float(CustomerManager.get_condition(cid).get("modifiers", {}).get("neural_load", 0.0))
	return load


## Load after installing `implant` (skill/tool modifiers reduce the added load).
static func projected(customer: CustomerData, implant: ImplantInstance) -> float:
	var added := implant.get_neural_load() if implant else 0.0
	return compute(customer) + added * maxf(0.2, ModifierManager.mult(&"neural.load"))


## The same projection from what the doctor can see (installed chrome and
## revealed conditions): what the patient's file and intake form show.
static func projected_visible(customer: CustomerData, implant: ImplantInstance) -> float:
	var added := implant.get_neural_load() if implant else 0.0
	return compute_visible(customer) + added * maxf(0.2, ModifierManager.mult(&"neural.load"))


static func band(load: float) -> Dictionary:
	for b: Dictionary in BANDS:
		if load < float(b["max"]):
			return b
	return BANDS[BANDS.size() - 1]


static func band_index(load: float) -> int:
	for i in BANDS.size():
		if load < float(BANDS[i]["max"]):
			return i
	return BANDS.size() - 1


## Neural-vital drain multiplier during surgery.
static func drain_multiplier(load: float) -> float:
	return 1.0 + maxf(0.0, load - 50.0) / 40.0


## Neural stability lost at the start of surgery.
static func start_penalty(load: float) -> float:
	return maxf(0.0, load - 60.0) * 0.5


## Additive complication chance.
static func complication_bonus(load: float) -> float:
	return maxf(0.0, load - 50.0) / 100.0


## Calibration sync window multiplier.
static func sync_range_multiplier(load: float) -> float:
	return clampf(1.0 - maxf(0.0, load - 70.0) / 80.0, 0.5, 1.0)


## Chance of a post-op neural break ("static fever").
static func break_chance(load: float) -> float:
	return clampf(maxf(0.0, load - 90.0) / 40.0, 0.0, 0.9)
