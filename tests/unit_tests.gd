extends RefCounted
## Unit / system tests (no UI). Run by tests/test_runner.gd.

var t: Node  # the runner (provides check())


func run(runner: Node) -> void:
	t = runner
	WorldEventManager.auto_roll = false
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
	_business_and_world()
	_staff()
	_story()
	_story_playthrough(0)
	_story_playthrough(1)
	_events()
	_black_market()
	_failure_and_death()
	_save_roundtrip()
	_save_migration_v1()
	_save_v4()
	_save_robustness()
	SaveManager.reset_all()
	WorldEventManager.auto_roll = true


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
	check(FactionManager.order.size() == 6, "6 factions (incl. Lyra Biocomp)")
	check(SkillManager.order.size() >= 12, "skill tree loaded (%d)" % SkillManager.order.size())
	check(ClinicManager.tiers.size() == 7, "7 purchasable clinics")
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
	check(CharacterArt.validate(v2).is_empty(), "migrated appearance renders %s" % [CharacterArt.validate(v2)])
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
	# --- PC options: every one persists and drives something real.
	Settings.reset_to_defaults()
	for k: String in ["fps_limit", "pixel_scaling", "crt_filter", "scanlines", "shake_intensity", "lighting_quality", "glow",
			"environment_effects", "dialogue_volume", "ui_volume", "auto_advance", "confirm_dangerous", "tutorial_hints",
			"tooltips", "pause_dialogue", "pause_focus_loss", "difficulty", "autosave", "damage_feedback", "ui_scale",
			"text_scale", "colorblind", "reduced_shake", "reduced_flashing", "reduced_effects"]:
		check(Settings.DEFAULTS.has(k), "setting %s exists" % k)
	Settings.set_value("fps_limit", 1)
	Settings.apply_runtime()
	check(Engine.max_fps == 60, "frame rate limit applies (60)")
	Settings.set_value("pixel_scaling", "integer")
	Settings.apply_runtime()
	check((Engine.get_main_loop() as SceneTree).root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "integer pixel scaling applies")
	Settings.set_value("pixel_scaling", "fit")
	Settings.set_value("ui_scale", 2)
	Settings.apply_runtime()
	check(is_equal_approx((Engine.get_main_loop() as SceneTree).root.content_scale_factor, 1.1), "UI scale applies")
	# Tooltips off: a tooltip panel (built the way Godot builds one) is blanked
	# the moment it enters the tree.
	Settings.set_value("tooltips", false)
	var tree := Engine.get_main_loop() as SceneTree
	# In the game Main connects this when it registers the UI layers.
	if not tree.node_added.is_connected(UIManager._on_node_added):
		tree.node_added.connect(UIManager._on_node_added)
	var owner_ctl := Control.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(owner_ctl)
	var tip := PopupPanel.new()
	tip.theme_type_variation = &"TooltipPanel"
	var tip_label := Label.new()
	tip_label.text = "TIP"
	tip.add_child(tip_label)
	owner_ctl.add_child(tip)
	check(not tip_label.visible and tip.get_theme_stylebox(&"panel") is StyleBoxEmpty, "tooltips off hides tooltip panels")
	Settings.set_value("tooltips", true)
	var tip2 := PopupPanel.new()
	tip2.theme_type_variation = &"TooltipPanel"
	var tip_label2 := Label.new()
	tip2.add_child(tip_label2)
	owner_ctl.add_child(tip2)
	check(tip_label2.visible, "tooltips on leaves them alone")
	owner_ctl.queue_free()
	Settings.set_value("reduced_shake", true)
	check(Settings.shake_scale() < 0.5, "reduced shake scales shake down")
	Settings.set_value("reduced_flashing", true)
	check(not Settings.flashing_allowed(), "reduced flashing")
	Settings.set_value("text_scale", 1.2)
	check(UIKit.fs(20) >= 24, "text scale grows fonts")
	# Audio buses: every slider controls its own bus.
	for bus: StringName in [&"Music", &"Ambience", &"SFX", &"Dialogue", &"UI"]:
		check(AudioServer.get_bus_index(bus) >= 0, "audio bus %s exists" % bus)
	Settings.set_value("dialogue_volume", 0.5)
	Settings.set_value("ui_volume", 0.0)
	check(is_equal_approx(AudioManager.bus_volume_db(&"Dialogue"), linear_to_db(0.5)), "dialogue slider drives the Dialogue bus")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"UI")), "interface slider at 0 mutes the UI bus")
	check(AudioManager.UI_SFX.has(&"click") and not AudioManager.UI_SFX.has(&"cut"), "clicks are UI sounds, tools are effects")
	# Difficulty and autosave.
	Settings.set_value("difficulty", 0)
	var easy := Difficulty.assist(10)
	Settings.set_value("difficulty", 2)
	check(Difficulty.assist(10) < easy and Difficulty.cost_mult() > 1.0, "difficulty changes tolerance and costs")
	Settings.set_value("autosave", 0)
	var sp := SaveManager.save_path
	SaveManager.save_path = "user://test_autosave.json"
	SaveManager.delete_save()
	check(not SaveManager.save_game() and not FileAccess.file_exists(SaveManager.save_path), "autosave off skips automatic saves")
	check(SaveManager.save_game(&"manual"), "manual saves always work")
	Settings.set_value("autosave", 2)
	check(not SaveManager.save_game() and SaveManager.save_game(&"night"), "nightly autosave saves only at night")
	SaveManager.delete_save()
	SaveManager.save_path = sp
	# Persist and reload the whole set.
	Settings.load_settings()
	check(Settings.difficulty == 2 and Settings.reduced_flashing and is_equal_approx(Settings.text_scale, 1.2), "new settings persist")
	Settings.reset_to_defaults()
	Settings.apply_runtime()
	_controls()
	Settings.reset_to_defaults()
	Settings.apply_runtime()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = path
	Settings.load_settings()


func _controls() -> void:
	Controls.reset_bindings()
	check(Controls.all_conflicts().is_empty(), "default bindings have no conflicts %s" % [Controls.all_conflicts().keys()])
	var cats := {}
	for id: String in Controls.ACTIONS:
		cats[str(Controls.ACTIONS[id]["group"])] = true
	check(cats.size() == 10, "ten control categories (%d)" % cats.size())
	check(Controls.key_name("pause") == "ESC" and Controls.key_name("quicksave") == "F5" and not Controls.is_mouse(KEY_ESCAPE), "special keys stay keys (ESC, F5)")
	check(InputMap.action_has_event(&"inspect", Controls.event_for(Controls.mouse(MOUSE_BUTTON_MIDDLE))), "mouse buttons are bindable (inspect on MMB)")
	# Conflict detection respects context: 1 is a tool in surgery and an answer in dialogue.
	check(Controls.conflicts_for("dialogue_1", KEY_1).is_empty(), "surgery and dialogue keys don't clash")
	check(Controls.conflicts_for("journal", KEY_I) == ["inventory"], "global keys clash")
	var hit := Controls.rebind("journal", KEY_I, 0, "keep")
	check(hit == ["inventory"] and Controls.all_conflicts().has("journal"), "duplicate kept and reported")
	Controls.reset_action("journal")
	check(Controls.is_default("journal") and Controls.all_conflicts().is_empty(), "reset a single binding")
	Controls.rebind("journal", KEY_I, 0, "swap")
	check(Controls.get_slots("inventory")[0] == KEY_J and Controls.get_slots("journal")[0] == KEY_I, "swap moves the old key over")
	Controls.rebind("tool_next", Controls.mouse(MOUSE_BUTTON_RIGHT), 1)
	check(Controls.code_name(Controls.get_slots("tool_next")[1]) == "RMB" and InputMap.action_has_event(&"tool_next", Controls.event_for(Controls.mouse(MOUSE_BUTTON_RIGHT))), "bind a mouse button to an action")
	Controls.rebind("move_up", KEY_I, 0, "keep")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_I
	check(InputMap.action_has_event(&"ui_up", ev), "menus follow the movement bindings")
	Controls.clear_slot("quick_coag", 0)
	check(Controls.get_keys("quick_coag").is_empty(), "a binding slot can be cleared")
	Controls.reset_bindings()
	check(Controls.get_slots("inventory")[0] == KEY_I and not InputMap.action_has_event(&"ui_up", ev), "reset all bindings")


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
	check(ClinicManager.tier == 0 and ClinicManager.clinic_id() == "backalley", "start in the back-alley room")
	check(ClinicManager.get_upgrade_block_reason() != "", "next clinic blocked at start")
	EconomyManager.add_money(1000)
	ProgressionManager.add_xp(ProgressionManager.xp_required_for_level(2))
	ReputationManager.change(5)
	check(ClinicManager.upgrade() and ClinicManager.tier == 1, "buy and move to the Undercity Clinic")
	check(ClinicManager.get_background_path().contains("undercity"), "clinic art changes with the clinic")
	check(ClinicManager.get_surgery_backdrop_level() == 1, "surgery backdrop improves with the clinic")
	check(ClinicManager.owns(0) and ClinicManager.owns(1), "the old room is still owned")
	check(ClinicManager.move_to(0) and ClinicManager.tier == 0 and ClinicManager.move_to(1), "move between owned clinics")
	# Upgrades: slots, levels, modifiers, overlays.
	EconomyManager.add_money(5000)
	var prec := ModifierManager.value(&"surgery.precision")
	check(ClinicManager.install(&"surgery") and ClinicManager.upgrade_level(&"surgery") == 1, "install a surgery upgrade")
	check(ModifierManager.value(&"surgery.precision") > prec, "upgrade modifiers apply")
	check(ClinicManager.get_overlays().size() == 1, "installed upgrade has a room overlay")
	for o: Dictionary in ClinicManager.get_overlays():
		check(ResourceLoader.exists(str(o["path"])), "overlay sprite exists")
	var all_ok := true
	for cid: String in ["backalley", "undercity", "industrial", "nightmarket", "professional", "corporate", "elite"]:
		for cat in ClinicManager.CATEGORIES:
			for lv in 3:
				if not ClinicManager.overlays.has("%s/%s/%d" % [cid, cat, lv + 1]):
					all_ok = false
	check(all_ok, "every clinic x category x level has an overlay")
	check(ClinicManager.install(&"security") and ClinicManager.security_rating() == int(ClinicManager.get_tier_data()["security"]) + 1, "security upgrade raises security")
	ClinicManager.install(&"customer")
	ClinicManager.install(&"diagnostics")
	ClinicManager.install(&"staff")
	check(ClinicManager.used_slots() == 5 and ClinicManager.install_block_reason(&"surgery") != "", "upgrade slots are limited (5 at the Undercity Clinic)")
	check(ClinicManager.install_block_reason(&"black_market") != "", "no free slot for black market gear")
	# Save round trip + legacy migration.
	var d := ClinicManager.get_save_data()
	ClinicManager.reset_state()
	ClinicManager.load_save_data(d)
	check(ClinicManager.tier == 1 and ClinicManager.upgrade_level(&"surgery") == 1 and ClinicManager.owns(0), "clinics and upgrades persist")
	ClinicManager.load_save_data({"tier": 3})
	check(ClinicManager.clinic_id() == "professional", "legacy tier 3 maps to the Old Caldera Practice")
	ClinicManager.load_save_data({"tier": 5})
	check(ClinicManager.clinic_id() == "elite" and ClinicManager.owns(0), "legacy tier 5 maps to the elite facility")
	SaveManager.reset_all()


func _staff() -> void:
	SaveManager.reset_all()
	StaffManager.refresh_candidates()
	check(StaffManager.candidates.size() >= 3, "hiring board has candidates")
	var c0: Dictionary = StaffManager.candidates[0]
	check(CharacterArt.validate(c0["appearance"]).is_empty(), "candidate portrait renders %s" % [CharacterArt.validate(c0["appearance"])])
	check(int(c0["salary"]) > 0 and StaffManager.specializations.has(str(c0["specialization"])), "candidate has salary and specialization")
	check(StaffManager.hire_block_reason(c0) != "", "no staff room in the back-alley room")
	# Move to the Undercity clinic (1 staff) and hire Teo.
	EconomyManager.add_money(5000)
	ClinicManager.owned.append(1)
	ClinicManager.move_to(1)
	BusinessManager.day = 2
	StaffManager.refresh_candidates()
	check(StringName(str(StaffManager.candidates[0]["id"])) == &"teo_marr", "Teo Marr is offered from day 2")
	check(StaffManager.hire(0) and StaffManager.count() == 1, "hire Teo")
	check(StaffManager.hire_block_reason(StaffManager.candidates[0]) != "", "capacity reached at 1")
	var teo := StaffManager.get_employee(&"teo_marr")
	# Ethics: no chrome into kids.
	var kid := CustomerManager.generator.generate({"archetype": "scavenger", "category": "dermal"})
	kid.age = 16
	check(EmployeeAI.refusal(teo, kid).contains("kid"), "Teo refuses to operate on a minor")
	check(StaffManager.assign(&"teo_marr", kid)["refused"], "assignment refused without insisting")
	var loyal := float(teo["loyalty"])
	var r := StaffManager.assign(&"teo_marr", kid, true)
	check(not r["refused"] and float(teo["loyalty"]) < loyal and StoryManager.has_flag(&"teo_crossed_line"), "insisting costs loyalty and Teo remembers")
	# Odds: specialization and difficulty matter.
	var limb := StaffManager.generate_candidate("cyber_limb")
	var neuro := StaffManager.generate_candidate("neural")
	for e: Dictionary in [limb, neuro]:
		e["skill"] = 3
		e["precision"] = 3
		e["reliability"] = 3
		e["stress"] = 0.0
		e["traits"] = []
	var arm := CustomerManager.generator.generate({"category": "arms"})
	arm.hidden_conditions.clear()
	check(EmployeeAI.success_chance(limb, arm) > EmployeeAI.success_chance(neuro, arm), "limb specialist is better at arms")
	limb["stress"] = 90.0
	var stressed := EmployeeAI.success_chance(limb, arm)
	limb["stress"] = 0.0
	check(stressed < EmployeeAI.success_chance(limb, arm), "stress lowers the odds")
	# Growth shows on the face.
	teo["xp"] = 0
	StaffManager._gain_xp(teo, 60 * 2 + 1)
	check(int(teo["skill"]) == 3 and str(teo["appearance"]["outfit"]) == "ripperdoc", "skill 3 earns a ripperdoc coat")
	check(str(CharacterManager.appearance(&"teo_marr")["outfit"]) == "ripperdoc", "Teo's story portrait changes too")
	# Days: stress recovers, salary paid.
	teo["stress"] = 50.0
	teo["jobs_today"] = 0
	var money := EconomyManager.money
	BusinessManager.end_day()
	check(float(teo["stress"]) < 50.0, "a quiet day lowers stress")
	check(EconomyManager.money < money and int(BusinessManager.last_report()["ledger"].get(&"salaries", 0)) < 0, "salaries are paid at night")
	# Staff-run clinic earns money.
	ClinicManager.upgrades["backalley"] = {"staff": 1}
	check(StaffManager.transfer(&"teo_marr", 0), "staff upgrade makes room in the back alley")
	BusinessManager.end_day()
	check(int(BusinessManager.last_report()["ledger"].get(&"staff_revenue", 0)) >= 0 and str(BusinessManager.last_report()["notes"]).contains("Back-Alley"), "the back-alley room runs without you")
	var d := StaffManager.get_save_data()
	StaffManager.reset_state()
	StaffManager.load_save_data(d)
	check(StaffManager.get_employee(&"teo_marr").get("skill", 0) == 3, "staff persist")
	check(StaffManager.fire(&"teo_marr") and StoryManager.has_flag(&"teo_gone"), "firing Teo is remembered")
	SaveManager.reset_all()


func _story() -> void:
	SaveManager.reset_all()
	var was_running := GameManager.is_running
	GameManager.is_running = true
	# Content integrity: every option points at a real node, every dialogue
	# speaker is cast, every beat's talk/quest/comms exists.
	var bad: Array[String] = []
	for id: Variant in DialogueManager.dialogues:
		var d: Dictionary = DialogueManager.dialogues[id]
		if not CharacterManager.has_character(StringName(str(d["character"]))):
			bad.append("%s speaker" % id)
		for nid: Variant in d["nodes"]:
			var nd: Dictionary = d["nodes"][nid]
			for o: Variant in nd.get("options", []):
				for k: String in ["next", "fail_next"]:
					if o.has(k) and not d["nodes"].has(str(o[k])):
						bad.append("%s/%s -> %s" % [id, nid, o[k]])
				var q: Variant = o.get("effects", {}).get("quest", "")
				if str(q) != "" and not QuestManager.quests.has(StringName(str(q))):
					bad.append("%s quest %s" % [id, q])
	for b: Variant in StoryManager.beats:
		for a: Variant in b["do"]:
			if a.has("talk") and not DialogueManager.has_dialogue(StringName(str(a["talk"]))):
				bad.append("beat talk %s" % a["talk"])
			if a.has("quest") and not QuestManager.quests.has(StringName(str(a["quest"]))):
				bad.append("beat quest %s" % a["quest"])
			if a.has("comms") and not CommsManager.templates.has(str(a["comms"])):
				bad.append("beat comms %s" % a["comms"])
	check(bad.is_empty(), "story content is consistent %s" % [bad])
	check(DialogueManager.dialogues.size() >= 20 and QuestManager.quests.size() >= 20, "20+ conversations and quests")
	var types := {}
	for id: StringName in QuestManager.quests:
		types[str(QuestManager.quests[id]["type"])] = true
	check(types.size() == 7, "all seven quest types are used")
	# Beats: day-1 quests start, Ilse wants to talk after the first job.
	StoryManager.check()
	check(QuestManager.is_active(&"q_find_wire") and QuestManager.is_active(&"q_fit_out"), "act I opening quests start")
	EventManager.operations = 1
	StoryManager.check()
	check(StoryManager.peek_talk() == &"d_ilse_intro", "Ilse comes to talk after the first job")
	# Dialogue: plain choice with effects, node expressions, quest start.
	check(DialogueManager.start(StoryManager.pop_talk()), "conversation starts")
	check(str(DialogueManager.current_node()["expr"]) == "neutral" and DialogueManager.options().size() == 3, "first line with three approaches")
	DialogueManager.choose(0)
	var rel := CharacterManager.relationship(&"ilse_hartmann")
	var r := DialogueManager.choose(1)
	check(not r.is_empty() and DialogueManager.is_active(), "branching continues")
	while DialogueManager.is_active() and not DialogueManager.options().is_empty():
		DialogueManager.choose(int(DialogueManager.options()[0]["index"]))
	while DialogueManager.is_active():
		DialogueManager.advance()
	check(StoryManager.has_flag(&"ilse_promise") and QuestManager.is_active(&"q_mentor_lessons"), "promise recorded and quest started")
	check(CharacterManager.relationship(&"ilse_hartmann") > rel and DialogueManager.choices.size() >= 2, "relationship changed; choices logged")
	# Checks: odds come from the world.
	DialogueManager.start(&"d_mother_protection")
	var intim := {"kind": "intimidate"}
	var low := DialogueManager.chance(intim)
	FactionManager.add_heat(60.0)
	check(DialogueManager.chance(intim) > low, "heat makes intimidation likelier")
	var bribe_opt := {"kind": "bribe", "cost": {"money": 99999}}
	check(DialogueManager.lock_reason(bribe_opt) != "", "can't bribe without the money")
	DialogueManager.end()
	# Delayed consequence: a choice schedules a conversation days later.
	StoryManager.apply_effects({"consequence": {"id": "d_landlord_enforcer", "days": 2}})
	BusinessManager.end_day()
	check(not StoryManager.talk_queue.has("d_landlord_enforcer"), "not yet")
	BusinessManager.end_day()
	check(StoryManager.talk_queue.has("d_landlord_enforcer"), "the consequence arrives two days later")
	# Quests complete against the world and pay out.
	var money := EconomyManager.money
	EventManager.operations = 3
	StoryManager.check()
	check(QuestManager.state_of(&"q_mentor_lessons") == "completed" and ProgressionManager.total_xp > 0, "quest completes and rewards")
	QuestManager.start(&"q_wire_courier")
	BusinessManager.day += 10
	QuestManager.check_all()
	check(QuestManager.state_of(&"q_wire_courier") == "failed", "deadline quests can fail")
	# Acts advance on their conditions.
	StoryManager.set_flag(&"bm_access")
	ReputationManager.change(20)
	StoryManager.check()
	check(StoryManager.act >= 2, "act II: reputation")
	check(CommsManager.inbox.size() > 0 and CommsManager.unread_count() > 0, "comms arrive with the story")
	# Contracts: actions apply effects once.
	var uid := CommsManager.send(&"c_contract_dune")
	check(CommsManager.act(uid, 0) and StoryManager.has_flag(&"dune_partner"), "signing a contract applies it")
	check(not CommsManager.act(uid, 1), "a contract resolves once")
	# Endings: only the paths you walked.
	check(not StoryManager.ending_available(&"investigator"), "no tribunal without evidence")
	StoryManager.apply_effects({"flag": "evidence_given", "path": {"investigator": 3}})
	check(StoryManager.ending_available(&"investigator") and StoryManager.ranked_endings()[0] == &"investigator", "the investigator ending opens")
	# Save round trip of story state.
	var sd := StoryManager.get_save_data()
	var qd := QuestManager.get_save_data()
	var cd := CommsManager.get_save_data()
	StoryManager.reset_state()
	QuestManager.reset_state()
	CommsManager.reset_state()
	StoryManager.load_save_data(sd)
	QuestManager.load_save_data(qd)
	CommsManager.load_save_data(cd)
	check(StoryManager.act >= 2 and StoryManager.path_score(&"investigator") == 3 and QuestManager.state_of(&"q_mentor_lessons") == "completed" and CommsManager.inbox.size() > 0, "story, quests and comms persist")
	GameManager.is_running = was_running
	SaveManager.reset_all()


## Simulates a whole campaign: every day the clinic works, every
## conversation is answered (strategy 0 = first option, 1 = last), and
## the world grows. The story must reach Act V and an ending.
func _story_playthrough(strategy: int) -> void:
	SaveManager.reset_all()
	var was_running := GameManager.is_running
	GameManager.is_running = true
	var talks := 0
	ClinicManager.owned.append(1)
	for day in 45:
		EventManager.operations += 3
		EconomyManager.add_money(700, &"revenue")
		ReputationManager.change(2)
		ProgressionManager.add_xp(80)
		if day == 8:
			StoryManager.set_flag(&"bm_access")
		StoryManager.check()
		var guard := 0
		while StoryManager.has_talk() and guard < 20:
			guard += 1
			DialogueManager.start(StoryManager.pop_talk())
			talks += 1
			var steps := 0
			while DialogueManager.is_active() and steps < 30:
				steps += 1
				var opts := DialogueManager.options().filter(func(o: Dictionary) -> bool: return str(o["locked"]) == "")
				if opts.is_empty():
					DialogueManager.advance()
				else:
					DialogueManager.choose(int(opts[0 if strategy == 0 else opts.size() - 1]["index"]))
		if StoryManager.ending != &"":
			break
		BusinessManager.end_day()
	check(StoryManager.act == 5, "playthrough %d reaches Act V (act %d, day %d)" % [strategy, StoryManager.act, BusinessManager.day])
	check(StoryManager.ending != &"", "playthrough %d reaches an ending (%s after %d conversations)" % [strategy, StoryManager.ending, talks])
	GameManager.is_running = was_running
	SaveManager.reset_all()


func _business_and_world() -> void:
	SaveManager.reset_all()
	check(BusinessManager.day == 1 and BusinessManager.capacity() == 3, "day 1, three jobs a day in the back alley")
	EconomyManager.add_money(200, &"revenue")
	EconomyManager.spend(70, &"supplies")
	check(int(BusinessManager.today.get(&"revenue", 0)) == 200 and int(BusinessManager.today.get(&"supplies", 0)) == -70, "ledger records categories")
	for i in 3:
		BusinessManager.record_job()
	check(BusinessManager.is_day_full(), "day is full after capacity jobs")
	var money := EconomyManager.money
	var bill := BusinessManager.projected_total()
	check(bill == 30, "back-alley nightly bill is rent 20 + running 10")
	var rep := BusinessManager.end_day()
	check(BusinessManager.day == 2 and BusinessManager.jobs_today == 0, "closing starts day 2")
	check(EconomyManager.money == money - bill, "rent and running costs are paid")
	check(int(rep["ledger"].get(&"rent", 0)) == -20 and int(rep["profit"]) == 200 - 70 - 30, "night report shows rent and profit")
	EconomyManager.spend(EconomyManager.money)
	BusinessManager.end_day()
	check(BusinessManager.debt == 30, "unpaid bills become debt")
	BusinessManager.end_day()
	check(BusinessManager.debt > 60, "debt accrues interest")
	EconomyManager.add_money(500)
	BusinessManager.pay_debt()
	check(BusinessManager.debt == 0, "debt can be paid off")
	var d := BusinessManager.get_save_data()
	BusinessManager.reset_state()
	BusinessManager.load_save_data(d)
	check(BusinessManager.day == 4 and BusinessManager.history.size() == 3, "business days persist")
	# World
	check(WorldManager.districts.size() == 7, "7 districts")
	check(WorldManager.current_district_id() == &"undercity", "start in the Sump (Undercity)")
	check(WorldManager.customer_weight("addict") > WorldManager.customer_weight("executive"), "Undercity draws addicts, not executives")
	check(not WorldManager.is_district_unlocked(&"corporate"), "corporate district locked at start")
	WorldManager.add_influence()
	check(WorldManager.get_influence(&"undercity") == 1, "work builds district influence")
	var gen := CustomerGenerator.new()
	var execs := 0
	for i in 200:
		var c := gen.generate()
		if c.archetype_id in [&"corporate", &"executive"]:
			execs += 1
	check(execs < 30, "few corporate walk-ins in the Sump (%d/200)" % execs)
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


func _save_v4() -> void:
	SaveManager.reset_all()
	# A v3 (previous release) save: six-tier clinic, none of the new systems.
	var v3 := {"version": 3, "saved_at": 0, "systems": {
		"EconomyManager": {"money": 4321}, "ReputationManager": {"reputation": 30},
		"ProgressionManager": {"total_xp": 900, "level": 5, "customers_served": 20, "surgery_records": {}},
		"ClinicManager": {"tier": 3}, "EventManager": {"operations": 20}, "TutorialManager": {"completed": true}}}
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v3))
	f.close()
	check(SaveManager.load_game(), "v3 save loads")
	check(EconomyManager.money == 4321 and ClinicManager.clinic_id() == "professional" and ClinicManager.owns(0), "v3 tier 3 becomes the Old Caldera Practice (back alley kept)")
	check(BusinessManager.day == 1 and StaffManager.count() == 0 and StoryManager.act == 1 and QuestManager.states.is_empty(), "new systems start fresh on an old save")
	# Everything new round-trips through a real save file.
	var was := GameManager.is_running
	GameManager.is_running = true
	EconomyManager.add_money(5000)
	ClinicManager.install(&"security")
	BusinessManager.record_job()
	BusinessManager.end_day()
	BusinessManager.debt = 77
	WorldManager.add_influence(&"oldcity", 4)
	StaffManager.refresh_candidates()
	StaffManager.hire(0)
	var hired := str(StaffManager.employees[0]["id"]) if StaffManager.count() > 0 else ""
	CharacterManager.apply_appearance_event(&"rook_varga", "lose_eye")
	CharacterManager.change_relationship(&"vesna_kalo", 25)
	StoryManager.set_flag(&"bm_access")
	StoryManager.schedule_consequence(&"d_dune_sabotage", 3)
	StoryManager.add_path(&"kingpin", 2)
	StoryManager.bump(&"bm_sell", 2)
	QuestManager.start(&"q_undermarket_trade")
	CommsManager.send(&"c_act2")
	DialogueManager.start(&"d_wire_contract")
	DialogueManager.choose(2)
	Settings.bindings = {}
	var wire_rel := CharacterManager.relationship(&"vesna_kalo")
	check(SaveManager.save_game(&"manual"), "v4 save written")
	SaveManager.reset_all()
	check(SaveManager.load_game(), "v4 save loads")
	check(ClinicManager.upgrade_level(&"security") == 1 and BusinessManager.day == 2 and BusinessManager.debt == 77, "clinic upgrades and business days persist")
	check(WorldManager.get_influence(&"oldcity") == 4, "district influence persists")
	check(hired == "" or not StaffManager.get_employee(StringName(hired)).is_empty(), "employees persist")
	check((CharacterManager.appearance(&"rook_varga")["cyber"] as Array).has("optic") and CharacterManager.relationship(&"vesna_kalo") == wire_rel, "character appearance changes and relationships persist")
	check(StoryManager.has_flag(&"bm_access") and StoryManager.pending.size() == 1 and StoryManager.path_score(&"kingpin") >= 2 and StoryManager.counter(&"bm_sell") == 2, "flags, pending consequences, paths and counters persist")
	check(QuestManager.is_active(&"q_undermarket_trade") and CommsManager.inbox.size() >= 1 and DialogueManager.choices.size() >= 1, "quests, comms and dialogue choices persist")
	var raw := FileAccess.get_file_as_string(SaveManager.save_path)
	check(raw.contains("\"version\": %d" % GameConfig.SAVE_VERSION) and GameConfig.SAVE_VERSION == 4, "save is versioned (v4)")
	GameManager.is_running = was
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
	check(ClinicManager.clinic_id() == "undercity", "v1 clinic becomes the Undercity Clinic")
	check(EventManager.operations == 3, "v1 operation count derived")
	check(CustomerManager.current_customer != null and CustomerManager.current_customer.character_id == &"juno_reyes", "v1 waiting customer restored")
	SaveManager.delete_save()
	CustomerManager.reset_state()
