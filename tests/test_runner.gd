extends Node
## Automated tests. Runs unit tests for the pure systems, then plays the full
## loop end-to-end by injecting real pointer events (taps, drags, holds) into
## the viewport, exactly like a finger on an iPhone would.
##
## Headless:   godot --headless --path . res://tests/test_runner.tscn
## With shots: xvfb-run godot --path . --rendering-driver opengl3 \
##               res://tests/test_runner.tscn -- --shots=/abs/dir
## Exit code 0 = all passed.

const TEST_SAVE_PATH := "user://test_savegame.json"
const STEP_TIMEOUT := 20.0
const DRAG_STEP_PX := 6.0

var _failures: Array[String] = []
var _checks: int = 0
var _shots_dir: String = ""
var _shot_index: int = 0
var _main: Node
var _handling_complication: bool = false


func _ready() -> void:
	# Pin the logical viewport to an iPhone size (headless windows are 64x64).
	var viewport_size := Vector2i(360, 780)
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
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.delete_save()
	await _run_all()


func _run_all() -> void:
	print("== UNIT TESTS ==")
	_test_vitals()
	_test_scoring()
	_test_progression()
	_test_economy_inventory()
	_test_data_loaded()
	_test_save_roundtrip()
	print("== END-TO-END ==")
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _e2e_full_loop()
	SaveManager.delete_save()
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


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   " + message)
	else:
		print("  FAIL " + message)
		_failures.append(message)


# --- Unit tests --------------------------------------------------------------

func _test_vitals() -> void:
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


func _test_scoring() -> void:
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
	var f := SurgeryResult.new()
	f.success = false
	SurgeryScoring.apply_rewards(f, surgery, null)
	check(f.grade == "F" and f.pay == 0 and f.reputation_delta < 0, "failed op pays nothing and costs rep")


func _test_progression() -> void:
	ProgressionManager.reset_state()
	var need := ProgressionManager.xp_required_for_level(2)
	var gained := ProgressionManager.add_xp(need)
	check(gained == 1 and ProgressionManager.level == 2, "XP threshold levels up")
	ProgressionManager.reset_state()


func _test_economy_inventory() -> void:
	SaveManager.reset_all()
	check(EconomyManager.money == GameConfig.STARTING_MONEY, "starting money")
	check(not EconomyManager.spend(EconomyManager.money + 1), "cannot overspend")
	check(InventoryManager.has_tool_category(&"scalpel"), "starter scalpel owned")
	var stock := InventoryManager.get_implant_count(&"nx1_neural_bridge")
	check(InventoryManager.buy_implant(&"nx1_neural_bridge"), "can buy implant")
	check(InventoryManager.get_implant_count(&"nx1_neural_bridge") == stock + 1, "implant stock increased")
	EconomyManager.add_money(1000)
	check(InventoryManager.buy_tool(&"scalpel_mono"), "can buy mono scalpel")
	check(InventoryManager.get_best_tool(&"scalpel").id == &"scalpel_mono", "best scalpel is the upgrade")
	SaveManager.reset_all()


func _test_data_loaded() -> void:
	check(CustomerManager.templates.size() >= 3, "customers loaded (%d)" % CustomerManager.templates.size())
	var s := SurgeryManager.get_surgery(&"install_basic_neural_implant")
	check(s != null and s.stages.size() == 8, "neural implant surgery has 8 stages")
	for stage in s.stages:
		check(SurgeryStageRegistry.STAGE_TYPES.has(stage.type), "stage type '%s' is registered" % stage.type)
	check(SurgeryManager.complications.size() >= 3, "complications loaded")
	for c: CustomerData in CustomerManager.templates.values():
		check(ResourceLoader.exists(c.portrait_path) and ResourceLoader.exists(c.sprite_path), "%s art exists" % c.id)


func _test_save_roundtrip() -> void:
	SaveManager.reset_all()
	EconomyManager.add_money(123)
	ReputationManager.change(7)
	ProgressionManager.add_xp(42)
	InventoryManager.add_implant(&"nx1_neural_bridge", 3)
	ProgressionManager.record_surgery(&"install_basic_neural_implant", true, "A")
	var expected_money := EconomyManager.money
	var expected_stock := InventoryManager.get_implant_count(&"nx1_neural_bridge")
	check(SaveManager.save_game(), "save writes")
	SaveManager.reset_all()
	check(EconomyManager.money == GameConfig.STARTING_MONEY, "reset clears state")
	check(SaveManager.load_game(), "save loads")
	check(EconomyManager.money == expected_money, "money persisted")
	check(ReputationManager.reputation == 7, "reputation persisted")
	check(ProgressionManager.total_xp == 42, "xp persisted")
	check(InventoryManager.get_implant_count(&"nx1_neural_bridge") == expected_stock, "inventory persisted")
	check(str(ProgressionManager.surgery_records.get("install_basic_neural_implant", {}).get("best_grade", "")) == "A", "surgery records persisted")
	# Corrupt main file -> falls back to backup.
	SaveManager.save_game()
	var f := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	check(SaveManager.load_game(), "corrupt save falls back to backup")
	SaveManager.delete_save()
	SaveManager.reset_all()


# --- End-to-end --------------------------------------------------------------

func _e2e_full_loop() -> void:
	await _wait_screen(UIManager.SCREEN_MAIN_MENU)
	await _checkpoint("main_menu")
	await _click_named("NewGameButton")
	await _wait_screen(UIManager.SCREEN_CLINIC)
	var start_money := EconomyManager.money
	var start_xp := ProgressionManager.total_xp

	# Run 1: clean operation.
	var r1 := await _play_customer_to_results(false)
	check(r1 != null and r1.success, "run 1: operation succeeded")
	if r1:
		print("     run 1 grade=%s score=%.2f pay=%d xp=%d mistakes=%d time=%.0fs complications=%d/%d" % [r1.grade, r1.score, r1.pay, r1.xp, r1.mistakes, r1.elapsed_sec, r1.complications_handled, r1.complications_total])
		check(r1.grade in ["S", "A", "B"], "run 1: clean play grades B or better (%s)" % r1.grade)
		check(r1.complications_total >= 1, "run 1: at least one complication happened")
		check(r1.complications_handled == r1.complications_total, "run 1: complications handled")
	await _checkpoint("results_clean")
	await _click_named("ContinueButton", 10.0)
	await _wait_screen(UIManager.SCREEN_CLINIC)
	check(EconomyManager.money > start_money, "money increased after surgery (%d -> %d)" % [start_money, EconomyManager.money])
	check(ProgressionManager.total_xp > start_xp, "xp increased after surgery")
	check(SaveManager.has_save(), "game autosaved after surgery")

	# Run 2: sloppy operation with deliberate mistakes.
	var rep_before := ReputationManager.reputation
	var r2 := await _play_customer_to_results(true)
	check(r2 != null and r2.success, "run 2: sloppy operation still completed")
	if r2:
		print("     run 2 grade=%s score=%.2f pay=%d mistakes=%d health=%.0f neural=%.0f" % [r2.grade, r2.score, r2.pay, r2.mistakes, r2.final_health, r2.final_neural])
		check(r2.mistakes >= 4, "run 2: mistakes were registered (%d)" % r2.mistakes)
		check(r1 == null or r2.score < r1.score, "run 2: mistakes lowered the score")
	await _click_named("ContinueButton", 10.0)
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# Run 3: abort mid-operation -> failure path.
	await _start_surgery_from_clinic(false)
	await _wait_stage_ready()
	await _click_named("AbortButton")
	await _click_dialog_button("ABORT")
	await _wait_screen(UIManager.SCREEN_RESULTS, 10.0)
	var r3 := GameManager.last_result
	check(r3 != null and not r3.success and r3.grade == "F", "run 3: aborted op is graded F")
	await _checkpoint("results_failed")
	await _click_named("ContinueButton", 10.0)
	await _wait_screen(UIManager.SCREEN_CLINIC)
	check(ReputationManager.reputation < rep_before + (r2.reputation_delta if r2 else 0) + 1, "failure cost reputation")

	# Run 4: reckless splicing until the neural link collapses.
	var r4 := await _play_customer_to_results(false, true)
	check(r4 != null and not r4.success and r4.failure_reason == &"neural_collapse", "run 4: repeated mistakes fail the operation (%s)" % (r4.failure_reason if r4 else &"none"))
	await _click_named("ContinueButton", 10.0)
	await _wait_screen(UIManager.SCREEN_CLINIC)

	# Supply terminal purchase.
	EconomyManager.add_money(500)
	await _click_named("SupplyButton")
	await _frames(5)
	var before_stock := InventoryManager.get_implant_count(&"nx1_neural_bridge")
	await _checkpoint("supply")
	await _click_named("BuyImplant_nx1_neural_bridge")
	check(InventoryManager.get_implant_count(&"nx1_neural_bridge") == before_stock + 1, "supply terminal restocks implant")
	await _click_named("CloseButton")

	# Persistence across a simulated relaunch.
	var money := EconomyManager.money
	SaveManager.save_game()
	SaveManager.reset_all()
	check(SaveManager.load_game() and EconomyManager.money == money, "progress survives reload")


## Clinic -> customer -> diagnosis -> plan -> surgery -> results.
func _play_customer_to_results(sloppy: bool, reckless: bool = false) -> SurgeryResult:
	await _start_surgery_from_clinic(sloppy)
	var stage_count := SurgeryManager.get_stage_count()
	for i in stage_count:
		var ok := await _wait_stage_ready()
		if not ok:
			check(false, "stage %d became ready" % i)
			return null
		var screen := UIManager.current_screen
		var stage: SurgeryStage = screen.current_stage
		var stage_id := stage.stage.id
		await _checkpoint("surgery_stage_%d_%s" % [i, stage_id])
		if reckless and stage is ConnectInterfaceStage:
			await _click_named("Tool_splicer")
			var attempts := 0
			while SurgeryManager.is_active and attempts < 30:
				var wrong: Array = stage.get_autoplay_hints()["wrong"]
				await _drag([stage.get_global_rect().position + wrong[0], stage.get_global_rect().position + wrong[1]])
				attempts += 1
			break
		await _play_stage(stage, sloppy)
		if stage_id in [&"incision", &"debride", &"install", &"connect", &"close"]:
			await _checkpoint("surgery_after_%s" % stage_id)
		var advanced := await _wait_until(func() -> bool: return not SurgeryManager.is_active or SurgeryManager.stage_index > i, STEP_TIMEOUT)
		check(advanced, "stage %d (%s) completed" % [i, stage_id])
		if not advanced or not SurgeryManager.is_active:
			break
	await _checkpoint("surgery_end")
	await _wait_screen(UIManager.SCREEN_RESULTS, 10.0)
	await _frames(10)
	return GameManager.last_result


func _start_surgery_from_clinic(sloppy: bool) -> void:
	await _wait_screen(UIManager.SCREEN_CLINIC)
	await _wait_until(func() -> bool: return CustomerManager.has_customer(), 10.0)
	await _frames(20)
	await _checkpoint("clinic")
	await _click_named("SeeButton")
	await _wait_screen(UIManager.SCREEN_CUSTOMER)
	await _frames(30)
	await _checkpoint("customer")
	await _click_named("AcceptButton")
	await _wait_screen(UIManager.SCREEN_DIAGNOSIS)
	var scan: ScanView = UIManager.current_screen.get_node("%ScanView")
	for region: StringName in [&"neck", &"head", &"spine"]:
		await _tap(scan.get_global_rect().position + scan.get_region_center(region))
		await _wait_until(func() -> bool: return not scan.is_busy(), 3.0)
	await _checkpoint("diagnosis")
	var customer := GameManager.get_current_customer()
	var diagnosis := customer.true_diagnosis_id
	if sloppy:
		for option in GameManager.get_current_surgery().diagnosis_options:
			if StringName(str(option["id"])) != diagnosis:
				diagnosis = StringName(str(option["id"]))
				break
	await _click_named("Option_%s" % diagnosis)
	await _click_named("ConfirmButton")
	await _frames(5)
	await _checkpoint("plan")
	await _click_named("BeginButton")
	await _wait_screen(UIManager.SCREEN_SURGERY)


func _wait_stage_ready() -> bool:
	return await _wait_until(func() -> bool:
		var screen := UIManager.current_screen
		if UIManager.current_screen_id != UIManager.SCREEN_SURGERY or UIManager.is_transitioning():
			return false
		var stage: SurgeryStage = screen.current_stage
		return stage != null and not stage.is_finished and stage.stage == SurgeryManager.get_current_stage(), STEP_TIMEOUT)


func _play_stage(stage: SurgeryStage, sloppy: bool) -> void:
	var origin := stage.get_global_rect().position
	if stage.requires_tool():
		if sloppy and stage.stage.id == &"incision":
			# Wrong tool first (counts as a mistake), then the right one.
			await _click_named("Tool_retractor")
			await _tap(origin + stage.get_autoplay_hints()["path"][0])
		await _click_named("Tool_%s" % stage.stage.tool_category)
	if stage is AnesthesiaStage:
		var h := stage.get_autoplay_hints()
		var target: float = (float(h["zone_min"]) + float(h["zone_max"])) / 2.0
		var button: Button = h["button"]
		await _press(button.get_global_rect().get_center())
		await _wait_until(func() -> bool: return (stage as AnesthesiaStage).dose >= target - 1.0, 10.0)
		await _release(button.get_global_rect().get_center())
	elif stage is IncisionStage:
		var path: Array = stage.get_autoplay_hints()["path"]
		var pts: Array[Vector2] = []
		for p: Vector2 in path:
			pts.append(origin + p)
		if sloppy:
			# Wobble off the line in the middle of the cut.
			var mid: Vector2 = pts[1]
			pts.insert(2, mid + Vector2(40, 30))
		await _drag(pts)
	elif stage is ExposeStage:
		if sloppy:
			await _tap(origin + stage.site.to_local_pos(Vector2(0.5, 0.12)))
		for p: Vector2 in stage.get_autoplay_hints()["targets"]:
			await _tap(origin + p)
	elif stage is RemoveTissueStage:
		var burn_time: float = stage.get_autoplay_hints()["burn_time"]
		for p: Vector2 in stage.get_autoplay_hints()["targets"]:
			await _press(origin + p)
			await _seconds(burn_time + 0.15)
			await _release(origin + p)
	elif stage is InstallImplantStage:
		var h := stage.get_autoplay_hints()
		await _drag([origin + h["implant"], origin + h["socket"]])
		await _frames(3)
		var error: float = stage.get_autoplay_hints()["angle_error_deg"]
		var steps := roundi(absf(error) / InstallImplantStage.ROTATE_STEP_DEG)
		var button_name := "RotateLeft" if error > 0.0 else "RotateRight"
		if sloppy:
			steps = maxi(steps - 3, 0)
		for s in steps:
			await _click_named(button_name)
		await _click_named("SeatButton")
	elif stage is ConnectInterfaceStage:
		if sloppy:
			var wrong: Array = stage.get_autoplay_hints()["wrong"]
			await _drag([origin + wrong[0], origin + wrong[1]])
		while not stage.is_finished:
			var pairs: Array = stage.get_autoplay_hints()["pairs"]
			if pairs.is_empty():
				break
			await _drag([origin + pairs[0][0], origin + pairs[0][1]])
			await _frames(2)
	elif stage is CalibrateStage:
		var cal := stage as CalibrateStage
		while not cal.is_finished:
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
			await _tap(origin + targets[2])
		for p: Vector2 in targets:
			await _tap(origin + p)


## Every visible button must be fully on-screen and at least touch-sized.
func _check_layout(label: String) -> void:
	var view := get_viewport().get_visible_rect().grow(1.0)
	var offenders: Array[String] = []
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		var b := node as Control
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		if not view.encloses(r):
			offenders.append("%s off-screen %s" % [b.name, r])
		elif minf(r.size.x, r.size.y) < GameConfig.MIN_TOUCH - 4.0:
			offenders.append("%s too small %s" % [b.name, r.size])
	check(offenders.is_empty(), "layout ok at '%s' %s" % [label, ", ".join(offenders)])


# --- Input helpers -----------------------------------------------------------

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


func _drag(points: Array[Vector2]) -> void:
	await _handle_complication()
	await _press(points[0])
	var last := points[0]
	for i in range(1, points.size()):
		var to := points[i]
		var steps := maxi(int(last.distance_to(to) / DRAG_STEP_PX), 1)
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
	await _tap(control.get_global_rect().get_center())


func _click_named(node_name: String, timeout: float = STEP_TIMEOUT) -> void:
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


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var t := 0.0
	while not predicate.call():
		if SurgeryManager.active_complication and UIManager.current_screen_id == UIManager.SCREEN_SURGERY and not UIManager.is_transitioning():
			await _handle_complication()
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
	_check_layout(label)
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		_shot_index += 1
		img.save_png("%s/%02d_%s.png" % [_shots_dir, _shot_index, label])
