class_name EmployeeAI
extends RefCounted
## How an employee thinks: whether they'll take a job (ethics, traits,
## mood), how likely they are to pull it off (skill vs difficulty,
## specialization, precision, reliability, stress, clinic gear), and how a
## day changes them (stress, loyalty, growth, ambition, secrets).
## Pure functions over employee dictionaries so they are easy to test.

const STRESS_PER_JOB := 6.0
const STRESS_PER_DIFFICULTY := 3.0


static func has_trait(e: Dictionary, t: String) -> bool:
	return (e.get("traits", []) as Array).has(t)


static func has_ethic(e: Dictionary, t: String) -> bool:
	return (e.get("ethics", []) as Array).has(t)


static func trait_value(e: Dictionary, key: String) -> float:
	var v := 0.0
	for t: Variant in e.get("traits", []):
		v += float(StaffManager.traits.get(str(t), {}).get(key, 0.0))
	return v


static func is_corporate(c: CustomerData) -> bool:
	return c.faction_id in [&"corporate_security", &"lyra_biocomp"] or c.archetype_id in [&"corporate", &"executive"]


static func job_pay(c: CustomerData) -> int:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var s := SurgeryManager.get_surgery(item.install_surgery_id) if item else null
	if item == null or s == null:
		return 0
	return int(round((s.base_pay + item.price * GameConfig.IMPLANT_PRICE_MARKUP) * c.pay_multiplier * ModifierManager.mult(&"pay")))


## "" if they'll do it, otherwise why not (in their words).
static func refusal(e: Dictionary, c: CustomerData) -> String:
	if c == null:
		return "There's nobody on the table."
	if str(e.get("status", "working")) != "working":
		return "%s is off shift (%s)." % [e["name"], e.get("status", "")]
	if int(e.get("jobs_today", 0)) >= max_jobs(e):
		return "%s has done enough cutting for one day." % e["name"]
	if has_trait(e, "butcher"):
		return ""
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if has_ethic(e, "no_minors") and c.age < 18:
		return "\"That's a kid. I'm not putting chrome in a kid.\""
	if (has_ethic(e, "no_harvest") or (has_trait(e, "idealist") and float(e.get("loyalty", 50)) < 70.0)) and item and item.black_market:
		return "\"Unregistered chrome? Somebody died for that. No.\""
	if (has_ethic(e, "no_corps") or has_trait(e, "hates_corps")) and is_corporate(c):
		return "\"I don't patch up corp dogs.\""
	if has_trait(e, "money_only") and job_pay(c) < int(StaffManager.traits["money_only"].get("min_pay", 250)):
		return "\"For that money? Do it yourself.\""
	return ""


static func max_jobs(e: Dictionary) -> int:
	return 2 + int(trait_value(e, "jobs"))


## Success chance (0.05..0.97) for this employee on this customer.
static func success_chance(e: Dictionary, c: CustomerData) -> float:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id) if c else null
	var d := float(item.install_difficulty) if item else 2.0
	var p := 0.58 + 0.1 * (float(e.get("skill", 1)) - d) + 0.04 * (float(e.get("precision", 3)) - 3.0) + 0.03 * (float(e.get("reliability", 3)) - 3.0)
	var spec: Dictionary = StaffManager.specializations.get(str(e.get("specialization", "general")), {})
	if item and (spec.get("categories", []) as Array).has(String(item.category)):
		p += 0.12
	p += float(spec.get("any_bonus", 0.0))
	if item and item.black_market:
		p += float(spec.get("black_market_bonus", 0.0)) - 0.05
	p += trait_value(e, "chance")
	p -= 0.25 * float(e.get("stress", 0)) / 100.0
	p += StaffLifeManager.team_modifier(e)
	p += TimeManager.staff_modifier(e)
	p += ModifierManager.value(&"staff.skill") * 0.5 - ModifierManager.value(&"complication.chance") * 0.5
	if c:
		p -= 0.05 * c.hidden_conditions.size()
		if item and NeuralLoad.projected(c, ImplantInstance.create(item.id)) > 80.0:
			p -= 0.1
	return clampf(p, 0.05, 0.97)


## Rolls the job. Returns {success, death, pay, xp, stress, text}.
static func perform(e: Dictionary, c: CustomerData, rng: RandomNumberGenerator) -> Dictionary:
	var chance := success_chance(e, c)
	var variance := trait_value(e, "variance")
	if variance > 0.0:
		chance = clampf(chance + rng.randf_range(-variance, variance), 0.05, 0.97)
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var d := float(item.install_difficulty) if item else 2.0
	var ok := rng.randf() < chance
	var death := not ok and rng.randf() < 0.12 + 0.35 * (1.0 - chance)
	var stress := STRESS_PER_JOB + STRESS_PER_DIFFICULTY * d
	stress *= 1.0 + trait_value(e, "stress") - ModifierManager.value(&"staff.stress")
	if death:
		stress += 25.0
	var xp := int(round(d * 10.0 * (1.0 + trait_value(e, "xp")) * (1.0 if ok else 0.5)))
	var pay := int(round(job_pay(c) * (0.9 + 0.03 * float(e.get("speed", 3))))) if ok else 0
	var who := str(e["name"]).get_slice(" ", 0)
	var what := item.display_name if item else "the job"
	var text := ""
	if ok:
		text = "%s installed %s in %s. Clean work." % [who, what, c.display_name]
	elif death:
		text = "%s lost %s on the table during %s. The body has to go somewhere." % [who, c.display_name, what]
	else:
		text = "%s botched %s on %s. They walked out bleeding and furious." % [who, what, c.display_name]
	return {"success": ok, "death": death, "pay": pay, "xp": xp, "stress": stress, "text": text, "chance": chance}


## Salary this person could get elsewhere.
static func market_salary(e: Dictionary) -> int:
	var spec: Dictionary = StaffManager.specializations.get(str(e.get("specialization", "general")), {})
	var base := 20.0 + 12.0 * float(e.get("skill", 1)) + 4.0 * (float(e.get("precision", 3)) + float(e.get("speed", 3)) + float(e.get("reliability", 3)) - 9.0)
	base += float(spec.get("premium", 0))
	base *= 1.0 + trait_value(e, "salary")
	return maxi(15, int(round(base)))
