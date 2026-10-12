class_name CustomerGenerator
extends RefCounted
## Builds procedural customers from archetype data: identity, faction,
## personality, finances, medical history, existing chrome, hidden
## conditions, the requested implant and a matching unique appearance.

const SCAN_REGIONS: Array[StringName] = [&"head", &"neck", &"chest", &"arms", &"legs"]
const CATEGORY_REGION := {&"eyes": &"head", &"neural": &"neck", &"spine": &"neck", &"arms": &"arms", &"dermal": &"arms",
	&"legs": &"legs", &"respiratory": &"chest", &"internal": &"chest"}
const NORMAL_FINDINGS := ["No anomalies.", "Tissue within normal range.", "Healthy signal.", "Minor wear, nothing urgent."]

var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func pick(arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)] if not arr.is_empty() else null


func pick_weighted(weights: Dictionary) -> Variant:
	var total := 0.0
	for k: Variant in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return weights.keys()[0] if not weights.is_empty() else null
	var r := rng.randf() * total
	for k: Variant in weights:
		r -= maxf(0.0, float(weights[k]))
		if r <= 0.0:
			return k
	return weights.keys()[weights.size() - 1]


func generate(context: Dictionary = {}) -> CustomerData:
	var arch := _pick_archetype(context)
	var c := CustomerData.new()
	c.id = StringName("cust_%d_%d" % [Time.get_ticks_usec(), rng.randi() % 100000])
	c.archetype_id = StringName(str(arch["id"]))
	var fw := {}
	for f: Variant in arch["factions"]:
		fw[f] = float(arch["factions"][f]) * FactionManager.customer_weight(StringName(str(f))) * WorldEventManager.faction_weight(StringName(str(f)))
	c.faction_id = StringName(str(context.get("faction", pick_weighted(fw))))
	var names: Dictionary = CustomerManager.names
	c.display_name = "%s %s" % [pick(names["first"]), pick(names["last"])]
	c.alias = str(pick(names["alias"])) if rng.randf() < 0.55 else ""
	c.age = rng.randi_range(19, 64)
	# Kids on the street want chrome too. Who operates on them is a choice.
	if str(arch["id"]) in ["scavenger", "addict", "gang_member"] and rng.randf() < 0.07:
		c.age = rng.randi_range(15, 17)
	c.occupation = str(pick(arch["occupations"]))
	c.personality = StringName(str(pick(arch["personalities"])))
	var w: Array = arch["wealth"]
	c.wealth = clampi(rng.randi_range(int(w[0]), int(w[1])) + int(ModifierManager.value(&"customer.quality")), 0, 3)
	c.street_rep = rng.randi_range(0, 60)
	var pr: Array = arch["pain"]
	c.pain_tolerance = rng.randf_range(float(pr[0]), float(pr[1]))
	var pa: Array = arch["patience"]
	c.patience = rng.randi_range(int(pa[0]), int(pa[1]))
	var ri: Array = arch["risk"]
	c.risk_tolerance = rng.randf_range(float(ri[0]), float(ri[1]))
	var ne: Array = arch["neural"]
	c.neural_stability = rng.randf_range(float(ne[0]), float(ne[1]))
	c.neural_sensitivity = rng.randf_range(0.85, 1.2)
	c.bleed_multiplier = rng.randf_range(0.9, 1.15)
	c.complication_risk = rng.randf_range(0.85, 1.15)
	c.pay_multiplier = float(arch.get("pay_mult", 1.0)) * (0.8 + 0.15 * c.wealth)
	roll_psychology(c, str(arch["id"]))
	_roll_existing_cyberware(c, arch)
	# Learning curve: early patients are calm, stable and have no surprises
	# (context "full_difficulty" opts out, e.g. for story spawns and tests).
	var learning := not bool(context.get("full_difficulty", false))
	if learning:
		while c.existing_cyberware.size() > 0 and c.get_neural_load() > Difficulty.early_load_cap():
			c.existing_cyberware.pop_back()
		if Difficulty.ops() < Difficulty.HIDDEN_CONDITIONS_FROM_OP:
			c.patience = maxi(c.patience, 70)
	if not learning or Difficulty.hidden_conditions_allowed():
		_roll_conditions(c)
	_roll_request(c, arch, context)
	_roll_diagnosis(c)
	_build_findings(c)
	_build_history(c)
	roll_budget(c)
	c.appearance = build_appearance(c, arch)
	c.dialogue = _build_dialogue(c, context)
	if context.has("referred_by"):
		c.referred_by = str(context["referred_by"])
		c.pay_multiplier *= 1.1
	return c


func _pick_archetype(context: Dictionary) -> Dictionary:
	var list: Array = CustomerManager.archetypes
	if context.has("archetype"):
		for a: Dictionary in list:
			if str(a["id"]) == str(context["archetype"]):
				return a
	var weights := {}
	for i in list.size():
		var a: Dictionary = list[i]
		if int(a.get("min_rep", -100)) > ReputationManager.reputation:
			continue
		var w := 0.0
		for f: Variant in a["factions"]:
			w += float(a["factions"][f]) * FactionManager.customer_weight(StringName(str(f)))
		# The district decides who walks past the door.
		weights[i] = w * WorldManager.customer_weight(str(a["id"])) * TimeManager.archetype_weight(str(a["id"])) * WorldEventManager.archetype_weight(str(a["id"])) * ReputationManager.archetype_weight(str(a["id"]))
	return list[int(pick_weighted(weights))]


func _roll_existing_cyberware(c: CustomerData, arch: Dictionary) -> void:
	var ex: Array = arch["existing"]
	var count := rng.randi_range(int(ex[0]), int(ex[1]))
	var used := {}
	for i in count:
		var cat := StringName(str(pick_weighted(arch["categories"])))
		if used.has(cat):
			continue
		var max_tier := 2 if c.wealth < 2 else 3
		var pool := CyberwareManager.get_by_category(cat, max_tier, c.risk_tolerance > 0.8)
		if pool.is_empty():
			continue
		used[cat] = true
		c.existing_cyberware.append((pick(pool) as CyberwareData).id)


func _roll_conditions(c: CustomerData) -> void:
	var ids: Array = CustomerManager.conditions.keys()
	var chances := [0.45, 0.15]
	for ch: float in chances:
		if rng.randf() < ch:
			var cid: StringName = pick(ids)
			if not c.hidden_conditions.has(cid):
				c.hidden_conditions.append(cid)
				c.apply_condition(CustomerManager.get_condition(cid))


func _roll_request(c: CustomerData, arch: Dictionary, context: Dictionary) -> void:
	var avail := CyberwareManager.get_available_tier()
	var cat := StringName(str(context.get("category", pick_weighted(arch["categories"]))))
	var wanted_tier := clampi(rng.randi_range(1, avail) + (1 if c.wealth >= 2 and rng.randf() < 0.4 else 0), 1, avail)
	var pool := CyberwareManager.get_by_category(cat, wanted_tier)
	if pool.is_empty():
		pool = CyberwareManager.get_by_category(&"neural", 1)
	# Prefer the highest tier the customer wants, and not a duplicate of what they have.
	pool.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.tier > b.tier)
	var choice: CyberwareData = pool[0]
	for item in pool:
		if not c.existing_cyberware.has(item.id):
			choice = item
			break
	# Most customers want jobs the clinic is equipped for (all of them while
	# the player is learning); the rest are a nudge to buy better tools.
	if not context.has("category") and not context.has("cyberware") and not is_feasible(choice):
		var feasible_share := 1.0 if Difficulty.ops() < Difficulty.EARLY_LOAD_CAP_UNTIL_OP else GameConfig.FEASIBLE_REQUEST_SHARE
		if rng.randf() < feasible_share:
			var options: Array[CyberwareData] = []
			for cat_id: Variant in arch["categories"]:
				for item in CyberwareManager.get_by_category(StringName(str(cat_id)), wanted_tier):
					if is_feasible(item) and not c.existing_cyberware.has(item.id):
						options.append(item)
			if options.is_empty():
				options = CyberwareManager.get_by_category(&"neural", 1)
			choice = options[rng.randi_range(0, options.size() - 1)]
	if context.has("cyberware") and CyberwareManager.get_cyberware(StringName(str(context["cyberware"]))):
		choice = CyberwareManager.get_cyberware(StringName(str(context["cyberware"])))
	c.requested_cyberware_id = choice.id
	c.requested_surgery_id = choice.install_surgery_id


## Whether the clinic owns every tool the job needs right now.
static func is_feasible(item: CyberwareData) -> bool:
	var surgery := SurgeryManager.get_surgery(item.install_surgery_id)
	if surgery == null:
		return false
	for category in surgery.get_required_tool_categories():
		if not InventoryManager.has_tool_category(category):
			return false
	for req in item.get_tool_requirements():
		if not InventoryManager.has_tool_category(req["category"], int(req["tier"])):
			return false
	return true


func _roll_diagnosis(c: CustomerData) -> void:
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	if surgery == null:
		return
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var has_old := false
	for id in c.existing_cyberware:
		var e := CyberwareManager.get_cyberware(id)
		if e and item and e.category == item.category:
			has_old = true
	var dx := StringName(str(pick(surgery.diagnosis_options)["id"]))
	if surgery.has_diagnosis(&"old_hardware") and has_old:
		dx = &"old_hardware"
	elif surgery.has_diagnosis(&"burnt_socket") and has_old:
		dx = &"burnt_socket"
	elif surgery.has_diagnosis(&"neural_rejection") and c.hidden_conditions.has(&"rejection_prone"):
		dx = &"neural_rejection"
	c.true_diagnosis_id = dx
	if dx in [&"tissue_damage", &"scar_tissue", &"burnt_socket"]:
		c.extra_damaged_tissue = 1 + rng.randi_range(0, 1)


func _build_findings(c: CustomerData) -> void:
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	for region in SCAN_REGIONS:
		var text := str(pick(NORMAL_FINDINGS))
		for id in c.existing_cyberware:
			var e := CyberwareManager.get_cyberware(id)
			if e and CATEGORY_REGION.get(e.category, &"") == region:
				text = "%s installed, %s." % [e.display_name, "running hot" if c.get_neural_load() > 60 else "functioning"]
		if surgery and region == surgery.scan_region:
			var pool: Array = surgery.diagnosis_findings.get(String(c.true_diagnosis_id), [])
			if not pool.is_empty():
				text = str(pick(pool))
		c.scan_findings[String(region)] = text


## Existing chrome is listed separately (customer file "Chrome:" line).
func _build_history(c: CustomerData) -> void:
	var extras := ["Old knife wound, healed badly", "Broken ribs, two years ago", "Allergic to polymer sealant",
		"Chronic lung irritation", "No prior surgery", "Stim use, past and present", "Burn scars on the forearm"]
	c.medical_history.append(str(pick(extras)))


## Look from occupation (archetype), faction, wealth, age, personality and
## the cyberware the customer really has (CharacterAppearanceManager rules).
func build_appearance(c: CustomerData, arch: Dictionary) -> Dictionary:
	var occ := str(arch.get("look", arch["id"]))
	var rules: Dictionary = CharacterAppearanceManager.rules.get("occupations", {}).get(occ, {})
	if rules.has("age"):
		var ar: Array = rules["age"]
		c.age = rng.randi_range(int(ar[0]), int(ar[1]))
	var ctx := {
		"occupation": occ, "faction": String(c.faction_id), "wealth": c.wealth, "age": c.age,
		"personality": String(c.personality), "cyberware": c.existing_cyberware,
	}
	return CharacterAppearanceManager.generate(ctx, rng)


## Traits (1-2, weighted by archetype), finances and today's budget.
## Traits nudge patience, risk appetite and the portrait's idle animation.
func roll_psychology(c: CustomerData, arch_id: String) -> void:
	var data: Dictionary = PeopleManager.patients
	var tw: Dictionary = data.get("trait_weights_by_archetype", {})
	var weights: Dictionary = (tw.get(arch_id, tw.get("_default", {"nervous": 1})) as Dictionary).duplicate()
	c.traits.clear()
	for i in (2 if rng.randf() < 0.45 else 1):
		if weights.is_empty():
			break
		var t := str(pick_weighted(weights))
		weights.erase(t)
		c.traits.append(StringName(t))
	var defs: Dictionary = data.get("traits", {})
	for t in c.traits:
		var d: Dictionary = defs.get(String(t), {})
		c.patience = clampi(c.patience + int(d.get("patience", 0)), 5, 100)
		c.risk_tolerance = clampf(c.risk_tolerance + float(d.get("risk", 0.0)), 0.0, 1.0)
		if d.has("anim"):
			c.personality = StringName(str(d["anim"]))
	c.mood = &"nervous" if c.traits.has(&"nervous") or c.traits.has(&"paranoid") else (&"angry" if c.traits.has(&"aggressive") else &"calm")
	var fw: Dictionary = data.get("finance_by_wealth", {}).get(str(c.wealth), {"working": 1})
	c.finance = StringName(str(pick_weighted(fw)))
	var fd: Dictionary = data.get("finances", {}).get(String(c.finance), {})
	var b: Array = fd.get("budget", [300, 600])
	c.budget = rng.randi_range(int(b[0]), int(b[1]))
	c.backer = StringName(str(fd.get("backer", "")))
	if c.traits.has(&"dependent"):
		c.dependency = 1


## What they can pay today: a share of the expected fee for the job they
## want, set by their finances (data/patients.json budget_ratio).
func roll_budget(c: CustomerData) -> void:
	var fd: Dictionary = PeopleManager.patients.get("finances", {}).get(String(c.finance), {})
	var fee := estimate_fee(c)
	if fee <= 0 or not fd.has("budget_ratio"):
		return
	var r: Array = fd["budget_ratio"]
	var ratio := rng.randf_range(float(r[0]), float(r[1]))
	# While learning the job, everyone can pay.
	if Difficulty.ops() < Difficulty.HIDDEN_CONDITIONS_FROM_OP + 2:
		ratio = maxf(ratio, 1.3)
	c.budget = maxi(20, int(round(fee * ratio / 10.0)) * 10)


## Roughly what the job will be billed at (an average result).
static func estimate_fee(c: CustomerData) -> int:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var s := SurgeryManager.get_surgery(c.requested_surgery_id)
	if item == null or s == null:
		return 0
	var mult := c.pay_multiplier * ModifierManager.mult(&"pay")
	var service := s.base_pay * 1.1 * mult
	return int(round(service + estimate_part(c)))


## The part's share of the estimate (what the patient pays for the implant).
static func estimate_part(c: CustomerData) -> float:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item == null:
		return 0.0
	var mult := c.pay_multiplier * ModifierManager.mult(&"pay")
	return InventoryManager.implant_price(item) * GameConfig.IMPLANT_PRICE_MARKUP * minf(mult, 1.0)


func _build_dialogue(c: CustomerData, context: Dictionary) -> String:
	var d: Dictionary = CustomerManager.dialogue
	var parts: Array[String] = []
	if context.has("referred_by"):
		parts.append(str(pick(d["referral"])).replace("{name}", str(context["referred_by"])))
	else:
		var hour := TimeManager.greeting_line()
		parts.append(hour if hour != "" else str(pick(d["greeting"].get(String(c.personality), d["greeting"]["calm"]))))
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item:
		parts.append(str(pick(d["reason"].get(String(item.category), ["I need chrome."]))))
	if c.get_neural_load() > 60.0:
		parts.append(str(pick(d["symptoms"])))
	parts.append(str(pick(d["money"].get(str(c.wealth), ["I can pay."]))))
	for t in c.traits:
		var lines: Array = PeopleManager.patients.get("traits", {}).get(String(t), {}).get("lines", [])
		if not lines.is_empty() and rng.randf() < 0.6:
			parts.append(str(pick(lines)))
			break
	return " ".join(parts)
