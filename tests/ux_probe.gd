extends Node
## UX probe (3.5): plays the early game in the real, rendered game with
## real mouse clicks and key presses, the way a new player would:
##  1 launch (first-launch control setup)    2 configure controls (search,
##  REPLACE conflict, CTRL combo, critical key, ESC cancels)
##  3 new game    4 the first patient from WHAT MATTERS NOW    5 the file
##  (recommendation)    6 diagnose    7 surgery preview    8 the recommended
##  ripperdoc    9 operate    10 results    11 the new lead    12 the map by
##  the player's own key    13 travel    14 meet someone    15 follow
##  16 the journal's MAIN page    recent changes    17-19 key conflicts
##  20-23 restart keeps the custom key, reset restores defaults
##  24 context-sensitive input (text field, guide, dialog, clinic ESC)
##  25-26 save and load keep follows and recent changes
## then checks every main UX screen at 1920x1080, 1600x900, 1366x768,
## 1280x720 windowed plus borderless and fullscreen (all buttons on-screen).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/ux_probe.tscn -- --shots=/abs/dir

var _shots: String = ""
var _fails: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	Hints.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	# A first launch: fresh settings, no saves.
	Settings.path = "user://ux_probe_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	Controls.apply_bindings()
	SaveManager.save_dir = "user://ux_probe_saves"
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
	Controls.reset_bindings()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("UX PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("UX PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _flow() -> void:
	var root := get_tree().root
	# 1. Launch: the main menu offers a quick control setup once.
	_check(UIManager.current_screen_id == UIManager.SCREEN_MAIN_MENU, "1: the game launches to the main menu")
	_check(_find_visible("ControlSetup") != null, "1: first launch offers DEFAULT / CUSTOMIZE controls")
	await _shot("01_first_launch")
	# 2. Configure controls.
	await _press_named("SetupCustomize")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_SETTINGS and _find_visible("ControlSearch") != null, "2: CUSTOMIZE opens Settings > Controls")
	var search := _find_visible("ControlSearch") as LineEdit
	if search:
		search.text = "map"
		search.text_changed.emit("map")
		await _frames(4)
		_check(_find_visible_button("Bind_map_0") != null and _find_visible_button("Bind_tool_1_0") == null, "2: searching 'map' narrows the list")
		await _shot("02_controls_search")
		search.text = ""
		search.text_changed.emit("")
		search.release_focus()
		await _frames(4)
	# REPLACE: give OPEN MAP the TAB key (Cycle panels has it).
	await _press_named("Bind_map_0")
	await _frames(3)
	_check(_find_visible_button("Bind_map_0") != null and (_find_visible_button("Bind_map_0").text.contains("PRESS")), "17: clicking a key shows PRESS ANY KEY")
	await _key(KEY_TAB)
	await _frames(6)
	_check(_find_visible("BindReplace") != null, "18: TAB is taken: a KEY CONFLICT dialog appears")
	await _shot("03_key_conflict")
	await _press_named("BindReplace")
	await _settle()
	_check(Controls.get_slots("map")[0] == KEY_TAB and Controls.is_unassigned("cycle_panel"), "19: REPLACE: map is TAB, cycle panels is unassigned")
	var status := _find_visible("BindStatus") as Label
	_check(status != null and status.text.contains("TAB"), "19: the change is confirmed on screen (%s)" % (status.text if status else "-"))
	# A second binding with a modifier: CTRL+M.
	await _press_named("Bind_map_1")
	await _frames(3)
	await _key(KEY_CTRL, true)
	await _key(KEY_M, true)
	await _key_up(KEY_CTRL)
	await _frames(6)
	_check(Controls.get_slots("map")[1] == (KEY_M | KEY_MASK_CTRL), "2: a secondary CTRL+M binding (%s)" % Controls.code_name(Controls.get_slots("map")[1]))
	# The critical action keeps its key.
	await _press_named("Bind_pause_0")
	await _frames(3)
	await _key(KEY_DELETE)
	await _frames(4)
	_check(Controls.get_keys("pause") == [KEY_ESCAPE], "2: pause/back can't be unassigned")
	# ESC cancels a rebind.
	await _press_named("Bind_journal_0")
	await _frames(3)
	await _key(KEY_ESCAPE)
	await _frames(4)
	_check(Controls.get_slots("journal")[0] == KEY_J and UIManager.current_screen_id == UIManager.SCREEN_SETTINGS, "24: ESC cancels rebinding (and stays on the screen)")
	await _shot("04_controls_custom")
	await _press_named("BackButton")
	await _settle()
	# 3. New game.
	await _press_named("NewGameButton")
	await _settle()
	TutorialManager.skip()
	UIManager.close_modal()
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC, "3: NEW GAME starts in the clinic")
	_check(Settings.controls_setup_done, "3: the setup offer is done")
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	WorldSimulationManager.auto_roll = false
	EventManager.operations = 10
	EconomyManager.money = 4000
	InventoryManager.supplies = 10
	# A ripperdoc on the team (for the recommendation).
	var e := StaffManager.generate_candidate()
	e["clinic"] = ClinicManager.tier
	e["skill"] = 5
	e["stress"] = 0.0
	e["status"] = "working"
	e["traits"] = []
	e["ethics"] = []
	StaffManager.employees.append(e)
	# 4. The first patient, found through WHAT MATTERS NOW.
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	InventoryManager.add_implant(c.requested_cyberware_id)
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	await _frames(10)
	var door := _find_matter("at the door")
	_check(door != null, "4: WHAT MATTERS NOW lists the patient at the door")
	_check(_find_visible("ClinicStatus") != null and _find_visible("StatusHeadline") != null, "4: CLINIC STATUS sums up the clinic in one headline")
	await _shot("05_clinic_priorities")
	if door:
		await _press(door)
		await _frames(10)
	_check(_find_visible("PatientSummary") != null, "4: clicking the line opens the patient summary")
	await _press_named("SummaryDetails")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_CUSTOMER, "4: MORE DETAILS opens the patient's file")
	# 5. The file: the recommendation and the decision.
	var rec := _find_visible("Recommendation") as Label
	_check(rec != null and rec.text.begins_with("RECOMMENDED"), "5: the file recommends who should operate")
	await _shot("06_customer_file")
	# 8. The recommended ripperdoc (listed first, starred).
	await _press_named("AssignButton")
	await _frames(6)
	var star := false
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text.contains("RECOMMENDED") and (l as Label).text.contains("★"):
			star = true
	_check(star, "8: the best ripperdoc is marked ★ RECOMMENDED with a reason")
	await _shot("07_recommended_staff")
	# 5-6. Do it yourself: diagnose.
	await _press_named("AcceptButton")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DIAGNOSIS, "5: PERFORM opens the body scan")
	for r in ["head", "neck", "torso"]:
		var b := _find_visible_button("Scan_%s" % r)
		if b:
			await _press(b)
			await _frames(40)
	var opt: Button = null
	for n in root.find_children("Option_*", "Button", true, false):
		if (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			opt = n
			break
	_check(opt != null, "6: scans unlock the diagnoses")
	if opt:
		await _press(opt)
		await _frames(3)
		await _press_named("ConfirmButton")
		await _frames(10)
	# 7. The surgery preview.
	var pv := _find_visible("SurgeryPreview")
	var pv_text := ""
	if pv:
		for l in pv.find_children("*", "Label", true, false):
			pv_text += (l as Label).text + " | "
	for key in ["DIFFICULTY", "PATIENT RISK", "TIME", "COST", "PAYMENT", "COMPLICATIONS", "YOUR ODDS", "RECOMMENDED"]:
		_check(pv_text.contains(key), "7: the preview shows %s" % key)
	_check(_find_visible_button("ChangeSurgeon") != null, "8: CHANGE SURGEON offers the ripperdoc")
	await _shot("08_surgery_preview")
	# 9. Operate (the operation itself is played by the E2E bot; here it ends clean).
	var mark := ChangeLog.mark()
	await _press_named("BeginButton")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_SURGERY, "9: BEGIN starts the operation")
	await _frames(20)
	for rid: StringName in StoryManager.rumor_order:
		if not StoryManager.unlocked_rumors.has(rid):
			StoryManager.unlock_rumor(rid)
			break
	SurgeryManager._finish(true, &"")
	await _settle()
	for i in 200:
		if UIManager.current_screen_id == UIManager.SCREEN_RESULTS:
			break
		await _frames(5)
	await _frames(120)
	# 10. Results.
	_check(UIManager.current_screen_id == UIManager.SCREEN_RESULTS, "10: the results screen explains the outcome")
	_check(not ChangeLog.since(mark, ["lead"]).is_empty(), "11: the job produced a new lead")
	_check(_find_visible_button("ViewLead") != null, "11: VIEW NEW LEAD is offered")
	await _shot("09_results")
	# 11. The lead.
	await _press_named("ViewLead")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DOSSIER, "11: the lead opens in the journal")
	# 12. The map, by the player's own key (TAB now).
	await _key(KEY_TAB)
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_MAP, "12: the custom key (TAB) opens the map")
	CustomerManager.dismiss_current()
	TimeManager.minute = 1320
	WorldSimulationManager.refresh()
	var map := root.find_child("CityMap", true, false) as CityMapView
	var target := &"rusty_valve"
	if map:
		await _click(map.get_global_rect().position + map.loc_pos(target) * float(GameConfig.PIXEL_SCALE))
		await _frames(5)
	_check(map != null and map.selected_location == target, "12: clicking a place selects it")
	var info_text := ""
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			info_text += (l as Label).text + "\n"
	_check(info_text.contains("Danger") and info_text.contains("GET THERE"), "12: the map says danger, travel time and cost")
	# 15. Follow the place.
	await _press_named("FollowPlace")
	await _frames(5)
	_check(Follows.is_following("place:rusty_valve"), "15: FOLLOW keeps the place")
	await _shot("10_map_follow")
	# 13. Travel there.
	var walk := _find_visible_button("Travel_walk")
	if walk:
		await _press(walk)
	await _settle()
	if WorldSimulationManager.has_encounter():
		var ch := _find_visible_button("Choice_0")
		if ch:
			await _press(ch)
		await _frames(5)
		var cont := _find_visible_button("ChoiceContinue")
		if cont:
			await _press(cont)
		await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_LOCATION, "13: travelling opens the place")
	# 14. Meet someone (a patient you treated walks in here) and follow them.
	await _frames(10)
	var fp := _find_visible_button("FollowPerson_0")
	if fp:
		await _press(fp)
		await _frames(5)
	await _shot("11_location")
	# 16. The journal's MAIN page.
	await _key(KEY_J)
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DOSSIER and _find_visible("Following") != null, "16: J opens the journal on MAIN")
	_check(_find_visible("Followed_place_rusty_valve") != null, "16: the followed place is on MAIN with where/when")
	await _shot("12_journal_main")
	# Recent changes.
	await _key(KEY_G)
	await _frames(6)
	_check(ChangesPanel.is_open() and _find_visible("ChangesList") != null, "recent changes open with G")
	_check(ChangeLog.unread_count() == 0, "opening recent changes marks them read")
	await _shot("13_recent_changes")
	await _key(KEY_ESCAPE)
	await _frames(5)
	_check(not ChangesPanel.is_open() and UIManager.current_screen_id == UIManager.SCREEN_DOSSIER, "24: ESC closes the panel, nothing else")
	# 24. Context-sensitive input.
	GameManager.go_to_clinic()
	await _settle()
	UIManager.close_modal()
	await _frames(5)
	UIManager.go_to(UIManager.SCREEN_INVENTORY)
	await _settle()
	var filter := _find_visible("Filter") as LineEdit
	if filter:
		filter.grab_focus()
		await _frames(2)
		await _key(KEY_J)
		await _frames(5)
		_check(UIManager.current_screen_id == UIManager.SCREEN_INVENTORY, "24: typing J in a text field doesn't open the journal")
		await _key(KEY_ESCAPE)
		await _frames(5)
		_check(UIManager.current_screen_id == UIManager.SCREEN_INVENTORY and get_viewport().gui_get_focus_owner() != filter, "24: ESC leaves the text field first")
	await _key(KEY_F1)
	await _frames(6)
	_check(Glossary.is_open(), "24: F1 opens the field guide")
	await _key(KEY_TAB)
	await _frames(5)
	_check(UIManager.current_screen_id == UIManager.SCREEN_INVENTORY, "24: hotkeys don't navigate under the guide")
	await _key(KEY_ESCAPE)
	await _frames(5)
	_check(not Glossary.is_open(), "24: ESC closes the guide")
	UIManager.confirm("TEST", "A dialog.", "OK", func() -> void: pass)
	await _frames(5)
	await _key(KEY_TAB)
	await _frames(5)
	_check(UIManager.current_screen_id == UIManager.SCREEN_INVENTORY and UIManager.has_modal(), "24: hotkeys don't navigate under a dialog")
	await _key(KEY_ESCAPE)
	await _frames(5)
	_check(not UIManager.has_modal(), "24: ESC closes the dialog")
	LocationManager.player_location = LocationManager.CLINIC
	GameManager.go_to_clinic()
	await _settle()
	UIManager.close_modal()
	await _frames(5)
	await _key(KEY_ESCAPE)
	await _frames(6)
	_check(UIManager.has_modal(), "24: ESC on the clinic opens the pause menu")
	await _key(KEY_ESCAPE)
	await _frames(5)
	UIManager.close_modal()
	# 25-26. Save and load keep follows and recent changes.
	SaveManager.save_game(&"manual")
	var n_follow := Follows.follows.size()
	var n_changes := ChangeLog.entries.size()
	Follows.reset_state()
	ChangeLog.reset_state()
	_check(SaveManager.load_game(), "25: the game loads")
	await _settle()
	_check(Follows.follows.size() == n_follow and n_follow > 0, "26: follows survive save/load (%d)" % n_follow)
	_check(ChangeLog.entries.size() == n_changes, "26: recent changes survive save/load")
	# 20-21. Restart: the custom keys come back from disk.
	Settings.load_settings()
	Controls.apply_bindings()
	_check(Controls.get_slots("map")[0] == KEY_TAB and Controls.get_slots("map")[1] == (KEY_M | KEY_MASK_CTRL), "21: the custom bindings persist across a restart")
	# 22-23. Reset.
	UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.SCREEN_CLINIC, "tab": 2})
	await _settle()
	await _press_named("ResetBind_map")
	await _frames(6)
	_check(Controls.is_default("map"), "22: ↺ resets OPEN MAP")
	await _press_named("ResetCat_General")
	await _frames(6)
	_check(Controls.is_default("cycle_panel"), "23: RESET CATEGORY brings TAB back to cycle panels")
	_check(Controls.current_preset() == "default", "23: defaults are back")
	await _shot("14_controls_reset")
	GameManager.go_to_clinic()
	await _settle()


## Every main UX screen at one window size: all buttons on-screen.
func _layout_round(label: String) -> void:
	UIManager.close_modal()
	Glossary.close()
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	InventoryManager.add_implant(c.requested_cyberware_id)
	for s: Array in [[UIManager.SCREEN_CLINIC, {}], [UIManager.SCREEN_CUSTOMER, {}], [UIManager.SCREEN_DOSSIER, {"tab_name": "MAIN"}],
			[UIManager.SCREEN_DOSSIER, {"tab_name": "PATIENTS"}], [UIManager.SCREEN_SETTINGS, {"tab": 2, "return_to": UIManager.SCREEN_CLINIC}],
			[UIManager.SCREEN_MAP, {"location": &"rusty_valve"}], [UIManager.SCREEN_INVENTORY, {}], [UIManager.SCREEN_STAFF, {}]]:
		UIManager.go_to(s[0], s[1])
		await _settle()
		UIManager.close_modal()
		await _frames(4)
		_layout_guard("%s/%s" % [label, s[0]])
	ChangesPanel.open()
	await _frames(4)
	_check(_find_visible("ChangesList") != null, "%s: recent changes fit" % label)
	Glossary.close()
	CustomerManager.dismiss_current()


# --- helpers ---------------------------------------------------------------------------------

func _find_matter(text: String) -> Button:
	for i in 6:
		var b := _find_visible_button("Matter_%d" % i)
		if b and b.text.to_lower().contains(text):
			return b
	return null


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
	# Bring it into view first (long lists live in scroll containers).
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


## A real key press (and release unless `hold`), optionally with CTRL held.
func _key(code: Key, ctrl: bool = false) -> void:
	var hold := code == KEY_CTRL
	for pressed in ([true] if hold else [true, false]):
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.pressed = pressed
		get_viewport().push_input(e, true)
		await _frames(2)


func _key_up(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = false
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
