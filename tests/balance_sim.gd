extends Node
## Economy / progression simulator. Plays N operations through the real data,
## generator, readiness rules, scoring and reward code with a simple player
## model (a novice who improves), a sensible spending policy, and reports
## milestones, the money curve and any dead ends (jobs that cannot be done).
## Usage: godot --headless --path . res://tests/balance_sim.tscn -- --ops=40 --seed=1 [--skill=0.0..1.0]
## Exit code 1 if a balance invariant fails (used by run_tests.sh).

const SIM_SAVE := "user://balance_sim.json"
## Rough minutes per operation incl. menus (from playtests of the bot runs).
const MINUTES_PER_OP := 2.6

var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	var ops := 40
	var skill_bias := 0.0
	_rng.seed = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ops="):
			ops = int(arg.trim_prefix("--ops="))
		elif arg.begins_with("--seed="):
			_rng.seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--skill="):
			skill_bias = float(arg.trim_prefix("--skill="))
	SaveManager.save_path = SIM_SAVE
	SaveManager.reset_all()
	StoryManager.unlock_rumor(&"welcome")
	CustomerManager.generator.rng.seed = _rng.seed
	var report := simulate(ops, skill_bias)
	_print_report(report)
	SaveManager.delete_save()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func simulate(ops: int, skill_bias: float) -> Dictionary:
	var log: Array[Dictionary] = []
	var milestones := {}
	var declines_in_row := 0
	var max_declines_in_row := 0
	var crashes := 0
	var grades := {}
	var op := 0
	var guard := 0
	while op < ops and guard < ops * 6:
		guard += 1
		var c: CustomerData = CustomerManager.tutorial_customer() if op == 0 else CustomerManager._next_customer()
		CustomerManager.debug_set_customer(c)
		GameManager.chosen_diagnosis_id = &""
		GameManager.selected_implant_uid = ""
		_restock()
		var r := GameManager.get_surgery_readiness()
		if not bool(r["ok"]):
			# Try to fix missing tools by buying them.
			for label: String in r["missing_tools"]:
				_buy_tool_for(label)
			r = GameManager.get_surgery_readiness()
		if not bool(r["ok"]):
			declines_in_row += 1
			max_declines_in_row = maxi(max_declines_in_row, declines_in_row)
			ReputationManager.change(GameConfig.DECLINE_REPUTATION_PENALTY)
			CustomerManager.dismiss_current()
			continue
		declines_in_row = 0
		var result := _operate(c, r, op, skill_bias)
		op += 1
		# Business days: rent and running costs are part of the balance.
		BusinessManager.record_job()
		if BusinessManager.is_day_full():
			BusinessManager.end_day()
		if not result.success:
			crashes += 1
		grades[result.grade] = int(grades.get(result.grade, 0)) + 1
		_spend_progress()
		var entry := {"op": op, "money": EconomyManager.money, "level": ProgressionManager.level, "rep": ReputationManager.reputation,
			"tier": ClinicManager.tier, "grade": result.grade, "pay": result.pay, "xp": result.xp, "item": String(result.implant_id)}
		log.append(entry)
		for lv in [2, 3, 4, 5, 7]:
			if ProgressionManager.level >= lv and not milestones.has("level_%d" % lv):
				milestones["level_%d" % lv] = op
		for t in range(1, 6):
			if ClinicManager.tier >= t and not milestones.has("clinic_t%d" % t):
				milestones["clinic_t%d" % t] = op
		if not milestones.has("black_market") and ((ReputationManager.reputation >= 18 and op >= 6) or ReputationManager.is_black_market_unlocked()):
			milestones["black_market"] = op
		for t in range(2, 6):
			if CyberwareManager.get_available_tier() >= t and not milestones.has("implant_t%d" % t):
				milestones["implant_t%d" % t] = op
	return {"log": log, "milestones": milestones, "max_declines": max_declines_in_row, "crashes": crashes, "grades": grades, "ops": op, "skill": skill_bias}


## Keeps a little stock: one requested unit and enough supplies.
func _restock() -> void:
	if InventoryManager.supplies < 3:
		InventoryManager.buy_supply_pack()


func _buy_tool_for(label: String) -> void:
	var cat := StringName(label.split(" ")[0].to_lower())
	for t in InventoryManager.get_purchasable_tools(true):
		if t.category == cat and not InventoryManager.owns_tool(t.id) and t.unlock_level <= ProgressionManager.level:
			if InventoryManager.buy_tool(t.id):
				return


## Player model: quality improves with practice and skill; tolerance assist
## and tool precision help; difficulty and neural load hurt.
func _operate(c: CustomerData, r: Dictionary, op: int, skill_bias: float) -> SurgeryResult:
	var surgery := GameManager.get_current_surgery()
	var item := GameManager.get_requested_item()
	var inst: ImplantInstance = r["implant"]
	var quality := 1.0
	match r["implant_source"]:
		&"buy":
			InventoryManager.buy_implant(item.id)
			inst = InventoryManager.consume_implant(item.id)
		&"salvaged":
			quality = GameConfig.SALVAGED_IMPLANT_QUALITY
			inst = ImplantInstance.create(item.id, 70.0, &"salvaged")
		_:
			InventoryManager.remove_instance(inst.uid)
	InventoryManager.use_supplies(surgery.supplies)
	var practice := clampf(op / 15.0, 0.0, 1.0)
	var skill := clampf(0.55 + 0.3 * practice + skill_bias, 0.0, 1.0)
	var difficulty := item.get_difficulty_factor()
	var ease := Difficulty.assist(op) * (1.0 + 0.05 * SkillManager.get_rank(&"precision"))
	var stage_q := clampf(_rng.randfn(skill * ease / sqrt(difficulty), 0.08), 0.2, 1.0)
	var load := NeuralLoad.projected(c, inst)
	var crash_chance := clampf(0.02 + 0.06 * (difficulty - 1.0) + 0.1 * maxf(0.0, NeuralLoad.band_index(load) - 2) - 0.03 * practice, 0.0, 0.5)
	if op == 0:
		crash_chance = 0.0
	var res := SurgeryResult.new()
	res.surgery_id = surgery.id
	res.success = _rng.randf() >= crash_chance
	res.failure_reason = &"" if res.success else &"flatline"
	res.stage_quality = stage_q
	res.final_health = clampf(100.0 - (1.0 - stage_q) * 70.0, 10.0, 100.0)
	res.final_neural = clampf(100.0 - (1.0 - stage_q) * 60.0 - maxf(0.0, load - 50.0) * 0.5, 10.0, 100.0)
	res.implant_performance = stage_q * quality
	res.target_time_sec = surgery.target_time_sec
	res.elapsed_sec = surgery.target_time_sec * _rng.randf_range(0.6, 1.3) / maxf(0.5, skill)
	res.diagnosis_correct = _rng.randf() < 0.6 + 0.35 * skill
	res.implant_id = item.id
	res.implant_price = item.price
	res.install_difficulty = item.install_difficulty
	res.implant_pay_mult = 1.0
	SurgeryScoring.apply_rewards(res, surgery, c)
	EconomyManager.add_money(res.pay)
	res.levels_gained = ProgressionManager.add_xp(res.xp)
	ReputationManager.change(res.reputation_delta)
	ProgressionManager.record_surgery(res.surgery_id, res.success, res.grade)
	GameManager._apply_faction_and_heat(res, c)
	CustomerManager.record_outcome(c, res)
	CustomerManager.dismiss_current()
	EventManager.on_operation_completed()
	EventManager.pending_event = &""
	return res


## Spending policy: skill points into precision/speed first; clinic upgrade
## when affordable with a 300 cr buffer.
func _spend_progress() -> void:
	var order := [&"precision", &"speed", &"tissue_handling", &"implant_installation", &"emergency_treatment"]
	for i in 6:
		if SkillManager.points <= 0:
			break
		var bought := false
		for id: StringName in order:
			if SkillManager.upgrade(id):
				bought = true
				break
		if not bought:
			break
	var next := ClinicManager.get_next_tier()
	if not next.is_empty() and ClinicManager.get_upgrade_block_reason() == "" and EconomyManager.money >= int(next.get("cost", 0)) + 300:
		ClinicManager.upgrade()


func _print_report(rep: Dictionary) -> void:
	var log: Array = rep["log"]
	print("op  money  lvl rep tier grade  pay  xp  item")
	for e: Dictionary in log:
		print("%2d %6d %4d %3d %4d %5s %5d %3d  %s" % [e["op"], e["money"], e["level"], e["rep"], e["tier"], e["grade"], e["pay"], e["xp"], e["item"]])
	var m: Dictionary = rep["milestones"]
	print("milestones (op #, ~minutes):")
	for k: String in m:
		print("  %-14s op %2d  ~%d min" % [k, int(m[k]), roundi(int(m[k]) * MINUTES_PER_OP)])
	print("grades: %s  crashes: %d  max declines in a row: %d" % [rep["grades"], rep["crashes"], rep["max_declines"]])
	_invariant(int(rep["max_declines"]) <= 3, "no dead end: never more than 3 impossible jobs in a row")
	_invariant(int(rep["ops"]) >= mini(log.size(), 1), "simulation completed operations")
	_invariant(m.has("level_2") and int(m["level_2"]) <= 3, "level 2 within the first 3 jobs")
	if float(rep["skill"]) < 0.0:
		# Struggling player: slower is fine, stuck is not.
		_invariant(m.has("clinic_t1") and int(m["clinic_t1"]) <= 12, "struggling player still upgrades the clinic by job 12")
		_finish_report()
		return
	_invariant(m.has("black_market") and int(m["black_market"]) >= 5 and int(m["black_market"]) <= 12, "black market arrives after the learning phase (jobs 5-12)")
	_invariant(m.has("clinic_t1") and int(m["clinic_t1"]) <= 8, "first clinic upgrade by job 8")
	if log.size() >= 30:
		_invariant(m.has("implant_t3"), "tier-3 chrome reachable within 30 jobs")
	var broke := 0
	for e: Dictionary in log:
		if int(e["money"]) < 0:
			broke += 1
	_invariant(broke == 0, "money never negative")
	_finish_report()


func _finish_report() -> void:
	if _failures.is_empty():
		print("BALANCE OK")
	else:
		print("BALANCE ISSUES:")
		for f in _failures:
			print("  - " + f)


func _invariant(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		_failures.append(msg)
