extends "res://tests/test_runner.gd"
## Rendered probe of the install-implant stage, played with real mouse
## input in the running surgery screen: every implant category at 1920x1080,
## and a neural, limb and optic install at 1280x720. At each step it checks
## that the drawn marks and the placement agree (the dropped implant shares
## the socket's anchor, the aligned notch is on the key slot on screen, the
## seated implant stays put, closed skin hides all but its exposed part) and,
## with --shots, saves the tray, held, placed (misaligned + aligned), seated,
## following stages and closed field.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/implant_probe.tscn -- [--shots=/abs/dir] [--only=neural]

const CATEGORIES := ["neural", "spine", "arms", "legs", "eyes", "dermal", "respiratory", "internal"]
## One implant per category, so every install surgery is exercised.
const IMPLANT_FOR := {"neural": "nx1_neural_bridge", "spine": "backbone_relay", "arms": "liftwell_arm", "legs": "strider_knee",
	"eyes": "kestrel_sight", "dermal": "kevlace_mesh", "respiratory": "smogbreaker_filter", "internal": "toxsponge_liver"}
const SMALL_RES := "1280x720"
const SMALL_RES_CATEGORIES := ["neural", "arms", "eyes"]

var _fails_probe: Array[String] = []
var _cat: String = ""


func _ready() -> void:
	Hints.enabled = false
	CutscenePlayer.enabled = false
	CustomerManager.breather_scale = 0.0
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir)
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	Settings.path = "user://implant_probe_settings.cfg"
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	SaveManager.use_slot(3)
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(20)
	Settings.window_mode = "windowed"
	GameManager.start_new_game()
	await _frames(30)
	TutorialManager.skip()
	UIManager.close_modal()
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	EventManager.operations = 10
	EconomyManager.money = 30000
	for res: String in ["1920x1080", SMALL_RES]:
		Settings.resolution = res
		Settings.apply_display()
		await _frames(20)
		for cat: String in CATEGORIES:
			if (only != "" and cat != only) or (res == SMALL_RES and cat not in SMALL_RES_CATEGORIES):
				continue
			_cat = "%s_%s" % [res, cat]
			await _operate(cat)
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("IMPLANT PROBE: %d shots%s" % [_shot_index, ("" if _fails_probe.is_empty() else ", issues: %s" % str(_fails_probe))])
	if _fails_probe.is_empty():
		print("IMPLANT PROBE PASSED")
	get_tree().quit(0 if _fails_probe.is_empty() else 1)


func _snap(label: String) -> void:
	await _frames(2)
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_index += 1
	img.save_png("%s/%s_%02d_%s.png" % [_shots_dir, _cat, _shot_index, label])


func _operate(cat: String) -> void:
	UIManager.close_modal()
	CustomerManager.debug_set_customer(CustomerManager.generator.generate({"full_difficulty": true, "category": cat, "cyberware": IMPLANT_FOR[cat]}))
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _frames(30)
	GameManager.open_customer()
	await _frames(30)
	GameManager.accept_customer()
	await _frames(30)
	var c := CustomerManager.current_customer
	_expect(c.requested_cyberware_id == StringName(IMPLANT_FOR[cat]), "the patient asks for %s" % IMPLANT_FOR[cat])
	GameManager.submit_diagnosis(c.true_diagnosis_id)
	InventoryManager.add_implant(c.requested_cyberware_id)
	InventoryManager.supplies = 20
	for t: ToolData in InventoryManager.get_purchasable_tools(true):
		if not InventoryManager.owned_tools.has(t.id):
			InventoryManager.owned_tools.append(t.id)
	if not GameManager.get_surgery_readiness()["ok"]:
		_fails_probe.append("%s: surgery not ready" % cat)
		return
	GameManager.begin_surgery()
	await _wait_screen(UIManager.SCREEN_SURGERY)
	print("%s: %s, implant %s, field %dx" % [_cat, SurgeryManager.surgery.id, c.requested_cyberware_id, UIManager.current_screen.field_scale])
	SurgeryManager._planned_complication_stages.clear()
	SurgeryManager.dilemma_stage = -1
	var seated := false
	while SurgeryManager.is_active:
		if not await _wait_stage_ready():
			break
		var stage: SurgeryStage = UIManager.current_screen.current_stage
		SurgeryManager.vitals.health = 100.0
		if stage is InstallImplantStage:
			await _probe_install(stage as InstallImplantStage)
			seated = true
		elif seated and stage is CloseIncisionStage:
			await _snap("before_close")
			# The closed field as it renders, before the end-of-operation
			# banner covers it.
			var site := stage.site
			site.closed = true
			await _snap("closed_field")
			_expect(_closed_art_leaks(site) == 0, "closed skin shows only the implant's exposed part")
			site.closed = false
			await _play_stage(stage, false)
			await _frames(10)
			await _snap("closed")
			break
		else:
			if seated:
				await _snap("after_seat_%s" % stage.stage.id)
			await _play_stage(stage, false)
		await _frames(5)
	if SurgeryManager.is_active:
		GameManager.abort_surgery()
	await _frames(30)
	UIManager.close_modal()
	CustomerManager.dismiss_current()
	await _frames(10)


func _probe_install(stage: InstallImplantStage) -> void:
	await _frames(10)
	await _snap("install_tray")
	var h := stage.get_autoplay_hints()
	var from := _fs(h["implant"])
	var to := _fs(h["socket"])
	await _press(from)
	var mid := from.lerp(to, 0.6)
	for s in 12:
		var p := from.lerp(mid, (s + 1) / 12.0)
		_send_motion(p, Vector2.ONE)
		await _frames(1)
	await _snap("install_held")
	for s in 8:
		var p := mid.lerp(to, (s + 1) / 8.0)
		_send_motion(p, Vector2.ONE)
		await _frames(1)
	await _release(to)
	await _frames(4)
	var site := stage.site
	_expect(site.implant_state == SurgicalSiteView.ImplantState.PLACED, "the implant dropped on the socket is placed")
	_expect(site.implant_center() == site.socket_center(), "the placed implant shares the socket's anchor pixel")
	await _snap("install_placed_misaligned")
	var error: float = stage.get_autoplay_hints()["angle_error_deg"]
	var steps := roundi(absf(error) / stage.rotate_step_deg())
	var key := "rotate_left" if error > 0.0 else "rotate_right"
	for s in steps:
		stage.key_action(StringName(key), true)
		await _frames(1)
	await _frames(4)
	_expect(site.implant_aligned, "stepping by the reported error aligns the notch")
	# On screen: the notch mark sits on the socket's key slot (within the
	# tolerance arc), measured in real screen pixels.
	var scale: float = UIManager.current_screen.field_scale
	var chord := (2.0 * site.key_radius() * sin(deg_to_rad(stage._tolerance_deg) / 2.0) + 1.0) * scale
	_expect(_fs(site.implant_notch_pos()).distance_to(_fs(site.socket_key_pos())) <= chord, "the aligned notch is drawn on the key slot")
	_expect(is_equal_approx(_fs(site.socket_key_pos()).distance_to(_fs(site.socket_center())), site.key_radius() * scale),
			"the key slot is key_radius() from the socket on screen")
	await _snap("install_placed_aligned")
	var placed := site.implant_pos
	stage.key_action(&"context", true)
	await _frames(6)
	# (Compared in field space: the field may re-centre in its frame when the
	# stage's control row goes away, which moves every local position alike.)
	_expect(site.implant_state == SurgicalSiteView.ImplantState.SEATED and site.implant_pos == placed
			and site.implant_center() == site.socket_center() and site.implant_angle == 0.0,
			"seating keeps the previewed placement (%s -> %s, angle %.3f)" % [placed, site.implant_pos, site.implant_angle])
	await _snap("install_seated")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails_probe.append("%s: %s" % [_cat, what])
		print("  FAIL %s: %s" % [_cat, what])


## Art pixels showing through closed skin outside the exposed radius.
func _closed_art_leaks(site: SurgicalSiteView) -> int:
	site._rebuild_implant_layer()
	var anchor := site.implant_center() - site.get_field_rect().position
	var pivot := anchor + SurgicalSiteView._pivot_offset(site.implant_size())
	var cover := site.implant_coverage(anchor, site.implant_angle)
	var leaks := 0
	for idx: int in cover:
		var x := idx % SurgicalSiteView.FIELD_SIZE
		var y := idx / SurgicalSiteView.FIELD_SIZE
		var px := site._implant_layer.get_pixel(x, y)
		var art := px.a > 0.0 and px.is_equal_approx(site._implant_image.get_pixelv(cover[idx]))
		if art and (Vector2(x + 0.5, y + 0.5) - pivot).length() > site.implant_exposed_radius:
			leaks += 1
	return leaks
