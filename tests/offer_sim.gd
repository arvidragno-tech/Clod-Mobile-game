extends Node
## Job-offer simulator: generates many patient offers through the real
## generator (CustomerGenerator.generate) at four points of progression and
## reports how many are worth taking. Per offer, from the game's own numbers:
##   direct margin  the fee the patient owes for the job (JobEstimate: an
##                  average result, the greedy haggle included) minus what
##                  the job uses up (the implant bought for it, supplies);
##                  money a patient can't pay today is still owed on an
##                  instalment plan, so it counts here
##   cash today     what they can pay now minus the same direct costs
##   at risk        the direct margin if 15% of operations fail (no fee,
##                  the implant and supplies are still spent)
## Rent, wages and upkeep are not per job: the economy simulator covers the
## overall picture (economy_sim.gd).
##   godot --headless --path . res://tests/offer_sim.tscn -- [--offers=2000] [--seed=7] [--check]
## --check asserts the 3.10 targets (exit 1 on failure; used by run_tests.sh).

const SIM_SAVE := "user://offer_sim.json"
const FAIL_RATE := 0.15
## {name, ops, level, rep, clinic}
const STAGES := [
	{"name": "early (ops 4, level 1, back alley)", "ops": 4, "level": 1, "rep": 5, "clinic": 0},
	{"name": "street (ops 12, level 3, undercity)", "ops": 12, "level": 3, "rep": 25, "clinic": 1},
	{"name": "established (ops 30, level 5, industrial)", "ops": 30, "level": 5, "rep": 50, "clinic": 2},
	{"name": "late (ops 60, level 8, corporate)", "ops": 60, "level": 8, "rep": 80, "clinic": 5},
]

var _failures: Array[String] = []


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	var offers := 2000
	var seed_value := 7
	var check := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--offers="):
			offers = int(arg.trim_prefix("--offers="))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg == "--check":
			check = true
	SaveManager.save_path = SIM_SAVE
	var results: Array[Dictionary] = []
	for st: Dictionary in STAGES:
		results.append(_run_stage(st, offers, seed_value))
	_print_targets(results)
	SaveManager.delete_save()
	get_tree().quit(1 if check and not _failures.is_empty() else 0)


func _setup(st: Dictionary) -> void:
	SaveManager.reset_all()
	EventManager.operations = int(st["ops"])
	ProgressionManager.level = int(st["level"])
	ReputationManager.reputation = int(st["rep"])
	var t := int(st["clinic"])
	ClinicManager.owned = [0] as Array[int]
	if t > 0:
		ClinicManager.owned.append(t)
	ClinicManager.tier = t
	# The tools a player at this level would own (all they can buy).
	for tool in InventoryManager.get_purchasable_tools(false):
		InventoryManager.owned_tools.append(tool.id)


func _run_stage(st: Dictionary, n: int, seed_value: int) -> Dictionary:
	_setup(st)
	CustomerManager.generator.rng.seed = seed_value
	var all: Array[Dictionary] = []
	for i in n:
		var c := CustomerManager.generator.generate()
		all.append(_measure(c))
	var feasible := all.filter(func(o: Dictionary) -> bool: return bool(o["feasible"]))
	var r := {"name": st["name"], "all": _stats(all), "feasible": _stats(feasible), "by_tier": {}, "by_finance": {}}
	for o: Dictionary in feasible:
		var tk := "T%d" % int(o["tier"])
		if not r["by_tier"].has(tk):
			r["by_tier"][tk] = []
		r["by_tier"][tk].append(o)
		var fk := str(o["finance"])
		if not r["by_finance"].has(fk):
			r["by_finance"][fk] = []
		r["by_finance"][fk].append(o)
	_print_stage(r)
	return r


func _measure(c: CustomerData) -> Dictionary:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var s := SurgeryManager.get_surgery(c.requested_surgery_id)
	var fee := CustomerGenerator.estimate_fee(c)
	if c.traits.has(&"greedy"):
		fee = int(round(fee * 0.85))  # PeopleManager.settle haggles full-price jobs
	var now := mini(fee, c.budget)
	var implant := InventoryManager.implant_price(item) if item else 0
	var supplies := int(round((s.supplies if s else 1) * GameManager.supply_unit_cost()))
	var cost := implant + supplies
	return {
		"feasible": item != null and CustomerGenerator.is_feasible(item),
		"tier": item.tier if item else 0,
		"finance": String(c.finance),
		"fee": fee,
		"cost": cost,
		"direct": fee - cost,
		"cash": now - cost,
		"risk": int(round(fee * (1.0 - FAIL_RATE))) - cost,
	}


func _stats(list: Array) -> Dictionary:
	var out := {"n": list.size(), "neg": 0.0, "thin": 0.0, "cash_neg": 0.0, "risk_neg": 0.0, "median": 0, "p10": 0, "p90": 0, "median_fee": 0}
	if list.is_empty():
		return out
	var d: Array[int] = []
	var f: Array[int] = []
	var neg := 0
	var thin := 0
	var cash_neg := 0
	var risk_neg := 0
	for o: Dictionary in list:
		d.append(int(o["direct"]))
		f.append(int(o["fee"]))
		if int(o["direct"]) < 0:
			neg += 1
		elif int(o["direct"]) < 50:
			thin += 1
		if int(o["cash"]) < 0:
			cash_neg += 1
		if int(o["risk"]) < 0:
			risk_neg += 1
	d.sort()
	f.sort()
	var k := float(list.size())
	out["neg"] = neg / k
	out["thin"] = thin / k
	out["cash_neg"] = cash_neg / k
	out["risk_neg"] = risk_neg / k
	out["median"] = d[d.size() / 2]
	out["p10"] = d[d.size() / 10]
	out["p90"] = d[d.size() * 9 / 10]
	out["median_fee"] = f[f.size() / 2]
	return out


func _line(label: String, s: Dictionary) -> String:
	return "  %-30s n=%5d  loss %5.1f%%  thin(<50) %5.1f%%  cash-today<0 %5.1f%%  loss@15%%fail %5.1f%%  margin p10/med/p90 %6d %6d %6d  fee med %5d" % [
		label, int(s["n"]), 100.0 * float(s["neg"]), 100.0 * float(s["thin"]), 100.0 * float(s["cash_neg"]), 100.0 * float(s["risk_neg"]),
		int(s["p10"]), int(s["median"]), int(s["p90"]), int(s["median_fee"])]


func _print_stage(r: Dictionary) -> void:
	print("\n== OFFERS: %s ==" % r["name"])
	print(_line("all offers", r["all"]))
	print(_line("doable now (tools owned)", r["feasible"]))
	var tiers: Array = r["by_tier"].keys()
	tiers.sort()
	for t: String in tiers:
		print(_line("  doable %s" % t, _stats(r["by_tier"][t])))
	var fins: Array = r["by_finance"].keys()
	fins.sort()
	for f: String in fins:
		print(_line("  doable %s" % f, _stats(r["by_finance"][f])))


## 3.10 targets: unprofitable jobs are the exception, not the norm, but they
## still exist once the player can take on bigger chrome; the median job pays.
func _print_targets(results: Array[Dictionary]) -> void:
	print("\n== OFFER TARGETS ==")
	var later_neg := 0.0
	var later_n := 0.0
	for i in results.size():
		var r: Dictionary = results[i]
		var s: Dictionary = r["feasible"]
		var name := str(r["name"]).get_slice(" ", 0)
		_target(float(s["neg"]) <= 0.12, "%s: at most 12%% of doable offers lose money on direct costs (%.1f%%)" % [name, 100.0 * float(s["neg"])])
		_target(float(s["risk_neg"]) <= 0.3, "%s: at most 30%% would lose money if 15%% of operations failed (%.1f%%)" % [name, 100.0 * float(s["risk_neg"])])
		_target(int(s["median"]) > 0, "%s: the median doable offer has a positive direct margin (%d cr)" % [name, int(s["median"])])
		if i > 0:
			later_neg += float(s["neg"]) * int(s["n"])
			later_n += int(s["n"])
	var share := later_neg / maxf(1.0, later_n)
	_target(share >= 0.01, "after the first days some offers are still bad deals, at least 1%% (%.1f%%)" % (100.0 * share))
	if _failures.is_empty():
		print("OFFERS OK")
	else:
		print("OFFER ISSUES:")
		for f in _failures:
			print("  - " + f)


func _target(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  MISS ") + msg)
	if not ok:
		_failures.append(msg)
