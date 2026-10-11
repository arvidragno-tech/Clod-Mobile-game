extends Node
## Screenshot tour of every screen and the main modals, for visual review
## (not a pass/fail test beyond "every screen opened and buttons are
## on-screen").
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/ui_tour.tscn -- --shots=/abs/dir [--res=1280x720]

var _shots: String = ""
var _fails: Array[String] = []
var _n: int = 0


func _ready() -> void:
	Hints.enabled = false
	var res := "1920x1080"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
		elif arg.begins_with("--res="):
			res = arg.trim_prefix("--res=")
	Settings.path = "user://ui_tour_settings.cfg"
	SaveManager.save_dir = "user://test_saves"
	SaveManager.use_slot(3)
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(20)
	Settings.window_mode = "windowed"
	Settings.resolution = res
	Settings.apply_display()
	await _frames(10)
	await _shot("00_main_menu")
	GameManager.start_new_game()
	await _settle()
	await _shot("01_clinic_tutorial")
	TutorialManager.skip()
	UIManager.close_modal()
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	EventManager.operations = 10
	EconomyManager.money = 3000
	await _settle()
	# Customer flow.
	CustomerManager.debug_set_customer(CustomerManager.generator.generate({"full_difficulty": true}))
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	await _shot("02_clinic_customer")
	GameManager.open_customer()
	await _settle()
	await _shot("03_customer")
	GameManager.accept_customer()
	await _settle()
	await _shot("04_diagnosis")
	var sv := get_tree().root.find_child("ScanView", true, false) as ScanView
	if sv:
		for r: StringName in [&"neck", &"head", &"chest"]:
			sv.scan(r)
			await _frames(60)
	await _shot("04b_diagnosis_scanned")
	var c := CustomerManager.current_customer
	if c:
		GameManager.submit_diagnosis(c.true_diagnosis_id)
		InventoryManager.add_implant(c.requested_cyberware_id)
		InventoryManager.supplies = 10
		for t: ToolData in InventoryManager.get_purchasable_tools(true):
			if not InventoryManager.owned_tools.has(t.id):
				InventoryManager.owned_tools.append(t.id)
	if GameManager.get_surgery_readiness()["ok"]:
		GameManager.begin_surgery()
		await _settle()
	else:
		_fails.append("surgery not ready: %s" % str(GameManager.get_surgery_readiness()))
	await _frames(60)
	await _shot("06_surgery")
	if SurgeryManager.is_active:
		GameManager.abort_surgery()
		await _settle()
	UIManager.close_modal()
	CustomerManager.dismiss_current()
	for s: Array in [[UIManager.SCREEN_INVENTORY, "07_inventory"], [UIManager.SCREEN_DATABASE, "08_database"], [UIManager.SCREEN_SHOP, "09_shop"],
			[UIManager.SCREEN_SKILLS, "10_skills"], [UIManager.SCREEN_UPGRADES, "11_facility"], [UIManager.SCREEN_STAFF, "12_staff"],
			[UIManager.SCREEN_BUSINESS, "13_business"], [UIManager.SCREEN_MAP, "14_map"], [UIManager.SCREEN_SETTINGS, "15_settings"]]:
		UIManager.go_to(s[0], {"return_to": UIManager.SCREEN_CLINIC})
		await _settle()
		await _shot(s[1])
	for tab in 8:
		UIManager.go_to(UIManager.SCREEN_DOSSIER, {"tab": tab})
		await _settle()
		await _shot("16_journal_%d" % tab)
	StoryManager.set_flag(&"bm_access")
	BlackMarketManager.refresh_stock()
	UIManager.go_to(UIManager.SCREEN_BLACK_MARKET)
	await _settle()
	await _shot("17_black_market")
	TimeManager.minute = 1320
	LocationManager.travel(&"rusty_valve")
	WorldSimulationManager.encounter = {}
	WorldSimulationManager.start_event(&"rusty_valve", "bar_fight")
	UIManager.go_to(UIManager.SCREEN_LOCATION)
	await _settle()
	await _shot("18_location")
	LocationManager.return_to_clinic()
	WorldSimulationManager.encounter = {}
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	DialogueManager.start(&"d_ilse_intro")
	var talk := DialoguePanel.new()
	talk.name = "DialoguePanel"
	UIManager.show_modal(talk)
	await _frames(90)
	await _shot("19_dialogue")
	UIManager.close_modal()
	DialogueManager.end()
	await _frames(5)
	EventManager.queue_event(&"wire_intro")
	var ev := EventPanel.new()
	ev.event_id = &"wire_intro"
	UIManager.show_modal(ev)
	await _frames(90)
	await _shot("20_event")
	UIManager.close_modal()
	EventManager.pending_event = &""
	UIManager.show_day_report(BusinessManager.end_day())
	await _frames(40)
	await _shot("21_day_report")
	UIManager.close_modal()
	await _frames(5)
	GameManager.open_pause_menu()
	await _frames(20)
	await _shot("22_pause")
	UIManager.close_modal()
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("UI TOUR: %d shots%s" % [_n, ("" if _fails.is_empty() else ", issues: %s" % str(_fails))])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _shot(name: String) -> void:
	_n += 1
	var view := get_viewport().get_visible_rect().grow(1.0)
	var bad: Array[String] = []
	for n in get_tree().root.find_children("*", "BaseButton", true, false):
		var b := n as Control
		if not b.is_visible_in_tree():
			continue
		var p := b.get_parent()
		var scrolled := false
		while p:
			if p is ScrollContainer:
				scrolled = true
				break
			p = p.get_parent()
		if not scrolled and not view.encloses(b.get_global_rect()):
			bad.append(String(b.name))
	if not bad.is_empty():
		_fails.append("%s: off-screen %s" % [name, bad])
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [_shots, name])


func _settle() -> void:
	var t := 0
	while UIManager.is_transitioning() and t < 200:
		await get_tree().process_frame
		t += 1
	await _frames(20)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
