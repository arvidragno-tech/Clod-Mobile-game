extends Node
## Automated tests. Runs unit/system tests (tests/unit_tests.gd), then plays
## the game end-to-end by injecting real mouse and keyboard events (clicks,
## drags, holds, hotkeys) into the viewport, exactly like a PC player would.
##
## Headless:   godot --headless --path . res://tests/test_runner.tscn -- --viewport=1920x1080
## With shots: xvfb-run godot --path . --rendering-driver opengl3 --resolution 1920x1080 \
##               res://tests/test_runner.tscn -- --shots=/abs/dir
## Exit code 0 = all passed.

const TEST_SAVE_PATH := "user://test_savegame.json"
const TEST_SAVE_DIR := "user://test_saves"
const STEP_TIMEOUT := 20.0
const DRAG_STEP_PX := 6.0
const UnitTests := preload("res://tests/unit_tests.gd")
const LivingWorldTests := preload("res://tests/living_world_tests.gd")
const LivingCityTests := preload("res://tests/living_city_tests.gd")
const UiOverhaulTests := preload("res://tests/ui_overhaul_tests.gd")
const UxTests := preload("res://tests/ux_tests.gd")
const QualityTests := preload("res://tests/quality_tests.gd")
const OnboardingTests := preload("res://tests/onboarding_tests.gd")
const IntakeTests := preload("res://tests/intake_tests.gd")
const Clinic310Tests := preload("res://tests/clinic_310_tests.gd")
const NarrativeTests := preload("res://tests/narrative_tests.gd")
const ReactiveTests := preload("res://tests/reactive_tests.gd")
const DialogueSaveTests := preload("res://tests/dialogue_save_tests.gd")
const EventQueueTests := preload("res://tests/event_queue_tests.gd")
const PreviewAccuracyTests := preload("res://tests/preview_accuracy_tests.gd")
const ResourceCostTests := preload("res://tests/resource_cost_tests.gd")
const PaymentTests := preload("res://tests/payment_tests.gd")
const OwnershipTests := preload("res://tests/ownership_tests.gd")
const SaveFixtureTests := preload("res://tests/save_fixture_tests.gd")

var _failures: Array[String] = []
var _dilemmas_seen: bool = false
var _checks: int = 0
var _shots_dir: String = ""
var _shot_index: int = 0
var _main: Node
var _handling_complication: bool = false


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	# Pin the logical viewport (headless windows are 64x64). The design canvas
	# is 1920x1080; smaller sizes emulate a window at that resolution.
	var viewport_size := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir)
		elif arg.begins_with("--viewport="):
			var parts := arg.trim_prefix("--viewport=").split("x")
			viewport_size = Vector2i(int(parts[0]), int(parts[1]))
	get_tree().root.content_scale_size = viewport_size
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await get_tree().process_frame
	print("viewport: ", get_viewport().get_visible_rect().size)
	SaveManager.save_dir = TEST_SAVE_DIR
	_clear_test_slots()
	SaveManager.save_path = TEST_SAVE_PATH
	SurgeryScreen.pause_on_suspend = false
	SaveManager.delete_save()
	await _run_all()


func _run_all() -> void:
	print("== UNIT / SYSTEM TESTS ==")
	UnitTests.new().run(self)
	print("== LIVING WORLD TESTS ==")
	LivingWorldTests.new().run(self)
	LivingCityTests.new().run(self)
	UiOverhaulTests.new().run(self)
	UxTests.new().run(self)
	QualityTests.new().run(self)
	OnboardingTests.new().run(self)
	IntakeTests.new().run(self)
	Clinic310Tests.new().run(self)
	NarrativeTests.new().run(self)
	ReactiveTests.new().run(self)
	DialogueSaveTests.new().run(self)
	EventQueueTests.new().run(self)
	PreviewAccuracyTests.new().run(self)
	ResourceCostTests.new().run(self)
	PaymentTests.new().run(self)
	OwnershipTests.new().run(self)
	SaveFixtureTests.new().run(self)
	if OS.get_cmdline_user_args().has("--unit-only"):
		_finish()
		return
	# Scripted surgeries stay deterministic; dilemmas get their own probe.
	SurgicalDilemmas.enabled = false
	print("== END-TO-END ==")
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _e2e()
	_finish()


func _finish() -> void:
	SaveManager.delete_save()
	_clear_test_slots()
	AudioManager.stop_all()
	await _frames(10)
	print("")
	if _failures.is_empty():
		print("ALL TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("FAILURES (%d of %d checks):" % [_failures.size(), _checks])
		for f in _failures:
			print("  - " + f)
		get_tree().quit(1)


func _clear_test_slots() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	for f in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute("%s/%s" % [TEST_SAVE_DIR, f])


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   " + message)
	else:
		print("  FAIL " + message)
		_failures.append(message)


# =============================================================================
# End-to-end scenarios
# =============================================================================

func _e2e() -> void:
	await _wait_screen(UIManager.SCREEN_MAIN_MENU)
	await _checkpoint("main_menu")
	await _click_named("NewGameButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	# Deterministic: no random incidents while scripted scenarios run.
	EventManager.history.clear()
	var start_money := EconomyManager.money
	var start_xp := ProgressionManager.total_xp
	var tutorial_seen: Array[String] = []
	TutorialManager.step_changed.connect(func(s: Dictionary) -> void: tutorial_seen.append(str(s["id"])))
	check(TutorialManager.is_active(), "new game starts the tutorial")
	var waited := 0.0
	while not CustomerManager.has_customer() and waited < 8.0:
		await _seconds(0.2)
		waited += 0.2
	check(CustomerManager.has_customer() and CustomerManager.current_customer.character_id == &"mara_quill", "tutorial: first patient is the scripted easy job")
	await _frames(10)
	check(_find_visible("CoachCard") != null, "tutorial: coach mark shown in the clinic")
	if not TutorialManager.current_step().is_empty():
		tutorial_seen.append(str(TutorialManager.current_step()["id"]))
	await _checkpoint("tutorial_clinic")

	# Run 1: the tutorial job (Step 1 neural slice), played cleanly.
	var r1 := await _play_customer(&"mara_quill", false)
	check(r1 != null and r1.success, "run 1: neural implant succeeded")
	check(_surgery_audio.get("profile", &"") == &"surgery" and _surgery_audio.get("music", &"") == &"surgery" and bool(_surgery_audio.get("layers", {}).get(&"hum", false)), "surgery switches to the surgery music and ambience mix")
	if r1:
		print("     run 1 grade=%s score=%.2f pay=%d xp=%d mistakes=%d time=%.0fs complications=%d/%d" % [r1.grade, r1.score, r1.pay, r1.xp, r1.mistakes, r1.elapsed_sec, r1.complications_handled, r1.complications_total])
		check(r1.grade in ["S", "A", "B"], "run 1: clean play grades B or better (%s)" % r1.grade)
		check(r1.complications_total == 0, "run 1: tutorial job has no complications")
	await _wait_results_ready()
	await _checkpoint("results_clean")
	await _click_named("ContinueButton", 10.0)
	await _after_results()
	check(EconomyManager.money > start_money and ProgressionManager.total_xp > start_xp, "money and XP increased")
	await _frames(10)
	for id in ["arrive", "intake", "diagnose", "plan", "tools", "cut", "install", "close", "payment", "upgrade"]:
		check(tutorial_seen.has(id), "tutorial step '%s' shown" % id)
	await _checkpoint("tutorial_upgrade")
	check(SaveManager.has_save(), "game autosaved after surgery")

	# Run 2: sloppy, wrong diagnosis, deliberate mistakes.
	var r2 := await _play_customer(&"hollis_brandt", true)
	check(r2 != null and r2.success, "run 2: sloppy operation still completed")
	if r2:
		print("     run 2 grade=%s score=%.2f mistakes=%d health=%.0f neural=%.0f" % [r2.grade, r2.score, r2.mistakes, r2.final_health, r2.final_neural])
		check(r2.mistakes >= 4, "run 2: mistakes registered (%d)" % r2.mistakes)
		check(r1 == null or r2.score < r1.score, "run 2: mistakes lowered the score")
	await _click_named("ContinueButton", 10.0)
	await _after_results()

	# Run 3: arm install needs a drill we don't have -> buy it -> anchors.
	EconomyManager.add_money(1500)
	var arm := CustomerManager.generator.generate({"cyberware": "liftwell_arm", "archetype": "dock_worker"})
	arm.hidden_conditions.clear()
	arm.risk_tolerance = 0.9  # consent is covered by unit tests; keep this run deterministic
	CustomerManager.debug_set_customer(arm)
	InventoryManager.add_implant(&"liftwell_arm")
	await _to_plan(arm.true_diagnosis_id)
	var begin := _find_visible("BeginButton") as Button
	check(begin != null and begin.disabled, "insufficient tools: BEGIN disabled without a drill")
	await _checkpoint("plan_missing_drill")
	await _click_named("BackButton")  # plan -> scan (3.12: BACK is the one way back)
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _click_named("Nav_supply")
	await _wait_screen(UIManager.SCREEN_SHOP)
	await _click_named("ShopTab_1")
	await _checkpoint("shop_tools")
	await _click_named("BuyTool_cyber_drill")
	check(InventoryManager.has_tool_category(&"drill"), "bought the cyber drill through the shop")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	var r3 := await _play_current(false, arm.true_diagnosis_id)
	check(r3 != null and r3.success and r3.surgery_id == &"install_arm", "run 3: arm implant with bone anchors succeeded")
	await _click_named("ContinueButton", 10.0)
	await _after_results()

	# Run 4: abort -> failure path.
	CustomerManager.debug_set_customer(CustomerManager.get_customer(&"juno_reyes"))
	await _to_plan(&"neural_rejection")
	await _click_named("BeginButton")
	await _wait_screen(UIManager.SCREEN_SURGERY)
	await _wait_stage_ready()
	# App suspension freezes the patient until RESUME.
	UIManager.current_screen.pause_operation()
	var t_before := SurgeryManager.elapsed
	await _seconds(0.6)
	check(UIManager.current_screen.is_paused() and is_equal_approx(SurgeryManager.elapsed, t_before), "suspending the app pauses the operation")
	await _checkpoint("surgery_paused")
	await _click_named("ResumeSurgery")
	await _frames(3)
	check(SurgeryManager.is_running, "RESUME continues the operation")
	# Abort asks first, and cancelling keeps the patient on the table.
	await _click_named("AbortButton")
	await _frames(3)
	check(not SurgeryManager.is_running, "abort confirmation freezes vitals")
	await _click_named("AbortCancel")
	await _frames(3)
	check(SurgeryManager.is_active and SurgeryManager.is_running, "cancelling abort keeps operating")
	await _click_named("AbortButton")
	await _click_named("AbortConfirm")
	await _wait_screen(UIManager.SCREEN_RESULTS, 10.0)
	var r4 := GameManager.last_result
	check(r4 != null and not r4.success and r4.grade == "F", "run 4: aborted op is graded F")
	await _wait_results_ready()
	await _checkpoint("results_failed")
	await _click_named("ContinueButton", 10.0)
	await _after_results()

	# Run 5: reckless splicing collapses the neural link.
	var r5 := await _play_customer(&"dez_okafor", false, true)
	check(r5 != null and not r5.success and r5.failure_reason == &"neural_collapse", "run 5: repeated mistakes fail the operation (%s)" % (r5.failure_reason if r5 else &"none"))
	await _click_named("ContinueButton", 10.0)
	await _after_results()

	# Events: the fixer shows up and opens the black market.
	EventManager.queue_event(&"wire_intro")
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _wait_until(func() -> bool: return _find_visible("EventPanel") != null, 5.0)
	await _checkpoint("event_wire")
	await _click_named("Choice_0")
	await _click_named("EventContinue")
	check(BlackMarketManager.is_unlocked(), "event choice unlocked the black market")

	# Black market: buy, study, sell through the UI.
	EconomyManager.add_money(4000)
	InventoryManager.add_parts(6)
	await _click_named("Nav_blackmarket")
	await _wait_screen(UIManager.SCREEN_BLACK_MARKET)
	await _frames(20)
	await _checkpoint("black_market")
	var units := InventoryManager.get_instances().size()
	await _click_named("BMBuy_0")
	check(InventoryManager.get_instances().size() == units + 1, "bought black-market chrome")
	await _click_named("BMTab_1")
	await _checkpoint("black_market_stash")
	var stash := InventoryManager.get_instances()
	var idx := -1
	for i in stash.size():
		if stash[i].has_unknown_traits():
			idx = i
			break
	if idx >= 0:
		await _click_named("Study_%d" % idx)
		check(not stash[idx].revealed.is_empty(), "studied an unknown property via the UI")
	var money := EconomyManager.money
	await _click_named("Sell_0")
	check(EconomyManager.money > money, "sold chrome via the UI")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# Skills
	SkillManager.add_points(1)
	await _click_named("Nav_skills")
	await _wait_screen(UIManager.SCREEN_SKILLS)
	check(TutorialManager.completed and not TutorialManager.is_active(), "tutorial completes when the player opens SKILLS")
	await _checkpoint("skills")
	var rank := SkillManager.get_rank(&"speed")
	await _click_named("Upgrade_speed")
	check(SkillManager.get_rank(&"speed") == rank + 1, "upgraded a skill via the UI")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# Clinic upgrade
	EconomyManager.add_money(int(ClinicManager.get_next_tier().get("cost", 0)))
	ReputationManager.change(maxi(0, int(ClinicManager.get_next_tier().get("min_reputation", 0)) - ReputationManager.reputation))
	while ProgressionManager.level < int(ClinicManager.get_next_tier().get("min_level", 1)):
		ProgressionManager.add_xp(ProgressionManager.get_xp_for_next_level())
	var tier := ClinicManager.tier
	await _click_named("Nav_upgrades")
	await _wait_screen(UIManager.SCREEN_UPGRADES)
	await _checkpoint("upgrades")
	await _click_named("FacilityTab_1")
	await _frames(3)
	await _checkpoint("property")
	await _click_named("UpgradeClinic")
	# 3.7: a new clinic is a big commitment: the preview dialog (when confirms are on).
	if get_tree().root.find_child("ConfirmYes", true, false):
		await _click_named("ConfirmYes")
	check(ClinicManager.tier == tier + 1, "upgraded the clinic via the UI")
	# Facility upgrade (visible overlay in the room).
	await _click_named("FacilityTab_0")
	await _frames(3)
	# Enough for the upgrade whatever the run has earned (events move money).
	var up_cost := int(ClinicManager.upgrade_def(&"surgery", ClinicManager.upgrade_level(&"surgery") + 1).get("cost", 0))
	EconomyManager.add_money(maxi(400, up_cost - EconomyManager.money + 100))
	await _frames(4)
	if ClinicManager.install_block_reason(&"surgery") != "":
		print("    install blocked: ", ClinicManager.install_block_reason(&"surgery"))
	await _click_named("Install_surgery")
	check(ClinicManager.upgrade_level(&"surgery") == 1, "installed a surgery upgrade via the UI")
	await _checkpoint("facility_installed")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _checkpoint("clinic_upgraded")
	# Business ledger and the city map.
	await _click_named("Nav_business")
	await _wait_screen(UIManager.SCREEN_BUSINESS)
	await _checkpoint("business")
	await _key(KEY_M)
	await _wait_screen(UIManager.SCREEN_MAP)
	await _checkpoint("city_map")
	var map := _find_visible("CityMap") as CityMapView
	check(map != null, "city map view present")
	if map:
		var mp: Array = WorldManager.get_district(&"market")["map"]
		await _tap(map.get_global_rect().position + Vector2(float(mp[0]) * 320.0, float(mp[1]) * 180.0).floor() * GameConfig.PIXEL_SCALE)
		check(map.selected == &"market", "clicking a district selects it")
		await _checkpoint("city_map_market")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	# Staff: hire from the board, then delegate a job.
	EconomyManager.add_money(300)
	await _key(KEY_T)
	await _wait_screen(UIManager.SCREEN_STAFF)
	await _frames(4)
	await _checkpoint("staff_hiring")
	await _click_named("Hire_0")
	check(StaffManager.count() == 1, "hired a ripperdoc via the UI")
	await _click_named("StaffTab_0")
	await _frames(3)
	await _checkpoint("staff_team")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	var hire_id := StringName(str(StaffManager.employees[0]["id"]))
	StaffManager.employees[0]["traits"] = []
	StaffManager.employees[0]["ethics"] = []
	var delegate := CustomerManager.generator.generate({"category": "dermal"})
	delegate.age = 30
	CustomerManager.debug_set_customer(delegate)
	await _frames(3)
	GameManager.open_customer()
	await _wait_screen(UIManager.SCREEN_CUSTOMER)
	await _click_named("AssignButton")
	await _frames(3)
	await _checkpoint("customer_assign")
	var jobs_before := BusinessManager.jobs_today
	await _click_named("Assign_%s" % hire_id)
	check(BusinessManager.jobs_today == jobs_before + 1 and not CustomerManager.has_customer(), "assigned a customer to staff via the UI")
	await _checkpoint("assign_result")
	await _click_named("AssignResultClose")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _frames(5)
	if _find_visible("DayReportClose") != null:
		await _checkpoint("day_report")
		await _click_named("DayReportClose")
	# Delegated jobs can trigger incidents like your own do.
	await _after_results()

	# Dossier tabs
	await _click_named("Nav_dossier")
	await _wait_screen(UIManager.SCREEN_DOSSIER)
	await _checkpoint("dossier_factions")
	for i in range(1, 4):
		await _click_named("DossierTab_%d" % i)
		await _checkpoint("dossier_tab_%d" % i)
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# PC: hotkeys, inventory grid, cyberware database, pause menu, quicksave.
	await _key(KEY_I)
	await _wait_screen(UIManager.SCREEN_INVENTORY)
	await _frames(5)
	await _checkpoint("inventory")
	var first := _first_slot()
	check(first != null, "inventory grid shows implant slots")
	if first:
		await _right_click(first.get_global_rect().get_center())
		var ca := _find_visible("CompareA") as ItemSlot
		check(ca != null and not ca.is_empty(), "right-click sets the CURRENT compare slot")
		var slots := _all_slots()
		if slots.size() > 1:
			_drop_on(slots[1], _find_visible("CompareB") as ItemSlot)
			await _frames(3)
			check(_find_visible("Verdict_PERFORMANCE") != null, "dropping a unit on NEW shows the comparison")
		await _checkpoint("inventory_compare")
	await _click_named("InvTab_1")
	await _frames(3)
	check(_find_visible("Slot_tool_starter_scalpel") != null or _first_slot("tool") != null, "TOOLS tab lists instruments")
	await _checkpoint("inventory_tools")
	await _key(KEY_B)
	await _wait_screen(UIManager.SCREEN_DATABASE)
	await _frames(5)
	await _checkpoint("database")
	check(_find_visible("Spec") != null and _find_visible("Compare") != null, "database shows spec sheet and comparison")
	await _key(KEY_ESCAPE)
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _key(KEY_ESCAPE)
	await _frames(5)
	check(UIManager.has_modal() and _find_visible("PauseResume") != null, "ESC on the clinic opens the pause menu")
	await _checkpoint("pause_menu_keyboard")
	await _key(KEY_ESCAPE)
	await _frames(5)
	check(not UIManager.has_modal(), "ESC again closes the pause menu")
	var saved_before := SaveManager.last_saved_unix
	await _key(KEY_F5)
	await _frames(3)
	check(SaveManager.has_save(), "F5 quick-saves (%s)" % SaveManager.save_path)
	await _key(KEY_TAB)
	await _frames(2)
	check(get_viewport().gui_get_focus_owner() != null, "TAB moves keyboard focus into a panel")

	# Detail zoom: double-tap the clinic art, pan, double-tap back.
	await _frames(10)
	var view := _find_visible("ClinicView") as ClinicView
	if view:
		# Empty floor (no prop hotspots there).
		var spot := view.get_global_rect().position + Vector2(view.size.x * 0.25, view.size.y * 0.86)
		await _tap(spot)
		await _tap(spot)
		check(view.zoomed, "double-tap zooms into the clinic art")
		await _checkpoint("clinic_zoom")
		await _drag([spot, spot + Vector2(-60, -30)])
		await _tap(spot)
		await _tap(spot)
		check(not view.zoomed, "double-tap again resets the zoom")
	# Pause menu -> how to play -> settings (sliders, toggles) -> back.
	await _frames(10)
	await _click_named("MenuButton")
	await _frames(10)
	await _checkpoint("pause_menu")
	await _click_named("PauseHelp")
	await _frames(10)
	check(Glossary.is_open(), "the pause menu opens the field guide")
	await _click_named("GuideTopic_surgery")
	await _frames(5)
	check(_find_visible("Guide_neural_load") != null, "the guide's SURGERY topic explains neural load")
	await _checkpoint("field_guide")
	await _click_named("GuideClose")
	await _frames(5)
	check(not Glossary.is_open(), "the field guide closes")
	await _click_named("MenuButton")
	await _frames(5)
	await _click_named("PauseSettings")
	await _wait_screen(UIManager.SCREEN_SETTINGS)
	await _frames(10)
	await _checkpoint("settings")
	var settings_path := Settings.path
	Settings.path = "user://test_settings.cfg"
	await _click_named("SettingsTab_1")
	await _frames(5)
	await _checkpoint("settings_audio")
	var slider := _find_visible("Slider_music_volume") as HSlider
	if slider:
		var r := slider.get_global_rect()
		await _drag([r.position + Vector2(r.size.x * 0.8, r.size.y / 2), r.position + Vector2(r.size.x * 0.2, r.size.y / 2)])
	check(Settings.music_volume < 0.4, "music slider drag changes volume (%.2f)" % Settings.music_volume)
	await _click_named("SettingsTab_2")
	await _frames(5)
	await _checkpoint("settings_controls")
	# Rebind JOURNAL to I through the UI: conflict dialog, then swap.
	await _click_named("Bind_journal_0")
	await _frames(2)
	await _key(KEY_I)
	await _frames(4)
	await _checkpoint("settings_bind_conflict")
	await _click_named("BindSwap")
	await _frames(4)
	check(Controls.get_slots("journal")[0] == KEY_I and Controls.get_slots("inventory")[0] == KEY_J, "rebinding with a conflict swaps via the UI")
	# A mouse button on a second slot.
	await _click_named("Bind_inspect_1")
	await _frames(2)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	get_viewport().push_input(mb, true)
	await _frames(4)
	check(Controls.get_slots("inspect")[1] == Controls.mouse(MOUSE_BUTTON_XBUTTON1) or not Controls.conflicts_for("inspect", Controls.mouse(MOUSE_BUTTON_XBUTTON1)).is_empty(), "mouse button rebinding via the UI")
	# MOUSE 4 is "previous tool" by default: the conflict dialog offers SWAP.
	if _find_visible("BindSwap"):
		await _click_named("BindSwap")
		await _frames(4)
	await _click_named("ResetBindings")
	await _frames(4)
	check(_find_visible("ConfirmYes") != null, "RESET ALL CONTROLS asks first")
	await _click_named("ConfirmYes")
	await _frames(4)
	check(Controls.all_conflicts().is_empty() and Controls.get_slots("journal")[0] == KEY_J, "reset all bindings via the UI")
	await _click_named("SettingsTab_0")
	await _frames(5)
	await _checkpoint("settings_graphics")
	await _click_named("SettingsTab_3")
	await _frames(5)
	await _checkpoint("settings_gameplay")
	await _click_named("Choice_text_speed_3")
	await _frames(5)
	check(Settings.text_speed == 3, "text speed choice works")
	await _click_named("SettingsTab_4")
	await _frames(5)
	var before := Settings.reduce_motion
	await _click_named("Toggle_reduce_motion")
	await _frames(5)
	check(Settings.reduce_motion != before, "reduce-motion toggle works")
	await _click_named("Toggle_large_text")
	await _frames(5)
	await _checkpoint("settings_accessibility")
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = settings_path
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# A generated customer through the whole loop (random archetype).
	var rng_c := CustomerManager.generator.generate({"category": "eyes"})
	rng_c.hidden_conditions.clear()
	rng_c.risk_tolerance = 0.9
	CustomerManager.debug_set_customer(rng_c)
	InventoryManager.add_implant(rng_c.requested_cyberware_id)
	InventoryManager.add_supplies(5)
	var r6 := await _play_current(false, rng_c.true_diagnosis_id)
	check(r6 != null and r6.success and r6.surgery_id == &"install_optic", "run 6: optic implant on a generated customer")
	await _click_named("ContinueButton", 10.0)
	await _after_results()

	# The story happened along the way.
	check(_talks_seen.has("d_ilse_intro"), "Ilse's conversation played in the clinic")
	check(DialogueManager.choices.size() >= 2 and QuestManager.by_state("active").size() + QuestManager.by_state("completed").size() >= 3, "dialogue choices logged, quests running")
	await _key(KEY_J)
	await _wait_screen(UIManager.SCREEN_DOSSIER)
	await _checkpoint("journal_quests")
	await _click_named("DossierTab_1")
	await _checkpoint("journal_comms")
	await _click_named("DossierTab_2")
	await _checkpoint("journal_people")
	await _click_named("DossierTab_6")
	await _checkpoint("journal_story")
	await _click_named("BackButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# Persistence across a simulated relaunch.
	var m := EconomyManager.money
	SaveManager.save_game()
	SaveManager.reset_all()
	check(SaveManager.load_game() and EconomyManager.money == m and ClinicManager.tier == tier + 1, "progress survives reload")


## Puts an authored character at the door and plays the whole loop.
func _play_customer(id: StringName, sloppy: bool, reckless: bool = false) -> SurgeryResult:
	var c := CustomerManager.get_customer(id)
	c.hidden_conditions.clear()
	CustomerManager.debug_set_customer(c)
	InventoryManager.add_implant(c.requested_cyberware_id)
	InventoryManager.add_supplies(3)
	var dx := c.true_diagnosis_id
	if sloppy:
		for option in SurgeryManager.get_surgery(c.requested_surgery_id).diagnosis_options:
			if StringName(str(option["id"])) != dx:
				dx = StringName(str(option["id"]))
				break
	return await _play_current(sloppy, dx, reckless)


var _surgery_audio: Dictionary = {}


func _play_current(sloppy: bool, dx: StringName, reckless: bool = false) -> SurgeryResult:
	GameManager.last_result = null  # never report a previous run's result
	await _to_plan(dx)
	await _click_named("BeginButton")
	await _wait_screen(UIManager.SCREEN_SURGERY)
	_surgery_audio = AudioManager.get_debug_state()
	var stage_count := SurgeryManager.get_stage_count()
	for i in stage_count:
		if not await _wait_stage_ready():
			check(false, "stage %d became ready" % i)
			return null
		var screen := UIManager.current_screen
		var stage: SurgeryStage = screen.current_stage
		var stage_id := stage.stage.id
		await _checkpoint("surgery_%s_%d_%s" % [SurgeryManager.surgery.id, i, stage_id])
		if reckless and stage is ConnectInterfaceStage:
			await _click_named("Tool_splicer")
			var attempts := 0
			# Drags cross more screen pixels at the PC field zoom (slower per
			# attempt), so allow more attempts for the collapse to happen.
			while SurgeryManager.is_active and attempts < 80:
				var wrong: Array = stage.get_autoplay_hints()["wrong"]
				await _drag([_fs(wrong[0]), _fs(wrong[1])], 30.0)
				attempts += 1
			break
		await _play_stage(stage, sloppy)
		var advanced := await _wait_until(func() -> bool: return not SurgeryManager.is_active or SurgeryManager.stage_index > i, STEP_TIMEOUT)
		check(advanced, "%s stage %d (%s) completed" % [SurgeryManager.surgery.id, i, stage_id])
		if not advanced or not SurgeryManager.is_active:
			break
	await _checkpoint("surgery_end")
	await _wait_screen(UIManager.SCREEN_RESULTS, 10.0)
	await _frames(10)
	return GameManager.last_result


## Clinic -> customer -> scan -> diagnosis -> plan.
func _to_plan(dx: StringName) -> void:
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _wait_until(func() -> bool: return CustomerManager.has_customer(), 10.0)
	await _frames(20)
	await _checkpoint("clinic")
	await _click_named("SeeButton")
	# 3.7: the patient summary first; MORE DETAILS opens the full file.
	await _wait_until(func() -> bool: return _find_visible("PatientSummary") != null, 5.0)
	check(_find_visible("PatientSummary") != null, "SEE PATIENT opens the patient summary")
	await _checkpoint("summary")
	await _click_named("SummaryDetails")
	await _click_named("SummaryFile")
	await _wait_screen(UIManager.SCREEN_CUSTOMER)
	await _frames(30)
	await _checkpoint("customer")
	await _click_named("AcceptButton")
	await _wait_screen(UIManager.SCREEN_DIAGNOSIS)
	var scan := UIManager.current_screen.find_child("ScanView", true, false) as ScanView
	var site := GameManager.get_current_surgery().scan_region
	for region: StringName in [site, &"head" if site != &"head" else &"chest"]:
		await _tap(scan.get_global_rect().position + scan.get_region_center(region))
		await _wait_until(func() -> bool: return not scan.is_busy(), 3.0)
	await _checkpoint("diagnosis")
	await _click_named("Option_%s" % dx)
	await _click_named("ConfirmButton")
	await _frames(5)
	await _checkpoint("plan")


func _after_results() -> void:
	await _wait_screen(UIManager.SCREEN_CLINIC)
	# Resolve any random incident so scripted runs stay deterministic.
	await _frames(10)
	if _find_visible("EventPanel") != null:
		await _checkpoint("event_random")
		var b := _first_enabled_choice()
		if b:
			await _click(b)
			await _click_named("EventContinue")
	EventManager.pending_event = &""
	UIManager.close_modal()


## Surgical dilemma: take the first available option, then continue.
func _handle_dilemma() -> void:
	if not _dilemmas_seen:
		_dilemmas_seen = true
		await _checkpoint("dilemma")
	for i in 4:
		var b := _find_visible("DilemmaChoice_%d" % i) as Button
		if b and not b.disabled:
			await _click(b)
			break
	await _frames(3)
	var c := _find_visible("DilemmaContinue")
	if c:
		await _click(c)
	await _frames(3)


func _resolve_incident() -> void:
	var b := _first_enabled_choice()
	if b:
		await _click(b)
		await _click_named("EventContinue")
	EventManager.pending_event = &""
	if _find_visible("EventPanel") != null:
		UIManager.close_modal()
	await _frames(3)


func _first_enabled_choice() -> Button:
	for i in 4:
		var b := _find_visible("Choice_%d" % i) as Button
		if b and not b.disabled:
			return b
	return null


func _wait_results_ready() -> void:
	await _wait_until(func() -> bool:
		var b := _find_visible("ContinueButton") as Button
		return b != null and not b.disabled, 10.0)


func _wait_stage_ready() -> bool:
	return await _wait_until(func() -> bool:
		var screen := UIManager.current_screen
		if UIManager.current_screen_id != UIManager.SCREEN_SURGERY or UIManager.is_transitioning():
			return false
		var stage: SurgeryStage = screen.current_stage
		return stage != null and not stage.is_finished and stage.stage == SurgeryManager.get_current_stage(), STEP_TIMEOUT)


## Field (pixel viewport) coordinate -> screen coordinate.
func _fs(p: Vector2) -> Vector2:
	return UIManager.current_screen.field_to_screen(p)


func _play_stage(stage: SurgeryStage, sloppy: bool) -> void:
	if stage.requires_tool():
		if sloppy and stage.stage.id == &"incision":
			await _click_named("Tool_retractor")
			await _tap(_fs(stage.get_autoplay_hints()["path"][0]))
		await _click_named("Tool_%s" % stage.stage.tool_category)
	if stage is AnesthesiaStage:
		var h := stage.get_autoplay_hints()
		var target: float = (float(h["zone_min"]) + float(h["zone_max"])) / 2.0
		var button: Button = h["button"]
		await _press(button.get_global_rect().get_center())
		await _wait_until(func() -> bool: return (stage as AnesthesiaStage).dose >= target - 1.0, 10.0)
		await _release(button.get_global_rect().get_center())
	elif stage is IncisionStage:
		var pts: Array[Vector2] = []
		for p: Vector2 in stage.get_autoplay_hints()["path"]:
			pts.append(_fs(p))
		if sloppy:
			pts.insert(2, pts[1] + Vector2(40, 30))
		await _drag(pts)
	elif stage is ExposeStage:
		if sloppy:
			await _tap(_fs(stage.site.to_local_pos(Vector2(0.5, 0.2))) + Vector2(60, 0))
		for p: Vector2 in stage.get_autoplay_hints()["targets"]:
			await _tap(_fs(p))
	elif stage is RemoveTissueStage:
		var burn_time: float = stage.get_autoplay_hints()["burn_time"]
		for p: Vector2 in stage.get_autoplay_hints()["targets"]:
			await _press(_fs(p))
			await _seconds(burn_time + 0.15)
			await _release(_fs(p))
	elif stage is AnchorDrillStage:
		var drill := stage as AnchorDrillStage
		while is_instance_valid(drill) and not drill.is_finished:
			var h := drill.get_autoplay_hints()
			var targets: Array = h["targets"]
			if targets.is_empty():
				break
			var mid := (float(h["zone_min"]) + float(h["zone_max"])) / 2.0
			await _press(_fs(targets[0]))
			await _wait_until(func() -> bool: return not is_instance_valid(drill) or drill.is_finished or drill.current_depth() >= mid, 5.0)
			await _release(_fs(targets[0]))
			await _frames(3)
	elif stage is InstallImplantStage:
		var h := stage.get_autoplay_hints()
		await _drag([_fs(h["implant"]), _fs(h["socket"])])
		await _frames(3)
		var error: float = stage.get_autoplay_hints()["angle_error_deg"]
		var steps := roundi(absf(error) / (stage as InstallImplantStage).rotate_step_deg())
		var button_name := "RotateLeft" if error > 0.0 else "RotateRight"
		if sloppy:
			steps = maxi(steps - 3, 0)
		for s in steps:
			await _click_named(button_name)
		await _click_named("SeatButton")
	elif stage is ConnectInterfaceStage:
		if sloppy:
			var wrong: Array = stage.get_autoplay_hints()["wrong"]
			await _drag([_fs(wrong[0]), _fs(wrong[1])])
		while is_instance_valid(stage) and not stage.is_finished:
			var pairs: Array = stage.get_autoplay_hints()["pairs"]
			if pairs.is_empty():
				break
			await _drag([_fs(pairs[0][0]), _fs(pairs[0][1])])
			await _frames(2)
	elif stage is CalibrateStage:
		var cal := stage as CalibrateStage
		while is_instance_valid(cal) and not cal.is_finished:
			var h := cal.get_autoplay_hints()
			var slider: TouchSlider = h["slider"]
			var value: float = 0.02 if sloppy else float(h["target"])
			await _tap(slider.get_global_rect().position + Vector2(slider.x_for_value(value), slider.size.y / 2.0))
			await _frames(2)
			await _click(cal.get_autoplay_hints()["lock_button"])
			await _frames(4)
	elif stage is CloseIncisionStage:
		var targets: Array = stage.get_autoplay_hints()["targets"]
		if sloppy and targets.size() > 2:
			await _tap(_fs(targets[2]))
		for p: Vector2 in targets:
			await _tap(_fs(p))


# =============================================================================
# Layout guard + input helpers
# =============================================================================

## Every visible button must be fully on-screen and at least touch-sized.
func _check_layout(label: String) -> void:
	# Screen shake offsets the whole screen for a few frames; measure at rest.
	var waited := 0
	while UIManager.is_shaking() and waited < 60:
		await get_tree().process_frame
		waited += 1
	var view := get_viewport().get_visible_rect().grow(1.0)
	var offenders: Array[String] = []
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		var b := node as Control
		if not b.is_visible_in_tree() or _clipped_by_scroll(b):
			continue
		var r := b.get_global_rect()
		if not view.encloses(r):
			offenders.append("%s off-screen %s" % [b.name, r])
		elif minf(r.size.x, r.size.y) < GameConfig.MIN_CONTROL - 4.0:
			offenders.append("%s too small %s" % [b.name, r.size])
	offenders.append_array(_horizontal_overflow(view))
	check(offenders.is_empty(), "layout ok at '%s' %s" % [label, ", ".join(offenders)])


## Controls wider than the screen (the cause of off-screen buttons). Reports
## the innermost overflowing controls only. Full-bleed art layers whose
## parent clips them are ignored.
func _horizontal_overflow(view: Rect2) -> Array[String]:
	var found: Array[Control] = []
	for node in get_tree().root.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or c.get_viewport() != get_viewport():
			continue
		if c.get_parent() is Control and (c.get_parent() as Control).clip_contents:
			continue
		if _in_horizontal_scroll(c):
			continue
		var r := c.get_global_rect()
		if r.position.x < view.position.x - 1.0 or r.end.x > view.end.x + 1.0:
			found.append(c)
	var out: Array[String] = []
	for c in found:
		var inner := false
		for other in found:
			if other != c and c.is_ancestor_of(other):
				inner = true
				break
		if not inner and out.size() < 4:
			out.append("%s overflows (%s w=%d)" % [c.get_path().get_concatenated_names().right(60), c.get_class(), int(c.size.x)])
	return out


func _in_horizontal_scroll(c: Control) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer and (p as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return true
		p = p.get_parent()
	return false


## Buttons inside scroll areas may legitimately be scrolled out of view.
func _clipped_by_scroll(c: Control) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _handle_complication() -> void:
	var c := SurgeryManager.active_complication
	if _handling_complication or c == null or UIManager.current_screen_id != UIManager.SCREEN_SURGERY:
		return
	var b := UIManager.current_screen.find_child("Quick_%s" % c.counter_action, true, false) as Button
	if b and not b.disabled:
		_handling_complication = true
		await _checkpoint("complication")
		await _click(b)
		_handling_complication = false


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


func _right_click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(1)
	await _frames(2)


func _all_slots(kind: StringName = &"implant") -> Array[ItemSlot]:
	var out: Array[ItemSlot] = []
	for n in get_tree().root.find_children("Slot_*", "Control", true, false):
		var s := n as ItemSlot
		if s and s.kind == kind and s.is_visible_in_tree():
			out.append(s)
	return out


func _first_slot(kind: StringName = &"implant") -> ItemSlot:
	var all := _all_slots(kind)
	return all[0] if not all.is_empty() else null


## Drag & drop through Godot's own DnD path is not injectable headless, so
## call the same drop hook the GUI uses.
func _drop_on(source: ItemSlot, target: ItemSlot) -> void:
	if source == null or target == null:
		check(false, "drag source and target exist")
		return
	var data := {"slot_kind": source.kind, "key": source.key, "source": source}
	check(target._can_drop_data(Vector2.ZERO, data), "compare slot accepts the dragged unit")
	target._drop_data(Vector2.ZERO, data)


func _send_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev, true)


func _send_motion(pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = relative
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(ev, true)


func _press(pos: Vector2) -> void:
	_send_motion(pos, Vector2.ZERO)
	_send_button(pos, true)
	await _frames(1)


func _release(pos: Vector2) -> void:
	_send_button(pos, false)
	await _frames(1)


func _tap(pos: Vector2) -> void:
	await _handle_complication()
	await _press(pos)
	await _release(pos)
	await _frames(2)


func _drag(points: Array[Vector2], step_px: float = DRAG_STEP_PX) -> void:
	await _handle_complication()
	await _press(points[0])
	var last := points[0]
	for i in range(1, points.size()):
		var to := points[i]
		var steps := maxi(int(last.distance_to(to) / step_px), 1)
		for s in range(1, steps + 1):
			var p := last.lerp(to, float(s) / steps)
			_send_motion(p, p - last)
			await _frames(1)
		last = to
	await _release(last)
	await _frames(2)


func _click(control: Control) -> void:
	if control == null:
		check(false, "click target exists")
		return
	var sc := _scroll_parent(control)
	if sc:
		sc.ensure_control_visible(control)
		await _frames(2)
	await _tap(control.get_global_rect().get_center())


func _scroll_parent(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _click_named(node_name: String, timeout: float = STEP_TIMEOUT) -> void:
	# Something the last step set off may open on the clinic at the end of
	# this frame (call_deferred): let it, so the click doesn't land on it.
	await get_tree().process_frame
	# Timed incidents (the supplier at 10:00, a midnight deal...) can pop up
	# on the clinic between scripted steps: resolve them first.
	if not (node_name.begins_with("Choice_") or node_name == "EventContinue") and _find_visible("EventPanel") != null:
		await _resolve_incident()
	# So can a conversation the run's money, reputation or flags just made
	# due (a story beat): play it through.
	if not node_name.begins_with("Dialogue") and _find_visible("DialoguePanel") != null:
		await _play_talks()
	# Back on the clinic with the day's jobs done (and nobody at the door),
	# the night closes by itself and its report covers the screen: read it.
	if node_name != "DayReportClose" and _find_visible("DayReportClose") != null:
		await _click(_find_visible("DayReportClose"))
		await _frames(4)
	var found := await _wait_until(func() -> bool:
		var n := _find_visible(node_name)
		return n != null and not (n is BaseButton and (n as BaseButton).disabled) and not UIManager.is_transitioning(), timeout)
	if not found:
		check(false, "button '%s' available on %s" % [node_name, UIManager.current_screen_id])
		return
	await _click(_find_visible(node_name))


func _click_dialog_button(label: String) -> void:
	await _frames(5)
	for b in get_tree().root.find_children("*", "Button", true, false):
		if (b as Button).text == label and (b as Button).is_visible_in_tree():
			await _click(b)
			return
	check(false, "dialog button '%s' found" % label)


func _find_visible(node_name: String) -> Control:
	for n in get_tree().root.find_children(node_name, "Control", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null


func _wait_screen(id: StringName, timeout: float = STEP_TIMEOUT) -> void:
	var ok := await _wait_until(func() -> bool: return UIManager.current_screen_id == id and not UIManager.is_transitioning(), timeout)
	if not ok:
		check(false, "reached screen '%s' (stuck on '%s')" % [id, UIManager.current_screen_id])
	await _frames(2)
	if id == UIManager.SCREEN_CLINIC:
		await _play_talks()


var _talks_seen: Dictionary = {}


## Story conversations pop up on the clinic screen: play each through by
## picking the first available option (screenshotting each new one).
func _play_talks() -> void:
	await _frames(4)
	var guard := 0
	while guard < 60:
		guard += 1
		var panel := _find_visible("DialoguePanel")
		if panel == null:
			await _frames(3)
			if _find_visible("DialoguePanel") == null:
				break
			continue
		var did := String(DialogueManager.current_id)
		if did != "" and not _talks_seen.has(did):
			_talks_seen[did] = true
			await _frames(6)
			await _checkpoint("talk_%s" % did)
		var b: Control = _find_visible("DialogueOption_0")
		if b == null or (b as Button).disabled:
			b = _find_visible("DialogueNext")
		if b == null:
			b = _find_visible("DialogueEnd")
		if b == null:
			UIManager.close_modal()
		else:
			await _click(b)
		await _frames(3)
	if _find_visible("EndingClose"):
		await _click_named("EndingClose")


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var t := 0.0
	while not predicate.call():
		if SurgeryManager.active_complication and UIManager.current_screen_id == UIManager.SCREEN_SURGERY and not UIManager.is_transitioning():
			await _handle_complication()
		if not SurgeryManager.active_dilemma.is_empty() and _find_visible("DilemmaPanel") != null:
			await _handle_dilemma()
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > timeout:
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Layout guard + optional screenshot at key moments of the playthrough.
func _checkpoint(label: String) -> void:
	await _check_layout(label)
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		_shot_index += 1
		img.save_png("%s/%03d_%s.png" % [_shots_dir, _shot_index, label])
