extends Node
## 3.10 end-to-end probe, real mouse clicks on the real screens:
##  - a scan that finds a condition says what it is, what it changes and
##    what to do, and the operation plan names it (not "x 1 condition(s)");
##  - a scan that finishes after the patient has left is ignored (it used
##    to read the missing patient and stop the script);
##  - storage sells a tool (confirm, cash up, item gone) and a stack of
##    supplies by quantity, and a double click on the confirm sells once.
##   godot --path . res://tests/clinic_310_probe.tscn -- [--shots=DIR]

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
	Settings.path = "user://clinic_310_probe_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	Controls.apply_bindings()
	SaveManager.save_dir = "user://clinic_310_probe_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	SurgeryScreen.pause_on_suspend = false
	GameManager.quit_enabled = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(30)
	GameManager.start_new_game_in_slot(1)
	await _settle()
	TutorialManager.skip()
	UIManager.close_modal()
	await _frames(4)
	await _scan_flow()
	await _scan_after_patient_left()
	await _sell_flow()
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("3.10 PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("3.10 PROBE FAILURES:")
		for f in _fails:
			print("  - " + f)
		get_tree().quit(1)


func _scan_flow() -> void:
	EventManager.operations = 10
	var c := CustomerManager.generator.generate({"archetype": "civilian", "full_difficulty": true})
	c.hidden_conditions.clear()
	c.revealed_conditions.clear()
	c.hidden_conditions.append(&"clotting_disorder")
	c.apply_condition(CustomerManager.get_condition(&"clotting_disorder"))
	var bleed := c.bleed_multiplier
	CustomerManager.debug_set_customer(c)
	# The scan's reveal roll is the game's; the probe makes it certain.
	EventManager.temp_modifiers.append({"key": "diagnosis.reveal", "value": 2.0, "ops": 99, "source": "probe"})
	ModifierManager.invalidate()
	GameManager.accept_customer()
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DIAGNOSIS, "scan: the body scan opens")
	await _press_named("Scan_chest")
	var t := 0
	while _find_visible("Condition_clotting_disorder") == null and t < 240:
		await get_tree().process_frame
		t += 1
	await _frames(4)
	var found := _find_visible("Condition_clotting_disorder") as Label
	var why := _find_visible("ConditionWhy_clotting_disorder") as Label
	var head := _find_visible("RegionName_chest") as Label
	_check(found != null and found.text.contains("CLOTTING DISORDER") and found.text.contains("Bleeds heavily"), "scan: the finding names the condition (%s)" % (found.text if found else "none"))
	_check(why != null and why.text.contains("Bleeds faster during surgery") and why.text.contains("COAG"), "scan: it says what it changes and what to do (%s)" % (why.text if why else "none"))
	_check(head != null and head.text.contains("CONDITION FOUND"), "scan: the region is marked CONDITION FOUND")
	_check(is_equal_approx(c.bleed_multiplier, bleed), "scan: finding it changes no gameplay value")
	await _shot("310_scan_condition_found")
	await _press_named("Scan_head")
	await _wait_scanned("head")
	await _frames(6)
	var opt: Button = null
	for b in get_tree().root.find_children("Option_*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			opt = b
			break
	_check(opt != null, "scan: a diagnosis can be picked")
	if opt:
		await _press(opt)
	await _press_named("ConfirmButton")
	await _frames(10)
	var plan_found := ""
	for l in get_tree().root.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text.contains("Clotting disorder (bleeding"):
			plan_found = (l as Label).text
	_check(plan_found.begins_with("! "), "plan: FOUND names the condition and what it affects, as a caution (%s)" % plan_found)
	await _shot("310_plan_found")
	EventManager.temp_modifiers.clear()
	ModifierManager.invalidate()
	GameManager.chosen_diagnosis_id = &""
	CustomerManager.dismiss_current()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()


func _sell_flow() -> void:
	var tool: ToolData = null
	for t2: ToolData in InventoryManager.tool_catalog.values():
		if not t2.starter and t2.price > 0 and t2.category == &"drill":
			tool = t2
	InventoryManager.owned_tools.append(tool.id)
	InventoryManager.supplies = 10
	EconomyManager.money = 500
	UIManager.go_to(UIManager.SCREEN_INVENTORY, {"tab": 1})
	await _settle()
	var slot := _slot(String(tool.id))
	_check(slot != null, "storage: the tool is in TOOLS")
	if slot:
		await _click(slot.get_global_rect().get_center())
	await _frames(4)
	var each := InventoryManager.sell_value(&"tool", String(tool.id))
	var sb := _find_visible_button("SellButton")
	_check(sb != null and sb.text.contains("+%d" % each), "storage: the tool shows SELL with its resale value (%s)" % (sb.text if sb else "none"))
	var info := _find_visible("SellInfo") as Label
	_check(info != null and info.text.contains(tool.display_name.to_upper()) and info.text.contains("you have 1") and info.text.contains("%d cr each" % each), "storage: name, quantity and price per unit are shown (%s)" % (info.text if info else "none"))
	await _shot("310_sell_tool")
	if sb:
		await _press(sb)
	await _frames(6)
	await _shot("310_sell_confirm")
	await _press_named("ConfirmYes")
	await _frames(8)
	_check(not InventoryManager.owns_tool(tool.id) and EconomyManager.money == 500 + each, "storage: after confirming, the tool is gone and cash is up %d" % each)
	_check(_slot(String(tool.id)) == null, "storage: the grid no longer shows it")
	# Supplies: pick 3, double-click the confirm.
	var tab := _find_visible_button("InvTab_2")
	if tab == null:
		for b in get_tree().root.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree() and (b as Button).text == "MEDICAL SUPPLIES":
				tab = b
	_check(tab != null, "storage: MEDICAL SUPPLIES tab")
	if tab:
		await _press(tab)
	await _frames(6)
	slot = _slot("supplies")
	if slot:
		await _click(slot.get_global_rect().get_center())
	await _frames(4)
	await _press_named("SellMore")
	await _press_named("SellMore")
	var unit := InventoryManager.sell_value(&"supplies", "supplies")
	sb = _find_visible_button("SellButton")
	_check(sb != null and sb.text.contains("SELL 3") and sb.text.contains("+%d" % (unit * 3)), "storage: 3 supplies show their total before selling (%s)" % (sb.text if sb else "none"))
	await _shot("310_sell_supplies")
	var money0 := EconomyManager.money
	if sb:
		await _press(sb)
	await _frames(6)
	var yes := _find_visible_button("ConfirmYes")
	if yes:
		var pos := yes.get_global_rect().get_center()
		await _click(pos)
		await _click(pos)  # a double click
	await _frames(8)
	_check(InventoryManager.supplies == 7 and EconomyManager.money == money0 + unit * 3, "storage: a double click sells 3 once (supplies %d, +%d)" % [InventoryManager.supplies, EconomyManager.money - money0])
	await _shot("310_sold_supplies")


func _slot(key: String) -> Control:
	for n in get_tree().root.find_children("*", "", true, false):
		if n is ItemSlot and (n as ItemSlot).key == key and (n as Control).is_visible_in_tree():
			return n
	return null


# --- helpers (as in ux_probe) -------------------------------------------------------

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


## Waits (up to 5 s) for a region's scan to be marked done. The surgical
## site's name already reads "HEAD  · SURGICAL SITE", so look for the scan's
## own mark.
func _wait_scanned(region: String) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		var l := _find_visible("RegionName_%s" % region) as Label
		if l and (l.text.contains("SCANNED") or l.text.contains("CONDITION FOUND")):
			break
		await get_tree().process_frame


## The patient leaves (DECLINE in the patient summary, which the patient-info
## key opens on this screen too) while a region is still being scanned. The
## scanner keeps running on the screen and finishes with nobody there.
## Before the fix that read the missing patient: a SCRIPT ERROR, which fails
## this suite in tests/run_tests.sh.
func _scan_after_patient_left() -> void:
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	GameManager.accept_customer()
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_DIAGNOSIS, "left mid-scan: the body scan opens")
	await _press_named("Scan_neck")
	var name_before := (_find_visible("RegionName_neck") as Label).text
	CustomerManager.dismiss_current()
	_check(GameManager.get_current_customer() == null, "left mid-scan: the patient is gone while the scanner runs")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:  # SCAN_TIME is 0.7 s
		await get_tree().process_frame
	var scan := get_tree().root.find_child("ScanView", true, false) as ScanView
	_check(scan != null and scan.get_scanned_count() >= 1 and not scan.is_busy(), "left mid-scan: the scan finished with nobody there")
	var name_label := _find_visible("RegionName_neck") as Label
	_check(name_label != null and name_label.text == name_before, "left mid-scan: nothing is reported for a patient who left (%s)" % (name_label.text if name_label else "none"))
	_check(get_tree().root.find_children("Condition_*", "Label", true, false).is_empty(), "left mid-scan: no finding is shown")
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_CLINIC, "left mid-scan: back to the clinic")


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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
