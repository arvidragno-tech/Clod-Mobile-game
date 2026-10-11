class_name JobVerdict
extends RefCounted
## "At a glance" for the patient at the door: can you do this job right
## now, what's in the way, what it pays, how risky it is, and one line of
## advice. Built from GameManager.get_surgery_readiness and the customer,
## so it always agrees with the operation plan.
##
## checks(c) -> [{key, label, value, level: &"good"|&"warn"|&"bad", term}]
## advice(c) -> {text, level}

const RISK_LABELS := ["", "LOW", "MEDIUM", "HIGH"]


static func checks(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c == null:
		return out
	var item := GameManager.get_requested_item()
	var surgery := GameManager.get_current_surgery()
	var r := GameManager.get_surgery_readiness()
	if str(r.get("invalid", "")) != "":
		out.append({"key": "request", "label": "REQUEST", "value": "can't be done here", "level": &"bad", "term": "tier"})
		return out
	# Implant.
	match StringName(str(r["implant_source"])):
		&"stock":
			out.append({"key": "implant", "label": "IMPLANT", "value": "in stock", "level": &"good", "term": "condition"})
		&"substitute":
			out.append({"key": "implant", "label": "IMPLANT", "value": "a substitute from stock", "level": &"warn", "term": "condition"})
		&"buy":
			out.append({"key": "implant", "label": "IMPLANT", "value": "buy one (%s)" % EconomyManager.format_money(InventoryManager.implant_price(item)), "level": &"warn", "term": "credits"})
		_:
			out.append({"key": "implant", "label": "IMPLANT", "value": "none: salvaged parts only", "level": &"bad", "term": "condition"})
	# Tools.
	var missing: Array = r["missing_tools"]
	if missing.is_empty():
		out.append({"key": "tools", "label": "TOOLS", "value": "you have what it needs", "level": &"good", "term": "difficulty"})
	else:
		out.append({"key": "tools", "label": "TOOLS", "value": "missing " + ", ".join(missing), "level": &"bad", "term": "difficulty"})
	# Supplies.
	if surgery:
		var ok := bool(r["supplies_ok"])
		out.append({"key": "supplies", "label": "SUPPLIES", "value": "%d needed, %d on hand" % [surgery.supplies, InventoryManager.supplies], "level": &"good" if ok else &"bad", "term": "supplies"})
	# Difficulty.
	if item:
		var d := item.install_difficulty
		var lvl := &"good" if d <= 2 or ProgressionManager.level >= d * 2 else (&"warn" if ProgressionManager.level >= d else &"bad")
		out.append({"key": "difficulty", "label": "DIFFICULTY", "value": "%d / 5 · %s" % [d, TimeManager.duration_text(TimeManager.procedure_minutes(d, c.is_emergency))], "level": lvl, "term": "difficulty"})
	# Neural load after.
	var band: Dictionary = NeuralLoad.band(float(r["neural_after"]))
	var nl := float(r["neural_after"])
	out.append({"key": "neural", "label": "NEURAL LOAD", "value": "≈ %d%% after · %s" % [roundi(nl), band["name"]], "level": &"good" if nl < 60.0 else (&"warn" if nl < 85.0 else &"bad"), "term": "neural_load"})
	# Risk.
	var risk := c.get_risk_level()
	out.append({"key": "risk", "label": "RISK", "value": RISK_LABELS[risk], "level": [&"good", &"good", &"warn", &"bad"][risk], "term": "risk"})
	# Pay.
	var fee := CustomerGenerator.estimate_fee(c)
	var cast := c.character_id != &"" and CharacterManager.has_character(c.character_id)
	var pays := cast or c.budget >= fee
	out.append({"key": "pay", "label": "PAY", "value": ("≈ %s" % EconomyManager.format_money(fee)) + ("" if pays else " · can pay %s now" % EconomyManager.format_money(c.budget)),
		"level": &"good" if pays else &"warn", "term": "terms_payment"})
	if not bool(r.get("accepts", true)):
		out.append({"key": "accepts", "label": "PATIENT", "value": "won't accept that unit", "level": &"bad", "term": "condition"})
	return out


## One line of advice.
static func advice(c: CustomerData) -> Dictionary:
	if c == null:
		return {"text": "", "level": &"good"}
	var cs := checks(c)
	var by := {}
	for x in cs:
		by[x["key"]] = x
	if by.has("request"):
		return {"text": "This clinic can't do that job. Refuse or defer.", "level": &"bad"}
	if by.has("tools") and by["tools"]["level"] == &"bad":
		var staff := StaffManager.at_clinic(ClinicManager.tier).size() > 0
		return {"text": "You're missing tools: buy them in SUPPLY first%s, or defer." % (", hand it to your staff" if staff else ""), "level": &"bad"}
	if by.has("supplies") and by["supplies"]["level"] == &"bad":
		return {"text": "Not enough medical supplies. Restock in SUPPLY before you operate.", "level": &"bad"}
	if by.has("accepts"):
		return {"text": "They won't take the unit you'd use. Pick another in the operation plan, or buy the right one.", "level": &"bad"}
	if by.has("neural") and by["neural"]["level"] == &"bad":
		return {"text": "Their nerves are near breaking. It can be done, but it can kill them. Think about refusing.", "level": &"bad"}
	if c.is_emergency:
		return {"text": "Emergency: decide fast. Operate, stabilise, or send them to a specialist.", "level": &"warn"}
	var warn := 0
	for x in cs:
		if x["level"] == &"warn":
			warn += 1
		elif x["level"] == &"bad":
			warn += 2
	if by.has("risk") and by["risk"]["level"] == &"bad":
		return {"text": "High risk: it pays, but it can go wrong. Scan carefully and keep supplies ready.", "level": &"warn"}
	if warn >= 2:
		var watch: Array[String] = []
		for x in cs:
			if x["level"] != &"good":
				watch.append(str(x["label"]).to_lower())
		return {"text": "Doable. Watch the %s." % ", ".join(watch), "level": &"warn"}
	return {"text": "A good job for you. Take it.", "level": &"good"}


static func color(level: StringName) -> Color:
	match level:
		&"good":
			return Palette.OK
		&"warn":
			return Palette.WARN
	return Palette.DANGER


static func mark(level: StringName) -> String:
	match level:
		&"good":
			return "✓"
		&"warn":
			return "!"
	return "✕"


## Builds the card into `parent`. compact: fewer rows (the clinic's door card).
static func build(parent: Control, c: CustomerData, compact: bool = false) -> void:
	var adv := advice(c)
	var a := UIKit.label(adv["text"], &"", true, color(adv["level"]))
	a.name = "VerdictAdvice"
	parent.add_child(a)
	for x in checks(c):
		# Compact (door card): only what needs attention, plus the pay.
		if compact and x["level"] == &"good" and x["key"] != "pay":
			continue
		var row := UIKit.hbox(8)
		row.name = "Verdict_%s" % x["key"]
		var m := UIKit.label(mark(x["level"]), &"MonoLabel", false, color(x["level"]))
		m.custom_minimum_size.x = 22
		row.add_child(m)
		var cap := UIKit.label(str(x["label"]), &"SubHeaderLabel")
		cap.custom_minimum_size.x = 130 if not compact else 104
		row.add_child(cap)
		var v := UIKit.label(str(x["value"]), &"DimLabel" if x["level"] == &"good" else &"", true, null if x["level"] == &"good" else color(x["level"]))
		UIKit.expand(v)
		row.add_child(v)
		if not compact:
			row.add_child(UIKit.info(str(x["term"])))
		parent.add_child(row)
