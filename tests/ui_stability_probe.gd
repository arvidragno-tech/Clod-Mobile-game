extends Node
## UI stability probe (3.6): reproduces the "menus are buggy, UI scale
## changes, buying implants is unreliable" reports in the real, rendered
## game with real mouse events, and guards the fixes:
##   A  implant shop: every affordable BUY button, clicked at its visible
##      centre (after scrolling it into view), buys exactly that implant,
##      charges exactly its price, and the detail panel keeps showing it
##   B  a fast double-click on BUY makes one purchase, not two
##   C  a second navigation request during a screen transition is honoured
##      (not silently dropped)
##   D  40 rapid screen switches: no drifting scale / position, no stacked
##      signal handlers, no leftover input-blocking overlays
##   E  every main screen fits the canvas (minimum size, buttons on-screen)
##      with default text, TEXT SCALE 1.4, LARGE TEXT, both, and INTEGER
##      pixel scaling (which must never crop a small window)
## at 1920x1080, 1600x900, 1366x768 and 1280x720 windowed, then borderless
## and fullscreen.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/ui_stability_probe.tscn -- [--shots=/abs/dir] [--report]
## --report prints the measurements and exits 0 (baseline mode).

var _shots: String = ""
var _report: bool = false
var _fails: Array[String] = []
var _checks: int = 0

const SCREENS: Array[StringName] = [&"clinic", &"shop", &"inventory", &"database", &"dossier", &"business", &"staff", &"map", &"upgrades", &"skills", &"settings", &"black_market"]


func _ready() -> void:
	Hints.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
		if arg == "--report":
			_report = true
	Settings.path = "user://ui_stability_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	Settings.set_value("controls_setup_done", true)
	SaveManager.save_dir = "user://ui_stability_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	SaveManager.use_slot(1)
	SaveManager.delete_save()
	GameManager.quit_enabled = false
	SurgeryScreen.pause_on_suspend = false
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _frames(30)
	GameManager.start_new_game()
	await _settle()
	TutorialManager.skip()
	UIManager.close_modal()
	WorldEventManager.auto_roll = false
	SecurityManager.auto_roll = false
	WorldSimulationManager.auto_roll = false
	ProgressionManager.level = 10
	ClinicManager.tier = 3
	await _settle()
	for mode_res: Array in [["windowed", "1920x1080"], ["windowed", "1600x900"], ["windowed", "1366x768"], ["windowed", "1280x720"], ["borderless", "1920x1080"], ["fullscreen", "1920x1080"]]:
		Settings.window_mode = str(mode_res[0])
		Settings.resolution = str(mode_res[1])
		Settings.apply_display()
		await _frames(20)
		var label := "%s_%s" % [mode_res[0], mode_res[1]]
		await _shop_round(label)
		if label == "windowed_1920x1080" or label == "windowed_1366x768":
			await _double_click(label)
			await _transition_request(label)
			await _rapid_switching(label)
			await _fit_round(label)
	SaveManager.delete_save()
	DirAccess.remove_absolute(Settings.path)
	print("")
	if _fails.is_empty():
		print("UI STABILITY PROBE PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("UI STABILITY PROBE FAILURES (%d of %d):" % [_fails.size(), _checks])
		for f in _fails:
			print("  - " + f)
		get_tree().quit(0 if _report else 1)


# --- A: the implant shop ------------------------------------------------------

func _shop_round(label: String) -> void:
	EconomyManager.money = 200000
	UIManager.go_to(UIManager.SCREEN_SHOP, {"tab": 0})
	await _settle()
	var buttons: Array[Button] = []
	for n in get_tree().root.find_children("BuyImplant_*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.disabled:
			buttons.append(b)
	_check(buttons.size() >= 3, "%s A: shop lists affordable implants (%d)" % [label, buttons.size()])
	var names: Array[String] = []
	for b in buttons:
		names.append(String(b.name))
	var tried := 0
	var wrong := 0
	var detail_wrong := 0
	# Every other button, so top, middle and scrolled-down rows are covered.
	for i in range(0, names.size(), 2):
		var b := _find_button(names[i])
		if b == null:
			continue
		var id := StringName(names[i].trim_prefix("BuyImplant_"))
		var before := _counts()
		var money := EconomyManager.money
		var price := InventoryManager.implant_price(CyberwareManager.get_cyberware(id))
		await _scroll_into_view(b)
		b = _find_button(names[i])
		await _click(b.get_global_rect().get_center())
		await _frames(4)
		tried += 1
		var after := _counts()
		var ok := int(after.get(id, 0)) == int(before.get(id, 0)) + 1 and EconomyManager.money == money - price
		for k in after:
			if k != id and int(after[k]) != int(before.get(k, 0)):
				ok = false
		if not ok:
			wrong += 1
			print("    %s: clicking %s bought %s (money %d -> %d, price %d)" % [label, id, _diff(before, after), money, EconomyManager.money, price])
		var shown := _detail_text()
		if not shown.contains(CyberwareManager.get_cyberware(id).display_name):
			detail_wrong += 1
	_check(tried > 0 and wrong == 0, "%s A: each BUY buys exactly its own implant (%d wrong of %d)" % [label, wrong, tried])
	# Hovering other cards (on the way to a BUY button) must not move it.
	var moved := 0
	for i in range(1, mini(names.size(), 9)):
		var target := _find_button(names[i])
		var other := _find_button(names[i - 1])
		if target == null or other == null:
			continue
		await _scroll_into_view(target)
		var r0 := target.get_global_rect()
		var card := other.get_parent().get_parent() as Control
		var m := InputEventMouseMotion.new()
		m.position = card.get_global_rect().position + Vector2(20, 20)
		m.global_position = m.position
		get_viewport().push_input(m, true)
		await _frames(4)
		target = _find_button(names[i])
		if target == null or not target.get_global_rect().position.is_equal_approx(r0.position):
			moved += 1
	_check(moved == 0, "%s A: hovering another card doesn't move a BUY button (%d moved)" % [label, moved])
	_check(detail_wrong == 0, "%s A: after buying, the detail panel still shows that implant (%d jumped of %d)" % [label, detail_wrong, tried])
	# Unaffordable: the button is disabled and a forced press is refused.
	EconomyManager.money = 5
	EventBus.money_changed.emit(5, 0)
	await _frames(4)
	var any := _find_button(names[0]) if not names.is_empty() else null
	_check(any != null and any.disabled, "%s A: unaffordable implants can't be bought" % label)
	var n_before := _counts()
	if not names.is_empty():
		InventoryManager.buy_implant(StringName(names[0].trim_prefix("BuyImplant_")))
	_check(_counts() == n_before, "%s A: the shop refuses a purchase without the money" % label)
	await _shot(label + "_shop")
	_layout_guard(label + " shop")


func _counts() -> Dictionary:
	var d := {}
	for item: CyberwareData in CyberwareManager.get_supply_catalog(true):
		d[item.id] = InventoryManager.get_implant_count(item.id)
	return d


func _diff(a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	for k in b:
		var d := int(b[k]) - int(a.get(k, 0))
		if d != 0:
			out.append("%s %+d" % [k, d])
	return ", ".join(out) if not out.is_empty() else "nothing"


func _detail_text() -> String:
	var d := get_tree().root.find_child("Detail", true, false)
	var t := ""
	if d:
		for l in d.find_children("*", "Label", true, false):
			t += (l as Label).text + "|"
	return t


# --- B: double click ------------------------------------------------------------

func _double_click(label: String) -> void:
	EconomyManager.money = 200000
	UIManager.go_to(UIManager.SCREEN_SHOP, {"tab": 0})
	await _settle()
	var b: Button = null
	for n in get_tree().root.find_children("BuyImplant_*", "Button", true, false):
		if (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			b = n
			break
	if b == null:
		_check(false, "%s B: a BUY button to double-click" % label)
		return
	var id := StringName(String(b.name).trim_prefix("BuyImplant_"))
	var before := InventoryManager.get_implant_count(id)
	var pos := b.get_global_rect().get_center()
	# Two clicks inside one double-click interval (no frames to settle between).
	for k in 2:
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.double_click = k == 1 and pressed
			e.position = pos
			e.global_position = pos
			get_viewport().push_input(e, true)
			await _frames(1)
	await _frames(6)
	_check(InventoryManager.get_implant_count(id) == before + 1, "%s B: a double-click buys one unit (%+d)" % [label, InventoryManager.get_implant_count(id) - before])


# --- C: navigation during a transition ----------------------------------------------

func _transition_request(label: String) -> void:
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	UIManager.go_to(UIManager.SCREEN_INVENTORY)
	await _frames(2)
	UIManager.go_to(UIManager.SCREEN_SHOP)  # the player clicked again during the fade
	await _settle()
	await _frames(20)
	_check(UIManager.current_screen_id == UIManager.SCREEN_SHOP, "%s C: a click during a screen transition still navigates (on '%s')" % [label, UIManager.current_screen_id])


# --- D: rapid switching -------------------------------------------------------------------

func _rapid_switching(label: String) -> void:
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	var base_conn := _connections()
	for i in 40:
		UIManager.go_to(SCREENS[i % SCREENS.size()])
		await _frames(1 + (i % 3) * 6)
	await _settle()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	await _settle()
	await _frames(10)
	var scr := UIManager.current_screen
	var xf_ok := scr != null and scr.get_global_transform().get_scale().is_equal_approx(Vector2.ONE) and scr.global_position.is_equal_approx(Vector2.ZERO)
	_check(xf_ok, "%s D: after 40 rapid switches the screen is unscaled at the origin (%s)" % [label, str(scr.get_global_transform()) if scr else "-"])
	var conn := _connections()
	_check(conn <= base_conn + 2, "%s D: no stacked signal handlers (EventBus/Economy connections %d -> %d)" % [label, base_conn, conn])
	var blockers: Array[String] = []
	var view := get_viewport().get_visible_rect()
	for n in get_tree().root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.mouse_filter != Control.MOUSE_FILTER_STOP or not c.is_visible_in_tree() or c.get_window() != get_tree().root:
			continue
		if scr and (scr == c or scr.is_ancestor_of(c) or c.is_ancestor_of(scr)):
			continue
		var r := c.get_global_rect()
		if r.size.x >= view.size.x * 0.9 and r.size.y >= view.size.y * 0.9:
			blockers.append(String(c.get_path()))
	_check(blockers.is_empty(), "%s D: no full-screen input blockers left over %s" % [label, blockers])
	# The clinic's own buttons still click (nothing invisible on top).
	# (SETTINGS: always in the side bar, whatever the player has been introduced to.)
	var b := _find_button("Nav_settings")
	if b:
		await _click(b.get_global_rect().get_center())
		await _settle()
	_check(UIManager.current_screen_id == UIManager.SCREEN_SETTINGS, "%s D: a nav click still lands after switching" % label)


func _connections() -> int:
	var n := 0
	for sig in EventBus.get_signal_list():
		n += EventBus.get_signal_connection_list(sig["name"]).size()
	return n


# --- E: every screen fits ------------------------------------------------------------------

func _fit_round(label: String) -> void:
	for variant: Array in [["default", 1.0, false, "fit"], ["text 1.4", 1.4, false, "fit"], ["large text", 1.0, true, "fit"], ["text 1.4 + large", 1.4, true, "fit"], ["integer pixels", 1.0, false, "integer"]]:
		Settings.set_value("text_scale", float(variant[1]))
		Settings.set_value("large_text", bool(variant[2]))
		Settings.set_value("pixel_scaling", str(variant[3]))
		await _frames(3)
		if str(variant[3]) == "integer":
			var win := get_tree().root.size
			var small := win.x < 1920 or win.y < 1080
			_check(not small or get_tree().root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL,
				"%s E: INTEGER pixels never crop a window smaller than the canvas (%s)" % [label, win])
		_check(is_equal_approx(get_tree().root.content_scale_factor, 1.0), "%s E [%s]: one scale authority (content scale factor 1.0)" % [label, variant[0]])
		var too_big: Array[String] = []
		var offscreen: Array[String] = []
		for s in SCREENS:
			UIManager.go_to(s)
			await _settle()
			var scr := UIManager.current_screen
			if scr == null:
				continue
			var vp := get_viewport().get_visible_rect().size
			var ms := scr.get_combined_minimum_size()
			if ms.x > vp.x + 1.0 or ms.y > vp.y + 1.0:
				too_big.append("%s %dx%d" % [s, ms.x, ms.y])
			if str(variant[0]) == "text 1.4 + large" and label == "windowed_1920x1080":
				await _shot("bigtext_" + String(s))
			var bad := _offscreen_buttons()
			if not bad.is_empty():
				offscreen.append("%s %s" % [s, bad])
		_check(too_big.is_empty(), "%s E [%s]: every screen fits the canvas %s" % [label, variant[0], too_big])
		_check(offscreen.is_empty(), "%s E [%s]: every button on-screen %s" % [label, variant[0], offscreen])
	Settings.set_value("text_scale", 1.0)
	Settings.set_value("large_text", false)
	Settings.set_value("pixel_scaling", "fit")
	await _frames(3)


func _offscreen_buttons() -> Array[String]:
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
	return bad


func _layout_guard(label: String) -> void:
	var bad := _offscreen_buttons()
	_check(bad.is_empty(), "%s: all buttons on-screen %s" % [label, bad])


# --- helpers ------------------------------------------------------------------------------------

func _find_button(n: String) -> Button:
	for b in get_tree().root.find_children(n, "Button", true, false):
		if (b as Button).is_visible_in_tree():
			return b
	return null


func _scroll_into_view(c: Control) -> void:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			await _frames(3)
			return
		p = p.get_parent()


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
	for i in 60:
		await _frames(2)
		if not UIManager.is_transitioning():
			break
	await _frames(4)


func _shot(name: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
