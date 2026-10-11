class_name Recommend
extends RefCounted
## The recommendation layer: reads the real game rules and says who/what
## suits a job best, with a reason. It never acts: the player picks, and
## every recommendation can be ignored.
##
## Numbers come from the same formulas the game uses:
##  - a ripperdoc's chance is EmployeeAI.success_chance (what assign rolls);
##  - your complication odds mirror SurgeryManager.get_extra_complication_chance
##    (customer risk, neural load, implant risk, tools, modifiers), assuming
##    your diagnosis is right (the preview never leaks whether it is), from
##    what the doctor can see (unrevealed conditions don't count yet);
##  - your own success is an ESTIMATE from your record on this procedure
##    and the job's difficulty against your level, because the operation
##    itself is in your hands.


## Ripperdocs on shift for a customer, best first: [{employee, chance, refusal, reason}].
static func staff_ranked(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c == null:
		return out
	for o: Dictionary in StaffManager.options_for(c):
		var e: Dictionary = o["employee"]
		var r := o.duplicate()
		r["reason"] = staff_reason(e, c)
		out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := str(a.get("refusal", "")) != ""
		var rb := str(b.get("refusal", "")) != ""
		if ra != rb:
			return rb
		return float(a["chance"]) > float(b["chance"]))
	return out


static func best_staff(c: CustomerData) -> Dictionary:
	var ranked := staff_ranked(c)
	return ranked[0] if not ranked.is_empty() and str(ranked[0].get("refusal", "")) == "" else {}


static func staff_reason(e: Dictionary, c: CustomerData) -> String:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id) if c else null
	var bits: Array[String] = []
	var spec: Dictionary = StaffManager.specializations.get(str(e.get("specialization", "general")), {})
	if item and (spec.get("categories", []) as Array).has(String(item.category)):
		bits.append("%s specialist" % str(spec.get("short", spec.get("name", "spec"))).to_upper())
	if item and int(e.get("skill", 1)) >= int(item.install_difficulty):
		bits.append("skill %d for difficulty %d" % [int(e.get("skill", 1)), int(item.install_difficulty)])
	if float(e.get("stress", 0)) >= 60.0:
		bits.append("stressed (%d)" % roundi(float(e["stress"])))
	return ", ".join(bits) if not bits.is_empty() else "general hands"


## Your odds on this job: {chance, record, complications: {guaranteed, extra}, factors}.
static func self_estimate(c: CustomerData) -> Dictionary:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id) if c else null
	var d := float(item.install_difficulty) if item else 2.0
	var rec: Dictionary = ProgressionManager.surgery_records.get(String(c.requested_surgery_id) if c else "", {})
	var done := int(rec.get("completed", 0))
	var failed := int(rec.get("failed", 0))
	# Your record on this procedure (smoothed toward a cautious 80%).
	var base := (float(done) + 4.0) / (float(done + failed) + 5.0)
	var factors: Array[String] = []
	var gap := d - (1.5 + float(ProgressionManager.level) * 0.5)
	if gap > 0.0:
		base -= 0.08 * gap
		factors.append("hard for your level")
	var extra := complication_odds(c)
	base -= extra * 0.25
	# Said whenever hidden conditions are possible and nothing was scanned:
	# never because this patient actually has one (that's the scan's to find).
	if c and Difficulty.hidden_conditions_allowed() and GameManager.chosen_diagnosis_id == &"":
		factors.append("hidden conditions not screened yet")
	if c and item and NeuralLoad.projected_visible(c, ImplantInstance.create(item.id)) > 80.0:
		base -= 0.08
		factors.append("neural load past 80")
	var record := "first time" if done + failed == 0 else "%d done, %d failed" % [done, failed]
	return {"chance": clampf(base, 0.15, 0.97), "record": record, "extra": extra,
		"guaranteed": mini(GameConfig.GUARANTEED_COMPLICATIONS, Difficulty.max_complications()), "factors": factors}


## Chance of an extra complication, the way SurgeryManager rolls it (if your
## diagnosis is right), from what the doctor can see: a hidden condition the
## scan hasn't found doesn't count yet (it never tips its hand early).
static func complication_odds(c: CustomerData) -> float:
	if c == null:
		return 0.0
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var risk := c.complication_risk
	for cid in c.hidden_conditions:
		if not c.revealed_conditions.has(cid):
			risk -= float(CustomerManager.get_condition(cid).get("modifiers", {}).get("complication_risk", 0.0))
	var chance := GameConfig.EXTRA_COMPLICATION_BASE_CHANCE * risk
	var unit := InventoryManager.get_instance(GameManager.selected_implant_uid) if GameManager.selected_implant_uid != "" else null
	if item:
		var inst := unit if unit else ImplantInstance.create(item.id)
		chance += NeuralLoad.complication_bonus(NeuralLoad.projected_visible(c, inst))
		chance += inst.get_extra_risk() if unit else item.failure_risk
	var s := SurgeryManager.get_surgery(c.requested_surgery_id)
	var tool_risk := 1.0
	if s:
		for cat in s.get_required_tool_categories():
			var t := InventoryManager.get_best_tool(cat)
			if t:
				tool_risk *= t.risk
	chance *= tool_risk * maxf(0.1, 1.0 + ModifierManager.value(&"complication.chance"))
	if Difficulty.max_complications() < 2:
		return 0.0
	return clampf(chance, 0.0, 0.95)


## Names of what can go wrong with this implant (the complication pool).
static func possible_complications(c: CustomerData, n: int = 3) -> Array[String]:
	var out: Array[String] = []
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id) if c else null
	if item == null:
		return out
	for id in item.complication_ids:
		var comp: ComplicationData = SurgeryManager.complications.get(id)
		if comp and not out.has(comp.title):
			out.append(comp.title)
		if out.size() >= n:
			break
	return out


## Who should operate: {who: "you" | employee id, name, chance, reason}.
static func surgeon(c: CustomerData) -> Dictionary:
	var me := self_estimate(c)
	var best := best_staff(c)
	if not best.is_empty() and float(best["chance"]) > float(me["chance"]) + 0.03:
		var e: Dictionary = best["employee"]
		return {"who": str(e["id"]), "name": str(e["name"]), "chance": float(best["chance"]), "reason": str(best["reason"])}
	var why := "your record on this procedure: %s" % me["record"]
	if best.is_empty() and StaffManager.options_for(c).is_empty():
		why += "; no ripperdoc on shift"
	return {"who": "you", "name": "You", "chance": float(me["chance"]), "reason": why}


## The implant unit to use: the best identified unit of the requested
## model (condition high, extra risk low). "" when none is in stock.
static func best_implant_uid(c: CustomerData) -> String:
	if c == null:
		return ""
	var best := ""
	var score := -INF
	for inst: ImplantInstance in InventoryManager.get_instances():
		if inst.cyberware_id != c.requested_cyberware_id:
			continue
		var s := inst.condition - 100.0 * inst.get_extra_risk() + (10.0 if inst.identified else -25.0)
		if s > score:
			score = s
			best = inst.uid
	return best
