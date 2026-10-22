extends Node
## Plays a few real operations in whatever build of the game this runs in
## and writes that build's own save file. Used to make the save fixtures
## in tests/fixtures/saves (each one written by the release it is named for).
const OUT_DIR := "user://fixture_gen"
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7
	seed(7)
	# Not every release has every switch: set what this one has.
	for spec: Array in [["Hints", "enabled", false], ["CutscenePlayer", "enabled", false], ["CustomerManager", "breather_scale", 0.0]]:
		var n := get_node_or_null("/root/" + str(spec[0]))
		if n and str(spec[1]) in n:
			n.set(str(spec[1]), spec[2])
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	SaveManager.save_dir = OUT_DIR
	SaveManager.save_path = OUT_DIR + "/fixture.json"
	SaveManager.delete_save()
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(10)
	GameManager.start_new_game()
	TutorialManager.skip()
	await _settle()
	var done := 0
	for shift in 14:
		if done >= 7:
			break
		await _go(UIManager.SCREEN_CLINIC)
		_clear_modals()
		if BusinessManager.is_day_full() and not CustomerManager.has_customer():
			GameManager.close_for_the_night()
			await _frames(3)
			_clear_modals()
		var waited := 0.0
		while not CustomerManager.has_customer() and waited < 8.0:
			CustomerManager.request_next_customer()
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		if not CustomerManager.has_customer():
			continue
		GameManager.open_customer()
		await _settle()
		GameManager.accept_customer()
		await _settle()
		var c := GameManager.get_current_customer()
		if c == null:
			continue
		GameManager.submit_diagnosis(c.true_diagnosis_id)
		var r := GameManager.get_surgery_readiness()
		if not bool(r["ok"]):
			GameManager.decline_customer()
			await _settle()
			continue
		GameManager.begin_surgery()
		await _settle()
		var t := 0
		while UIManager.current_screen_id == UIManager.SCREEN_SURGERY and t < 1500:
			t += 1
			if not SurgeryManager.active_dilemma.is_empty():
				var opts: Array = SurgeryManager.active_dilemma["choices"]
				for i in opts.size():
					if SurgicalDilemmas.block_reason(opts[i]) == "" and not SurgeryManager.resolve_dilemma(i).is_empty():
						break
				UIManager.close_modal()
				SurgeryManager.resume()
			if SurgeryManager.active_complication:
				SurgeryManager.use_quick_action(SurgeryManager.active_complication.counter_action)
			var screen := UIManager.current_screen as SurgeryScreen
			if screen and screen.current_stage and not screen.current_stage.is_finished and not UIManager.is_transitioning():
				screen.current_stage._finish(_rng.randf_range(0.7, 1.0))
			await _frames(2)
			if not SurgeryManager.is_active and UIManager.current_screen_id == UIManager.SCREEN_SURGERY:
				await get_tree().create_timer(GameConfig.RESULTS_DELAY_SEC + 0.6).timeout
		await _settle()
		if UIManager.current_screen_id == UIManager.SCREEN_RESULTS:
			GameManager.finish_results()
			done += 1
			await _settle()
	await _go(UIManager.SCREEN_CLINIC)
	_clear_modals()
	var ok := SaveManager.save_game(&"manual")
	print("FIXTURE version=%s ops=%d day=%d money=%d saved=%s path=%s" % [ProjectSettings.get_setting("application/config/version"), done, BusinessManager.day, EconomyManager.money, ok, ProjectSettings.globalize_path(SaveManager.save_path)])
	get_tree().quit(0 if ok and done >= 3 else 1)

func _clear_modals() -> void:
	if EventManager.has_pending():
		var ch: Array = EventManager.get_event(EventManager.pending_event).get("choices", [])
		for i in ch.size():
			if EventManager.get_choice_block_reason(ch[i]) == "":
				EventManager.resolve(i)
				break
	UIManager.close_modal()

func _go(id: StringName) -> void:
	if UIManager.current_screen_id != id:
		UIManager.go_to(id)
	await _settle()

func _settle() -> void:
	await _frames(4)
	var g := 0
	while UIManager.is_transitioning() and g < 120:
		g += 1
		await _frames(1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
