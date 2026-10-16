extends Node
## 3.11 end-to-end probe on the rendered game, with real clicks and keys:
##  - a new game opens on the opening cutscene; nobody knocks while it
##    plays; a click finishes the line, another moves on; ESC skips; the
##    first patient knocks after it;
##  - a chapter card ends by itself (no input) in reasonable time;
##  - the SKIP button ends a scene and the conversation it leads into
##    follows;
##  - a story case at the door, its decision, and the cutscene it queues;
##  - the clinic and a street in each season (screenshots), with the
##    season's weather on the street;
##  - after a story case, the next knock waits longer than after a routine
##    patient;
##  - 3.12: a patient your standing brought (who sent them, what they say),
##    the decision that follows (named as one, its rivals shown, the
##    betrayal telegraphed), and the NEXT line bringing it back when it
##    isn't on screen.
##   godot --path . res://tests/narrative_probe.tscn -- [--shots=DIR]

var _shots: String = ""
var _fails: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	Settings.path = "user://narrative_probe_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	Settings.story_cutscenes = true
	Settings.text_speed = 2
	Controls.apply_bindings()
	SaveManager.save_dir = "user://narrative_probe_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(30)
	await _opening()
	await _chapter_card_runs_by_itself()
	await _skip_button_then_conversation()
	await _story_case()
	await _reactive_case()
	await _breathers()
	await _seasons()
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("3.11 NARRATIVE PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("3.11 NARRATIVE PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _player() -> CutscenePlayer:
	var m := UIManager.top_modal()
	return m as CutscenePlayer


func _opening() -> void:
	GameManager.start_new_game_in_slot(1)
	await _settle()
	var p := _player()
	_check(p != null and p.cutscene_id == &"cs_opening", "opening: a new game opens on the opening scene")
	var line := _find_visible("CutsceneLine") as Label
	_check(line != null and line.text.begins_with("Caldera"), "opening: the first line is typed out (%s)" % (line.text if line else "none"))
	# Nobody knocks during a scene, however long it takes.
	await _wait(1.0)
	await _shot("311_opening_1")
	await _wait(1.5)
	_check(not CustomerManager.has_customer(), "opening: nobody knocks while the scene plays")
	await _click(Vector2(960, 540))  # finish the line (or go on)
	if p and is_instance_valid(p) and p._index == 0:
		await _click(Vector2(960, 540))
	await _wait(1.0)
	_check(p != null and is_instance_valid(p) and p._index >= 1, "opening: a click moves the scene on")
	await _shot("311_opening_2")
	await _key(KEY_ESCAPE)
	await _wait(1.0)
	_check(_player() == null, "opening: ESC skips the rest")
	var t := 0.0
	while not CustomerManager.has_customer() and t < 8.0:
		await _wait(0.25)
		t += 0.25
	_check(CustomerManager.has_customer() and CustomerManager.current_customer.character_id == &"mara_quill", "opening: the first patient knocks after the scene (%.1f s)" % t)
	TutorialManager.skip()
	UIManager.close_modal()
	await _frames(4)


func _chapter_card_runs_by_itself() -> void:
	CustomerManager.dismiss_current()
	StoryManager.talk_queue.clear()
	StoryManager.advance_act()  # ACT II
	StoryManager.talk_queue.clear()
	EventManager.pending_event = &""
	await _frames(10)
	var p := _player()
	_check(p != null and p.cutscene_id == &"cs_act_2", "chapter: a new act plays its card")
	var card := _find_visible("CutsceneCard") as Label
	_check(card != null and card.text == "ACT II · REPUTATION", "chapter: the card names the act")
	await _shot("311_chapter_card")
	var t := 0.0
	while _player() != null and t < 30.0:
		await _wait(0.25)
		t += 0.25
	_check(_player() == null and t < 20.0, "chapter: it ends by itself without input (%.1f s)" % t)
	await _frames(10)
	UIManager.close_modal()


func _skip_button_then_conversation() -> void:
	StoryManager.cutscene_queue.clear()
	StoryManager.talk_queue.clear()
	EventManager.pending_event = &""
	CustomerManager.dismiss_current()
	UIManager.close_modal()
	await _frames(4)
	StoryManager.act = 2
	StoryManager.advance_act()  # ACT III: the card, then Voss walks in (beat b_act3)
	await _frames(12)
	_check(_player() != null and _player().cutscene_id == &"cs_act_3", "skip: the act III scene plays first")
	_check(StoryManager.has_talk(), "skip: Voss's conversation waits behind it")
	await _wait(0.6)
	await _press_named("CutsceneSkip")
	await _wait(1.2)
	var talk := UIManager.top_modal()
	_check(talk is DialoguePanel, "skip: SKIP ends the scene and the conversation follows (%s)" % (talk.name if talk else "nothing"))
	await _shot("311_after_skip_conversation")
	UIManager.close_modal()
	StoryManager.talk_queue.clear()
	await _frames(6)


func _story_case() -> void:
	StoryManager.cutscene_queue.clear()
	StoryManager.talk_queue.clear()
	EventManager.pending_event = &""
	UIManager.close_modal()
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	var c := CustomerManager.make_case_customer(StoryManager.get_case(&"case_lyra_runaway"))
	CustomerManager.debug_set_customer(c)
	await _frames(10)
	GameManager.show_patient_summary()
	await _frames(10)
	_check(c.dialogue.begins_with("Bed 14"), "case: the runaway says her own words")
	await _shot("311_case_at_door")
	UIManager.close_modal()
	# The operation itself is the E2E's; here the case ends (away from the
	# clinic, as after the results screen) and its decision follows.
	InventoryManager.supplies = 10
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_INVENTORY)
	await _settle()
	StoryManager.case_finished(c, "success")
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	await _frames(6)
	_check(UIManager.top_modal() is EventPanel, "case: BED 14 asks for a decision in the clinic")
	await _shot("311_case_decision")
	await _press_named("Choice_0")
	await _frames(6)
	await _press_named("EventContinue")
	await _frames(12)
	var p := _player()
	_check(p != null and p.cutscene_id == &"cs_runaway_freed", "case: cutting the lattice out plays its short scene")
	_check(ClinicLifeManager.has_pin("case_runaway") and StoryManager.has_flag(&"runaway_freed"), "case: and leaves its mark on the Wall")
	await _wait(1.5)
	await _shot("311_case_scene")
	await _key(KEY_ESCAPE)
	await _wait(1.0)
	_check(_player() == null, "case: ESC skips it")


func _reactive_case() -> void:
	UIManager.close_modal()
	StoryManager.cutscene_queue.clear()
	StoryManager.talk_queue.clear()
	EventManager.pending_event = &""
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	FactionManager.rep[&"street_gangs"] = 20
	FactionManager.rep[&"corporate_security"] = 0
	var c := CustomerManager.make_case_customer(StoryManager.get_case(&"case_crew_lieutenant"))
	CustomerManager.debug_set_customer(c)
	await _frames(10)
	var sent := _find_visible("DoorSentBy") as Label
	_check(sent != null and sent.text == "Sent by Rook Varga", "reactive: the door card says who sent him (%s)" % (sent.text if sent else "none"))
	await _shot("312_door_sent_by")
	await _press_named("SeeButton")
	await _frames(10)
	var said := _find_visible("SummarySaid") as Label
	_check(said != null and said.text.contains("Rook"), "reactive: the summary lets him speak (his words carry the story)")
	await _shot("312_summary_said")
	UIManager.close_modal()
	InventoryManager.supplies = 10
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_INVENTORY)
	await _settle()
	StoryManager.case_finished(c, "success")
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	await _frames(6)
	var panel := UIManager.top_modal() as EventPanel
	_check(panel != null and panel.event_id == &"case_lieutenant_after", "reactive: THE BOUNTY asks for a decision")
	var labels := ""
	if panel:
		for l in panel.find_children("*", "Label", true, false):
			labels += (l as Label).text + "\n"
	_check(labels.contains("DECISION") and not labels.contains("INCIDENT"), "reactive: it's headed DECISION, not INCIDENT")
	_check(labels.contains("(rivals)"), "reactive: the choice shows what the rivals will think")
	var sell := _find_visible_button("Choice_1")
	_check(sell != null and sell.text.contains("Rook will find out"), "reactive: the betrayal says who will know (%s)" % (sell.text if sell else "none"))
	await _shot("312_decision")
	# Not on screen (closed by something else): the NEXT line brings it back.
	UIManager.close_modal()
	await _frames(20)
	var obj := _find_visible("Objective") as Label
	_check(obj != null and obj.text.contains("DECIDE: THE BOUNTY"), "reactive: NEXT names the waiting decision (%s)" % (obj.text if obj else "none"))
	var bar := _find_visible("StatusHeadline") as Button
	_check(bar != null and not bar.text.contains("ACTION REQUIRED"), "reactive: the bar under the room doesn't say it a second time (%s)" % (bar.text if bar else "none"))
	await _shot("312_next_decide")
	if obj:
		await _click(obj.get_global_rect().get_center())
	await _frames(10)
	_check(UIManager.top_modal() is EventPanel, "reactive: clicking NEXT brings the decision back")
	await _press_named("Choice_0")
	await _frames(6)
	await _press_named("EventContinue")
	await _frames(10)
	_check(StoryManager.has_flag(&"sided_crews"), "reactive: keeping him hidden puts you with the Crews")
	UIManager.close_modal()


func _breathers() -> void:
	UIManager.close_modal()
	StoryManager.talk_queue.clear()
	EventManager.pending_event = &""
	CustomerManager.dismiss_current()
	CustomerManager.breather_scale = 1.0
	CustomerManager.visits_today = 0
	CustomerManager.story_slot = 99
	CustomerManager.quiet_until = -1
	ClinicLifeManager.waiting.clear()
	BusinessManager.jobs_today = 0
	TimeManager.minute = 700
	var times := {}
	for kind in [&"routine", &"story"]:
		CustomerManager.dismiss_current()
		CustomerManager.stop_arrivals()  # whoever was already on the way (the screen asks on customer_left)
		CustomerManager.last_kind = kind
		var start := Time.get_ticks_msec()
		CustomerManager.request_next_customer()
		while not CustomerManager.has_customer() and Time.get_ticks_msec() - start < 12000:
			await _frames(1)
		times[kind] = (Time.get_ticks_msec() - start) / 1000.0
	_check(float(times[&"routine"]) >= 2.0 and float(times[&"story"]) >= float(times[&"routine"]) + 3.0,
		"pacing: the next knock waits %.1f s after a routine patient and %.1f s after a story case" % [times[&"routine"], times[&"story"]])
	CustomerManager.dismiss_current()


func _seasons() -> void:
	UIManager.close_modal()
	StoryManager.talk_queue.clear()
	EventManager.pending_event = &""
	CustomerManager.dismiss_current()
	BusinessManager.doors_open = false
	var len := TimeManager.season_length()
	for i in 4:
		var id := StringName(str(TimeManager._season_order()[i]))
		# A wet (or hazy) day in the middle of the season.
		var day := 1 + i * len + 2
		for d in range(1 + i * len, 1 + i * len + len - 2):
			if float(TimeManager.weather(d)["density"]) > 0.0:
				day = d
				break
		BusinessManager.day = day
		TimeManager.minute = 1300
		TimeManager._season_ambience()
		UIManager.go_to(UIManager.SCREEN_CLINIC)
		await _settle()
		UIManager.close_modal()
		await _frames(30)
		_check(TimeManager.stamp().contains(TimeManager.season_label()), "%s: the clinic's clock names the season" % id)
		await _shot("311_season_%s_clinic" % id)
		LocationManager.player_location = &"sump_tenements"
		UIManager.go_to(UIManager.SCREEN_LOCATION)
		await _settle()
		UIManager.close_modal()
		await _frames(60)
		var view: LocationView = null
		for n in get_tree().root.find_children("*", "LocationView", true, false):
			if (n as Control).is_visible_in_tree():
				view = n
		var w := TimeManager.weather()
		var kinds := {}
		if view:
			for k in view._drop_kind:
				kinds[LocationView.WEATHER_KINDS[k]] = true
		var expect := str(w["kind"])
		# Haze is a band of light, not particles; the summer's second weather is rain.
		var fits := expect == "haze" or kinds.has(expect)
		_check(view != null and fits, "%s: the street shows %s (%s)" % [id, expect, ", ".join(kinds.keys())])
		await _shot("311_season_%s_street" % id)
		LocationManager.player_location = LocationManager.CLINIC
	BusinessManager.doors_open = true
	BusinessManager.day = 1


# --- helpers (as in clinic_310_probe) -----------------------------------------------------

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
		get_viewport().push_input(e)
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


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [_shots, name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
