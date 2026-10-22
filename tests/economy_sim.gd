extends Node
## Economy simulator (3.6). Plays whole business days through the real game
## systems: the patient generator, readiness rules, scoring and rewards,
## PeopleManager.settle (patient budgets, debts, nightly instalments),
## nightly bills (BusinessManager.end_day), staff (hire + real
## GameManager.assign_customer jobs), clinic and facility upgrades and the
## black market, with five player strategies:
##   conservative  only jobs that pay for themselves, no staff, slow upgrades
##   specialist    takes every job incl. high-tier chrome, invests in tools
##   black_market  buys off-the-books chrome once the market opens
##   investment    hires early, buys facility upgrades and better clinics
##   mixed         a bit of everything (a typical player)
## Each strategy runs over several seeds and reports money over time,
## revenue, direct costs, recurring costs, profit, upgrade timing,
## bankruptcy and recovery after a forced loss. The story is played too:
## every event, conversation and COMMS reply that comes up is answered with
## a choice the player could make (seeded, so a run repeats exactly), and
## the money it brings in or costs (cash and debt) is reported as story
## income and story costs.
##   godot --headless --path . res://tests/economy_sim.tscn -- [--days=20] [--seeds=5] [--check]
## --check asserts the 3.6 targets (exit 1 on failure; used by run_tests.sh).

const SIM_SAVE := "user://economy_sim.json"
const STRATEGIES: Array[String] = ["conservative", "specialist", "black_market", "investment", "mixed"]

var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []
var _check := false


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	var days := 20
	var seeds := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
		elif arg.begins_with("--seeds="):
			seeds = int(arg.trim_prefix("--seeds="))
		elif arg == "--check":
			_check = true
	SaveManager.save_path = SIM_SAVE
	var summary := {}
	for strat in STRATEGIES:
		var runs: Array[Dictionary] = []
		for s in seeds:
			runs.append(_run(strat, 1000 + s * 17, days))
		summary[strat] = runs
		_print_strategy(strat, runs)
	# A seed replays exactly, story choices included.
	var again := _run(STRATEGIES[0], 1000, days)
	var first: Dictionary = summary[STRATEGIES[0]][0]
	_target(again["final"] == first["final"] and again["tot"] == first["tot"], "a seed replays exactly, story included (%d / %d)" % [again["final"], first["final"]])
	_print_targets(summary, days)
	SaveManager.delete_save()
	get_tree().quit(1 if _check and not _failures.is_empty() else 0)


# --- one run -----------------------------------------------------------------------------

## Repeatable runs: the global generator and every manager's own generator
## are seeded from the run's seed (each manager offset by its name).
var _bm_buys := 0


func _seed_everything(seed_value: int) -> void:
	seed(seed_value)
	CustomerManager.generator.rng.seed = seed_value
	for n in get_tree().root.get_children():
		var r: Variant = n.get("_rng")
		if r is RandomNumberGenerator:
			(r as RandomNumberGenerator).seed = seed_value + absi(hash(String(n.name)))

func _run(strat: String, seed_value: int, days: int) -> Dictionary:
	SaveManager.reset_all()
	StoryManager.unlock_rumor(&"welcome")
	_rng.seed = seed_value
	_seed_everything(seed_value)
	_bm_buys = 0
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	var curve: Array[int] = []
	var tot := {"revenue": 0, "direct": 0, "recurring": 0, "jobs": 0, "staff_jobs": 0, "declined": 0, "fails": 0, "bm_buys": 0,
		"story_in": 0, "story_out": 0, "story_choices": 0}
	var first_upgrade := -1
	var first_clinic := -1
	var bankrupt_days := 0
	var loss_day := days / 2
	var recovered := -1
	var money_before_loss := 0
	var op := 0
	for day in days:
		var cap := BusinessManager.capacity()
		var guard := 0
		# 3.11: the day's schedule decides how many people come (jobs a day +
		# a few spare), story cases included in place of routine patients.
		while BusinessManager.jobs_today < cap and CustomerManager.visits_left() > 0 and guard < cap * 4:
			guard += 1
			var c: CustomerData = null
			if op == 0:
				CustomerManager.count_visit()
				c = CustomerManager.tutorial_customer()
			else:
				c = CustomerManager.next_visit()
			CustomerManager.debug_set_customer(c)
			GameManager.chosen_diagnosis_id = &""
			GameManager.selected_implant_uid = ""
			if InventoryManager.supplies < 3:
				InventoryManager.buy_supply_pack()
			# Staff take a share of the jobs (real hand-off path).
			if StaffManager.count() > 0 and BusinessManager.jobs_today % 2 == 1:
				var done := _staff_job(c, tot)
				if done:
					BusinessManager.record_job()
					continue
			var r := GameManager.get_surgery_readiness()
			if not bool(r["ok"]):
				for label: String in r["missing_tools"]:
					_buy_tool_for(label)
				r = GameManager.get_surgery_readiness()
			if not bool(r["ok"]) or not _accept(strat, c, r):
				tot["declined"] += 1
				CustomerManager.dismiss_current()
				continue
			var res := _operate(strat, c, r, op, tot)
			op += 1
			tot["jobs"] += 1
			if not res.success:
				tot["fails"] += 1
			BusinessManager.record_job()
		# Night: bills (recurring), instalments, salaries.
		var before := EconomyManager.money
		var rep: Dictionary = BusinessManager.end_day()
		tot["recurring"] += maxi(0, before - EconomyManager.money)
		_play_story(tot)  # the morning's news, consequences and messages
		_invest(strat, day)
		if first_upgrade < 0 and _upgrades() > 0:
			first_upgrade = day + 1
		if first_clinic < 0 and ClinicManager.tier > 0:
			first_clinic = day + 1
		if BusinessManager.debt > 200:
			bankrupt_days += 1
		# An ordinary mid-run loss (a raid, a bad deal): can the clinic recover?
		if day == loss_day:
			money_before_loss = EconomyManager.money
			EconomyManager.spend(mini(EconomyManager.money, 400), &"other")
		if day > loss_day and recovered < 0 and EconomyManager.money >= money_before_loss:
			recovered = day - loss_day
		curve.append(EconomyManager.money - BusinessManager.debt)
	tot["bm_buys"] = _bm_buys
	# What the clinics you moved out of would fetch (ClinicManager.sell):
	# money an investing strategy has parked, not lost.
	var resale := 0
	for i in ClinicManager.owned:
		if i != ClinicManager.tier:
			resale += int(ClinicManager.price(i) * ClinicManager.SELL_BACK)
	return {"seed": seed_value, "curve": curve, "tot": tot, "first_upgrade": first_upgrade, "first_clinic": first_clinic,
		"resale": resale,
		"bankrupt_days": bankrupt_days, "recovered": recovered, "final": EconomyManager.money - BusinessManager.debt,
		"debt": BusinessManager.debt, "tier": ClinicManager.tier, "staff": StaffManager.count(), "upgrades": _upgrades(), "heat": roundi(FactionManager.heat)}


func _upgrades() -> int:
	var n := 0
	for cat in ClinicManager.CATEGORIES:
		n += ClinicManager.upgrade_level(cat)
	return n


## Which jobs a strategy takes.
func _accept(strat: String, c: CustomerData, r: Dictionary) -> bool:
	var item := GameManager.get_requested_item()
	if item == null:
		return false
	match strat:
		"conservative":
			return item.install_difficulty <= 3 and _contribution(c, r) >= 0
		"mixed":
			return _contribution(c, r) >= -50
	return true


## The job's expected contribution: what they can pay minus the implant
## and the supplies (the same estimate the game shows the player).
func _contribution(c: CustomerData, r: Dictionary) -> int:
	return int(JobEstimate.for_customer(c, r)["net"])


func _operate(strat: String, c: CustomerData, r: Dictionary, op: int, tot: Dictionary) -> SurgeryResult:
	var surgery := GameManager.get_current_surgery()
	var item := GameManager.get_requested_item()
	var inst: ImplantInstance = r["implant"]
	var quality := 1.0
	var money0 := EconomyManager.money
	# Black-market players buy matching chrome off the books when they can.
	if strat == "black_market" and BlackMarketManager.is_unlocked() and r["implant_source"] == &"buy":
		for i in BlackMarketManager.stock.size():
			var o: ImplantInstance = BlackMarketManager.stock[i]["instance"]
			if o.cyberware_id == item.id and BlackMarketManager.buy(i):
				_bm_buys += 1
				inst = InventoryManager.get_instance(o.uid)
				InventoryManager.remove_instance(o.uid)
				r["implant_source"] = &"stock"
				break
	match r["implant_source"]:
		&"buy":
			InventoryManager.buy_implant(item.id)
			inst = InventoryManager.consume_implant(item.id)
		&"salvaged":
			quality = GameConfig.SALVAGED_IMPLANT_QUALITY
			inst = ImplantInstance.create(item.id, 70.0, &"salvaged")
		_:
			if InventoryManager.get_instance(inst.uid):
				InventoryManager.remove_instance(inst.uid)
	InventoryManager.use_supplies(surgery.supplies)
	tot["direct"] += maxi(0, money0 - EconomyManager.money) + int(round(surgery.supplies * GameManager.supply_unit_cost()))
	var practice := clampf(op / 15.0, 0.0, 1.0)
	var skill := clampf(0.55 + 0.3 * practice + (0.05 if strat == "specialist" else 0.0), 0.0, 1.0)
	var difficulty := item.get_difficulty_factor()
	var ease := Difficulty.assist(op) * (1.0 + 0.05 * SkillManager.get_rank(&"precision"))
	var stage_q := clampf(_rng.randfn(skill * ease / sqrt(difficulty), 0.08), 0.2, 1.0)
	var load := NeuralLoad.projected(c, inst)
	var crash_chance := clampf(0.02 + 0.05 * (difficulty - 1.0) + 0.1 * maxf(0.0, NeuralLoad.band_index(load) - 2) - 0.03 * practice, 0.0, 0.5)
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
	res.elapsed_sec = surgery.target_time_sec * _rng.randf_range(0.6, 1.2) / maxf(0.5, skill)
	res.diagnosis_correct = _rng.randf() < 0.6 + 0.35 * skill
	res.implant_id = item.id
	res.implant_price = item.price
	res.install_difficulty = item.install_difficulty
	res.black_market_implant = inst != null and inst.source == &"black_market"
	res.implant_pay_mult = 1.0
	SurgeryScoring.apply_rewards(res, surgery, c)
	if res.success:
		res.settlement = PeopleManager.settle(c, res.pay)
		res.pay = int(res.settlement["paid"])
	EconomyManager.add_money(res.pay, &"revenue")
	tot["revenue"] += res.pay
	res.levels_gained = ProgressionManager.add_xp(res.xp)
	ReputationManager.change(res.reputation_delta)
	ProgressionManager.record_surgery(res.surgery_id, res.success, res.grade)
	GameManager._apply_faction_and_heat(res, c)
	CustomerManager.record_outcome(c, res)
	PeopleManager.after_visit(c, "success" if res.success else "death", res.pay)
	CustomerManager.dismiss_current()
	EventManager.on_operation_completed()
	_play_story(tot)
	BlackMarketManager.on_operation_completed()  # as GameManager does: restocks the market
	_spend_skills()
	return res


## Answers what the story put in front of the player (events in line,
## queued conversations, COMMS replies) with a seeded pick among the
## choices they could make, and books the money that moved.
func _play_story(tot: Dictionary) -> void:
	var worth := EconomyManager.money - BusinessManager.debt
	for guard in 12:
		if EventManager.has_pending():
			var choices: Array = EventManager.get_event(EventManager.pending_event).get("choices", [])
			var open := range(choices.size()).filter(func(i: int) -> bool: return EventManager.get_choice_block_reason(choices[i]) == "")
			if open.is_empty():
				EventManager.pending_event = EventManager._next_waiting()
			else:
				EventManager.resolve(int(open[_rng.randi() % open.size()]))
				tot["story_choices"] += 1
		elif StoryManager.has_talk() and not DialogueManager.is_active():
			if DialogueManager.start(StoryManager.pop_talk()):
				for step in 40:
					if not DialogueManager.is_active():
						break
					var opts := DialogueManager.options().filter(func(o: Dictionary) -> bool: return str(o["locked"]) == "")
					if opts.is_empty():
						DialogueManager.advance()
					else:
						DialogueManager.choose(int(opts[_rng.randi() % opts.size()]["index"]))
						tot["story_choices"] += 1
				if DialogueManager.is_active():
					DialogueManager.end()
		else:
			break
	for m in CommsManager.inbox:
		var acts: Array = m.get("actions", [])
		if acts.is_empty() or int(m["resolved"]) >= 0:
			continue
		var open := range(acts.size()).filter(func(i: int) -> bool: return CommsManager.block_reason(acts[i]) == "")
		if not open.is_empty() and CommsManager.act(int(m["uid"]), int(open[_rng.randi() % open.size()])):
			tot["story_choices"] += 1
	var moved := EconomyManager.money - BusinessManager.debt - worth
	if moved > 0:
		tot["story_in"] += moved
	else:
		tot["story_out"] += -moved


func _staff_job(c: CustomerData, tot: Dictionary) -> bool:
	var best := Recommend.best_staff(c)
	if best.is_empty():
		return false
	var money0 := EconomyManager.money
	var r := GameManager.assign_customer(StringName(str(best["employee"]["id"])), false)
	if bool(r.get("refused", true)):
		CustomerManager.debug_set_customer(c)
		return false
	tot["staff_jobs"] += 1
	tot["revenue"] += int(r.get("pay", 0))
	tot["direct"] += maxi(0, money0 + int(r.get("pay", 0)) - EconomyManager.money)
	CustomerManager.dismiss_current()
	return true


func _buy_tool_for(label: String) -> void:
	var cat := StringName(label.split(" ")[0].to_lower())
	for t in InventoryManager.get_purchasable_tools(true):
		if t.category == cat and not InventoryManager.owns_tool(t.id) and t.unlock_level <= ProgressionManager.level:
			if InventoryManager.buy_tool(t.id):
				return


func _spend_skills() -> void:
	for i in 6:
		if SkillManager.points <= 0:
			return
		var bought := false
		for id: StringName in [&"precision", &"speed", &"tissue_handling", &"implant_installation", &"emergency_treatment"]:
			if SkillManager.upgrade(id):
				bought = true
				break
		if not bought:
			return


## Nightly investment policy per strategy.
func _invest(strat: String, _day: int) -> void:
	var reserve: int = {"conservative": 900, "specialist": 600, "black_market": 600, "investment": 300, "mixed": 600}.get(strat, 600)
	if BusinessManager.debt > 0:
		BusinessManager.pay_debt()
	# Better clinic.
	var nxt := ClinicManager.tier + 1
	if nxt < ClinicManager.tiers.size() and not ClinicManager.owns(nxt) and ClinicManager.purchase_block_reason(nxt) == "" \
			and EconomyManager.money >= ClinicManager.price(nxt) + reserve:
		if ClinicManager.buy(nxt):
			ClinicManager.move_to(nxt)
	# Staff.
	var wants_staff: int = {"investment": 1, "mixed": 1, "specialist": 0, "conservative": 0, "black_market": 0}.get(strat, 0)
	if StaffManager.count() < wants_staff * maxi(1, ClinicManager.staff_capacity()) and ClinicManager.staff_capacity() > StaffManager.at_clinic(ClinicManager.tier).size() \
			and EconomyManager.money >= 700 + reserve:
		StaffManager.refresh_candidates()
		for i in StaffManager.candidates.size():
			if StaffManager.hire_block_reason(StaffManager.candidates[i]) == "" and StaffManager.hire(i):
				break
	# Black-market players stock cheap off-the-books chrome they can install.
	if strat == "black_market" and BlackMarketManager.is_unlocked():
		var bought := 0
		var i := 0
		while i < BlackMarketManager.stock.size() and bought < 2:
			var o: Dictionary = BlackMarketManager.stock[i]
			var data := (o["instance"] as ImplantInstance).get_data()
			if data and CyberwareManager.is_tier_available(data.tier) and int(o["price"]) <= data.price * 0.8 \
					and EconomyManager.money >= int(o["price"]) + reserve and BlackMarketManager.buy(i):
				bought += 1
				_bm_buys += 1
				continue
			i += 1
	# Facility upgrades (surgery first).
	if strat in ["investment", "mixed", "specialist"]:
		for cat: StringName in [&"surgery", &"diagnostics", &"customer"]:
			var lv := ClinicManager.upgrade_level(cat) + 1
			var d := ClinicManager.upgrade_def(cat, lv)
			if not d.is_empty() and ClinicManager.install_block_reason(cat) == "" and EconomyManager.money >= int(d.get("cost", 0)) + reserve:
				ClinicManager.install(cat)
				break


# --- report ------------------------------------------------------------------------------------

func _print_strategy(strat: String, runs: Array[Dictionary]) -> void:
	print("\n== %s ==" % strat.to_upper())
	print("seed  final  debt  revenue  direct  recurring  profit/day  jobs staff decl fails  1st upgr  1st clinic  bankrupt  recov  tier staff heat  bm  story+ story- picks")
	for r in runs:
		var t: Dictionary = r["tot"]
		var days := (r["curve"] as Array).size()
		var profit := int(t["revenue"]) - int(t["direct"]) - int(t["recurring"]) + int(t["story_in"]) - int(t["story_out"])
		print("%4d %6d %5d %8d %7d %10d %11d %5d %5d %4d %5d %9s %11s %9d %6s %5d %5d %4d %3d %7d %6d %5d" % [r["seed"], r["final"], r["debt"], t["revenue"], t["direct"], t["recurring"],
			profit / maxi(1, days), t["jobs"], t["staff_jobs"], t["declined"], t["fails"], _d(r["first_upgrade"]), _d(r["first_clinic"]), r["bankrupt_days"], _d(r["recovered"]), r["tier"], r["staff"], r["heat"], t["bm_buys"],
			t["story_in"], t["story_out"], t["story_choices"]])
	var mid: Array = []
	for r in runs:
		mid.append(r["curve"])
	var line := "money by day (median): "
	for d in (mid[0] as Array).size():
		var vals: Array[int] = []
		for c: Array in mid:
			vals.append(int(c[d]))
		vals.sort()
		line += "%d " % vals[vals.size() / 2]
	print(line)


func _d(v: int) -> String:
	return "-" if v < 0 else "d%d" % v


## 3.6 targets (see docs/QUALITY_PASS_3.6.md).
func _print_targets(summary: Dictionary, days: int) -> void:
	print("\n== TARGETS ==")
	for strat in STRATEGIES:
		var runs: Array = summary[strat]
		var stable := 0
		var bankrupt := 0
		var upgraded := 0
		var recovered := 0
		for r: Dictionary in runs:
			if int(r["final"]) > 0:
				stable += 1
			if int(r["bankrupt_days"]) >= 3:
				bankrupt += 1
			if int(r["first_upgrade"]) > 0 or int(r["first_clinic"]) > 0:
				upgraded += 1
			if int(r["recovered"]) >= 0:
				recovered += 1
		var n := runs.size()
		_target(stable * 10 >= n * 8, "%s: ends ahead after %d days in at least 80%% of runs (%d/%d)" % [strat, days, stable, n])
		_target(bankrupt == 0, "%s: no run spends 3+ nights deep in debt (%d)" % [strat, bankrupt])
		_target(upgraded * 10 >= n * 8, "%s: affords a first upgrade or clinic in at least 80%% of runs (%d/%d)" % [strat, upgraded, n])
		_target(recovered * 10 >= n * 6, "%s: recovers from a 400 cr loss in at least 60%% of runs (%d/%d)" % [strat, recovered, n])
		# The story is played and stays a side income or cost, not the business.
		for r: Dictionary in runs:
			var t: Dictionary = r["tot"]
			_target(int(t["story_choices"]) > 0, "%s seed %d: the story comes up and is answered (%d choices)" % [strat, r["seed"], t["story_choices"]])
			_target(int(t["story_in"]) * 4 <= int(t["revenue"]) and int(t["story_out"]) * 4 <= int(t["revenue"]),
				"%s seed %d: story money in (%d) and out (%d) each stay under a quarter of job revenue (%d)" % [strat, r["seed"], t["story_in"], t["story_out"], t["revenue"]])
		# Calibration bounds (3.6): viable, not trivial, long-term goals kept.
		var finals: Array[int] = []
		var tiers: Array[int] = []
		for r: Dictionary in runs:
			finals.append(int(r["final"]))
			tiers.append(int(r["tier"]))
		finals.sort()
		tiers.sort()
		var med := finals[n / 2]
		# Cash plus the resale value of clinics moved out of: a strategy that
		# just bought its next clinic hasn't gone broke (3.10).
		var worths: Array[int] = []
		for r: Dictionary in runs:
			worths.append(int(r["final"]) + int(r.get("resale", 0)))
		worths.sort()
		_target(worths[n / 2] >= 1000, "%s: median money (+ resale of clinics moved out of) after %d days is at least 1000 cr (%d)" % [strat, days, worths[n / 2]])
		_target(med <= 40000, "%s: median money stays under 40000 cr: money keeps its meaning (%d)" % [strat, med])
		_target(tiers[n / 2] < ClinicManager.tiers.size() - 1, "%s: the best clinic is still a goal after %d days (median tier %d)" % [strat, days, tiers[n / 2]])
	if _failures.is_empty():
		print("ECONOMY OK")
	else:
		print("ECONOMY ISSUES:")
		for f in _failures:
			print("  - " + f)


func _target(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  MISS ") + msg)
	if not ok:
		_failures.append(msg)
