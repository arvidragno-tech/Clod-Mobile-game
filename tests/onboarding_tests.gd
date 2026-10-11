extends RefCounted
## 3.7 UX overhaul tests: the patient summary's facts (one source of truth
## with the dossier, the plan and the results), the clinic dashboard,
## guidance deduplication, progressive features (rules, save migration,
## validation, the setting, gated navigation), decision previews, the
## handbook (known / not yet, related entries) and known consequences in
## conversations. Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	GameManager.is_running = true
	_patient_brief()
	_dashboard()
	_guidance()
	_features()
	_previews()
	_handbook()
	_conversations()
	SaveManager.reset_all()
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _customer() -> CustomerData:
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	return c


func _patient_brief() -> void:
	SaveManager.reset_all()
	var c := _customer()
	var b := PatientBrief.build(c)
	var r := GameManager.get_surgery_readiness()
	var est := JobEstimate.for_customer(c, r)
	var f: Dictionary = b["finance"]
	check(int(f["margin"]) == int(est["net"]) and int(f["pays_now"]) == int(est["can_pay"]) and int(f["direct_cost"]) == int(est["implant_cost"]) + int(est["supplies_cost"]),
		"summary money is JobEstimate's (margin %d)" % int(f["margin"]))
	check(int(f["margin"]) == int(f["pays_now"]) - int(f["direct_cost"]), "margin = what they pay now - direct costs")
	check(is_equal_approx(float(b["operation"]["success"]), float(Recommend.self_estimate(c)["chance"])), "summary odds are Recommend.self_estimate")
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	check(str(b["operation"]["difficulty_word"]) == PatientBrief.difficulty_word(item.install_difficulty) and int(b["operation"]["difficulty"]) == item.install_difficulty,
		"difficulty is the implant's install difficulty, in words")
	check(str(b["request"]["implant"]) == item.display_name and str(b["request"]["procedure"]) != "?", "request names the implant and the procedure")
	check(bool(b["operation"]["uncertain"]), "the odds are marked as an estimate")
	check(int(b["decline"]["rep"]) == GameConfig.DECLINE_REPUTATION_PENALTY, "declining shows its real reputation cost")
	# Missing tools block (and say how to fix it); salvaged parts are a risk, not a block.
	var blocking := (b["missing"] as Array).all(func(m: Dictionary) -> bool: return PatientBrief.BLOCKING.has(str(m["key"])))
	check(blocking, "only blocking checks are listed as missing")
	InventoryManager.supplies = 0
	var b2 := PatientBrief.build(c)
	var sup: Array = (b2["missing"] as Array).filter(func(m: Dictionary) -> bool: return str(m["key"]) == "supplies")
	check(not sup.is_empty() and str(sup[0]["fix"]) != "" and (sup[0]["link"] as Dictionary).has("screen"), "no supplies: listed as missing, with a fix that opens SUPPLY")
	check(str(b2["recommendation"]["text"]).contains("can't start"), "the recommendation says you can't start yet")
	InventoryManager.supplies = 8
	# Emergencies point to triage.
	c.is_emergency = true
	check(str(PatientBrief.build(c)["recommendation"]["text"]).begins_with("Emergency"), "an emergency's summary points to triage")
	c.is_emergency = false
	CustomerManager.dismiss_current()


func _dashboard() -> void:
	SaveManager.reset_all()
	EventManager.operations = 5
	var d := ClinicStatus.dashboard()
	check(str(d["headline"]["text"]) == "READY FOR PATIENTS", "a quiet clinic: READY FOR PATIENTS")
	check((d["issues"] as Array).all(func(i: Dictionary) -> bool: return i["level"] != ClinicStatus.GOOD), "only issues that need you are listed")
	check(not (d["issues"] as Array).any(func(i: Dictionary) -> bool: return str(i["key"]) == "rep"), "a new name (rep 0) isn't an issue")
	InventoryManager.supplies = 0
	d = ClinicStatus.dashboard()
	check(str(d["headline"]["key"]) == "supplies" and (d["headline"]["link"] as Dictionary).get("screen", &"") == &"shop", "no supplies: the headline says so and links to SUPPLY")
	InventoryManager.supplies = 8
	BusinessManager.set_doors_open(false)
	check(str(ClinicStatus.dashboard()["headline"]["text"]) == "DOORS CLOSED", "doors closed: the headline says so")
	BusinessManager.set_doors_open(true)
	FactionManager.heat = 60.0
	d = ClinicStatus.dashboard()
	check((d["issues"] as Array).any(func(i: Dictionary) -> bool: return str(i["key"]) == "heat"), "high heat is listed as an issue")
	check((d["issues"] as Array).size() <= 3, "at most three issues")
	EventManager.operations = 0
	check((ClinicStatus.dashboard()["issues"] as Array).is_empty(), "the first patient: only the headline")
	FactionManager.heat = 0.0
	# A patient missing what the job needs.
	EventManager.operations = 5
	_customer()
	InventoryManager.supplies = 0
	d = ClinicStatus.dashboard()
	check(str(d["headline"]["key"]) in ["supplies", "missing"], "a patient waiting on missing supplies is the headline")
	InventoryManager.supplies = 8
	CustomerManager.dismiss_current()


func _guidance() -> void:
	SaveManager.reset_all()
	InventoryManager.supplies = 0
	FactionManager.heat = 80.0
	var ids := Guidance.for_player().map(func(it: Dictionary) -> String: return str(it["id"]))
	check(not ids.has("supplies_out") and not ids.has("heat"), "WHAT MATTERS doesn't repeat what the dashboard shows")
	check(Guidance.items().any(func(it: Dictionary) -> bool: return str(it["id"]) == "supplies_out"), "... the data is still there for the dashboard")
	InventoryManager.supplies = 8
	FactionManager.heat = 0.0
	var o := GameManager.get_next_objective()
	check(str(o.get("why", "")) != "" and o.has("optional"), "the NEXT line says why it matters (%s)" % o.get("why", ""))
	# Lines that lead into a section not introduced yet wait.
	TutorialManager.start()
	SkillManager.points = 2
	ids = Guidance.for_player().map(func(it: Dictionary) -> String: return str(it["id"]))
	check(not ids.has("skills"), "skill points wait until SKILLS is introduced")
	TutorialManager.reset_state()


func _features() -> void:
	SaveManager.reset_all()
	check(Features.is_on(&"staff") and Features.is_on(&"map"), "test resets and old saves have every section")
	# A new game starts small.
	TutorialManager.start()
	TutorialManager.active = false
	TutorialManager.completed = true
	EventManager.operations = 0
	Features.refresh()
	for id: StringName in [&"skills", &"supply", &"staff", &"upgrades", &"map", &"database"]:
		check(not Features.is_on(id), "a new game: %s not yet" % id)
	EventManager.operations = 1
	Features.refresh()
	for id: StringName in [&"skills", &"supply", &"inventory", &"business", &"dossier"]:
		check(Features.is_on(id), "after the first job: %s" % id)
	check(not Features.is_on(&"staff"), "after the first job: STAFF still waits")
	check(TutorialManager.intro_pending.size() == 5, "each new section queues one intro card (%d)" % TutorialManager.intro_pending.size())
	check(Features.is_new(&"supply"), "a section introduced today is NEW")
	EventManager.operations = 3
	Features.refresh()
	check(Features.is_on(&"staff") and Features.is_on(&"upgrades") and Features.is_on(&"database"), "three jobs in: STAFF, FACILITY, CYBERWARE DB")
	check(not Features.is_on(&"map"), "three jobs in: the city still waits")
	# A contextual link introduces its section.
	Features.introduce(&"map")
	check(Features.is_on(&"map"), "a link to the city introduces it")
	# The black market keeps its own rule.
	check(Features.is_on(&"blackmarket") == BlackMarketManager.is_unlocked(), "the black market follows its own unlock")
	# Saved and restored.
	var saved := TutorialManager.get_save_data()
	TutorialManager.introduced = {}
	TutorialManager.load_save_data(saved)
	check(TutorialManager.introduced.has("staff") and TutorialManager.introduced.has("map"), "introduced sections are saved and loaded")
	# Old saves: everything.
	TutorialManager.load_save_data({"active": false, "step": -1, "completed": true})
	check(TutorialManager.introduced.size() == Features.LIST.size() and TutorialManager.intro_pending.is_empty(), "a save from before 3.7 keeps every section, no cards")
	# Validation: a lost flag never locks something relevant.
	TutorialManager.introduced = {}
	EventManager.operations = 5
	Features.refresh()
	check(Features.is_on(&"staff") and Features.is_on(&"supply"), "a lost flag is restored from the game state")
	# The setting.
	TutorialManager.introduced = {}
	Settings.progressive_features = false
	check(Features.is_on(&"staff") and Features.is_on(&"map"), "INTRODUCE FEATURES GRADUALLY off: everything")
	Settings.progressive_features = true
	TutorialManager.reset_state()


func _previews() -> void:
	SaveManager.reset_all()
	EconomyManager.money = 500
	var f := DecisionPreview.facts(200, 30)
	check(int(f["now"]) == 500 and int(f["after"]) == 300 and int(f["bill"]) == BusinessManager.projected_total() + 30, "preview: cash now, after and tonight's bill (+ the new recurring cost)")
	check(not bool(f["short"]), "preview: affordable")
	check(bool(DecisionPreview.facts(600)["short"]), "preview: can't afford")
	var bill := BusinessManager.projected_total()
	EconomyManager.money = bill + 100
	check(bill <= 0 or bool(DecisionPreview.facts(101)["below_bill"]), "preview: warns when it leaves less than tonight's bill (bill %d)" % bill)
	check(bill <= 0 or DecisionPreview.summary(101).contains("tonight's bill"), "preview summary says so in words")
	check(BlackMarketManager.BUY_HEAT > 0.0 and BlackMarketManager.BUY_STANDING != 0, "black-market purchase effects are shared constants")


func _handbook() -> void:
	SaveManager.reset_all()
	var terms: Dictionary = Glossary.data().get("terms", {})
	var bad: Array[String] = []
	for k: String in terms:
		var fe := str(terms[k].get("feature", ""))
		if fe != "" and not Features.LIST.has(StringName(fe)):
			bad.append(k)
		for s: Variant in terms[k].get("see", []):
			if not terms.has(str(s)):
				bad.append("%s->%s" % [k, s])
	check(bad.is_empty(), "every handbook gate and SEE ALSO link is valid %s" % [bad])
	for k in ["success_estimate", "direct_margin", "the_money", "outlook", "doors", "standing", "guidance"]:
		check(Glossary.has(k), "the handbook explains %s" % k)
	# Not yet introduced: held back, counted.
	TutorialManager.start()
	TutorialManager.active = false
	TutorialManager.completed = true
	EventManager.operations = 0
	check(not Glossary.known("stress") and Glossary.hidden_in("staff") > 0, "staff entries wait until STAFF is introduced")
	check(not Glossary.search("stress").has("stress"), "search doesn't reveal entries not introduced yet")
	check(Glossary.known("loop") and Glossary.known("supplies"), "the basics are always there")
	Features.introduce(&"staff")
	check(Glossary.known("stress") and Glossary.is_new("stress"), "introducing STAFF reveals its entries, marked NEW")
	TutorialManager.reset_state()


func _conversations() -> void:
	var o := {"text": "x", "kind": "plain", "effects": {"rel": 8, "fear": 3, "faction": {"street_gangs": 6}, "heat": 4, "money": 120}}
	var k := DialogueManager.known_effects(o)
	check(k.contains("+6") and k.contains("heat") and k.contains("+120"), "a line's public consequences are shown (%s)" % k)
	check(not k.to_lower().contains("rel") and not k.to_lower().contains("fear"), "how a person feels stays hidden")
	o["kind"] = "persuade"
	check(DialogueManager.known_effects(o).begins_with("if it works"), "a check's effects say 'if it works'")
	check(DialogueManager.known_effects({"effects": {"rel": 5}}) == "", "a purely personal line shows nothing")
