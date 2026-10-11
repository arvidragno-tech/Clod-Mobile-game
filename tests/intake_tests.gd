extends RefCounted
## Patient intake form tests: real data only, the existing visibility
## boundary (unrevealed conditions and pre-generated scan findings never
## shown, doctor-visible neural load), honest statuses, and that building
## the form changes nothing (presentation only). Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	GameManager.is_running = true
	SaveManager.reset_all()
	_real_data()
	_hidden_stays_hidden()
	_revealed_is_confirmed()
	_statuses()
	_presentation_only()
	_special_cases()
	SaveManager.reset_all()
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _patient(ctx: Dictionary = {"archetype": "civilian", "full_difficulty": true}) -> CustomerData:
	var c := CustomerManager.generator.generate(ctx)
	CustomerManager.debug_set_customer(c)
	GameManager.chosen_diagnosis_id = &""
	return c


## Every value the record shows, as one string (for "is it in there?").
static func _all_text(r: Dictionary) -> String:
	var s := ""
	for k in ["patient", "request", "history", "risks"]:
		for e: Dictionary in r.get(k, []):
			s += " | %s %s %s %s" % [e["label"], e["value"], e["why"], e["affects"]]
	return s.to_lower()


func _real_data() -> void:
	var c := _patient()
	var r := IntakeRecord.build(c)
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var txt := _all_text(r)
	check(txt.contains(item.display_name.to_lower()), "the form names the requested implant")
	check(txt.contains(SurgeryManager.get_surgery(c.requested_surgery_id).display_name.to_lower()), "... and the procedure")
	check(txt.contains(c.occupation.to_lower()) and txt.contains(str(c.age)), "... and who they are")
	for h in c.medical_history:
		check(txt.contains(h.to_lower()), "the patient's own history is on the form (%s)" % h)
	for id in c.existing_cyberware:
		check(txt.contains(CyberwareManager.get_cyberware(id).display_name.to_lower()), "installed chrome is on file (%s)" % id)
	CustomerManager.dismiss_current()


func _hidden_stays_hidden() -> void:
	var c := _patient()
	# A hidden condition the scan hasn't found: never named, never counted.
	c.hidden_conditions.clear()
	c.revealed_conditions.clear()
	c.hidden_conditions.append(&"counterfeit_implant")
	c.apply_condition(CustomerManager.get_condition(&"counterfeit_implant"))
	var r := IntakeRecord.build(c)
	var txt := _all_text(r)
	check(not txt.contains("counterfeit"), "an unrevealed condition isn't named on the form")
	check(not txt.contains("1 hidden") and not txt.contains("hidden condition:"), "... nor counted")
	var hidden: Array = (r["history"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "hidden")
	check(not hidden.is_empty() and str(hidden[0]["status"]) == IntakeRecord.UNKNOWN, "hidden conditions read UNKNOWN until the scan")
	# Neural load: the doctor-visible figure (the fake chrome's +12 isn't seen).
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var vis := NeuralLoad.projected_visible(c, ImplantInstance.create(item.id))
	var real := NeuralLoad.projected(c, ImplantInstance.create(item.id))
	check(real > vis, "(the hidden condition adds load the doctor can't see: %d vs %d)" % [roundi(real), roundi(vis)])
	var neural: Array = (r["risks"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "neural")
	check(neural.is_empty() or str(neural[0]["value"]).contains("%d%%" % roundi(vis)), "the form's neural load is the visible figure")
	# Pre-generated scan findings (which hint at the diagnosis) aren't shown.
	var leaked := false
	for region: String in c.scan_findings:
		var f := str(c.scan_findings[region]).to_lower()
		if f.length() > 12 and txt.contains(f):
			leaked = true
	check(not leaked, "scan findings stay on the scan table")
	var dx: Array = (r["history"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "diagnosis")
	check(not dx.is_empty() and str(dx[0]["status"]) == IntakeRecord.UNKNOWN and not txt.contains(String(c.true_diagnosis_id).replace("_", " ")), "the diagnosis is UNKNOWN before the scan, never named")
	# The odds' "based on" text no longer depends on whether they really hide one.
	var with_hidden: Array = Recommend.self_estimate(c)["factors"]
	c.hidden_conditions.clear()
	var without: Array = Recommend.self_estimate(c)["factors"]
	check(with_hidden == without, "the odds' explanation doesn't reveal whether a condition is hiding")
	c.hidden_conditions.append(&"rejection_prone")
	c.apply_condition(CustomerManager.get_condition(&"rejection_prone"))
	var odds_hidden := Recommend.complication_odds(c)
	c.complication_risk -= 0.3
	c.hidden_conditions.erase(&"rejection_prone")
	check(is_equal_approx(odds_hidden, Recommend.complication_odds(c)), "the complication estimate doesn't move for an unrevealed condition")
	CustomerManager.dismiss_current()


func _revealed_is_confirmed() -> void:
	var c := _patient()
	c.hidden_conditions.clear()
	c.revealed_conditions.clear()
	for cid: StringName in [&"clotting_disorder", &"sedative_resistance"]:
		c.hidden_conditions.append(cid)
		c.revealed_conditions.append(cid)
	var r := IntakeRecord.build(c)
	var risks: Array = r["risks"]
	var clot: Array = risks.filter(func(e: Dictionary) -> bool: return str(e["key"]) == "cond_clotting_disorder")
	check(not clot.is_empty() and str(clot[0]["status"]) == IntakeRecord.CONFIRMED, "a condition the scan found is CONFIRMED in the risk factors")
	check(not clot.is_empty() and str(clot[0]["why"]).to_lower().contains("bleeds faster") and str(clot[0]["affects"]).contains("bleeding"), "... with what it does (from its own modifiers)")
	var sed: Array = risks.filter(func(e: Dictionary) -> bool: return str(e["key"]) == "cond_sedative_resistance")
	check(not sed.is_empty() and str(sed[0]["why"]).to_lower().contains("more sedation"), "sedative resistance: needs more sedation")
	var findings: Array = (r["history"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "condition")
	check(findings.size() == 2, "found conditions are listed as findings in the history")
	CustomerManager.dismiss_current()


func _statuses() -> void:
	var c := _patient()
	var r := IntakeRecord.build(c)
	var ok := true
	var levels_ok := true
	for k in ["patient", "request", "history", "risks"]:
		for e: Dictionary in r[k]:
			ok = ok and str(e["status"]) in [IntakeRecord.REPORTED, IntakeRecord.ON_FILE, IntakeRecord.CONFIRMED, IntakeRecord.SUSPECTED, IntakeRecord.UNKNOWN]
			levels_ok = levels_ok and e["level"] in [IntakeRecord.NONE, IntakeRecord.CAUTION, IntakeRecord.SIGNIFICANT, IntakeRecord.CRITICAL]
	check(ok, "every line says where it comes from (one of five statuses)")
	check(levels_ok, "emphasis uses the four levels only")
	var hist: Array = (r["history"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "history")
	check(hist.all(func(e: Dictionary) -> bool: return str(e["status"]) == IntakeRecord.REPORTED and e["level"] == IntakeRecord.NONE),
		"the patient's own history is REPORTED and not flagged (nothing in the rules depends on it)")
	var risks: Array = r["risks"]
	check(risks.all(func(e: Dictionary) -> bool: return e["level"] != IntakeRecord.NONE), "every risk factor carries an emphasis level")
	check(risks.all(func(e: Dictionary) -> bool: return str(e["status"]) != IntakeRecord.REPORTED), "risk factors are examined or on file, never just the patient's word")
	CustomerManager.dismiss_current()


func _presentation_only() -> void:
	var c := _patient()
	c.hidden_conditions.append(&"old_infection")
	var before := JSON.stringify(c.to_save_dict())
	var rng_before := CustomerManager.generator.rng.state
	var odds_before := float(Recommend.self_estimate(c)["chance"])
	var fee_before := CustomerGenerator.estimate_fee(c)
	var comp_before := Recommend.complication_odds(c)
	var money := EconomyManager.money
	for i in 3:
		IntakeRecord.build(c)
		PatientBrief.build(c)
	check(JSON.stringify(c.to_save_dict()) == before, "building the form doesn't change the patient")
	check(CustomerManager.generator.rng.state == rng_before, "... rolls nothing")
	check(is_equal_approx(float(Recommend.self_estimate(c)["chance"]), odds_before) and CustomerGenerator.estimate_fee(c) == fee_before
		and is_equal_approx(Recommend.complication_odds(c), comp_before) and EconomyManager.money == money, "... and changes no odds, fee or money")
	check(not c.revealed_conditions.has(&"old_infection"), "... and reveals nothing")
	CustomerManager.dismiss_current()


func _special_cases() -> void:
	var c := _patient()
	c.is_emergency = true
	var r := IntakeRecord.build(c)
	check((r["risks"] as Array).any(func(e: Dictionary) -> bool: return str(e["key"]) == "emergency" and e["level"] == IntakeRecord.CRITICAL), "an emergency is a CRITICAL risk factor")
	c.is_emergency = false
	c.age = 16
	r = IntakeRecord.build(c)
	var age: Array = (r["patient"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "occupation")
	check(not age.is_empty() and age[0]["level"] == IntakeRecord.CAUTION and str(age[0]["why"]).contains("minors"), "a minor is flagged with its real consequence (staff refuse)")
	c.neural_stability = 50.0
	r = IntakeRecord.build(c)
	check((r["risks"] as Array).any(func(e: Dictionary) -> bool: return str(e["key"]) == "stability"), "low measured neural stability is a risk factor")
	CustomerManager.dismiss_current()
