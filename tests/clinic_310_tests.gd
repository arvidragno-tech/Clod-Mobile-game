extends RefCounted
## 3.10 tests: what a scan finding means (from the condition's own
## modifiers, nothing invented, nothing hidden revealed, no gameplay value
## changed), job pay (difficulty-scaled service, estimate = payout rule,
## wealth-shaped requests) and selling from storage (values, protected
## items, quantities, the cash balance, no double sale, no buy/sell loop,
## saves). Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	GameManager.is_running = true
	SaveManager.reset_all()
	_condition_explanations()
	_scan_reveal_changes_no_values()
	_findings_belong_to_their_patient()
	_job_pay()
	_requests_follow_means()
	_sell_values()
	_sell_tools_and_supplies()
	_sell_implants()
	_sell_protects_the_planned_job()
	_sell_no_loops_and_saves()
	SaveManager.reset_all()
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


static func _all_text(r: Dictionary) -> String:
	var out := ""
	for k in ["patient", "request", "history", "risks"]:
		for e: Dictionary in r.get(k, []):
			out += " | %s %s %s %s" % [e["label"], e["value"], e["why"], e["affects"]]
	return out.to_lower()


func _patient() -> CustomerData:
	var c := CustomerManager.generator.generate({"archetype": "civilian", "full_difficulty": true})
	CustomerManager.debug_set_customer(c)
	GameManager.chosen_diagnosis_id = &""
	GameManager.selected_implant_uid = ""
	return c


# --- Scanning ---------------------------------------------------------------------

func _condition_explanations() -> void:
	var all_have_effects := true
	var no_title_case := true
	for cid: StringName in CustomerManager.conditions:
		var fx := IntakeRecord.condition_effects(cid)
		var mods: Dictionary = CustomerManager.get_condition(cid).get("modifiers", {})
		all_have_effects = all_have_effects and not (fx["effects"] as Array).is_empty() and str(fx["text"]) != ""
		# Every effect named comes from one of the condition's own modifiers.
		for k: String in mods:
			if IntakeRecord.MODIFIER_EFFECTS.has(k):
				all_have_effects = all_have_effects and (fx["affects"] as Array).has(str(IntakeRecord.MODIFIER_EFFECTS[k][1]))
		no_title_case = no_title_case and not str(fx["text"]).contains("Faster During")
	check(all_have_effects, "every condition in the data explains a real effect, named after its own modifiers")
	check(no_title_case, "explanations are sentences, not Title Case")
	var clot := IntakeRecord.condition_effects(&"clotting_disorder")
	check(str(clot["text"]).to_lower().contains("bleeds faster") and str(clot["text"]).contains("COAG"), "clotting disorder: bleeds faster, keep COAG ready (%s)" % clot["text"])
	check(not bool(clot["counted"]) and not str(clot["text"]).contains("odds"), "... and it doesn't claim to change the odds estimate (it doesn't)")
	var rej := IntakeRecord.condition_effects(&"rejection_prone")
	check(str(rej["text"]).contains("REJECTION SPASM") and str(rej["text"]).contains("SEDATE"), "rejection-prone: names the complication only it can cause and its counter")
	check(bool(rej["counted"]) and str(rej["text"]).contains("odds"), "... and that the odds estimate now counts it (Recommend does)")
	var fake := IntakeRecord.condition_effects(&"counterfeit_implant")
	check(str(fake["text"]).contains("12% neural load") and bool(fake["counted"]), "counterfeit implant: its real neural load, counted in the odds")
	var sed := IntakeRecord.condition_effects(&"sedative_resistance")
	check(str(sed["text"]).to_lower().contains("more sedation") and str(sed["text"]).contains("infusion"), "sedative resistance: more sedation, hold the infusion longer")
	var stim := IntakeRecord.condition_effects(&"stim_addiction")
	check(str(stim["text"]).to_lower().contains("tolerates pain") and str(stim["text"]).contains("STABIL"), "stim addiction: both of its effects")
	var inf := IntakeRecord.condition_effects(&"old_infection")
	check(str(inf["text"]).contains("after the operation"), "old infection: post-op trouble")


func _scan_reveal_changes_no_values() -> void:
	EventManager.operations = 10  # past the learning curve: second complications exist
	var c := _patient()
	c.hidden_conditions.clear()
	c.revealed_conditions.clear()
	c.hidden_conditions.append(&"rejection_prone")
	c.apply_condition(CustomerManager.get_condition(&"rejection_prone"))
	var before := [c.bleed_multiplier, c.neural_sensitivity, c.pain_tolerance, c.complication_risk, c.health_drain_multiplier,
		c.neural_stability, c.post_op_risk, NeuralLoad.compute(c), c.get_risk_level()]
	var odds_before := Recommend.complication_odds(c)
	var r := IntakeRecord.build(c)
	check(not _all_text(r).contains("rejection"), "an unrevealed condition is never named")
	c.revealed_conditions.append(&"rejection_prone")
	var after := [c.bleed_multiplier, c.neural_sensitivity, c.pain_tolerance, c.complication_risk, c.health_drain_multiplier,
		c.neural_stability, c.post_op_risk, NeuralLoad.compute(c), c.get_risk_level()]
	check(before == after, "finding a condition changes none of the values the operation uses")
	check(Recommend.complication_odds(c) > odds_before, "the odds estimate counts it once found (as it always did)")
	r = IntakeRecord.build(c)
	var risks: Array = (r["risks"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "cond_rejection_prone")
	check(risks.size() == 1 and str(risks[0]["why"]) == str(IntakeRecord.condition_effects(&"rejection_prone")["text"]), "the patient's risks show the same explanation as the scan, once")
	var overall: Array = (r["risks"] as Array).filter(func(e: Dictionary) -> bool: return str(e["key"]) == "overall")
	check(overall.is_empty() or not str(overall[0]["why"]).contains("isn't identified"), "OVERALL RISK no longer says the cause is unidentified once the scan found one")
	CustomerManager.dismiss_current()
	EventManager.operations = 0


func _findings_belong_to_their_patient() -> void:
	var a := _patient()
	var b := CustomerManager.generator.generate({"archetype": "civilian", "full_difficulty": true})
	a.hidden_conditions.clear()
	a.revealed_conditions.clear()
	b.hidden_conditions.clear()
	b.revealed_conditions.clear()
	a.hidden_conditions.append(&"clotting_disorder")
	b.hidden_conditions.append(&"clotting_disorder")
	# Force a reveal on A only (the roll's chance is raised for the test).
	var found: Array[StringName] = []
	for i in 40:
		found = CustomerManager.try_reveal_conditions(a, &"chest")
		if not found.is_empty():
			break
	check(a.revealed_conditions.has(&"clotting_disorder") and b.revealed_conditions.is_empty(), "a finding is recorded on the scanned patient only")
	var again := CustomerManager.try_reveal_conditions(a, &"chest")
	check(again.is_empty() and a.revealed_conditions.count(&"clotting_disorder") == 1, "scanning again doesn't find it twice")
	var saved := CustomerData.from_save_dict(a.to_save_dict())
	check(saved.revealed_conditions.has(&"clotting_disorder"), "the finding survives a save")
	CustomerManager.dismiss_current()


# --- Economy ----------------------------------------------------------------------

func _job_pay() -> void:
	SaveManager.reset_all()
	var easy := SurgeryScoring.service_pay(200.0, 1.0, 1, 0.6)
	var hard := SurgeryScoring.service_pay(200.0, 1.0, 5, 0.6)
	check(is_equal_approx(easy, 220.0) and is_equal_approx(hard, 220.0 * (1.0 + 4.0 * GameConfig.DIFFICULTY_PAY_STEP)), "the service fee grows with install difficulty (%d -> %d)" % [roundi(easy), roundi(hard)])
	check(is_equal_approx(SurgeryScoring.part_pay(1000.0, 0.5), 1000.0 * GameConfig.IMPLANT_PRICE_MARKUP * 0.5), "the part is paid at the patient's means")
	for i in 20:
		var c := CustomerManager.generator.generate({"full_difficulty": true})
		var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
		var s := SurgeryManager.get_surgery(c.requested_surgery_id)
		if item == null or s == null:
			continue
		var mult := c.pay_multiplier * ModifierManager.mult(&"pay")
		var expect := int(round(SurgeryScoring.service_pay(s.base_pay, mult, item.install_difficulty, 0.6) + SurgeryScoring.part_pay(item.price, mult)))
		if CustomerGenerator.estimate_fee(c) != expect:
			check(false, "the fee estimate is the payout rule at an average score (%d != %d)" % [CustomerGenerator.estimate_fee(c), expect])
			return
	check(true, "the fee estimate is the payout rule at an average score")
	# The estimate bills the part at its list price, like the payout does,
	# whatever today's shop prices are.
	var c2 := CustomerManager.generator.generate({"full_difficulty": true})
	var item2 := CyberwareManager.get_cyberware(c2.requested_cyberware_id)
	var part0 := CustomerGenerator.estimate_part(c2)
	var shop0 := InventoryManager.implant_price(item2)
	EventManager.temp_modifiers.append({"key": "price.buy", "value": 0.35, "ops": 5, "source": "test"})
	ModifierManager.invalidate()
	var part1 := CustomerGenerator.estimate_part(c2)
	check(InventoryManager.implant_price(item2) > shop0, "(test setup: shop prices went up)")
	EventManager.temp_modifiers.clear()
	ModifierManager.invalidate()
	check(is_equal_approx(part0, part1), "the estimated part follows the list price, not shop price swings (as the payout does)")


func _requests_follow_means() -> void:
	SaveManager.reset_all()
	ProgressionManager.level = 8
	ClinicManager.owned = [0, 5] as Array[int]
	ClinicManager.tier = 5
	ReputationManager.reputation = 80
	for tool in InventoryManager.get_purchasable_tools(false):
		InventoryManager.owned_tools.append(tool.id)
	var poor := 0
	var poor_high := 0
	var rich := 0
	var rich_high := 0
	for i in 600:
		var c := CustomerManager.generator.generate()
		var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
		if item == null:
			continue
		if c.wealth == 0:
			poor += 1
			poor_high += 1 if item.tier >= 3 else 0
		elif c.wealth >= 2:
			rich += 1
			rich_high += 1 if item.tier >= 3 else 0
	var ps := poor_high / maxf(1.0, poor)
	var rs := rich_high / maxf(1.0, rich)
	check(poor > 20 and ps < rs, "poorer patients ask for top-tier chrome less often than richer ones (%d%% vs %d%%)" % [roundi(ps * 100.0), roundi(rs * 100.0)])
	check(poor_high > 0, "... but some still reach above their means (%d of %d)" % [poor_high, poor])
	SaveManager.reset_all()


# --- Selling from storage -----------------------------------------------------------

func _sell_values() -> void:
	SaveManager.reset_all()
	var starter: ToolData = null
	var bought: ToolData = null
	for t2: ToolData in InventoryManager.tool_catalog.values():
		if t2.starter and starter == null:
			starter = t2
		if not t2.starter and t2.price > 0 and t2.unlock_level <= 1 and bought == null:
			bought = t2
	check(starter != null and InventoryManager.sell_value(&"tool", String(starter.id)) == 0, "basic kit has no resale value")
	check(starter != null and InventoryManager.sell_block_reason(&"tool", String(starter.id)) != "", "... and can't be sold")
	if bought:
		InventoryManager.owned_tools.append(bought.id)
		var v := InventoryManager.sell_value(&"tool", String(bought.id))
		check(v == int(round(bought.price * InventoryManager.resale_ratio())), "a bought tool resells at the market's resale share of its price (%d of %d)" % [v, bought.price])
		InventoryManager.tool_condition[bought.id] = 50.0
		check(InventoryManager.sell_value(&"tool", String(bought.id)) == int(round(bought.price * InventoryManager.resale_ratio() * 0.5)), "... less when it's worn")
	check(InventoryManager.sell_value(&"supplies", "supplies") > 0 and InventoryManager.sell_value(&"supplies", "supplies") < GameManager.supply_unit_cost(), "a unit of supplies resells for less than it costs")
	check(InventoryManager.sell_block_reason(&"parts", "parts") != "" and InventoryManager.sell_block_reason(&"tokens", "tokens") != "", "parts and tokens aren't sold from storage")


func _sell_tools_and_supplies() -> void:
	SaveManager.reset_all()
	var tool: ToolData = null
	for t2: ToolData in InventoryManager.tool_catalog.values():
		if not t2.starter and t2.price > 0:
			tool = t2
			break
	InventoryManager.owned_tools.append(tool.id)
	var money0 := EconomyManager.money
	var ledger0 := int(BusinessManager.today.get(&"tools", 0))
	var v := InventoryManager.sell_value(&"tool", String(tool.id))
	var got := InventoryManager.sell(&"tool", String(tool.id))
	check(got == v and EconomyManager.money == money0 + v, "selling a tool adds its resale value to your cash (+%d)" % v)
	check(not InventoryManager.owns_tool(tool.id), "... and it leaves storage")
	check(int(BusinessManager.today.get(&"tools", 0)) == ledger0 + v, "... and the ledger books it against tool spending")
	check(InventoryManager.sell(&"tool", String(tool.id)) == 0 and EconomyManager.money == money0 + v, "selling it again does nothing (no double sale)")
	# Supplies: a quantity.
	InventoryManager.supplies = 10
	money0 = EconomyManager.money
	var each := InventoryManager.sell_value(&"supplies", "supplies")
	check(InventoryManager.sell_block_reason(&"supplies", "supplies", 0) != "", "zero units can't be sold")
	check(InventoryManager.sell_block_reason(&"supplies", "supplies", 11) != "", "you can't sell more than you have")
	got = InventoryManager.sell(&"supplies", "supplies", 3)
	check(got == each * 3 and InventoryManager.supplies == 7 and EconomyManager.money == money0 + each * 3, "selling 3 supplies: -3 units, +%d cr" % (each * 3))
	check(InventoryManager.sell(&"supplies", "supplies", 8) == 0 and InventoryManager.supplies == 7, "a failed sale changes nothing")


func _sell_implants() -> void:
	SaveManager.reset_all()
	InventoryManager.instances.clear()
	var item: CyberwareData = null
	for d: CyberwareData in CyberwareManager.catalog.values():
		if not d.black_market and d.tier == 2:
			item = d
			break
	var inst := ImplantInstance.create(item.id)
	InventoryManager.add_instance(inst)
	var v := InventoryManager.sell_value(&"implant", inst.uid)
	check(v > 0 and v <= BlackMarketManager.sell_value(inst) and v < InventoryManager.implant_price(item), "an implant resells for the market's resale value, under what it costs (%d < %d)" % [v, InventoryManager.implant_price(item)])
	var money0 := EconomyManager.money
	check(InventoryManager.sell(&"implant", inst.uid) == v and InventoryManager.get_instance(inst.uid) == null and EconomyManager.money == money0 + v, "selling it removes the unit and pays %d" % v)
	var mystery := ImplantInstance.create(item.id)
	mystery.identified = false
	InventoryManager.add_instance(mystery)
	check(InventoryManager.sell_block_reason(&"implant", mystery.uid) != "" and InventoryManager.sell(&"implant", mystery.uid) == 0, "an unidentified device isn't sold from storage (it has its own routes)")


func _sell_protects_the_planned_job() -> void:
	SaveManager.reset_all()
	var c := _patient()
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var surgery := GameManager.get_current_surgery()
	InventoryManager.add_implant(item.id)
	InventoryManager.supplies = surgery.supplies + 2
	# Not planned yet: nothing is held back.
	check(str(InventoryManager.reserved_for_job()["implant"]) == "", "nothing is held back before you plan the operation")
	GameManager.chosen_diagnosis_id = c.true_diagnosis_id
	var unit := GameManager.get_selected_implant()
	check(unit != null and InventoryManager.sell_block_reason(&"implant", unit.uid) != "", "the unit for the operation you're planning can't be sold")
	check(InventoryManager.spare_supplies() == 2 and InventoryManager.sell_block_reason(&"supplies", "supplies", 3) != "", "the supplies it needs are set aside")
	check(InventoryManager.sell_block_reason(&"supplies", "supplies", 2) == "", "... the rest can go")
	var cat: StringName = surgery.get_required_tool_categories()[0]
	var best := InventoryManager.get_best_tool(cat)
	check(best != null and InventoryManager.sell_block_reason(&"tool", String(best.id)) != "", "the instrument it needs can't be sold")
	GameManager.chosen_diagnosis_id = &""
	CustomerManager.dismiss_current()


func _sell_no_loops_and_saves() -> void:
	SaveManager.reset_all()
	var loop := false
	for t2: ToolData in InventoryManager.tool_catalog.values():
		if t2.price > 0:
			InventoryManager.owned_tools.append(t2.id)
			loop = loop or InventoryManager.sell_value(&"tool", String(t2.id)) >= InventoryManager.tool_price(t2)
	for d: CyberwareData in CyberwareManager.catalog.values():
		var inst := ImplantInstance.create(d.id)
		InventoryManager.add_instance(inst)
		loop = loop or (not d.black_market and InventoryManager.sell_value(&"implant", inst.uid) >= InventoryManager.implant_price(d))
	loop = loop or InventoryManager.sell_value(&"supplies", "supplies") * GameConfig.SUPPLY_PACK_SIZE >= GameConfig.SUPPLY_PACK_PRICE
	check(not loop, "nothing resells for what it costs to buy (no money loop)")
	# Sold stays sold across a save.
	SaveManager.reset_all()
	var tool: ToolData = null
	for t2: ToolData in InventoryManager.tool_catalog.values():
		if not t2.starter and t2.price > 0:
			tool = t2
			break
	InventoryManager.owned_tools.append(tool.id)
	InventoryManager.sell(&"tool", String(tool.id))
	InventoryManager.supplies = 6
	InventoryManager.sell(&"supplies", "supplies", 2)
	var data := InventoryManager.get_save_data()
	InventoryManager.load_save_data(data)
	check(not InventoryManager.owns_tool(tool.id) and InventoryManager.supplies == 4, "a sale survives save and load")
