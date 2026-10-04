class_name CustomerGenerator
extends RefCounted
## Builds procedural customers from archetype data: identity, faction,
## personality, finances, medical history, existing chrome, hidden
## conditions, the requested implant and a matching unique appearance.

const SCAN_REGIONS: Array[StringName] = [&"head", &"neck", &"chest", &"arms", &"legs"]
const CATEGORY_REGION := {&"eyes": &"head", &"neural": &"neck", &"spine": &"neck", &"arms": &"arms", &"dermal": &"arms",
	&"legs": &"legs", &"respiratory": &"chest", &"internal": &"chest"}
const NORMAL_FINDINGS := ["No anomalies.", "Tissue within normal range.", "Healthy signal.", "Minor wear, nothing urgent."]
const EXPR_BY_PERSONALITY := {&"hard": "hard", &"aggressive": "hard", &"stoic": "neutral", &"tired": "tired",
	&"nervous": "tired", &"smooth": "smirk", &"chatty": "smirk", &"paranoid": "hard", &"calm": "neutral"}
const GLOW_BY_FACTION := {&"black_market": "magenta", &"corporate_security": "blue", &"street_gangs": "red",
	&"independent_mercs": "amber", &"medical_authorities": "green"}
const NATURAL_HAIR := ["black", "black", "dark_brown", "dark_brown", "brown", "auburn", "blond", "gray"]
const DYED_HAIR := ["dye_cyan", "dye_magenta", "dye_green", "dye_blue", "dye_red"]

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
		fw[f] = float(arch["factions"][f]) * FactionManager.customer_weight(StringName(str(f)))
	c.faction_id = StringName(str(context.get("faction", pick_weighted(fw))))
	var names: Dictionary = CustomerManager.names
	c.display_name = "%s %s" % [pick(names["first"]), pick(names["last"])]
	c.alias = str(pick(names["alias"])) if rng.randf() < 0.55 else ""
	c.age = rng.randi_range(19, 64)
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
		weights[i] = w
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


func build_appearance(c: CustomerData, arch: Dictionary) -> Dictionary:
	var hair := str(pick(arch["hair"]))
	var dyed := c.archetype_id in [&"gang_member", &"criminal", &"civilian", &"bm_tech", &"fixer"] and rng.randf() < 0.3
	var a := {
		"build": pick(["slim", "average", "average", "heavy"]),
		"face": pick(["narrow", "broad", "round"]),
		"expr": EXPR_BY_PERSONALITY.get(c.personality, "neutral"),
		"hair": hair,
		"hair_back": hair if hair in ["long", "locs"] else "",
		"outfit": pick(arch["outfits"]),
		"facial_hair": "",
		"scar": "",
		"tattoos": [],
		"cyber": [],
		"accessories": [],
		"body_cyber": [],
		"skin": rng.randi_range(0, 6),
		"hair_color": pick(DYED_HAIR) if dyed else pick(NATURAL_HAIR),
		"iris": pick(["brown", "dark", "hazel", "green", "blue", "gray"]),
		"cloth_a": pick(arch["cloth_a"]),
		"cloth_b": pick(arch["cloth_b"]),
		"metal": "chrome",
		"glow": GLOW_BY_FACTION.get(c.faction_id, "cyan"),
	}
	var fh := str(pick(arch["facial_hair"]))
	if fh != "none" and rng.randf() < 0.6:
		a["facial_hair"] = fh
	var sc := str(pick(arch["scars"]))
	if sc != "none":
		a["scar"] = sc
	var tat := str(pick(arch["tattoos"]))
	if tat != "none":
		a["tattoos"] = [tat]
	var acc := str(pick(arch["accessories"]))
	if acc != "none":
		a["accessories"] = [acc]
	# Visible chrome follows the customer's real cyberware.
	var top_tier := 1
	for id in c.existing_cyberware:
		var e := CyberwareManager.get_cyberware(id)
		top_tier = maxi(top_tier, e.tier)
		match e.category:
			&"eyes":
				a["cyber"].append("visor" if e.tier >= 3 and rng.randf() < 0.5 else "eye")
			&"neural":
				a["cyber"].append(pick(["temple_port", "circuit", "neck_ports"]))
			&"arms":
				a["cyber"].append("arm_shoulder")
				a["body_cyber"].append("arm")
			&"legs":
				a["body_cyber"].append("legs")
			&"respiratory":
				a["cyber"].append("respirator")
			&"dermal":
				a["cyber"].append("cheek_mesh")
	if a["cyber"].is_empty() and rng.randf() < 0.35:
		var v := str(pick(arch["cyber_visual"]))
		if v != "none":
			a["cyber"].append(v)
	a["metal"] = {1: "chrome", 2: "chrome", 3: "gunmetal", 4: "ceramic", 5: "blackened"}.get(top_tier, "chrome")
	if a["cyber"].has("visor") and a["accessories"].has("shades"):
		a["accessories"].erase("shades")
	return a


func _build_dialogue(c: CustomerData, context: Dictionary) -> String:
	var d: Dictionary = CustomerManager.dialogue
	var parts: Array[String] = []
	if context.has("referred_by"):
		parts.append(str(pick(d["referral"])).replace("{name}", str(context["referred_by"])))
	else:
		parts.append(str(pick(d["greeting"].get(String(c.personality), d["greeting"]["calm"]))))
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item:
		parts.append(str(pick(d["reason"].get(String(item.category), ["I need chrome."]))))
	if c.get_neural_load() > 60.0:
		parts.append(str(pick(d["symptoms"])))
	parts.append(str(pick(d["money"].get(str(c.wealth), ["I can pay."]))))
	return " ".join(parts)
