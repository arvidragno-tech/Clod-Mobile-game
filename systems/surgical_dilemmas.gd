class_name SurgicalDilemmas
extends RefCounted
## Decision complications (data/dilemmas.json): the operation stops and
## you choose. NEURAL REJECTION, UNKNOWN FIRMWARE, INTERNAL BLEEDING,
## CYBERWARE INSTABILITY, UNEXPECTED NERVE DAMAGE, FOREIGN DEVICE. Whether
## one happens, and which, depends on the patient (load, hidden conditions,
## existing chrome, previous operations, emergency), the chrome (black
## market, unknown traits), your tools and your skill. Every choice shows
## its odds and its risk before you commit.

static var _data: Dictionary = {}
## Scripted test runs switch random dilemmas off (they still use
## SurgeryManager.debug_trigger_dilemma).
static var enabled: bool = true


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = DataLoader.load_json(GameConfig.DATA_DILEMMAS)
		_data = d if d is Dictionary else {"dilemmas": []}
	return _data


static func get_dilemma(id: StringName) -> Dictionary:
	for d: Dictionary in data().get("dilemmas", []):
		if str(d["id"]) == String(id):
			return d
	return {}


## What's true about this operation (feeds chance and which dilemma).
static func conditions(sm: Node) -> Dictionary:
	var c: CustomerData = sm.customer
	var inst: ImplantInstance = sm.implant
	var item: CyberwareData = sm.implant_item
	return {
		"high_load": float(sm.neural_load_after) > 60.0,
		"neural": item != null and item.category == &"neural",
		"black_market": (inst != null and inst.source == &"black_market") or (item != null and item.black_market),
		"unknown_traits": inst != null and inst.has_unknown_traits(),
		"existing_chrome": c != null and c.existing_cyberware.size() >= 2,
		"hidden_conditions": c != null and not c.hidden_conditions.is_empty(),
		"emergency": c != null and c.is_emergency,
		"previous_ops": c != null and c.visits >= 1,
		"criminal": c != null and c.faction_id in [&"street_gangs", &"black_market", &"independent_mercs"],
	}


## Chance this operation hits a dilemma at all.
static func chance(sm: Node) -> float:
	if not enabled or Difficulty.ops() < int(data().get("learning_ops", 5)) or TutorialManager.is_active():
		return 0.0
	var cond := conditions(sm)
	var m := 1.0
	for k: String in ["black_market", "unknown_traits", "existing_chrome", "hidden_conditions", "emergency", "high_load"]:
		if bool(cond[k]):
			m += 0.4
	m -= ModifierManager.value(&"complication.chance")
	return clampf(float(data().get("base_chance", 0.16)) * m, 0.0, 0.6)


## Picks the stage to stop at (-1 = no dilemma this time).
static func plan(sm: Node, rng: RandomNumberGenerator) -> int:
	var stages: Array = sm.surgery.stages
	if stages.size() < 3 or rng.randf() >= chance(sm):
		return -1
	return rng.randi_range(1, stages.size() - 2)


static func pick(sm: Node, rng: RandomNumberGenerator, exclude: Array = []) -> Dictionary:
	var cond := conditions(sm)
	var weights := {}
	var list: Array = data().get("dilemmas", [])
	for i in list.size():
		var d: Dictionary = list[i]
		if exclude.has(str(d["id"])):
			continue
		var w := float(d.get("weight", 1))
		var ww: Dictionary = d.get("weight_when", {})
		for k: Variant in ww:
			if bool(cond.get(str(k), false)):
				w += float(ww[k])
		weights[i] = w
	if weights.is_empty():
		return {}
	return list[int(CustomerGenerator.new(rng).pick_weighted(weights))]


## The employee who'd come in to help (best odds, on shift here).
static func helper(c: CustomerData) -> Dictionary:
	var best: Dictionary = {}
	var best_p := -1.0
	for e in StaffManager.at_clinic(ClinicManager.tier):
		if str(e.get("status", "")) != "working":
			continue
		var p := EmployeeAI.success_chance(e, c)
		if p > best_p:
			best_p = p
			best = e
	return best


## "" if the choice can be taken, otherwise why not.
static func block_reason(choice: Dictionary) -> String:
	var req: Dictionary = choice.get("requires", {})
	if req.has("tool") and not InventoryManager.has_tool_category(StringName(str(req["tool"]))):
		return "Needs a %s" % str(req["tool"])
	if InventoryManager.parts < int(req.get("parts", 0)):
		return "Needs %d parts" % int(req["parts"])
	if InventoryManager.supplies < int(req.get("supplies", 0)):
		return "Needs %d supplies" % int(req["supplies"])
	if bool(req.get("staff", false)) and helper(null).is_empty():
		return "Nobody on shift"
	return ""


## Odds of the good outcome for this choice, here and now.
static func odds(sm: Node, choice: Dictionary) -> float:
	var c: CustomerData = sm.customer
	var req: Dictionary = choice.get("requires", {})
	if bool(req.get("staff", false)):
		var e := helper(c)
		return EmployeeAI.success_chance(e, c) if not e.is_empty() else 0.0
	var p := float(choice.get("odds", 0.5))
	if p >= 1.0:
		return 1.0
	p += ModifierManager.value(&"surgery.precision") * 0.5
	if req.has("tool"):
		var t: ToolData = sm.get_tool_for_category(StringName(str(req["tool"])))
		if t:
			p += 0.05 * (t.tier - 1)
	if c:
		p -= 0.15 * (c.complication_risk - 1.0)
	if float(sm.neural_load_after) > 70.0:
		p -= 0.08
	return clampf(p, 0.05, 0.97)
