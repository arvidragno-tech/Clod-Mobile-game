extends RefCounted
## 3.6 quality-pass tests: purchase guards, the economy rules, the job
## estimate, the money breakdown, the standing history (causes, batching,
## bounds, save/load, trends), the standing overview, choice previews,
## clinic doors (close / open, save, morning) and the stage tool rules.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	GameManager.is_running = true
	_debounce()
	_economy()
	_standing_history()
	_standing_overview()
	_doors()
	_guidance_levels()
	_surgery_rules()
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _debounce() -> void:
	var k := "test_%d" % Time.get_ticks_usec()
	check(UIKit.debounce(k), "the first press goes through")
	check(not UIKit.debounce(k), "a second press within the double-click window is ignored")
	check(UIKit.debounce(k + "_other"), "other buttons aren't blocked")


func _economy() -> void:
	SaveManager.reset_all()
	# Fee = service (scaled by the result) + the part (at most ~cost, x means).
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var s := SurgeryManager.get_surgery(c.requested_surgery_id)
	if item and s:
		var res := SurgeryResult.new()
		res.success = true
		res.stage_quality = 1.0
		res.final_health = 100.0
		res.final_neural = 100.0
		res.implant_performance = 1.0
		res.elapsed_sec = 10.0
		res.target_time_sec = 100.0
		res.diagnosis_correct = true
		res.implant_price = item.price
		res.implant_pay_mult = 1.0
		SurgeryScoring.apply_rewards(res, s, c)
		var mult := c.pay_multiplier * ModifierManager.mult(&"pay")
		var part := item.price * GameConfig.IMPLANT_PRICE_MARKUP * minf(mult, 1.0)
		check(res.pay >= int(part), "a clean job pays at least the part share (%d >= %d)" % [res.pay, int(part)])
		check(float(res.pay) <= s.base_pay * mult * 1.5 + item.price + 1.0, "and never more than service x1.5 plus the implant")
	# Job estimate: one source of truth.
	c.budget = 0
	var est := JobEstimate.for_customer(c)
	check(int(est["fee"]) == CustomerGenerator.estimate_fee(c), "the estimate's fee is the generator's estimate")
	check(int(est["net"]) == int(est["can_pay"]) - int(est["implant_cost"]) - int(est["supplies_cost"]), "net = what they can pay - implant - supplies")
	c.budget = 50
	est = JobEstimate.for_customer(c)
	check(int(est["can_pay"]) == mini(50, int(est["fee"])) and int(est["owed"]) == int(est["fee"]) - int(est["can_pay"]), "the estimate respects what the patient can pay today")
	# A shortfall goes on instalments.
	c.budget = 100
	var st := PeopleManager.settle(c, 400)
	var plans := PeopleManager.open_debts().filter(func(d: Dictionary) -> bool: return str(d["status"]) == "plan")
	check(int(st["debt"]) == 300 and plans.size() == 1, "a patient who can't pay goes on an instalment plan")
	# Mothballed clinics: half rent, no running costs.
	SaveManager.reset_all()
	ClinicManager.owned.append(1)
	ClinicManager.owned.sort()
	ClinicManager.tier = 1
	check(BusinessManager.is_mothballed(0) and not BusinessManager.is_mothballed(1), "a clinic you've left with no staff is mothballed")
	var rent_old := 0
	var running_old := false
	for line in BusinessManager.projected_costs():
		if str(line["note"]).begins_with(str(ClinicManager.get_tier_data(0).get("name", ""))):
			if line["category"] == &"rent":
				rent_old = int(line["amount"])
			if line["category"] == &"operating":
				running_old = true
	check(rent_old == int(round(round(int(ClinicManager.daily_costs(0)["rent"]) * BusinessManager.MOTHBALL_RENT) * Difficulty.cost_mult())) and not running_old, "mothballed: half rent and no running costs")
	check(is_equal_approx(BusinessManager.DEBT_INTEREST, 0.04), "debt interest is 4% a day")
	# The outlook explains a loss with its real main cause.
	SaveManager.reset_all()
	BusinessManager.today[&"revenue"] = 200
	BusinessManager.today[&"cyberware"] = -450
	var o := BusinessManager.outlook(3)
	check(str(o["verdict"]) == "Losing money" and int(o["profit"]) == -250 and str(o["cause"]).begins_with("Implants and supplies"), "losing money: the outlook names implants and supplies as the cause")
	BusinessManager.today.clear()
	BusinessManager.today[&"revenue"] = 900
	o = BusinessManager.outlook(3)
	check(str(o["verdict"]) == "Healthy" and str(o["cause"]) == "", "a healthy clinic gets no scary cause")
	SaveManager.reset_all()


func _standing_history() -> void:
	SaveManager.reset_all()
	ChangeLog.reset_state()
	ReputationManager.change(3, "Test: explicit reason")
	var h := ChangeLog.standing_history("rep", 5)
	check(h.size() == 1 and str(h[0]["reason"]) == "Test: explicit reason" and int(round(float(h[0]["delta"]))) == 3, "an explicit reason is recorded with the change")
	ChangeLog.push_cause("Test: an operation")
	FactionManager.change(&"street_gangs", 4)
	FactionManager.add_heat(6.0)
	ChangeLog.pop_cause()
	var f := ChangeLog.standing_history("faction:street_gangs", 5)
	check(f.size() == 1 and str(f[0]["reason"]) == "Test: an operation", "a change without a reason takes the current cause")
	var heat := ChangeLog.standing_history("heat", 5)
	check(heat.size() == 1 and str(heat[0]["reason"]) == "Test: an operation", "one decision, several changes, the same cause")
	FactionManager.change(&"street_gangs", -1)
	f = ChangeLog.standing_history("faction:street_gangs", 5)
	check(str(f[0]["reason"]) == ChangeLog.NO_CAUSE, "no cause is never guessed: it says so")
	# Batching: the same thing, same cause, same hour -> one line.
	ChangeLog.push_cause("Test: batch")
	for i in 5:
		ReputationManager.change_dim(&"civilian", 1)
	ChangeLog.pop_cause()
	var b := ChangeLog.standing_history("dim:civilian", 10)
	check(b.size() == 1 and int(round(float(b[0]["delta"]))) == 5, "minor repeats are batched into one line (+5)")
	check(ChangeLog.standing_trend("dim:civilian", 3) >= 4.9, "the trend sums the last days")
	# Relationships are separate from their group.
	var cast := CharacterManager.state.keys()
	if not cast.is_empty():
		var cid: StringName = cast[0]
		var fac_before := ChangeLog.standing.size()
		CharacterManager.change_relationship(cid, 5, 0, "Test: a kind word")
		var p := ChangeLog.standing_history("person:%s" % cid, 3)
		check(p.size() == 1 and str(p[0]["reason"]) == "Test: a kind word" and ChangeLog.standing.size() == fac_before + 1, "a personal relationship is recorded on its own, not as faction standing")
	# Bounded and saved.
	for i in ChangeLog.MAX_STANDING + 30:
		ReputationManager.change_dim(&"medical", 1 if i % 2 == 0 else -1, "Test %d" % i)
	check(ChangeLog.standing.size() <= ChangeLog.MAX_STANDING, "the history never grows past %d entries" % ChangeLog.MAX_STANDING)
	var saved := ChangeLog.get_save_data()
	var n := ChangeLog.standing.size()
	var last_reason := str(ChangeLog.standing[n - 1]["reason"])
	ChangeLog.reset_state()
	check(ChangeLog.standing.is_empty(), "a reset clears the history")
	ChangeLog.load_save_data(saved)
	check(ChangeLog.standing.size() == n and str(ChangeLog.standing[n - 1]["reason"]) == last_reason, "the history survives save and load")
	ChangeLog.reset_state()
	SaveManager.reset_all()


func _standing_overview() -> void:
	SaveManager.reset_all()
	var rows := Standing.overview()
	check(rows.size() == 5 and str(rows[0]["group"]) == "rep" and str(rows[1]["group"]) == "heat" and str(rows[2]["group"]) == "faction:black_market", "default view: reputation, heat, the black market and the two most relevant factions")
	check(Standing.overview(true).size() == 2 + FactionManager.order.size(), "ALL FACTIONS shows every faction")
	for r: Dictionary in rows:
		check(str(r["next"]) != "" and not (r["affects"] as Array).is_empty() and str(r["category"]) != "", "%s explains category, effects and the next threshold" % r["name"])
	ReputationManager.reputation = 0
	check(Standing.next_rep_threshold().begins_with("At "), "the next reputation threshold comes from the data (%s)" % Standing.next_rep_threshold())
	ReputationManager.reputation = -5
	check(ReputationManager.get_tier_name() == "Distrusted", "a slightly negative reputation reads Distrusted, not Butcher")
	ReputationManager.reputation = -30
	check(ReputationManager.get_tier_name() == "Butcher", "a deeply negative one reads Butcher")
	ReputationManager.reputation = 0
	check(Standing.heat_row()["kind"] == "attention" and Standing.rep_row()["kind"] == "reputation", "attention is kept apart from reputation")
	check(Standing.trend_text(-3.0, false).contains("improving") and Standing.trend_text(3.0, true).contains("improving"), "trend words follow what's good (falling heat improves)")
	# Choice previews: exact when fixed, honest when risky.
	check(Standing.preview({"reputation": 2, "faction": {"street_gangs": -3}, "heat": 5}) == "REP +2, %s -3, heat +5" % FactionManager.get_name_of(&"street_gangs"), "a choice shows its exact standing effects")
	check(Standing.preview({"risk": {"chance": 0.4, "success": {"reputation": 3}, "fail": {"heat": 10}}}).begins_with("Risky (40%)"), "a risky choice says it's a gamble")
	check(Standing.preview({"money": 50}) == "", "no standing effect, no line")
	SaveManager.reset_all()


func _doors() -> void:
	SaveManager.reset_all()
	CustomerManager.dismiss_current()
	BusinessManager.set_doors_open(false)
	check(not BusinessManager.doors_open, "CLOSE DOORS closes them")
	CustomerManager.request_next_customer(0.0)
	check(not CustomerManager.has_customer() and not CustomerManager.is_customer_pending(), "no walk-ins while the doors are closed")
	var saved := BusinessManager.get_save_data()
	BusinessManager.reset_state()
	BusinessManager.load_save_data(saved)
	check(not BusinessManager.doors_open, "closed doors survive save and load")
	check(Guidance.items().any(func(i: Dictionary) -> bool: return str(i["id"]) == "doors"), "WHAT MATTERS NOW says the doors are closed")
	check(Nav.can_open({"doors": "open"}), "and links straight to opening them")
	BusinessManager.end_day()
	check(BusinessManager.doors_open, "the doors open again in the morning")
	BusinessManager.set_doors_open(false)
	BusinessManager.set_doors_open(true)
	check(CustomerManager.has_customer() or CustomerManager.is_customer_pending(), "opening the doors lets the next customer in")
	CustomerManager.dismiss_current()
	SaveManager.reset_all()


func _guidance_levels() -> void:
	SaveManager.reset_all()
	var was := Settings.guidance_level
	BusinessManager.set_doors_open(false)  # adds an INFO line
	InventoryManager.supplies = 0          # adds a CRITICAL line
	Settings.guidance_level = 0
	var minimal := Guidance.for_player()
	check(minimal.size() <= 3 and minimal.all(func(it: Dictionary) -> bool: return it["level"] != Guidance.INFO),
		"MINIMAL guidance shows only critical and important lines")
	check(ClinicStatus.visible_rows().all(func(r: Dictionary) -> bool: return r["level"] != ClinicStatus.GOOD),
		"MINIMAL clinic status hides what is fine")
	check(not Hints.first("heat"), "MINIMAL guidance shows no first-time cards")
	Settings.guidance_level = 1
	check(Guidance.for_player().size() <= 4, "STANDARD guidance keeps the list short")
	check(ClinicStatus.visible_rows().size() == ClinicStatus.rows().size(), "STANDARD shows every status row")
	Settings.guidance_level = 2
	var detailed := Guidance.for_player()
	check(detailed.any(func(it: Dictionary) -> bool: return it["id"] == "doors"), "DETAILED guidance includes information lines")
	Settings.guidance_level = was
	BusinessManager.set_doors_open(true)
	check(Settings.DEFAULTS.has("guidance_level") and Settings.GUIDANCE_NAMES.size() == 3, "the guidance setting exists with three levels")
	for k in ["doors", "standing", "outlook", "the_money", "guidance"]:
		check(Glossary.has(k), "the field guide explains %s" % k)


func _surgery_rules() -> void:
	# A correctly diagnosed clean site skips debridement (a shorter job).
	var s := SurgeryManager.get_surgery(&"install_arm")
	if s:
		var clean := s.for_diagnosis(&"clean_site", true)
		check(clean.stages.size() == s.stages.size() - 1 and not clean.stages.any(func(x: SurgeryStageData) -> bool: return x.type == &"remove_tissue"), "a correct clean-site diagnosis skips debridement")
		check(s.for_diagnosis(&"clean_site", false) == s and s.for_diagnosis(&"tissue_damage", true) == s, "otherwise the procedure is unchanged (and the template never edited)")
	# Categories play differently through their own parameters.
	var eyes := SurgeryManager.get_surgery(&"install_optic")
	var dermal := SurgeryManager.get_surgery(&"install_dermal")
	if eyes and dermal:
		var ae := 0.0
		var ad := 0.0
		for st in eyes.stages:
			if st.type == &"install_implant":
				ae = st.param_float("align_tolerance_deg", 12.0)
		for st in dermal.stages:
			if st.type == &"install_implant":
				ad = st.param_float("align_tolerance_deg", 12.0)
		check(ae < 12.0 and ad > 12.0, "optics need tighter alignment than dermal plates (%.0f vs %.0f deg)" % [ae, ad])
	for sd: SurgeryData in SurgeryManager.surgeries.values():
		for st in (sd as SurgeryData).stages:
			check(not st.instruction.begins_with("Select "), "%s / %s: no 'Select the tool' busywork (the tool is put in your hand)" % [sd.id, st.id])
