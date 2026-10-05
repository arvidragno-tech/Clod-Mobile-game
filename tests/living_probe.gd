extends Node
## Living-world QA in the real, rendered game: a returning patient with
## memories, changes and a debt at the door; payment terms; the patient
## debt panel; known patients in the journal. Screenshots every screen at
## 1920x1080 and 1280x720 and checks buttons stay on-screen.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       res://tests/living_probe.tscn -- --shots=/abs/dir
## Exit code 0 = all checks passed.

var _shots: String = ""
var _fails: Array[String] = []
var _checks: int = 0
var _main: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	Settings.path = "user://living_probe_settings.cfg"
	SaveManager.save_dir = "user://test_saves"
	SaveManager.save_path = "user://living_probe_save.json"
	SurgeryScreen.pause_on_suspend = false
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(30)
	GameManager.start_new_game()
	TutorialManager.skip()
	await _settle()
	UIManager.close_modal()
	EventManager.operations = 10
	for res in ["1920x1080", "1280x720"]:
		Settings.window_mode = "windowed"
		Settings.resolution = res
		Settings.apply_display()
		await _frames(20)
		await _living(res)
		await _staff_life(res)
		await _time_of_day(res)
		await _clinic_life(res)
		await _world(res)
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("LIVING PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("LIVING PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _living(label: String) -> void:
	print("== %s" % label)
	# A patient you saw before: discounted, given chrome, now owes you.
	var first := CustomerManager.generator.generate({"full_difficulty": true})
	first.terms = &"discount"
	PeopleManager.after_visit(first, "success", 200)
	MemoryManager.remember(first.id, &"PLAYER_KEPT_SECRET")
	PeopleManager.add_debt(first.id, 340, "couldn't cover the fee")
	PeopleManager.get_person(first.id)["last_day"] = BusinessManager.day - 15
	PeopleManager.get_person(first.id)["next_day"] = BusinessManager.day
	CustomerManager.dismiss_current()
	CustomerManager.queue.clear()
	var back := CustomerManager._next_customer()
	_check(back != null and back.id == first.id, "%s: the returning patient walks in" % label)
	back.traits = [&"greedy", &"proud"] as Array[StringName]
	back.backer = &"street_gangs"
	CustomerManager.debug_set_customer(back)
	UIManager.go_to(UIManager.SCREEN_CUSTOMER)
	await _settle()
	var root := get_tree().root
	_check(root.find_child("RelationshipLabel", true, false) != null, "%s: relationship shown" % label)
	_check(root.find_child("TermsRow", true, false) != null, "%s: payment terms shown" % label)
	var preview := root.find_child("TermsPreview", true, false) as Label
	_check(preview != null and preview.text.contains("haggle"), "%s: greedy patient will haggle (%s)" % [label, preview.text if preview else ""])
	var plan := root.find_child("Terms_plan", true, false) as Button
	_check(plan != null, "%s: pay-later button" % label)
	if plan:
		plan.pressed.emit()
		plan.button_pressed = true
		await _frames(3)
		_check(back.terms == &"plan" and preview.text.contains("owed"), "%s: choosing PAY LATER updates the terms (%s)" % [label, preview.text])
	_check(root.find_child("Terms_faction", true, false) != null, "%s: a backed patient can have their crew pay" % label)
	await _shot(label, "customer_returning")
	# Their file scrolled to the payment section.
	# Business: the debt panel and its actions.
	UIManager.go_to(UIManager.SCREEN_BUSINESS)
	await _settle()
	var debts := PeopleManager.open_debts()
	_check(not debts.is_empty(), "%s: a debt is open" % label)
	if not debts.is_empty():
		var did := int(debts[0]["id"])
		_check(root.find_child("Debt_%d" % did, true, false) != null, "%s: the debt is listed" % label)
		await _shot(label, "business_debts")
		var pb := root.find_child("Plan_%d" % did, true, false) as Button
		_check(pb != null, "%s: PLAN button" % label)
		if pb:
			pb.pressed.emit()
			await _frames(5)
			_check(str(PeopleManager.get_debt(did)["status"]) == "plan", "%s: PLAN puts them on a payment plan" % label)
			_check(root.find_child("Plan_%d" % did, true, false) == null, "%s: the panel refreshes" % label)
		var fav := root.find_child("Favor_%d" % did, true, false) as Button
		if fav:
			fav.pressed.emit()
			await _frames(5)
			_check(str(PeopleManager.get_debt(did)["status"]) == "favor", "%s: FAVOUR trades the debt" % label)
	# Journal: the patient appears under PEOPLE.
	UIManager.go_to(UIManager.SCREEN_DOSSIER, {"tab": 2})
	await _settle()
	_check(root.find_child("Patient_%s" % String(first.id), true, false) != null, "%s: known patient in the journal" % label)
	await _shot(label, "journal_people")
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _staff_life(label: String) -> void:
	if StaffManager.employees.size() < 2:
		for i in 2:
			var e := StaffManager.generate_candidate()
			e["clinic"] = ClinicManager.tier
			for o in StaffManager.employees:
				o["relationships"][str(e["id"])] = -20
				e["relationships"][str(o["id"])] = -20
			StaffManager.employees.append(e)
		StaffManager.staff_changed.emit()
	var a: Dictionary = StaffManager.employees[0]
	var b: Dictionary = StaffManager.employees[1]
	UIManager.go_to(UIManager.SCREEN_STAFF)
	await _settle()
	var root := get_tree().root
	_check(root.find_child("Life_%s" % str(a["id"]), true, false) != null, "%s: staff life shown" % label)
	_check(root.find_child("Bonds_%s" % str(a["id"]), true, false) != null, "%s: colleague bonds shown" % label)
	await _shot(label, "staff_life")
	var uid := StaffLifeManager.fire(&"argument", a, b)
	UIManager.go_to(UIManager.SCREEN_DOSSIER, {"tab": 1})
	await _settle()
	await _shot(label, "staff_event_comms")
	var btn := root.find_child("MsgAction_2", true, false) as Button
	_check(btn != null, "%s: life event choices in COMMS" % label)
	if btn:
		var r0 := StaffLifeManager.rel(a, b)
		btn.pressed.emit()
		await _frames(5)
		_check(int(CommsManager.get_message(uid)["resolved"]) >= 0 and StaffLifeManager.rel(a, b) != r0, "%s: clicking a choice resolves it" % label)
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _time_of_day(label: String) -> void:
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	var root := get_tree().root
	for m: int in [600, 1100, 1380, 1560]:
		TimeManager.minute = m
		TimeManager.advance(1)
		EventManager.pending_event = &""
		UIManager.close_modal()
		await _frames(10)
		var clock := root.find_child("ClockLabel", true, false) as Label
		_check(clock != null and clock.text.contains(TimeManager.clock_text()) and clock.text.contains(TimeManager.period_label()), "%s: the room shows %s %s" % [label, TimeManager.clock_text(), TimeManager.period_label()])
		var ag := root.find_child("AgendaLabel", true, false) as Label
		_check(ag != null and ag.text.contains("doors lock"), "%s: today's agenda shown" % label)
		await _shot(label, "clinic_%s" % String(TimeManager.period()))
	TimeManager.minute = TimeManager.open_minute()


func _clinic_life(label: String) -> void:
	ClinicManager.upgrades[ClinicManager.clinic_id()] = {"customer": 2}
	BusinessManager.jobs_today = 0
	ClinicLifeManager.waiting.clear()
	CustomerManager.debug_set_customer(CustomerManager.generator.generate({"full_difficulty": true}))
	for i in 2:
		ClinicLifeManager.seat(CustomerManager.generator.generate({"full_difficulty": true, "faction": "independent_mercs"}))
	ClinicLifeManager.pin("milestone", "First job", "Probe note")
	ClinicLifeManager.pin("loss", "Someone", "Died on the table")
	ClinicLifeManager.pin("patient", "A regular", "Photo")
	ClinicLifeManager.pin("wanted", "WANTED", "Notice")
	ClinicLifeManager.pin("faction", "Rustline", "Mark")
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	TimeManager.minute = 1300
	ClinicLifeManager.post("Somebody leaves a bag of salvaged servos by the door. No note.")
	await _frames(10)
	var root := get_tree().root
	var cap := root.find_child("LifeCaption", true, false) as Label
	_check(cap != null and cap.text.contains("servos") and cap.modulate.a > 0.5, "%s: clinic life caption in the room" % label)
	_check(ClinicLifeManager.waiting.size() >= 1, "%s: people waiting on the bench" % label)
	await _shot(label, "waiting_room_wall")
	UIManager.go_to(UIManager.SCREEN_DOSSIER, {"tab": 7})
	await _settle()
	_check(root.find_child("Pin_0", true, false) != null, "%s: the wall in the journal" % label)
	await _shot(label, "journal_wall")
	ClinicLifeManager.waiting.clear()
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _world(label: String) -> void:
	WorldEventManager.start(&"gang_war")
	WorldEventManager.post("Sources: gang-linked clinic operating in the Sump", "", true)
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	await _frames(30)
	var root := get_tree().root
	var tk := root.find_child("TickerText", true, false) as Label
	_check(tk != null and tk.text.contains("GANG-LINKED") and tk.is_visible_in_tree(), "%s: the news ticker runs in the room" % label)
	await _shot(label, "clinic_ticker")
	UIManager.go_to(UIManager.SCREEN_DOSSIER, {"tab": 4})
	await _settle()
	_check(root.find_child("Situation_gang_war", true, false) != null, "%s: running situations in NEWS" % label)
	await _shot(label, "journal_news")
	WorldEventManager.active.clear()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		_fails.append(msg)


func _settle() -> void:
	var t := 0
	while UIManager.is_transitioning() and t < 200:
		await get_tree().process_frame
		t += 1
	await _frames(15)


func _shot(label: String, what: String) -> void:
	_layout_guard("%s/%s" % [label, what])
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s_%s.png" % [_shots, label, what])


func _layout_guard(label: String) -> void:
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
		if scrolled:
			continue
		if not view.encloses(b.get_global_rect()):
			bad.append(String(b.name))
	_check(bad.is_empty(), "%s: all buttons on-screen %s" % [label, bad])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
