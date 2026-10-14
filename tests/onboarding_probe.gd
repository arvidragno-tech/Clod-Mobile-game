extends Node
## Onboarding probe (3.7): a first-time player in the real, rendered game,
## with real clicks and keys.
##  1 a new game shows only the clinic (no padlocks, no staff, no city)
##  2 CLINIC STATUS: one headline, nothing else during the first patient
##  3 SEE PATIENT opens the PATIENT SUMMARY; its numbers are the game's own
##    (JobEstimate, Recommend) and DECLINE / MORE DETAILS / ACCEPT work
##  4 a hidden section's hotkey explains when it opens
##  5 after the first job: SKILLS, SUPPLY, INVENTORY, BUSINESS, JOURNAL
##    appear, each with an intro card (WHAT / WHY / HOW / COST)
##  6 SUPPLY shows BEFORE YOU PAY (cash now -> after)
##  7 the FIELD GUIDE: entries held back until introduced, NEW, SEE ALSO and
##    BACK, TUTORIALS (show again)
##  8 three jobs in: STAFF and FACILITY; later the city
##  9 an old save keeps every section; INTRODUCE FEATURES GRADUALLY off
##    shows everything
## then the summary and the clinic at 1920x1080, 1600x900, 1366x768,
## 1280x720 windowed plus borderless and fullscreen (all buttons on-screen).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/onboarding_probe.tscn -- --shots=/abs/dir

var _shots: String = ""
var _fails: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	Settings.path = "user://onboarding_probe_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	Settings.set_value("controls_setup_done", true)
	Settings.set_value("tutorial_hints", false)  # no coach marks: this probe drives the flow itself
	Controls.apply_bindings()
	SaveManager.save_dir = "user://onboarding_probe_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	SaveManager.use_slot(1)
	SaveManager.delete_save()
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(40)
	await _flow()
	for mode_res: Array in [["windowed", "1920x1080"], ["windowed", "1600x900"], ["windowed", "1366x768"], ["windowed", "1280x720"], ["borderless", "1920x1080"], ["fullscreen", "1920x1080"]]:
		Settings.window_mode = str(mode_res[0])
		Settings.resolution = str(mode_res[1])
		Settings.apply_display()
		await _frames(20)
		await _layout_round("%s_%s" % [mode_res[0], mode_res[1]])
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("ONBOARDING PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("ONBOARDING PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _flow() -> void:
	# 1. A new game: only the clinic.
	GameManager.start_new_game()
	await _settle()
	await _until(func() -> bool: return CustomerManager.has_customer())
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC, "1: a new game opens on the clinic")
	_check(_find_visible("Nav_clinic") != null and _find_visible("Nav_settings") != null and _find_visible("Nav_help") != null, "1: CLINIC, SETTINGS and FIELD GUIDE are there")
	var hidden: Array[String] = []
	for id in ["staff", "skills", "upgrades", "business", "inventory", "supply", "database", "blackmarket", "map", "dossier"]:
		if _find_visible("Nav_%s" % id) != null:
			hidden.append(id)
	_check(hidden.is_empty(), "1: nothing else yet, no padlocks (%s)" % [hidden])
	# 2. The status line: one sentence, no extra rows during the first patient.
	var head := _find_visible("StatusHeadline") as Button
	_check(head != null and head.text.begins_with("Jobs 0 /"), "2: a quiet clinic's one status line is today's progress (%s)" % (head.text if head else "-"))
	_check(_find_visible("Status_heat") == null and _find_visible("Status_rep") == null, "2: no permanent status rows on the first patient")
	_check(_find_visible("ObjectiveWhy") != null and (_find_visible("ObjectiveWhy") as Label).text != "", "2: the NEXT line says why it matters")
	await _shot("01_new_game_clinic")
	# 4. A hidden section's hotkey (STAFF, T) explains instead of opening.
	await _key(Controls.get_slots("staff")[0] as Key)
	await _frames(6)
	_check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC, "4: the STAFF key doesn't open a section that isn't introduced")
	# 3. The patient summary.
	await _press_named("SeeButton")
	await _frames(10)
	_check(_find_visible("PatientSummary") != null, "3: SEE PATIENT opens the patient summary")
	# Level 1: what they want, the one risk, the money, three actions.
	for blk in ["SummaryWants", "SummaryMargin", "AcceptButton", "SummaryDetails", "SummaryDecline"]:
		_check(_find_visible(blk) != null, "3: the summary shows %s" % blk)
	_check(_find_visible("SummarySuccess") == null and _find_visible("IntakeForm") == null, "3: odds and the intake form wait behind DETAILS")
	var c := CustomerManager.current_customer
	var est := JobEstimate.for_customer(c, GameManager.get_surgery_readiness())
	var odds := roundi(float(Recommend.self_estimate(c)["chance"]) * 100.0)
	var ml := _find_visible("SummaryMargin")
	_check(ml != null and _text_of(ml).contains("%+d" % int(est["net"])) and _text_of(ml).contains("before rent"), "3: the money line is JobEstimate's direct margin (%+d)" % int(est["net"]))
	await _shot("02_patient_summary")
	# Level 2: DETAILS.
	await _press_named("SummaryDetails")
	await _frames(6)
	var sl := _find_visible("SummarySuccess")
	_check(sl != null and _text_of(sl).contains("%d%%" % odds), "3: DETAILS: YOUR ODDS is the game's estimate (%d%%)" % odds)
	_check(_find_visible("SummaryCosts") != null, "3: DETAILS: the costs line by line")
	# Level 3: the intake form, every line sourced.
	await _press_named("SummaryForm")
	await _frames(6)
	_check(_find_visible("IntakeForm") != null and _find_visible("IntakeRisks") != null and _find_visible("IntakeHistory") != null, "3: INTAKE FORM shows the patient's record")
	var form_text := _text_of(_find_visible("IntakeForm"))
	_check(form_text.contains("REPORTED") and form_text.contains("ON FILE") and form_text.contains("UNKNOWN"), "3: form lines say where they come from")
	_check(_find_visible("IntakeLegend") != null, "3: the form explains its labels")
	# FULL FILE opens the file; back, then ACCEPT goes to the scan.
	await _press_named("SummaryDetails")
	await _frames(6)
	await _press_named("SummaryFile")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_CUSTOMER, "3: FULL FILE opens the patient's file")
	GameManager.go_to_clinic()
	await _settle()
	await _key(Controls.get_slots("customer_info")[0] as Key)
	await _frames(10)
	_check(_find_visible("PatientSummary") != null, "3: the customer key opens the summary too")
	await _key(KEY_ESCAPE)
	await _frames(6)
	_check(_find_visible("PatientSummary") == null and CustomerManager.has_customer(), "3: ESC closes it; the patient still waits")
	await _press_named("SeeButton")
	await _frames(8)
	await _press_named("AcceptButton")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DIAGNOSIS, "3: ACCEPT JOB goes to the scan")
	# 5. The first job done (the operation itself is covered by the E2E bot).
	CustomerManager.dismiss_current()
	EventManager.operations = 1
	SkillManager.points = maxi(1, SkillManager.points)
	Hints.enabled = true
	GameManager.go_to_clinic()
	await _settle()
	await _frames(10)
	var shown: Array[String] = []
	for id in ["skills", "supply", "inventory", "business", "dossier"]:
		if _find_visible("Nav_%s" % id) != null:
			shown.append(id)
	_check(shown == ["skills"], "5: after the first job only SKILLS appears (%s)" % [shown])
	_check(_find_visible("Nav_staff") == null and _find_visible("Nav_map") == null, "5: STAFF and the city still wait")
	var coach := _find_visible("CoachCard")
	_check(coach != null and _text_of(coach).contains("SKILLS"), "5: a new section is introduced by one coach step on its button")
	await _shot("03_feature_intro")
	await _dismiss_intros()
	# The second job: supply, inventory and the journal.
	EventManager.operations = 2
	Features.refresh()
	GameManager.go_to_clinic()
	await _settle()
	await _frames(10)
	_check(_find_visible("Nav_supply") != null and _find_visible("Nav_inventory") != null and _find_visible("Nav_dossier") != null, "5: two jobs in: SUPPLY, INVENTORY, JOURNAL")
	_check(_find_visible("Nav_business") == null or BusinessManager.day >= 2 or BusinessManager.debt > 0, "5: BUSINESS waits for the second day")
	await _dismiss_intros()
	_check(TutorialManager.intro_pending.is_empty(), "5: every intro was shown once")
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	# 6. SUPPLY: before you pay.
	await _press_named("Nav_supply")
	await _settle()
	await _frames(6)
	_check(_find_visible("DecisionPreview") != null and _find_visible("PreviewCash") != null, "6: SUPPLY shows BEFORE YOU PAY (cash now -> after)")
	var cash := _text_of(_find_visible("PreviewCash"))
	_check(cash.contains(EconomyManager.format_money(EconomyManager.money)), "6: the preview uses your real cash (%s)" % cash)
	await _shot("04_supply_preview")
	# 7. The field guide.
	GameManager.go_to_clinic()
	await _settle()
	Glossary.open_guide("staff")
	await _frames(6)
	_check(_find_visible("Guide_stress") == null, "7: entries for sections not introduced yet are held back")
	Glossary.close()
	Glossary.open_guide("money", "direct_margin")
	await _frames(6)
	_check(_find_visible("Guide_direct_margin") != null, "7: DIRECT MARGIN is explained")
	var see := _find_visible_button("SeeAlso_direct_margin_the_money")
	_check(see != null, "7: SEE ALSO links related entries")
	if see:
		await _press(see)
		await _frames(6)
		_check(_find_visible("Guide_the_money") != null, "7: SEE ALSO opens the related entry")
		await _press_named("GuideBack")
		await _frames(6)
		_check(_find_visible("Guide_direct_margin") != null, "7: BACK returns to where you were")
	await _shot("05_field_guide")
	await _press_named("GuideTopic_tutorials")
	await _frames(6)
	_check(_find_visible("Tutorial_supply") != null and _find_visible("TutorialAgain_supply") != null, "7: TUTORIALS lists what was introduced, with SHOW AGAIN")
	await _shot("06_tutorials")
	await _press_named("TutorialAgain_supply")
	await _frames(6)
	_check(_find_visible("CoachCard") != null, "7: SHOW AGAIN brings the introduction back")
	await _press_named("CoachDone")
	await _frames(4)
	Hints.dismiss()
	Glossary.close()
	# 8. Three jobs in: staff and facility. Four: the city.
	EventManager.operations = 3
	GameManager.go_to_clinic()
	await _settle()
	_check(_find_visible("Nav_staff") != null and _find_visible("Nav_upgrades") != null, "8: three jobs in: STAFF and FACILITY")
	EventManager.operations = 4
	Features.refresh()
	await _frames(4)
	_check(Features.is_on(&"map"), "8: four jobs in: the city")
	_check(not Features.is_on(&"blackmarket") or BlackMarketManager.is_unlocked(), "8: the black market keeps its own rule (a contact or street rep)")
	# 9. Old saves keep everything; the setting shows everything.
	TutorialManager.load_save_data({"active": false, "step": -1, "completed": true})
	var all_on := true
	for id: StringName in Features.LIST:
		if id != &"blackmarket":
			all_on = all_on and Features.is_on(id)
	_check(all_on, "9: a save from before 3.7 keeps every section (no cards)")
	_check(TutorialManager.intro_pending.is_empty(), "9: ... and shows no intro cards")
	TutorialManager.introduced = {}
	Settings.set_value("progressive_features", false)
	_check(Features.is_on(&"staff") and Features.is_on(&"map"), "9: INTRODUCE FEATURES GRADUALLY off shows every section")
	Settings.set_value("progressive_features", true)
	Features.refresh()
	_check(Features.is_on(&"staff"), "9: a lost flag re-introduces what is relevant")


func _layout_round(label: String) -> void:
	UIManager.close_modal()
	Glossary.close()
	Hints.dismiss()
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	GameManager.go_to_clinic()
	await _settle()
	_layout_guard("%s/clinic" % label)
	GameManager.show_patient_summary()
	await _frames(8)
	_check(_find_visible("PatientSummary") != null, "%s: the summary opens" % label)
	_layout_guard("%s/summary" % label)
	if label == "windowed_1366x768":
		await _shot("07_summary_1366")
	UIManager.close_modal()
	CustomerManager.dismiss_current()


# --- helpers ---------------------------------------------------------------------------------

func _text_of(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	if n is Label:
		out += (n as Label).text + " "
	elif n is Button:
		out += (n as Button).text + " "
	for ch in n.get_children():
		out += _text_of(ch)
	return out


func _until(cond: Callable, max_frames: int = 600) -> void:
	var i := 0
	while not cond.call() and i < max_frames:
		await get_tree().process_frame
		i += 1


## GOT IT on each pending section introduction, in turn.
func _dismiss_intros() -> void:
	for i in 8:
		if _find_visible("CoachDone") == null:
			break
		await _press_named("CoachDone")
		await _frames(4)
		GameManager.go_to_clinic()
		await _settle()
		await _frames(4)


func _find_visible(n: String) -> Node:
	for x in get_tree().root.find_children(n, "", true, false):
		if x is CanvasItem and (x as CanvasItem).is_visible_in_tree():
			return x
	return null


func _find_visible_button(n: String) -> Button:
	for b in get_tree().root.find_children(n, "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


func _press_named(n: String) -> void:
	var b := _find_visible_button(n)
	_check(b != null, "button %s is there" % n)
	if b:
		await _press(b)


func _press(b: Button) -> void:
	var p := b.get_parent()
	while p:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(b)
			await _frames(2)
			break
		p = p.get_parent()
	await _click(b.get_global_rect().get_center())


func _click(pos: Vector2) -> void:
	var vp := get_viewport()
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	vp.push_input(m, true)
	await _frames(2)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		vp.push_input(e, true)
		await _frames(2)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		get_viewport().push_input(e, true)
		await _frames(2)


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


func _shot(name: String) -> void:
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [_shots, name])


func _layout_guard(label: String) -> void:
	var view := get_viewport().get_visible_rect().grow(1.0)
	var bad: Array[String] = []
	for n in get_tree().root.find_children("*", "BaseButton", true, false):
		var b := n as Control
		if not b.is_visible_in_tree() or b.get_window() != get_tree().root:
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
