extends Node
## Living-city QA in the real, rendered game, with real mouse clicks and
## keys: open the map (hotkey), click a place on the map, travel (time and
## money move), the location screen (street view, people, event, services),
## an encounter on the way, ESC back to the map, return to the clinic, a
## quick save/load while out, every place's screen, at 1920x1080, 1600x900,
## 1366x768 and 1280x720 windowed plus borderless and fullscreen. Checks
## buttons stay on-screen and screenshots everything.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/city_probe.tscn -- --shots=/abs/dir
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
	Settings.path = "user://city_probe_settings.cfg"
	SaveManager.save_dir = "user://test_saves"
	SaveManager.use_slot(2)
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(30)
	GameManager.start_new_game()
	TutorialManager.skip()
	await _settle()
	UIManager.close_modal()
	EventManager.operations = 10
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	for mode_res: Array in [["windowed", "1920x1080"], ["windowed", "1600x900"], ["windowed", "1366x768"], ["windowed", "1280x720"], ["borderless", "1920x1080"], ["fullscreen", "1920x1080"]]:
		Settings.window_mode = str(mode_res[0])
		Settings.resolution = str(mode_res[1])
		Settings.apply_display()
		await _frames(20)
		await _round("%s_%s" % [mode_res[0], mode_res[1]])
	Settings.window_mode = "windowed"
	Settings.resolution = "1920x1080"
	Settings.apply_display()
	await _frames(10)
	await _every_place()
	await _save_load_away()
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("CITY PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("CITY PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


## One full trip: map (hotkey) -> click a place -> travel -> location ->
## event, service, talk -> encounter -> ESC to map -> back to the clinic.
func _round(label: String) -> void:
	WorldSimulationManager.auto_roll = false
	await _go_clinic()
	WorldSimulationManager.used.clear()
	TimeManager.minute = 1320
	EconomyManager.money = 2000
	InventoryManager.supplies = 6
	WorldSimulationManager.refresh()
	# The map, by its hotkey.
	await _key_action(&"map")
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_MAP, "%s: M opens the city map" % label)
	var map := get_tree().root.find_child("CityMap", true, false) as CityMapView
	_check(map != null, "%s: the map view is there" % label)
	if map == null:
		return
	await _shot(label, "map")
	# Click the Rusty Valve's marker with the mouse.
	var target := &"rusty_valve"
	var at := map.get_global_rect().position + map.loc_pos(target) * float(GameConfig.PIXEL_SCALE)
	await _click(at)
	_check(map.selected_location == target, "%s: clicking a place's marker selects it" % label)
	_check(_find_visible_button("Travel_walk") != null, "%s: travel options appear" % label)
	await _shot(label, "map_place")
	var minute := TimeManager.minute
	var b := _find_visible_button("Travel_walk")
	if b:
		await _press(b)
	await _settle()
	if WorldSimulationManager.has_encounter():
		await _handle_choice_modal(label)
	_check(UIManager.current_screen_id == UIManager.SCREEN_LOCATION and LocationManager.player_location == target, "%s: walking there opens the place" % label)
	_check(TimeManager.minute > minute, "%s: the trip took time" % label)
	_check(get_tree().root.find_child("LocationView", true, false) != null, "%s: the street view is drawn" % label)
	# Something happening here.
	WorldSimulationManager.events.erase(String(target))
	WorldSimulationManager.start_event(target, "bar_fight")
	await _frames(5)
	await _shot(label, "location_event")
	var ev := _find_visible_button("LocEvent_0")
	_check(ev != null, "%s: the event's choices are buttons" % label)
	if ev:
		await _press(ev)
		await _frames(5)
	_check(WorldSimulationManager.event_at(target).is_empty(), "%s: choosing resolves the event" % label)
	# A service.
	var sv := _find_visible_button("Service_tout")
	if sv == null:
		WorldSimulationManager.used.erase("rusty_valve|tout")
		await _frames(3)
		sv = _find_visible_button("Service_tout")
	var q := CustomerManager.queue.size()
	if sv:
		await _press(sv)
		await _frames(5)
	_check(CustomerManager.queue.size() == q + 1, "%s: handing out cards sends someone to the clinic" % label)
	await _shot(label, "location_service")
	# TAB moves between the panels.
	var focused := false
	for i in 2:
		focused = UIManager.cycle_panels() or focused
	_check(focused, "%s: TAB cycles the location's panels" % label)
	# An encounter on the way somewhere.
	WorldSimulationManager.roll_encounter("walk", LocationManager.CLINIC, target, 1.0, "wounded_stranger")
	TravelFlow.show_encounter()
	await _frames(10)
	await _shot(label, "encounter")
	await _handle_choice_modal(label)
	_check(not WorldSimulationManager.has_encounter(), "%s: the encounter is dealt with" % label)
	# ESC: back to the map, focused on this place.
	await _key(KEY_ESCAPE)
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_MAP, "%s: ESC goes back to the map" % label)
	map = get_tree().root.find_child("CityMap", true, false) as CityMapView
	_check(map != null and map.selected_location == target, "%s: the map opens on where you are" % label)
	var enter := _find_visible_button("MapEnter")
	if enter:
		await _press(enter)
		await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_LOCATION, "%s: GO IN returns to the place" % label)
	# Home.
	var home := _find_visible_button("ReturnClinic")
	_check(home != null, "%s: RETURN TO CLINIC is there" % label)
	if home:
		await _press(home)
	await _settle()
	if WorldSimulationManager.has_encounter():
		await _handle_choice_modal(label)
	_check(not LocationManager.is_away(), "%s: back at the clinic" % label)
	_check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC, "%s: on the clinic screen" % label)
	UIManager.close_modal()
	CustomerManager.queue.clear()


func _every_place() -> void:
	await _go_clinic()
	ProgressionManager.level = 10
	StoryManager.set_flag(&"bm_access")
	StoryManager.set_flag(&"static_seen")
	LocationManager.check_discovery()
	LocationManager.grant_zone("pass")
	EconomyManager.money = 5000
	CharacterManager.mark_met(&"rook_varga")
	CharacterManager.mark_met(&"vesna_kalo")
	for i in 8:
		var c := CustomerManager.generator.generate({})
		PeopleManager.after_visit(c, "success", 50)
	for p in [700, 1320]:
		for id in LocationManager.order:
			if id == LocationManager.CLINIC:
				continue
			await _go_clinic()
			TimeManager.minute = p
			WorldSimulationManager.refresh()
			if LocationManager.access_block(id) != "":
				# Closed at this hour: it says so, and that's fine.
				_check(LocationManager.access_block(id).begins_with("Closed"), "%s at %s: not reachable only because it's closed (%s)" % [id, TimeManager.clock_text(), LocationManager.access_block(id)])
				continue
			var r := LocationManager.travel(id)
			WorldSimulationManager.encounter = {}
			_check(bool(r.get("ok", false)), "%s at %s: you can get there" % [id, TimeManager.clock_text()])
			UIManager.go_to(UIManager.SCREEN_LOCATION)
			await _settle()
			_check(UIManager.current_screen_id == UIManager.SCREEN_LOCATION, "%s: its screen opens" % id)
			await _shot("place_%s" % TimeManager.clock_text().replace(":", ""), String(id))
	await _go_clinic()


func _save_load_away() -> void:
	await _go_clinic()
	TimeManager.minute = 1320
	WorldSimulationManager.refresh()
	LocationManager.travel(&"rusty_valve")
	WorldSimulationManager.encounter = {}
	UIManager.go_to(UIManager.SCREEN_LOCATION)
	await _settle()
	await _key_action(&"quicksave")
	await _frames(5)
	# Without saving: pretend we wandered home, then F9.
	LocationManager.player_location = LocationManager.CLINIC
	_check(not LocationManager.is_away(), "back home before loading")
	await _key_action(&"quickload")
	await _settle()
	_check(LocationManager.player_location == &"rusty_valve", "quick load while out: you're back where you saved")
	_check(UIManager.current_screen_id == UIManager.SCREEN_LOCATION, "and on that place's screen")
	await _go_clinic()


func _go_clinic() -> void:
	UIManager.close_modal()
	WorldSimulationManager.encounter = {}
	if LocationManager.is_away():
		LocationManager.return_to_clinic()
	WorldSimulationManager.encounter = {}
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	await _frames(3)


func _handle_choice_modal(label: String) -> void:
	await _frames(5)
	var c := _find_visible_button("Choice_0")
	if c == null:
		c = _find_visible_button("Choice_1")
	_check(c != null, "%s: the encounter has choices" % label)
	if c:
		await _press(c)
		await _frames(5)
	var cont := _find_visible_button("ChoiceContinue")
	if cont:
		await _press(cont)
	await _settle()


func _press(b: Button) -> void:
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


func _key_action(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


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
