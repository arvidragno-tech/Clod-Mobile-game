extends RefCounted
## Unit / system tests (no UI). Run by tests/test_runner.gd.

var t: Node  # the runner (provides check())


func run(runner: Node) -> void:
	t = runner
	_vitals()
	_scoring()
	_progression()
	_economy_inventory()
	_insufficient_money_and_tools()
	_data_integrity()
	_customer_generation()
	_learning_curve()
	_settings()
	_neural_load()
	_invalid_cyberware()
	_modifiers_and_skills()
	_factions_and_heat()
	_clinic_upgrade()
	_events()
	_black_market()
	_failure_and_death()
	_save_roundtrip()
	_save_migration_v1()
	_save_robustness()
	SaveManager.reset_all()


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _vitals() -> void:
	var v := SurgeryVitals.new()
	v.set_wound_open(true)
	for i in 100:
		v.tick(0.1)
	check(v.blood_loss > 0.5 and v.blood_loss < 5.0, "open wound bleeds slowly (%.2f%% in 10s)" % v.blood_loss)
	var before := v.neural
	v.apply_effects(GameConfig.MISTAKE_EFFECTS[&"wrong_connection"])
	check(v.neural < before, "wrong connection reduces neural stability")
	v.apply_effects({"bleed_rate": 3.0})
	for i in 600:
		v.tick(0.1)
	check(v.health < 100.0, "heavy bleeding drains health")
	v.health = 0.0
	check(v.get_failure_reason() == &"flatline", "zero health = flatline")
	var calm := SurgeryVitals.new()
	calm.sedated = true
	for i in 100:
		calm.tick(0.1)
	check(calm.pain < GameConfig.START_PAIN, "sedation lowers pain over time")


func _scoring() -> void:
	SaveManager.reset_all()
	check(SurgeryScoring.grade_for_score(0.95) == "S", "score 0.95 = S")
	check(SurgeryScoring.grade_for_score(0.7) == "B", "score 0.7 = B")
	check(SurgeryScoring.time_modifier(10, 100) > 0.0, "fast surgery gets a time bonus")
	check(SurgeryScoring.time_modifier(400, 100) < 0.0, "slow surgery gets a time penalty")
	var surgery := SurgeryManager.get_surgery(&"install_basic_neural_implant")
	var r := SurgeryResult.new()
	r.success = true
	r.stage_quality = 1.0
	r.final_health = 100.0
	r.final_neural = 100.0
	r.implant_performance = 1.0
	r.elapsed_sec = 60.0
	r.target_time_sec = surgery.target_time_sec
	r.diagnosis_correct = true
	SurgeryScoring.apply_rewards(r, surgery, null)
	check(r.grade == "S" and r.pay > surgery.base_pay, "perfect op = S grade, pays above base (%d)" % r.pay)
	var hard := SurgeryResult.new()
	for k in ["success", "stage_quality", "final_health", "final_neural", "implant_performance", "elapsed_sec", "target_time_sec", "diagnosis_correct"]:
		hard.set(k, r.get(k))
	hard.install_difficulty = 5
	hard.implant_price = 2000
	SurgeryScoring.apply_rewards(hard, surgery, null)
	check(hard.pay > r.pay and hard.xp > r.xp, "harder, pricier installs pay and teach more")
	var f := SurgeryResult.new()
	f.success = false
	SurgeryScoring.apply_rewards(f, surgery, null)
	check(f.grade == "F" and f.pay == 0 and f.reputation_delta < 0, "failed op pays nothing and costs rep")


func _progression() -> void:
	SaveManager.reset_all()
	var pts := SkillManager.points
	var need := ProgressionManager.xp_required_for_level(2)
	var gained := ProgressionManager.add_xp(need)
	check(gained == 1 and ProgressionManager.level == 2, "XP threshold levels up")
	check(SkillManager.points == pts + GameConfig.SKILL_POINTS_PER_LEVEL, "level up grants a skill point")
	check(CyberwareManager.get_available_tier() == 1, "LV2 still tier-1 chrome (tier 2 unlocks at LV%d)" % GameConfig.CYBERWARE_TIER_LEVEL[2])
	ProgressionManager.add_xp(ProgressionManager.xp_required_for_level(GameConfig.CYBERWARE_TIER_LEVEL[2]) - ProgressionManager.total_xp)
	check(CyberwareManager.get_available_tier() == 2, "LV%d unlocks tier-2 cyberware (in a T2 clinic)" % GameConfig.CYBERWARE_TIER_LEVEL[2])
	SaveManager.reset_all()
	check(CyberwareManager.get_available_tier() == 1, "new game: tier 1 only")


func _economy_inventory() -> void:
	SaveManager.reset_all()
	check(EconomyManager.money == GameConfig.STARTING_MONEY, "starting money")
	check(not EconomyManager.spend(EconomyManager.money + 1), "cannot overspend")
	check(InventoryManager.has_tool_category(&"scalpel"), "starter scalpel owned")
	check(not InventoryManager.has_tool_category(&"drill"), "no drill at start")
	var stock := InventoryManager.get_implant_count(&"nx1_neural_bridge")
	check(InventoryManager.buy_implant(&"nx1_neural_bridge"), "can buy a tier-1 implant")
	check(InventoryManager.get_implant_count(&"nx1_neural_bridge") == stock + 1, "implant stock increased")
	check(not InventoryManager.buy_implant(&"warden_coprocessor"), "cannot buy a locked tier-3 implant")
	check(not InventoryManager.buy_implant(&"unknown_military_core"), "black-market chrome is not sold at supply")
	EconomyManager.add_money(5000)
	ProgressionManager.add_xp(ProgressionManager.xp_required_for_level(2))
	check(InventoryManager.buy_tool(&"scalpel_mono"), "can buy precision scalpel at LV2")
	check(InventoryManager.get_best_tool(&"scalpel").id == &"scalpel_mono", "best scalpel is the upgrade")
	check(not InventoryManager.buy_tool(&"laser_cutter"), "laser cutter locked until LV5")
	var supplies := InventoryManager.supplies
	check(InventoryManager.buy_supply_pack() and InventoryManager.supplies > supplies, "supply pack adds supplies")
	SaveManager.reset_all()


func _insufficient_money_and_tools() -> void:
	SaveManager.reset_all()
	EconomyManager.spend(EconomyManager.money)
	check(not InventoryManager.buy_tool(&"cyber_drill"), "insufficient money: cannot buy drill")
	check(not InventoryManager.buy_implant(&"kestrel_sight"), "insufficient money: cannot buy implant")
	check(not InventoryManager.buy_supply_pack(), "insufficient money: cannot buy supplies")
	# Arm customer without a drill -> readiness blocks the operation.
	EconomyManager.add_money(100)
	var c := CustomerManager.generator.generate({"category": "arms"})
	CustomerManager.debug_set_customer(c)
	var r := GameManager.get_surgery_readiness()
	check(not r["ok"] and "DRILL T1" in r["missing_tools"], "insufficient tools: arm install needs a DRILL (%s)" % [r["missing_tools"]])
	EconomyManager.add_money(1000)
	InventoryManager.buy_tool(&"cyber_drill")
	r = GameManager.get_surgery_readiness()
	check(r["missing_tools"].is_empty(), "buying the drill clears the requirement")
	CustomerManager.reset_state()
	SaveManager.reset_all()


func _data_integrity() -> void:
	for id: StringName in CyberwareManager.catalog:
		var item: CyberwareData = CyberwareManager.catalog[id]
		check(SurgeryManager.get_surgery(item.install_surgery_id) != null, "%s has an install surgery" % id)
		check(ResourceLoader.exists(item.icon_path), "%s icon exists" % id)
		for req in item.get_tool_requirements():
			var found := false
			for t2: ToolData in InventoryManager.tool_catalog.values():
				if t2.category == req["category"] and t2.tier >= int(req["tier"]):
					found = true
			check(found, "%s tool requirement %s is obtainable" % [id, req])
	var cats := {}
	for item: CyberwareData in CyberwareManager.catalog.values():
		cats[item.category] = maxi(int(cats.get(item.category, 0)), item.tier)
	check(cats.size() == 8, "all 8 cyberware categories have items (%d)" % cats.size())
	for s: SurgeryData in SurgeryManager.surgeries.values():
		for stage in s.stages:
			check(SurgeryStageRegistry.STAGE_TYPES.has(stage.type), "%s stage '%s' is registered" % [s.id, stage.type])
		check(ResourceLoader.exists(SurgicalSiteView.REGION_TEXTURES.get(s.get_region(), "")), "%s region art exists" % s.id)
		for opt in s.diagnosis_options:
			check(s.diagnosis_findings.has(str(opt["id"])), "%s has findings for %s" % [s.id, opt["id"]])
	for t2: ToolData in InventoryManager.tool_catalog.values():
		check(ResourceLoader.exists(t2.icon_path), "tool %s icon exists" % t2.id)
	for id: StringName in CustomerManager.characters:
		var c := CustomerManager.get_customer(id)
		check(CharacterArt.validate(c.appearance).is_empty(), "character %s art parts exist %s" % [id, CharacterArt.validate(c.appearance)])
		check(CyberwareManager.is_valid(c.requested_cyberware_id), "character %s requests valid chrome" % id)
	check(FactionManager.order.size() == 5, "5 factions")
	check(SkillManager.order.size() >= 12, "skill tree loaded (%d)" % SkillManager.order.size())
	check(ClinicManager.tiers.size() == 6, "6 clinic tiers")
	check(EventManager.order.size() >= 12, "events loaded (%d)" % EventManager.order.size())


func _customer_generation() -> void:
	SaveManager.reset_all()
	var gen := CustomerGenerator.new(RandomNumberGenerator.new())
	gen.rng.seed = 1234
	var archetypes := {}
	var bad := 0
	var appearances := {}
	for i in 300:
		var c := gen.generate()
		archetypes[c.archetype_id] = true
		appearances[JSON.stringify(c.appearance)] = true
		var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
		var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
		var problems: Array[String] = []
		if item == null or surgery == null:
			problems.append("invalid request")
		elif item.tier > CyberwareManager.get_available_tier():
			problems.append("tier too high")
		if surgery and not surgery.has_diagnosis(c.true_diagnosis_id):
			problems.append("bad diagnosis")
		if not FactionManager.factions.has(c.faction_id):
			problems.append("bad faction")
		if c.wealth < 0 or c.wealth > 3 or c.patience < 0 or c.patience > 100 or c.risk_tolerance < 0 or c.risk_tolerance > 1:
			problems.append("stat out of range")
		if not CharacterArt.validate(c.appearance).is_empty():
			problems.append("missing art %s" % CharacterArt.validate(c.appearance))
		if c.display_name == "" or c.dialogue == "" or c.occupation == "":
			problems.append("missing text")
		if not problems.is_empty():
			bad += 1
			if bad < 4:
				print("     bad customer: ", problems)
	check(bad == 0, "300 generated customers are valid (%d bad)" % bad)
	check(archetypes.size() >= 7, "generation covers many archetypes (%d)" % archetypes.size())
	check(appearances.size() >= 290, "customers look different (%d unique of 300)" % appearances.size())
	var a := CustomerGenerator.new(RandomNumberGenerator.new())
	a.rng.seed = 99
	var b := CustomerGenerator.new(RandomNumberGenerator.new())
	b.rng.seed = 99
	var ca := a.generate()
	var cb := b.generate()
	check(ca.display_name == cb.display_name and ca.requested_cyberware_id == cb.requested_cyberware_id, "generation is deterministic per seed")
	var round_trip := CustomerData.from_save_dict(ca.to_save_dict())
	check(round_trip.display_name == ca.display_name and round_trip.existing_cyberware == ca.existing_cyberware and round_trip.appearance == ca.appearance, "customer serialises losslessly")
	var tex := CharacterArt.portrait(ca.appearance)
	check(tex != null and tex.get_width() == 96 and tex.get_height() == 112, "portrait composites to 96x112")
	check(CharacterArt.body(ca.appearance).get_height() == 80, "body sprite composites to 40x80")
	_character_system(gen)


## Character art v2: cast, silhouettes, migration, visible consequences.
func _character_system(gen: CustomerGenerator) -> void:
	for id: StringName in CharacterManager.cast:
		var app := CharacterManager.appearance(id)
		check(CharacterArt.validate(app).is_empty(), "cast %s art parts exist %s" % [id, CharacterArt.validate(app)])
		var c := CharacterManager.get_character(id)
		check(c.background != "" and c.motivation != "" and c.arc != "" and c.silhouette != "", "cast %s has background, motivation, arc, silhouette" % id)
	check(CharacterManager.cast.size() >= 10, "story cast loaded (%d)" % CharacterManager.cast.size())
	# Silhouettes: occupation decides outfit + posture + kit.
	var silhouettes := {}
	var by_occ := {}
	gen.rng.seed = 4242
	for i in 200:
		var c := gen.generate()
		var a := c.appearance
		silhouettes["%s|%s|%s" % [a.get("outfit"), a.get("posture"), a.get("build")]] = true
		by_occ[str(c.archetype_id)] = a.get("outfit")
	check(silhouettes.size() >= 30, "customers have many distinct silhouettes (%d)" % silhouettes.size())
	var corp := CharacterAppearanceManager.generate({"occupation": "executive", "faction": "lyra_biocomp", "wealth": 3, "age": 45})
	var gang := CharacterAppearanceManager.generate({"occupation": "gang_member", "faction": "street_gangs", "wealth": 0, "age": 24})
	check(corp["outfit"] in ["executive", "corporate"] and corp["posture"] == "upright" and corp["metal"] != "brass", "executive reads clean, upright, discreet")
	check(gang["outfit"] == "gang" and gang["posture"] in ["wide", "slouch"], "ganger reads asymmetric and aggressive")
	var old := CharacterAppearanceManager.generate({"occupation": "elder", "age": 78})
	check(old["age_look"] == "old", "age shows on the face")
	# v1 appearances (old saves) still render.
	var v1 := {"build": "heavy", "face": "broad", "expr": "hard", "hair": "long", "outfit": "dock", "facial_hair": "beard",
		"scar": "cheek", "tattoos": ["gang_mark"], "cyber": ["eye", "circuit"], "accessories": ["earring", "beanie"],
		"body_cyber": ["arm"], "skin": 3, "hair_color": "gray", "iris": "blue", "cloth_a": "navy", "cloth_b": "hivis"}
	var v2 := CharacterAppearanceManager.normalize(v1)
	check(int(v2["v"]) == 2 and v2["outfit"] == "worker" and v2["face"] == "square" and (v2["cyber"] as Array).has("optic"), "v1 appearance migrates to v2")
	check(CharacterArt.validate(v2).is_empty(), "migrated appearance renders %s" % CharacterArt.validate(v2))
	# Story consequences change how a character looks, and survive a save.
	CharacterManager.reset_state()
	CharacterManager.apply_appearance_event(&"teo_marr", "lose_eye")
	check((CharacterManager.appearance(&"teo_marr")["cyber"] as Array).has("optic"), "losing an eye gives the character an optic")
	var saved := CharacterManager.get_save_data()
	CharacterManager.reset_state()
	check(not (CharacterManager.appearance(&"teo_marr")["cyber"] as Array).has("optic"), "reset restores the base look")
	CharacterManager.load_save_data(saved)
	check((CharacterManager.appearance(&"teo_marr")["cyber"] as Array).has("optic"), "appearance changes persist through save/load")
	CharacterManager.change_relationship(&"vesna_kalo", 30)
	check(CharacterManager.relationship_state(&"vesna_kalo") == "transactional", "fixers stay transactional until trust is high")
	CharacterManager.change_relationship(&"vesna_kalo", 40)
	check(CharacterManager.relationship_state(&"vesna_kalo") == "loyal", "high trust turns loyal")
	CharacterManager.reset_state()
	# Compositing is cheap enough for live expression swaps.
	var t0 := Time.get_ticks_usec()
	for e in ["neutral", "angry", "smirk", "sad", "fear", "pain"]:
		for g in ["center", "left", "right", "closed"]:
			CharacterArt.portrait_layers(gang, e, g)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(ms < 2500.0, "24 portrait variants composite quickly (%.0f ms)" % ms)


func _learning_curve() -> void:
	SaveManager.reset_all()
	EventManager.operations = 0
	var gen := CustomerGenerator.new(RandomNumberGenerator.new())
	gen.rng.seed = 77
	var worst := 0.0
	var hidden := 0
	for i in 60:
		var c := gen.generate()
		worst = maxf(worst, NeuralLoad.compute(c))
		hidden += c.hidden_conditions.size()
	check(worst <= Difficulty.EARLY_LOAD_CAP + 0.01 and hidden == 0, "early customers: stable load (max %d%%) and no hidden conditions" % roundi(worst))
	check(Difficulty.assist(0) > Difficulty.assist(3) and Difficulty.assist(3) > Difficulty.assist(12) and is_equal_approx(Difficulty.assist(20), 1.0), "assist tapers to 1.0 as the player learns")
	check(Difficulty.max_complications(1) == 1 and Difficulty.max_complications(5) > 1, "second complications only after the learning phase")
	check(EventManager.roll_random_event(false) == &"", "no random events during the first jobs")
	EventManager.operations = 8
	gen.rng.seed = 77
	var later_hidden := 0
	for i in 60:
		later_hidden += gen.generate().hidden_conditions.size()
	check(later_hidden > 0, "hidden conditions appear later (%d in 60)" % later_hidden)
	TutorialManager.start()
	EventManager.operations = 0
	check(CustomerManager.tutorial_customer().character_id == &"mara_quill" and Difficulty.max_complications(0) == 0, "tutorial patient is scripted and complication-free")
	SaveManager.reset_all()


func _settings() -> void:
	var path := Settings.path
	Settings.path = "user://test_settings.cfg"
	Settings.reset_to_defaults()
	Settings.set_value("sfx_volume", 0.25)
	Settings.set_value("reduce_motion", true)
	Settings.load_settings()
	check(is_equal_approx(Settings.sfx_volume, 0.25) and Settings.reduce_motion and not Settings.shake_allowed(), "settings persist and reduce motion disables shake")
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string("[settings]\nsfx_volume=\"loud\"\ntext_speed=99\n")
	f.close()
	Settings.load_settings()
	check(is_equal_approx(Settings.sfx_volume, Settings.DEFAULTS["sfx_volume"]) and Settings.text_speed == Settings.TEXT_SPEEDS.size() - 1, "corrupt settings fall back to safe values")
	Settings.set_value("haptics", false)
	UIManager.last_haptic = &""
	UIManager.haptic(&"critical")
	check(UIManager.last_haptic == &"", "haptics off suppresses feedback")
	Settings.set_value("haptics", true)
	UIManager.haptic(&"implant")
	check(UIManager.last_haptic == &"implant", "haptic kinds fire when enabled")
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = path
	Settings.load_settings()


func _neural_load() -> void:
	SaveManager.reset_all()
	var c := CustomerManager.get_customer(&"mara_quill")
	var base := NeuralLoad.compute(c)
	c.existing_cyberware.append_array([&"warden_coprocessor", &"gunsight_ocular", &"kinetic_lattice", &"breacher_limb", &"mnemos_core"])
	var heavy := NeuralLoad.compute(c)
	check(heavy > base + 80.0, "chrome adds neural load (%d -> %d)" % [roundi(base), roundi(heavy)])
	check(NeuralLoad.band(30.0)["id"] == &"stable" and NeuralLoad.band(60.0)["id"] == &"minor" and NeuralLoad.band(80.0)["id"] == &"unstable"
		and NeuralLoad.band(90.0)["id"] == &"severe" and NeuralLoad.band(99.0)["id"] == &"critical", "neural load bands 50/70/85/95")
	check(NeuralLoad.drain_multiplier(heavy) > 2.0 and NeuralLoad.complication_bonus(heavy) > 0.4, "excessive load: faster neural drain, more complications")
	check(NeuralLoad.break_chance(heavy) > 0.2 and NeuralLoad.break_chance(30.0) == 0.0, "excessive load risks a post-op neural break")
	# Surgery reacts to load
	var surgery := SurgeryManager.get_surgery(&"install_basic_neural_implant")
	SurgeryManager.start_session(surgery, c, true, 1.0, 7, ImplantInstance.create(&"nx1_neural_bridge"))
	check(SurgeryManager.vitals.neural < c.neural_stability and SurgeryManager.vitals.neural_multiplier > 2.0, "excessive load: patient starts unstable")
	check(SurgeryManager.get_extra_complication_chance() > 0.5, "excessive load: complication chance %.2f" % SurgeryManager.get_extra_complication_chance())
	SurgeryManager.abort()
	CustomerManager.debug_set_customer(c)
	var r := GameManager.get_surgery_readiness()
	check(float(r["neural_after"]) >= 95.0, "plan projects CRITICAL load (%d%%)" % roundi(r["neural_after"]))
	c.risk_tolerance = 0.2
	check(not bool(GameManager.get_surgery_readiness()["accepts"]) and not bool(GameManager.get_surgery_readiness()["ok"]), "excessive load: cautious customer refuses consent")
	c.risk_tolerance = 0.9
	check(bool(GameManager.get_surgery_readiness()["accepts"]), "excessive load: reckless customer still consents")
	CustomerManager.reset_state()


func _invalid_cyberware() -> void:
	SaveManager.reset_all()
	check(not InventoryManager.add_implant(&"not_a_real_implant"), "invalid cyberware rejected by inventory")
	check(not CyberwareManager.is_valid(&"not_a_real_implant"), "invalid cyberware id not valid")
	var c := CustomerManager.get_customer(&"mara_quill")
	c.requested_cyberware_id = &"not_a_real_implant"
	CustomerManager.debug_set_customer(c)
	var r := GameManager.get_surgery_readiness()
	check(not r["ok"] and str(r["invalid"]) != "", "invalid cyberware request blocks the operation")
	var loaded := InventoryManager.get_instances().size()
	InventoryManager.load_save_data({"instances": [{"id": "bogus", "condition": 50}, {"id": "nx1_neural_bridge"}]})
	check(InventoryManager.get_instances().size() == 1, "invalid units dropped on load (was %d)" % loaded)
	CustomerManager.reset_state()


func _modifiers_and_skills() -> void:
	SaveManager.reset_all()
	check(ModifierManager.value(&"surgery.precision") == 0.0, "no precision bonus at start")
	check(SkillManager.upgrade(&"precision"), "spend starting point on Precision")
	check(is_equal_approx(ModifierManager.value(&"surgery.precision"), 0.12), "skill feeds modifier stack")
	check(not SkillManager.upgrade(&"precision"), "no points left")
	var surgery := SurgeryManager.get_surgery(&"install_arm")
	var c := CustomerManager.generator.generate({"cyberware": "breacher_limb"})
	SurgeryManager.start_session(surgery, c, true, 1.0, 3, ImplantInstance.create(&"breacher_limb"))
	var hard_prec := SurgeryManager.get_tool_precision(&"scalpel")
	SurgeryManager.abort()
	SurgeryManager.start_session(surgery, c, true, 1.0, 3, ImplantInstance.create(&"liftwell_arm"))
	var easy_prec := SurgeryManager.get_tool_precision(&"scalpel")
	SurgeryManager.abort()
	check(hard_prec < easy_prec, "install difficulty tightens tolerances (%.2f vs %.2f)" % [hard_prec, easy_prec])
	EventManager.apply_outcomes({"modifier": {"key": "complication.chance", "value": 0.3, "ops": 1}})
	check(is_equal_approx(ModifierManager.value(&"complication.chance"), 0.3 + float(ClinicManager.get_modifiers().get("complication.chance", 0.0))), "timed event modifier applies")
	EventManager.on_operation_completed()
	check(is_equal_approx(ModifierManager.value(&"complication.chance"), float(ClinicManager.get_modifiers().get("complication.chance", 0.0))), "timed modifier expires after the operation")
	SaveManager.reset_all()


func _factions_and_heat() -> void:
	SaveManager.reset_all()
	var before := FactionManager.get_rep(&"street_gangs")
	FactionManager.change(&"street_gangs", 30)
	check(FactionManager.get_rep(&"street_gangs") == before + 30, "faction rep changes")
	check(FactionManager.get_standing(&"street_gangs") in ["FRIENDLY", "NEUTRAL"], "standing name (%s)" % FactionManager.get_standing(&"street_gangs"))
	check(FactionManager.customer_weight(&"street_gangs") > FactionManager.customer_weight(&"corporate_security"), "friendlier factions send more customers")
	FactionManager.change(&"street_gangs", -500)
	check(FactionManager.get_rep(&"street_gangs") == -100 and FactionManager.is_hostile(&"street_gangs"), "rep clamps and turns hostile")
	FactionManager.add_heat(40)
	check(FactionManager.heat == 40.0, "heat accumulates")
	check(EventManager.is_eligible(&"inspector_visit"), "high heat makes inspections possible")
	SaveManager.reset_all()


func _clinic_upgrade() -> void:
	SaveManager.reset_all()
	check(ClinicManager.tier == 0 and ClinicManager.get_tier_name() == "Basement Hole", "start in the basement")
	check(ClinicManager.get_upgrade_block_reason() != "", "upgrade blocked at start")
	EconomyManager.add_money(1000)
	ProgressionManager.add_xp(ProgressionManager.xp_required_for_level(2))
	ReputationManager.change(5)
	check(ClinicManager.upgrade() and ClinicManager.tier == 1, "upgrade to Backroom Clinic")
	check(ClinicManager.get_background_path().contains("t1"), "clinic art changes with tier")
	check(ClinicManager.get_surgery_backdrop_level() == 1, "surgery backdrop improves with tier")
	SaveManager.reset_all()


func _events() -> void:
	SaveManager.reset_all()
	EventManager.queue_event(&"power_outage")
	var money := EconomyManager.money
	EventManager.resolve(0)
	check(EconomyManager.money == money - 150 and not EventManager.has_pending(), "event choice applies cost")
	EventManager.queue_event(&"wire_intro")
	EventManager.resolve(0)
	check(StoryManager.has_flag(&"bm_access") and BlackMarketManager.is_unlocked(), "story event unlocks the black market")
	check(StoryManager.met_characters.has(&"vesna_kalo"), "meeting Wire is recorded")
	check(StoryManager.unlocked_rumors.has(&"undermarket"), "event unlocks a rumor")
	check(not EventManager.is_eligible(&"wire_intro"), "one-time event does not repeat")
	EconomyManager.spend(EconomyManager.money)
	var e := EventManager.get_event(&"inspector_visit")
	check(EventManager.get_choice_block_reason(e["choices"][0]) != "", "unaffordable choice is blocked")
	EventManager.queue_event(&"emergency_patient")
	EventManager.resolve(0)
	check(CustomerManager.has_customer() and CustomerManager.current_customer.is_emergency, "emergency event spawns an emergency patient")
	CustomerManager.reset_state()
	# Post-op complications: a risky patient on a sloppy job comes back.
	EventManager.operations = 6  # past the learning phase
	var risky := CustomerManager.generator.generate({"category": "neural"})
	risky.post_op_risk = 1.0
	var ok := SurgeryResult.new()
	ok.success = true
	ok.grade = "C"
	check(CustomerManager.get_post_op_risk(risky, "C") >= 0.85, "risky patient has a high post-op risk")
	var notes := {}
	for attempt in 20:  # risk is capped below 100%, so retry the roll
		EventManager.pending_event = &""
		notes = CustomerManager.record_outcome(risky, ok)
		if bool(notes["post_op"]):
			break
	check(bool(notes["post_op"]) and EventManager.pending_event == &"post_op_return", "post-op complication brings the patient back")
	check(CustomerManager.get_post_op_risk(risky, "S") > CustomerManager.get_post_op_risk(CustomerManager.generator.generate({}), "S"), "hidden conditions raise post-op risk")
	InventoryManager.supplies = 0
	var post := EventManager.get_event(&"post_op_return")
	check(EventManager.get_choice_block_reason(post["choices"][0]) != "", "treating free needs supplies")
	SaveManager.reset_all()


func _black_market() -> void:
	SaveManager.reset_all()
	check(not BlackMarketManager.is_unlocked(), "black market locked at start")
	StoryManager.set_flag(&"bm_access")
	BlackMarketManager.refresh_stock()
	check(BlackMarketManager.stock.size() >= 3, "black market has stock (%d)" % BlackMarketManager.stock.size())
	var offer: Dictionary = BlackMarketManager.stock[0]
	EconomyManager.spend(EconomyManager.money)
	check(not BlackMarketManager.buy(0), "can't buy without credits")
	EconomyManager.add_money(int(offer["price"]))
	var count := InventoryManager.get_instances().size()
	check(BlackMarketManager.buy(0) and InventoryManager.get_instances().size() == count + 1, "black-market purchase adds the unit")
	check(EconomyManager.money == 0 and FactionManager.heat > 0.0, "purchase costs credits and draws heat")
	var inst := ImplantInstance.create(&"unknown_military_core", 73.0, &"black_market")
	BlackMarketManager.roll_traits(inst)
	InventoryManager.add_instance(inst)
	check(inst.traits.size() == 2 and inst.has_unknown_traits(), "military core rolls 2 unknown traits")
	InventoryManager.add_parts(10)
	check(BlackMarketManager.study(inst.uid) and inst.revealed.size() == 1, "STUDY reveals a property")
	var cond := inst.condition
	var msg := BlackMarketManager.modify(inst.uid)
	check(msg != "" and (inst.condition > cond or msg.begins_with("Purged")), "MODIFY repairs or purges (%s)" % msg)
	var tokens := InventoryManager.tokens
	var value := BlackMarketManager.sell(inst.uid)
	check(value > 0 and InventoryManager.get_instance(inst.uid) == null and InventoryManager.tokens == tokens + 1, "SELL pays out and gives a token")
	InventoryManager.add_tokens(2)
	check(BlackMarketManager.open_mystery_case() != null, "mystery case opens for tokens")
	SaveManager.reset_all()


func _failure_and_death() -> void:
	SaveManager.reset_all()
	var c := CustomerManager.generator.generate({"faction": "street_gangs", "category": "neural"})
	var rep := FactionManager.get_rep(&"street_gangs")
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	SurgeryManager.start_session(surgery, c, true, 1.0, 5, ImplantInstance.create(c.requested_cyberware_id))
	SurgeryManager.resume()
	SurgeryManager.vitals.health = 0.0
	SurgeryManager._process(0.016)
	var r := SurgeryManager.last_result
	check(r != null and not r.success and r.failure_reason == &"flatline" and r.grade == "F", "death state: flatline fails the operation")
	GameManager._apply_faction_and_heat(r, c)
	check(FactionManager.get_rep(&"street_gangs") < rep and FactionManager.heat > 0.0, "death angers the faction and draws heat")
	SaveManager.reset_all()


func _save_roundtrip() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(123)
	ReputationManager.change(7)
	ProgressionManager.add_xp(42)
	InventoryManager.add_implant(&"nx1_neural_bridge", 3)
	InventoryManager.add_parts(4)
	ProgressionManager.record_surgery(&"install_basic_neural_implant", true, "A")
	FactionManager.change(&"black_market", 12)
	FactionManager.add_heat(20)
	SkillManager.upgrade(&"precision")
	StoryManager.set_flag(&"bm_access")
	BlackMarketManager.refresh_stock()
	EventManager.queue_event(&"supply_drop")
	var bm_inst := ImplantInstance.create(&"ghostlink_eye", 61.0, &"black_market")
	BlackMarketManager.roll_traits(bm_inst)
	InventoryManager.add_instance(bm_inst)
	var c := CustomerManager.generator.generate()
	CustomerManager.debug_set_customer(c)
	var expected_money := EconomyManager.money
	var expected_units := InventoryManager.get_instances().size()
	var stock_n := BlackMarketManager.stock.size()
	check(SaveManager.save_game(), "save writes")
	SaveManager.reset_all()
	check(EconomyManager.money == GameConfig.STARTING_MONEY and not StoryManager.has_flag(&"bm_access"), "reset clears state")
	check(SaveManager.load_game(), "save loads")
	check(EconomyManager.money == expected_money, "money persisted")
	check(ReputationManager.reputation == 7 and ProgressionManager.total_xp == 42, "rep + xp persisted")
	check(InventoryManager.get_instances().size() == expected_units and InventoryManager.parts == GameConfig.STARTING_PARTS + 4, "inventory + parts persisted")
	var loaded := InventoryManager.get_instance(bm_inst.uid)
	check(loaded != null and is_equal_approx(loaded.condition, 61.0) and loaded.traits == bm_inst.traits, "black-market unit (condition, traits) persisted")
	check(FactionManager.get_rep(&"black_market") == 12 and is_equal_approx(FactionManager.heat, 20.0), "factions + heat persisted")
	check(SkillManager.get_rank(&"precision") == 1, "skills persisted")
	check(StoryManager.has_flag(&"bm_access") and BlackMarketManager.stock.size() == stock_n, "story + black market persisted")
	check(EventManager.pending_event == &"supply_drop", "pending event persisted")
	check(CustomerManager.current_customer != null and CustomerManager.current_customer.display_name == c.display_name, "generated customer persisted")
	check(str(ProgressionManager.surgery_records.get("install_basic_neural_implant", {}).get("best_grade", "")) == "A", "surgery records persisted")
	SaveManager.save_game()
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	check(SaveManager.load_game(), "corrupt save falls back to backup")
	SaveManager.delete_save()
	CustomerManager.reset_state()
	SaveManager.reset_all()


## A Step 1 (v1) save must load into the v2 format without losing progress.
func _save_robustness() -> void:
	SaveManager.reset_all()
	SaveManager.delete_save()
	EconomyManager.add_money(1111)
	check(SaveManager.save_game(), "save writes")
	var good := EconomyManager.money
	EconomyManager.add_money(5)
	SaveManager.save_game()  # previous file becomes the .bak
	# Flip one digit inside the main file: JSON still parses, checksum fails.
	var text := FileAccess.get_file_as_string(SaveManager.save_path)
	var i := text.find(str(good + 5))
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(text.substr(0, i) + str(good + 6) + text.substr(i + str(good + 5).length()))
	f.close()
	check(SaveManager.load_game() and EconomyManager.money == good, "tampered save fails its checksum; backup restores")
	# Killed mid-swap: only the temp file survived.
	SaveManager.save_game()
	var m := EconomyManager.money
	DirAccess.rename_absolute(SaveManager.save_path, SaveManager.save_path + ".tmp")
	DirAccess.remove_absolute(SaveManager.save_path + ".bak")
	check(SaveManager.has_save() and SaveManager.load_game() and EconomyManager.money == m, "interrupted save recovers from the temp file")
	# Truncated file (power loss) with no backup -> safe failure, not a crash.
	SaveManager.delete_save()
	f = FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string("{\"version\": 3, \"systems\": {\"Econ")
	f.close()
	check(not SaveManager.load_game(), "truncated save is rejected safely")
	# v2 -> v3 migration: settings leave the save, tutorial counts as done.
	var v2 := {"version": 2, "saved_at": 0, "systems": {"EconomyManager": {"money": 4321}, "AudioManager": {"sfx_enabled": false}}}
	f = FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v2))
	f.close()
	check(SaveManager.load_game() and EconomyManager.money == 4321 and TutorialManager.completed and not TutorialManager.is_active(), "v2 save migrates (tutorial skipped for veterans)")
	SaveManager.delete_save()
	SaveManager.reset_all()


func _save_migration_v1() -> void:
	SaveManager.reset_all()
	var v1 := {
		"version": 1, "saved_at": 0,
		"systems": {
			"EconomyManager": {"money": 777},
			"ReputationManager": {"reputation": 9},
			"ProgressionManager": {"total_xp": 150, "level": 2, "customers_served": 3,
				"surgery_records": {"install_basic_neural_implant": {"completed": 3, "failed": 0, "best_grade": "S"}}},
			"CyberwareManager": {"unlocked": ["nx1_neural_bridge"]},
			"InventoryManager": {"owned_tools": ["scalpel_rust", "scalpel_mono"], "implant_stock": {"nx1_neural_bridge": 2}},
			"CustomerManager": {"current_customer": "juno_reyes", "last_customer": "mara_quill"},
			"AudioManager": {"sfx_enabled": true, "ambient_enabled": true},
		},
	}
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	check(SaveManager.load_game(), "v1 save loads")
	check(EconomyManager.money == 777 and ReputationManager.reputation == 9 and ProgressionManager.level == 2, "v1 progress kept")
	check(InventoryManager.get_implant_count(&"nx1_neural_bridge") == 2, "v1 implant stock -> units")
	check(InventoryManager.owns_tool(&"scalpel_mono"), "v1 tools kept")
	check(ClinicManager.tier == 1, "v1 clinic becomes the Backroom tier")
	check(EventManager.operations == 3, "v1 operation count derived")
	check(CustomerManager.current_customer != null and CustomerManager.current_customer.character_id == &"juno_reyes", "v1 waiting customer restored")
	SaveManager.delete_save()
	CustomerManager.reset_state()
