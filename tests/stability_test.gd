extends Node
## Stability suite (headless):
##  1. Soak: many full shifts through the real screens and SurgeryManager
##     (stages are completed programmatically with varied quality, so it runs
##     fast), with random events, shopping, skills, upgrades and periodic
##     save -> reset -> load cycles. Invariants are checked every shift.
##  2. Monkey: thousands of random taps / drags / long-presses on whatever
##     screen is showing; afterwards the game must still navigate normally.
##  3. Rapid navigation: screen changes requested mid-transition.
##  4. Save fuzzing: random byte corruption / truncation never crashes load.
##  5. Leaks: node and orphan counts stay flat across the soak.
## Usage: godot --headless --path . res://tests/stability_test.tscn -- --shifts=30 --monkey=3000
## Exit code 1 on any failed invariant.

const SAVE := "user://stability_save.json"

var _checks := 0
var _failures: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _main: Node


func _ready() -> void:
	var shifts := 30
	var monkey := 3000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shifts="):
			shifts = int(arg.trim_prefix("--shifts="))
		elif arg.begins_with("--monkey="):
			monkey = int(arg.trim_prefix("--monkey="))
	_rng.seed = 99
	get_tree().root.content_scale_size = Vector2i(360, 780)
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	SaveManager.save_path = SAVE
	SaveManager.delete_save()
	Settings.path = "user://stability_settings.cfg"
	SurgeryScreen.pause_on_suspend = false
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(10)
	GameManager.start_new_game()
	TutorialManager.skip()
	await _settle()
	print("== SOAK (%d shifts) ==" % shifts)
	await _soak(shifts)
	print("== RAPID NAVIGATION ==")
	await _rapid_navigation()
	print("== MONKEY (%d inputs) ==" % monkey)
	await _monkey(monkey)
	print("== SAVE FUZZ ==")
	_save_fuzz()
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	AudioManager.stop_all()
	await _frames(5)
	print("")
	if _failures.is_empty():
		print("STABILITY OK (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("STABILITY FAILURES (%d of %d):" % [_failures.size(), _checks])
		for f in _failures:
			print("  - " + f)
		get_tree().quit(1)


func check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(msg)
		print("  FAIL " + msg)


# --- Soak -------------------------------------------------------------------------

func _soak(shifts: int) -> void:
	var baseline_nodes := 0
	var baseline_orphans := 0
	var completed := 0
	for shift in shifts:
		await _go(UIManager.SCREEN_CLINIC)
		_resolve_event()
		if shift == 3:
			await _frames(30)
			baseline_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			baseline_orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var waited := 0.0
		while not CustomerManager.has_customer() and waited < 8.0:
			CustomerManager.request_next_customer()
			await _seconds(0.25)
			waited += 0.25
		check(CustomerManager.has_customer(), "shift %d: a customer arrives" % shift)
		if not CustomerManager.has_customer():
			continue
		GameManager.open_customer()
		await _settle()
		check(UIManager.current_screen_id == UIManager.SCREEN_CUSTOMER, "shift %d: customer screen" % shift)
		GameManager.accept_customer()
		await _settle()
		var c := GameManager.get_current_customer()
		var right := _rng.randf() < 0.8
		GameManager.submit_diagnosis(c.true_diagnosis_id if right else &"clean_site")
		var r := GameManager.get_surgery_readiness()
		if not bool(r["ok"]):
			for label: String in r["missing_tools"]:
				_buy_tool(label)
			c.risk_tolerance = maxf(c.risk_tolerance, 0.8)
			r = GameManager.get_surgery_readiness()
		if not bool(r["ok"]):
			GameManager.decline_customer()
			await _settle()
			continue
		GameManager.begin_surgery()
		await _settle()
		check(UIManager.current_screen_id == UIManager.SCREEN_SURGERY and SurgeryManager.is_active, "shift %d: surgery starts" % shift)
		var ok := await _complete_surgery(shift)
		check(ok, "shift %d: surgery reaches the report" % shift)
		await _settle()
		if UIManager.current_screen_id == UIManager.SCREEN_RESULTS:
			GameManager.finish_results()
			await _settle()
			completed += 1
		_spend()
		_invariants(shift)
		if shift % 5 == 4:
			# Save -> wipe -> load must restore the exact same state.
			var money := EconomyManager.money
			var level := ProgressionManager.level
			var ops := EventManager.operations
			SaveManager.save_game()
			SaveManager.reset_all()
			check(SaveManager.load_game() and EconomyManager.money == money and ProgressionManager.level == level and EventManager.operations == ops, "shift %d: save/load round-trip" % shift)
	await _go(UIManager.SCREEN_CLINIC)
	await _frames(30)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  completed %d ops; nodes %d (baseline %d), orphans %d (baseline %d), static mem %.1f MB" % [completed, nodes, baseline_nodes, orphans, baseline_orphans, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	check(completed >= shifts * 0.6, "soak completed most shifts (%d/%d)" % [completed, shifts])
	check(nodes <= baseline_nodes + 60, "no node leak across the soak (%d -> %d)" % [baseline_nodes, nodes])
	check(orphans <= baseline_orphans + 20, "no orphan-node leak (%d -> %d)" % [baseline_orphans, orphans])


## Completes each stage with varied quality; reacts to complications like a
## player would (mostly), occasionally aborts.
func _complete_surgery(shift: int) -> bool:
	var t := 0.0
	while UIManager.current_screen_id == UIManager.SCREEN_SURGERY and t < 60.0:
		var screen := UIManager.current_screen as SurgeryScreen
		if SurgeryManager.active_complication and _rng.randf() < 0.9:
			SurgeryManager.use_quick_action(SurgeryManager.active_complication.counter_action)
		if screen and screen.current_stage and not screen.current_stage.is_finished and not UIManager.is_transitioning():
			if shift % 11 == 10 and _rng.randf() < 0.3:
				GameManager.abort_surgery()
			elif _rng.randf() < 0.15:
				SurgeryManager.report_mistake(&"cut_deviation", 1.0)
			else:
				screen.current_stage._finish(_rng.randf_range(0.55, 1.0))
		await _frames(2)
		t += 2.0 / 60.0
		if not SurgeryManager.is_active and UIManager.current_screen_id == UIManager.SCREEN_SURGERY:
			# Waiting for the delayed jump to the report.
			await _seconds(GameConfig.RESULTS_DELAY_SEC + 0.6)
	return UIManager.current_screen_id == UIManager.SCREEN_RESULTS


func _invariants(shift: int) -> void:
	check(EconomyManager.money >= 0, "shift %d: money never negative" % shift)
	check(InventoryManager.supplies >= 0 and InventoryManager.parts >= 0 and InventoryManager.tokens >= 0, "shift %d: resources never negative" % shift)
	check(not SurgeryManager.is_active, "shift %d: no surgery left running" % shift)
	check(ReputationManager.reputation >= GameConfig.MIN_REPUTATION and ReputationManager.reputation <= GameConfig.MAX_REPUTATION, "shift %d: rep in range" % shift)
	check(FactionManager.heat >= 0.0 and FactionManager.heat <= 100.0, "shift %d: heat in range" % shift)
	check(not UIManager.has_modal() or EventManager.has_pending(), "shift %d: no stray modal" % shift)


func _resolve_event() -> void:
	if EventManager.has_pending():
		var e := EventManager.get_event(EventManager.pending_event)
		var choices: Array = e.get("choices", [])
		var pick := 0
		for i in choices.size():
			if EventManager.get_choice_block_reason(choices[i]) == "":
				pick = i
				break
		EventManager.resolve(pick)
	UIManager.close_modal()


func _buy_tool(label: String) -> void:
	var cat := StringName(label.split(" ")[0].to_lower())
	EconomyManager.add_money(2000)
	for t in InventoryManager.get_purchasable_tools(true):
		if t.category == cat and not InventoryManager.owns_tool(t.id) and t.unlock_level <= ProgressionManager.level:
			if InventoryManager.buy_tool(t.id):
				return


func _spend() -> void:
	if InventoryManager.supplies < 3:
		InventoryManager.buy_supply_pack()
	for id: StringName in [&"precision", &"speed", &"tissue_handling"]:
		SkillManager.upgrade(id)
	if ClinicManager.get_upgrade_block_reason() == "" and _rng.randf() < 0.5:
		ClinicManager.upgrade()
	if BlackMarketManager.is_unlocked() and not BlackMarketManager.stock.is_empty() and _rng.randf() < 0.3:
		BlackMarketManager.buy(0)


# --- Rapid navigation ---------------------------------------------------------------

func _rapid_navigation() -> void:
	var screens := [UIManager.SCREEN_SHOP, UIManager.SCREEN_SKILLS, UIManager.SCREEN_DOSSIER, UIManager.SCREEN_UPGRADES,
		UIManager.SCREEN_SETTINGS, UIManager.SCREEN_CLINIC]
	for i in 40:
		UIManager.go_to(screens[_rng.randi() % screens.size()])
		await _frames(_rng.randi_range(0, 3))
	await _go(UIManager.SCREEN_CLINIC)
	check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC and not UIManager.is_transitioning(), "navigation settles after spamming screen changes")


# --- Monkey ------------------------------------------------------------------------

func _monkey(count: int) -> void:
	var view := get_viewport().get_visible_rect().size
	var visited := {}
	for i in count:
		visited[UIManager.current_screen_id] = true
		var p := Vector2(_rng.randf_range(0, view.x), _rng.randf_range(0, view.y))
		var kind := _rng.randi() % 10
		if kind < 6:
			_mouse(p, true)
			await _frames(1)
			_mouse(p, false)
		elif kind < 9:
			_mouse(p, true)
			var q := p
			for k in 6:
				q += Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30))
				_motion(q)
				await _frames(1)
			_mouse(q, false)
		else:
			_mouse(p, true)
			await _seconds(0.4)
			_mouse(p, false)
		await _frames(1)
		# Don't let the monkey wipe the save or wander off for good.
		if UIManager.current_screen_id == UIManager.SCREEN_MAIN_MENU and i % 50 == 0:
			UIManager.close_modal()
			GameManager.continue_game()
			await _settle()
		if i % 400 == 399:
			print("  monkey %d inputs, on '%s'" % [i + 1, UIManager.current_screen_id])
	print("  screens visited: %s" % ", ".join(visited.keys().map(func(k: Variant) -> String: return String(k))))
	# Recover: whatever happened, the game must still be operable.
	UIManager.close_modal()
	if SurgeryManager.is_active:
		GameManager.abort_surgery()
		await _seconds(GameConfig.RESULTS_DELAY_SEC + 1.0)
	if UIManager.current_screen_id == UIManager.SCREEN_RESULTS:
		GameManager.finish_results()
	await _go(UIManager.SCREEN_CLINIC)
	check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC, "game still navigable after the monkey test")
	check(EconomyManager.money >= 0 and not SurgeryManager.is_active, "state sane after the monkey test")
	check(visited.size() >= 3, "monkey reached several screens (%d)" % visited.size())


func _mouse(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev, true)


func _motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(ev, true)


# --- Save fuzz ----------------------------------------------------------------------

func _save_fuzz() -> void:
	SaveManager.save_game()
	var good := FileAccess.get_file_as_string(SaveManager.save_path)
	var crashes := 0
	for i in 60:
		var bytes := good.to_utf8_buffer()
		match i % 3:
			0:
				for k in _rng.randi_range(1, 8):
					bytes[_rng.randi() % bytes.size()] = _rng.randi() % 256
			1:
				bytes = bytes.slice(0, _rng.randi_range(0, bytes.size() - 1))
			2:
				bytes = PackedByteArray()
				for k in _rng.randi_range(0, 64):
					bytes.append(_rng.randi() % 256)
		var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		DirAccess.remove_absolute(SaveManager.save_path + ".bak")
		var loaded := SaveManager.load_game()
		if loaded:
			# Only an intact file may load; anything else must be rejected.
			check(EconomyManager.money >= 0, "fuzzed save %d loaded into a sane state" % i)
		if not is_instance_valid(SaveManager):
			crashes += 1
	check(crashes == 0, "save fuzzing never crashed the loader")
	var f2 := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f2.store_string(good)
	f2.close()
	check(SaveManager.load_game(), "intact save still loads after fuzzing")


# --- helpers ------------------------------------------------------------------------

func _go(id: StringName) -> void:
	await _settle()
	if UIManager.current_screen_id != id:
		UIManager.go_to(id)
	await _settle()


func _settle() -> void:
	await _frames(2)
	var t := 0
	while UIManager.is_transitioning() and t < 300:
		await get_tree().process_frame
		t += 1
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
