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
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
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
	for res in ["1920x1080", "1600x900", "1366x768", "1280x720"]:
		Settings.window_mode = "windowed"
		Settings.resolution = res
		Settings.apply_display()
		await _frames(20)
		await _living(res)
		await _staff_life(res)
		await _time_of_day(res)
		await _clinic_life(res)
		await _world(res)
		await _high_stakes(res)
		await _suppliers(res)
		await _security(res)
	await _rooms()
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
	var made := PeopleManager.add_debt(first.id, 340, "couldn't cover the fee")
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
	# The debt made above (earlier ones may already be on a plan).
	var debts := PeopleManager.open_debts().filter(func(d: Dictionary) -> bool: return int(d["id"]) == int(made.get("id", -1)))
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
		var st := root.find_child("StatusHeadline", true, false) as Button
		_check(st != null and st.text != "", "%s: the clinic's status line is shown (%s)" % [label, st.text if st else "-"])
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


func _high_stakes(label: String) -> void:
	var root := get_tree().root
	# Emergency triage on the customer file.
	InventoryManager.supplies = 8
	InventoryManager.parts = 6
	EconomyManager.add_money(3000)
	var em := CustomerManager.spawn_emergency()
	UIManager.go_to(UIManager.SCREEN_CUSTOMER)
	await _settle()
	_check(root.find_child("TriageSection", true, false) != null, "%s: emergency triage options" % label)
	await _frames(40)
	await _shot(label, "emergency_triage")
	var rig := root.find_child("TriageRig", true, false) as Button
	if rig and not rig.disabled:
		rig.pressed.emit()
		await _settle()
		_check(em.triage.has(&"rig"), "%s: experimental rig applied from the UI" % label)
	var stab := _find_visible_button("TriageStabilize")
	_check(stab != null, "%s: stabilise available" % label)
	if stab:
		stab.pressed.emit()
		await _frames(10)
		_check(not CustomerManager.has_customer() and MemoryManager.has(em.id, &"PLAYER_STABILIZED_ME"), "%s: stabilised from the UI" % label)
		var close := _find_visible_button("TriageClose")
		if close:
			close.pressed.emit()
		await _settle()
	# A dilemma on the operating table.
	var c := CustomerManager.generator.generate({"full_difficulty": true, "category": "neural"})
	CustomerManager.debug_set_customer(c)
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	SurgeryManager.start_session(SurgeryManager.get_surgery(item.install_surgery_id), c, true, 1.0, -1, ImplantInstance.create(item.id))
	UIManager.go_to(UIManager.SCREEN_SURGERY)
	await _settle()
	SurgeryManager.debug_trigger_dilemma(&"foreign_device")
	await _frames(20)
	_check(root.find_child("DilemmaPanel", true, false) != null and not SurgeryManager.is_running, "%s: the dilemma stops the table" % label)
	await _shot(label, "surgery_dilemma")
	var ch := _find_visible_button("DilemmaChoice_1")
	if ch:
		ch.pressed.emit()
		await _frames(5)
		await _shot(label, "surgery_dilemma_result")
		var cont := _find_visible_button("DilemmaContinue")
		_check(cont != null, "%s: dilemma outcome shown" % label)
		if cont:
			cont.pressed.emit()
		await _frames(5)
		_check(SurgeryManager.is_running and SurgeryManager.active_dilemma.is_empty(), "%s: back to the table" % label)
	SurgeryManager.abort()
	await _frames(10)
	UIManager.close_modal()
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _suppliers(label: String) -> void:
	var root := get_tree().root
	StoryManager.set_flag(&"bm_access")
	SupplierManager.discover("glass", "probe")
	SupplierManager.discover("curator", "probe")
	SupplierManager.change_trust("glass", 55)
	SupplierManager._refresh("glass")
	EconomyManager.add_money(30000)
	var u := ImplantInstance.create(&"ghostlink_eye", 60.0, &"black_market")
	u.identified = false
	InventoryManager.add_instance(u)
	UIManager.go_to(UIManager.SCREEN_BLACK_MARKET)
	await _settle()
	var tab := _find_visible_button("BMTab_3")
	_check(tab != null, "%s: CONTACTS tab" % label)
	if tab:
		tab.pressed.emit()
		await _frames(10)
	_check(root.find_child("Contact_glass", true, false) != null and root.find_child("Contact_curator", true, false) != null, "%s: known contacts listed" % label)
	await _shot(label, "bm_contacts")
	var buy := _find_visible_button("SupplierBuy_glass_0_cash")
	if buy:
		var n := (SupplierManager.st("glass")["stock"] as Array).size()
		buy.pressed.emit()
		await _frames(10)
		_check((SupplierManager.st("glass")["stock"] as Array).size() == n - 1, "%s: bought from a contact via the UI" % label)
	var stash := _find_visible_button("BMTab_1")
	if stash:
		stash.pressed.emit()
		await _frames(10)
	_check(_find_visible_button("Curator_%d" % InventoryManager.get_instances().find(u)) != null or root.find_children("Analyse_*", "Button", true, false).size() > 0, "%s: unidentified device actions in the stash" % label)
	await _shot(label, "bm_stash_unknown")
	InventoryManager.remove_instance(u.uid)
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _security(label: String) -> void:
	var root := get_tree().root
	ClinicManager.upgrades[ClinicManager.clinic_id()] = {"security": 1}
	EconomyManager.add_money(2000)
	FactionManager.add_heat(55.0 - FactionManager.heat)
	var c := SecurityManager.roll_theft(true)
	_check(not c.is_empty(), "%s: a break-in" % label)
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	await _frames(5)
	var b := _find_visible_button("SecurityButton")
	_check(b != null and b.text.contains("OPEN CASE"), "%s: the SECURITY button shows open cases" % label)
	if b:
		b.pressed.emit()
		await _frames(10)
	_check(root.find_child("SecurityPanel", true, false) != null, "%s: security panel opens" % label)
	var cam := _find_visible_button("Investigate_%d_cameras" % int(c["id"]))
	if cam:
		cam.pressed.emit()
		await _frames(5)
	_check((SecurityManager.get_case(int(c["id"]))["clues"] as Array).size() >= 1, "%s: cameras give a clue from the UI" % label)
	await _shot(label, "security_panel")
	UIManager.close_modal()
	FactionManager.add_heat(-FactionManager.heat)
	await _settle()


## Every clinic: the Wall and the waiting room sit in clear space.
func _rooms() -> void:
	Settings.resolution = "1920x1080"
	Settings.apply_display()
	await _frames(10)
	for i in 12:
		ClinicLifeManager.pin("milestone" if i % 3 else "patient", "pin %d" % i)
	for i in ClinicManager.tiers.size():
		if not ClinicManager.owned.has(i):
			ClinicManager.owned.append(i)
		ClinicManager.move_to(i)
		BusinessManager.jobs_today = 0
		ClinicLifeManager.waiting.clear()
		CustomerManager.debug_set_customer(CustomerManager.generator.generate({"full_difficulty": true}))
		ClinicManager.upgrades[ClinicManager.clinic_id()] = {"customer": 2}
		for k in 2:
			ClinicLifeManager.seat(CustomerManager.generator.generate({"full_difficulty": true, "faction": "independent_mercs"}))
		UIManager.go_to(UIManager.SCREEN_CLINIC)
		await _settle()
		UIManager.close_modal()
		await _frames(10)
		_check(ClinicLifeManager.waiting.size() >= 1, "%s: people waiting" % ClinicManager.clinic_id())
		await _shot("room", ClinicManager.clinic_id())
	ClinicLifeManager.waiting.clear()
	CustomerManager.dismiss_current()


func _find_visible_button(n: String) -> Button:
	for b in get_tree().root.find_children(n, "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


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
