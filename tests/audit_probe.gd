extends Node
## UI audit probe (3.9): walks a fresh save through the core loop (clinic,
## the patient, their file, the scan, the plan, surgery, supply) with real
## clicks, and on each screen counts what a player sees: panels, text labels
## and buttons (visible, on-screen). Prints a table and takes screenshots,
## so the simplification can be measured before and after.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/audit_probe.tscn -- --shots=/abs/dir

const AUDIT_SEED := 39

var _shots: String = ""
var _rows: Array[String] = []


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false  # scenes have their own tests (narrative_tests, narrative_probe)
	CustomerManager.breather_scale = 0.0  # the next patient knocks at once
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	Settings.path = "user://audit_probe_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	Settings.set_value("controls_setup_done", true)
	Settings.set_value("tutorial_hints", false)
	Controls.apply_bindings()
	SaveManager.save_dir = "user://audit_probe_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	SaveManager.use_slot(1)
	SaveManager.delete_save()
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(40)
	await _flow()
	print("")
	print("UI AUDIT (visible, on-screen)")
	# On screen: what you see without scrolling. Page: everything shown,
	# scrolled out of view or not (a shorter page can show MORE on screen).
	print("%-22s %7s %7s %8s | %11s %12s" % ["screen", "panels", "labels", "buttons", "page labels", "page buttons"])
	for r in _rows:
		print(r)
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	get_tree().quit(0)


func _flow() -> void:
	# Same patients every run, so before / after compare the same screens
	# (a random patient can bring whole extra sections, e.g. a dependency).
	seed(AUDIT_SEED)
	GameManager._rng.seed = AUDIT_SEED
	CustomerManager._rng.seed = AUDIT_SEED
	CustomerManager.generator.rng.seed = AUDIT_SEED
	GameManager.start_new_game()
	await _settle()
	var t := 0
	while not CustomerManager.has_customer() and t < 600:
		await get_tree().process_frame
		t += 1
	await _settle()
	await _measure("1 clinic")
	await _press_named("SeeButton")
	await _frames(10)
	await _measure("2 patient (click)")
	var det := _find_visible_button("SummaryDetails")
	if det:
		await _press(det)
		await _frames(10)
		await _measure("2b patient details")
	GameManager.open_customer()
	await _settle()
	await _measure("3 full file")
	GameManager.accept_customer()
	await _settle()
	await _measure("4 scan")
	for r in ["head", "neck", "torso", "chest", "arms", "legs"]:
		var b := _find_visible_button("Scan_%s" % r)
		if b:
			await _press(b)
			await _frames(40)
	var opt: Button = null
	for n in get_tree().root.find_children("Option_*", "Button", true, false):
		if (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			opt = n
			break
	if opt:
		await _press(opt)
		await _frames(3)
		await _press_named("ConfirmButton")
		await _frames(15)
	await _measure("5 plan")
	await _press_named("BeginButton")
	await _settle()
	await _frames(30)
	await _measure("6 surgery")
	SurgeryManager.abort()
	await _settle()
	UIManager.close_modal()
	EventManager.operations = 1
	Features.refresh()
	CustomerManager.dismiss_current()
	GameManager.go_to_clinic()
	await _settle()
	UIManager.close_modal()
	await _frames(5)
	await _measure("7 clinic after job 1")
	UIManager.go_to(UIManager.SCREEN_SHOP)
	await _settle()
	await _measure("8 supply")


func _measure(label: String) -> void:
	await _frames(4)
	var view := get_viewport().get_visible_rect()
	var panels := 0
	var labels := 0
	var buttons := 0
	var page_labels := 0
	var page_buttons := 0
	for n in get_tree().root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.get_window() != get_tree().root:
			continue
		if c is BaseButton:
			page_buttons += 1
		elif c is Label and (c as Label).text.strip_edges() != "":
			page_labels += 1
		var r := c.get_global_rect()
		if r.size.x < 2 or r.size.y < 2 or not view.intersects(r):
			continue
		if _clipped_out(c):
			continue
		if c is BaseButton:
			buttons += 1
		elif c is Label and (c as Label).text.strip_edges() != "":
			labels += 1
		elif c is PanelContainer:
			panels += 1
	_rows.append("%-22s %7d %7d %8d | %11d %12d" % [label, panels, labels, buttons, page_labels, page_buttons])
	if not _shots.is_empty():
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/%s.png" % [_shots, label.replace(" ", "_").replace("(", "").replace(")", "")])


## Hidden inside a scroll container's viewport (not on screen).
func _clipped_out(c: Control) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return not (p as Control).get_global_rect().intersects(c.get_global_rect())
		p = p.get_parent()
	return false


func _find_visible_button(n: String) -> Button:
	for b in get_tree().root.find_children(n, "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


func _press_named(n: String) -> void:
	var b := _find_visible_button(n)
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
	var pos := b.get_global_rect().get_center()
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


func _settle() -> void:
	var t := 0
	while UIManager.is_transitioning() and t < 200:
		await get_tree().process_frame
		t += 1
	await _frames(15)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
