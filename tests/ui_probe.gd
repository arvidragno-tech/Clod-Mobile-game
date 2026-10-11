extends Node
## UI overhaul QA (3.3) in the real, rendered game with real mouse clicks
## and keys, at 1920x1080, 1600x900, 1366x768, 1280x720 windowed plus
## borderless and fullscreen:
## - F1 opens the FIELD GUIDE; topics, search, close.
## - Clicking a status-bar stat and a "?" chip opens an explanation card.
## - The door card shows AT A GLANCE and SEE CUSTOMER stays on-screen.
## - The customer file's AT A GLANCE and DECISION are on-screen.
## - Diagnosis: SCAN buttons scan regions; findings fill in; options unlock.
## - The operation plan says why BEGIN is blocked (or that it's ready).
## - Settings has ROOM BRIGHTNESS.
## Every button stays on-screen; screenshots with --shots.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/ui_probe.tscn -- --shots=/abs/dir

var _shots: String = ""
var _fails: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	Hints.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	Settings.path = "user://ui_probe_settings.cfg"
	SaveManager.save_dir = "user://test_saves"
	SaveManager.use_slot(2)
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(30)
	GameManager.start_new_game()
	TutorialManager.skip()
	await _settle()
	UIManager.close_modal()
	EventManager.operations = 10
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	WorldSimulationManager.auto_roll = false
	for mode_res: Array in [["windowed", "1920x1080"], ["windowed", "1600x900"], ["windowed", "1366x768"], ["windowed", "1280x720"], ["borderless", "1920x1080"], ["fullscreen", "1920x1080"]]:
		Settings.window_mode = str(mode_res[0])
		Settings.resolution = str(mode_res[1])
		Settings.apply_display()
		await _frames(20)
		await _round("%s_%s" % [mode_res[0], mode_res[1]])
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("UI PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("UI PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _round(label: String) -> void:
	await _go_clinic()
	EconomyManager.money = 3000
	InventoryManager.supplies = 10
	# F1: the field guide, anywhere.
	await _key(KEY_F1)
	await _frames(8)
	_check(Glossary.is_open(), "%s: F1 opens the field guide" % label)
	var topic := _find_visible_button("GuideTopic_city")
	if topic:
		await _press(topic)
		await _frames(4)
	_check(_find_visible("Guide_travel") != null, "%s: the CITY topic explains travel" % label)
	await _shot(label, "field_guide")
	var close := _find_visible_button("GuideClose")
	if close:
		await _press(close)
	await _frames(6)
	_check(not Glossary.is_open(), "%s: the guide closes" % label)
	# A status-bar stat explains itself on click.
	var bar := get_tree().root.find_child("StatusBar", true, false) as StatusBar
	if bar:
		var heat: Control = bar._boxes.get("heat")
		if heat:
			await _click(heat.get_global_rect().get_center())
			await _frames(6)
	_check(_find_visible("GlossaryCard") != null or Glossary.is_open(), "%s: clicking HEAT explains heat" % label)
	await _shot(label, "explain_heat")
	var got := _find_visible_button("GlossaryClose")
	if got:
		await _press(got)
	await _frames(6)
	_check(not Glossary.is_open(), "%s: the card closes" % label)
	# The door card.
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	InventoryManager.add_implant(c.requested_cyberware_id)
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	await _frames(5)
	_check(_find_visible("DoorVerdict") != null and _find_visible("VerdictAdvice") != null, "%s: the door card has AT A GLANCE" % label)
	_check(_find_visible_button("SeeButton") != null, "%s: SEE PATIENT is visible" % label)
	var chip := _find_visible_button("Info_time")
	if chip:
		await _press(chip)
		await _frames(6)
		_check(_find_visible("GlossaryCard") != null, "%s: a ? chip opens its explanation" % label)
		var g2 := _find_visible_button("GlossaryClose")
		if g2:
			await _press(g2)
		await _frames(5)
	await _shot(label, "clinic")
	# Customer file.
	var see := _find_visible_button("SeeButton")
	if see:
		await _press(see)
	await _settle()
	# 3.7: the patient summary first, the full file behind MORE DETAILS.
	_check(_find_visible("PatientSummary") != null and _find_visible("SummarySuccess") != null and _find_visible("SummaryMargin") != null,
		"%s: SEE PATIENT opens the patient summary (odds, margin)" % label)
	await _shot(label, "patient_summary")
	var more := _find_visible_button("SummaryDetails")
	if more:
		await _press(more)
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_CUSTOMER, "%s: MORE DETAILS opens the file" % label)
	_check(_find_visible("AtAGlance") != null, "%s: the file has AT A GLANCE" % label)
	await _shot(label, "customer")
	var accept := _find_visible_button("AcceptButton")
	if accept:
		await _press(accept)
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DIAGNOSIS, "%s: PERFORM opens the body scan" % label)
	# Diagnosis by SCAN buttons.
	for r in ["head", "neck"]:
		var b := _find_visible_button("Scan_%s" % r)
		if b:
			await _press(b)
			await _frames(60)
	var scan := get_tree().root.find_child("ScanView", true, false) as ScanView
	_check(scan != null and scan.get_scanned_count() >= 2, "%s: SCAN buttons scan regions" % label)
	var finding := get_tree().root.find_child("Finding_neck", true, false) as Label
	_check(finding != null and not finding.text.begins_with("Not scanned"), "%s: findings fill in" % label)
	var opt: Button = null
	for n in get_tree().root.find_children("Option_*", "Button", true, false):
		if (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			opt = n
			break
	_check(opt != null, "%s: two scans unlock the diagnoses" % label)
	await _shot(label, "diagnosis")
	if opt:
		await _press(opt)
		await _frames(3)
		var conf := _find_visible_button("ConfirmButton")
		if conf:
			await _press(conf)
		await _frames(10)
	var note := get_tree().root.find_child("ReadyNote", true, false) as Label
	_check(note != null and note.text != "", "%s: the plan says whether you're ready" % label)
	await _shot(label, "plan")
	GameManager.go_to_clinic()
	await _settle()
	CustomerManager.dismiss_current()
	# Settings: room brightness.
	UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.SCREEN_CLINIC})
	await _settle()
	_check(get_tree().root.find_child("Slider_brightness", true, false) != null, "%s: SETTINGS has ROOM BRIGHTNESS" % label)
	await _go_clinic()


func _go_clinic() -> void:
	UIManager.close_modal()
	Glossary.close()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.close_modal()
	await _frames(3)


func _find_visible(n: String) -> Node:
	for x in get_tree().root.find_children(n, "", true, false):
		if x is CanvasItem and (x as CanvasItem).is_visible_in_tree():
			return x
		if x is Window and (x as Window).visible:
			return x
	return null


func _find_visible_button(n: String) -> Button:
	for b in get_tree().root.find_children(n, "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


func _press(b: Button) -> void:
	await _click(b.get_global_rect().get_center() + _window_offset(b))


## Controls inside a popup window: their global rect is relative to it.
func _window_offset(c: Control) -> Vector2:
	var w := c.get_window()
	if w != get_tree().root and w is Window:
		return Vector2((w as Window).position)
	return Vector2.ZERO


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


## A real key press through the viewport (like the keyboard).
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
