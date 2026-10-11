extends Node
## Display QA: drives the real window through every supported windowed
## resolution, borderless, fullscreen and a non-16:9 window (letterbox),
## and screenshots the main menu, clinic and surgery at each one. Checks
## the window actually took the size/mode, the 1920x1080 canvas fits
## (uniform scale, letterboxed) and every button stays on-screen.
##
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       res://tests/display_probe.tscn -- --shots=/abs/dir
## Exit code 0 = all checks passed.

const CASES := [
	{"mode": "windowed", "res": "1920x1080"},
	{"mode": "windowed", "res": "1600x900"},
	{"mode": "windowed", "res": "1366x768"},
	{"mode": "windowed", "res": "1280x720"},
	{"mode": "borderless", "res": "1600x900"},
	{"mode": "fullscreen", "res": "1600x900"},
	{"mode": "windowed", "res": "1280x1024"},  # 5:4 -> letterbox
]

var _shots: String = ""
var _fails: Array[String] = []
var _checks: int = 0
var _main: Node


func _ready() -> void:
	Hints.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	Settings.path = "user://display_probe_settings.cfg"
	SaveManager.save_dir = "user://test_saves"
	SaveManager.save_path = "user://display_probe_save.json"
	SurgeryScreen.pause_on_suspend = false
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(30)
	for c: Dictionary in CASES:
		await _run_case(c)
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("DISPLAY PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("DISPLAY PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		_fails.append(msg)


func _run_case(c: Dictionary) -> void:
	var label := "%s_%s" % [c["mode"], c["res"]]
	print("== %s" % label)
	Settings.window_mode = str(c["mode"])
	Settings.resolution = str(c["res"])
	Settings.apply_display()
	await _frames(20)
	var win := DisplayServer.window_get_size()
	var mode := DisplayServer.window_get_mode()
	var want := Settings.parse_resolution(str(c["res"]))
	var screen := DisplayServer.screen_get_size()
	match str(c["mode"]):
		"windowed":
			_check(mode == DisplayServer.WINDOW_MODE_WINDOWED, "%s: windowed mode" % label)
			var expect := Vector2i(mini(want.x, screen.x), mini(want.y, screen.y))
			_check(win == expect, "%s: window is %s (got %s)" % [label, expect, win])
		"borderless":
			_check(mode == DisplayServer.WINDOW_MODE_FULLSCREEN, "%s: borderless fullscreen mode" % label)
		"fullscreen":
			_check(mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_FULLSCREEN, "%s: fullscreen mode" % label)
	# The 1920x1080 canvas is uniformly scaled; the rest is letterbox.
	var vis := get_viewport().get_visible_rect().size
	_check(vis.x >= 1919.0 and vis.y >= 1079.0 and (is_equal_approx(vis.x, 1920.0) or is_equal_approx(vis.y, 1080.0)), "%s: canvas %s keeps 16:9 design (letterboxed)" % [label, vis])
	_check(get_tree().root.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST, "%s: nearest texture filtering" % label)
	UIManager.go_to(UIManager.SCREEN_MAIN_MENU)
	await _settle()
	await _shot(label, "menu")
	if not GameManager.is_running:
		GameManager.start_new_game()
		TutorialManager.skip()
	else:
		GameManager.go_to_clinic()
	await _settle()
	await _shot(label, "clinic")
	UIManager.close_modal()
	for sid: StringName in [UIManager.SCREEN_INVENTORY, UIManager.SCREEN_STAFF, UIManager.SCREEN_BUSINESS, UIManager.SCREEN_MAP,
			UIManager.SCREEN_UPGRADES, UIManager.SCREEN_DOSSIER, UIManager.SCREEN_SETTINGS]:
		UIManager.go_to(sid)
		await _settle()
		await _shot(label, String(sid))
	# A conversation at this window size.
	DialogueManager.start(&"d_ilse_intro")
	var panel := DialoguePanel.new()
	panel.name = "DialoguePanel"
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.show_modal(panel)
	await _frames(20)
	await _shot(label, "dialogue")
	UIManager.close_modal()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


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
