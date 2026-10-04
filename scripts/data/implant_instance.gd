class_name ImplantInstance
extends RefCounted
## One physical implant in the clinic's stock. Supply-bought units are pristine;
## black-market units have a condition and hidden traits that STUDY reveals.

var uid: String = ""
var cyberware_id: StringName
var condition: float = 100.0
## Trait ids from data/black_market.json.
var traits: Array[StringName] = []
var revealed: Array[StringName] = []
var source: StringName = &"supply"
var modified: int = 0


static func create(item_id: StringName, p_condition: float = 100.0, p_source: StringName = &"supply") -> ImplantInstance:
	var inst := ImplantInstance.new()
	inst.uid = "imp_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	inst.cyberware_id = item_id
	inst.condition = clampf(p_condition, 1.0, 100.0)
	inst.source = p_source
	return inst


func get_data() -> CyberwareData:
	return CyberwareManager.get_cyberware(cyberware_id)


func has_unknown_traits() -> bool:
	return revealed.size() < traits.size()


func trait_effect(key: String) -> float:
	var total := 0.0
	for t in traits:
		var data := BlackMarketManager.get_trait(t)
		total += float(data.get("effects", {}).get(key, 0.0))
	return total


## Effective neural load of this unit.
func get_neural_load() -> float:
	var data := get_data()
	return maxf(0.0, (data.neural_load if data else 0.0) + trait_effect("neural_load"))


## Multiplier on implant performance from wear and traits.
func get_quality() -> float:
	return clampf((0.55 + 0.45 * condition / 100.0) * (1.0 + trait_effect("performance")), 0.1, 1.4)


func get_extra_risk() -> float:
	var data := get_data()
	var r := (data.failure_risk if data else 0.0) + trait_effect("complication_risk")
	r += (100.0 - condition) / 100.0 * GameConfig.WORN_IMPLANT_RISK
	return maxf(0.0, r)


func to_dict() -> Dictionary:
	var t: Array[String] = []
	for x in traits:
		t.append(String(x))
	var r: Array[String] = []
	for x in revealed:
		r.append(String(x))
	return {"uid": uid, "id": String(cyberware_id), "condition": condition, "traits": t, "revealed": r,
			"source": String(source), "modified": modified}


static func from_dict(d: Dictionary) -> ImplantInstance:
	var inst := ImplantInstance.new()
	inst.uid = str(d.get("uid", "imp_legacy_%d" % randi()))
	inst.cyberware_id = StringName(str(d.get("id", "")))
	inst.condition = float(d.get("condition", 100.0))
	for x: Variant in d.get("traits", []):
		inst.traits.append(StringName(str(x)))
	for x: Variant in d.get("revealed", []):
		inst.revealed.append(StringName(str(x)))
	inst.source = StringName(str(d.get("source", "supply")))
	inst.modified = int(d.get("modified", 0))
	return inst
