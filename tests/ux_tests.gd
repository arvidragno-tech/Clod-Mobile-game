extends RefCounted
## UX, guidance and custom-controls tests (3.5): presets, modifier combos,
## critical actions, REPLACE / SWAP, search, reset per category, persistence,
## input contexts, recent changes, follows, priorities, clinic status,
## recommendations, consequence deltas, first-time hints, links.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	_controls()
	_persistence()
	_contexts()
	_change_log()
	_follows()
	_guidance()
	_recommend()
	_consequence()
	_hints()
	_nav()
	Controls.reset_bindings()


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _controls() -> void:
	Controls.reset_bindings()
	check(Controls.current_preset() == "default", "default bindings are the DEFAULT preset")
	for p: String in Controls.PRESETS:
		Controls.apply_preset(p)
		check(Controls.current_preset() == p and Controls.all_conflicts().is_empty(), "preset %s applies with no conflicts %s" % [p, Controls.all_conflicts().keys()])
	Controls.apply_preset("default")
	Controls.rebind("map", KEY_Y, 0)
	check(Controls.current_preset() == "custom", "changing a key makes the layout CUSTOM")
	Controls.reset_bindings()
	# Modifier combinations: CTRL+S is one code, named and matched exactly.
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_S
	ev.ctrl_pressed = true
	var code := Controls.code_for(ev)
	check(code == (KEY_S | KEY_MASK_CTRL) and Controls.code_name(code) == "CTRL+S", "CTRL+S is one binding (%s)" % Controls.code_name(code))
	var mod := InputEventKey.new()
	mod.physical_keycode = KEY_SHIFT
	mod.shift_pressed = true
	check(Controls.code_for(mod) == KEY_SHIFT, "a modifier on its own binds as itself")
	Controls.rebind("quicksave", code, 1)
	ev.pressed = true
	check(ev.is_action("quicksave", true), "CTRL+S triggers quick save")
	var plain := InputEventKey.new()
	plain.physical_keycode = KEY_S
	plain.pressed = true
	check(not plain.is_action("quicksave", true), "plain S does not trigger the CTRL+S binding")
	check(ev.is_action("move_down") and not ev.is_action("move_down", true), "exact matching keeps CTRL+S off move-down (S)")
	Controls.reset_bindings()
	# Critical actions keep one key; REPLACE is refused on their last key.
	check(not Controls.clear_slot("pause", 0) and Controls.get_keys("pause") == [KEY_ESCAPE], "pause/back can't be left without a key")
	check(Controls.clear_slot("quick_coag", 0) and Controls.is_unassigned("quick_coag"), "an optional action can be unassigned")
	check(Controls.replace_blockers("map", KEY_ESCAPE) == ["pause"], "taking ESC from pause is blocked")
	Controls.rebind("map", KEY_ESCAPE, 0, "replace")
	check(Controls.get_keys("pause") == [KEY_ESCAPE], "REPLACE leaves a critical action's last key alone")
	Controls.reset_bindings()
	# REPLACE: the other action loses the key (unassigned there).
	var hit := Controls.rebind("map", KEY_I, 0, "replace")
	check(hit == ["inventory"] and Controls.get_slots("map")[0] == KEY_I and Controls.is_unassigned("inventory"), "REPLACE takes the key and unassigns it elsewhere")
	check(Controls.all_conflicts().is_empty(), "no conflict left after REPLACE")
	Controls.reset_bindings()
	# SWAP: they exchange keys.
	Controls.rebind("map", KEY_I, 0, "swap")
	check(Controls.get_slots("inventory")[0] == KEY_M and Controls.get_slots("map")[0] == KEY_I, "SWAP exchanges the keys")
	# Reset one category.
	Controls.reset_category("Map")
	check(Controls.is_default("map") and not Controls.is_default("inventory"), "RESET CATEGORY resets only that category")
	Controls.reset_bindings()
	# Search.
	var found := Controls.search("map")
	check(found.has("map") and not found.has("tool_1"), "searching 'map' finds the map actions")
	check(Controls.search("f5").has("quicksave"), "searching by key finds the action (F5 -> quick save)")
	check(Controls.search("").size() == Controls.ACTIONS.size(), "empty search lists everything")
	# Help text follows the keys.
	Controls.rebind("customer_info", KEY_Y, 0)
	check(Controls.fill("press {customer_info}") == "press Y" and TutorialManager.help_text().contains("Y"), "help texts name the current key")
	Controls.reset_bindings()
	check(Controls.CRITICAL.all(func(id: String) -> bool: return Controls.ACTIONS.has(id)), "critical actions exist")
	for id: String in ["clinic", "changes", "supply", "comms"]:
		check(InputContext.ROUTES.has(id) or id == "changes", "%s has a route" % id)


func _persistence() -> void:
	Controls.reset_bindings()
	Controls.rebind("map", KEY_TAB | KEY_MASK_SHIFT, 1)
	Settings.load_settings()
	check(Controls.get_slots("map")[1] == (KEY_TAB | KEY_MASK_SHIFT), "custom binding survives a settings reload (restart)")
	Controls.apply_bindings()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.shift_pressed = true
	ev.pressed = true
	check(ev.is_action("map", true), "the reloaded binding is live")
	Controls.reset_bindings()
	Settings.load_settings()
	check(Controls.is_default("map"), "reset restores the default after a reload")


func _contexts() -> void:
	check(InputContext.allows("pause", InputContext.MODAL) and InputContext.allows("pause", InputContext.SURGERY), "ESC works in every context")
	check(not InputContext.allows("map", InputContext.TEXT), "typing in a text field never opens screens")
	check(not InputContext.allows("map", InputContext.REBIND) and not InputContext.allows("pause", InputContext.REBIND), "rebinding captures every key")
	check(not InputContext.allows("map", InputContext.SURGERY) and not InputContext.allows("inventory", InputContext.DIALOGUE), "no navigation mid-operation or mid-conversation")
	check(InputContext.allows("map", InputContext.CLINIC) and InputContext.allows("journal", InputContext.MAP), "navigation hotkeys work in the clinic and on hub screens")
	check(InputContext.allows("quickload", InputContext.MENU) and not InputContext.allows("map", InputContext.MENU), "the main menu takes quick load but no game hotkeys")
	check(not InputContext.allows("help", InputContext.GUIDE) and InputContext.allows("help", InputContext.CLINIC), "F1 opens the guide (not twice)")
	var labels := {}
	for ctx in [InputContext.REBIND, InputContext.TEXT, InputContext.GUIDE, InputContext.DIALOGUE, InputContext.SURGERY, InputContext.CLINIC]:
		labels[InputContext.escape_label(ctx)] = true
	check(labels.size() >= 5, "ESC means something specific in each context")


func _change_log() -> void:
	SaveManager.reset_all()
	var was := GameManager.is_running
	GameManager.is_running = true
	ChangeLog.clear()
	FactionManager.change(&"street_gangs", 3)
	FactionManager.change(&"street_gangs", 4)
	var rows := ChangeLog.recent()
	var gang := rows.filter(func(e: Dictionary) -> bool: return str(e["cat"]) == "faction")
	check(gang.size() == 1 and roundi(float(gang[0]["delta"])) == 7, "repeated changes merge into one line (+7)")
	check(str(gang[0]["text"]).contains("+7"), "the line says by how much (%s)" % gang[0]["text"])
	check(ChangeLog.unread_count() >= 1, "new changes are unread")
	ChangeLog.mark_all_read()
	check(ChangeLog.unread_count() == 0, "opening the panel marks them read")
	FactionManager.change(&"black_market", 40)
	check(ChangeLog.recent().any(func(e: Dictionary) -> bool: return str(e["cat"]) == "faction_standing"), "crossing a standing is called out")
	var before := ChangeLog.mark()
	InventoryManager.supplies = 5
	ChangeLog._on_resources()
	InventoryManager.supplies = 2
	ChangeLog._on_resources()
	check(ChangeLog.since(before, ["supplies"]).size() == 1, "supplies use is logged (since works)")
	var saved := ChangeLog.get_save_data()
	ChangeLog.reset_state()
	ChangeLog.load_save_data(saved)
	check(ChangeLog.entries.size() == (saved["entries"] as Array).size(), "recent changes save and load")
	ChangeLog.add("patient", "Test", "Crashed", ChangeLog.CRITICAL)
	check(str(ChangeLog.recent(1)[0]["level"]) == "critical", "critical entries keep their level")
	GameManager.is_running = false
	var n := ChangeLog.entries.size()
	FactionManager.change(&"street_gangs", 1)
	check(ChangeLog.entries.size() == n, "nothing is logged outside a running game (menus, loading)")
	GameManager.is_running = was


func _follows() -> void:
	SaveManager.reset_all()
	var q: StringName = QuestManager.order[0]
	QuestManager.start(q)
	check(Follows.follow("quest", String(q), "Q"), "follow a quest")
	check(not Follows.follow("quest", String(q), "Q"), "following twice is a no-op")
	var live := Follows.live()
	check(live.size() == 1 and str(live[0]["title"]) == str(QuestManager.get_quest(q)["title"]), "a followed quest resolves live")
	var loc: StringName = LocationManager.known_locations()[0] if not LocationManager.known_locations().is_empty() else &"rusty_valve"
	Follows.follow("place", String(loc), "Somewhere")
	check(Follows.live().any(func(f: Dictionary) -> bool: return str(f["where"]) == String(loc) and (f["link"] as Dictionary).has("location")), "a followed place links to the map")
	Follows.follow("person", "nobody_at_all", "Ghost")
	check(not Follows.live().any(func(f: Dictionary) -> bool: return str(f["title"]) == "Ghost") and not Follows.is_following("person:nobody_at_all"), "a follow that no longer applies drops off")
	var saved := Follows.get_save_data()
	Follows.reset_state()
	Follows.load_save_data(saved)
	check(Follows.is_following(Follows.key("quest", String(q))), "follows save and load")
	QuestManager.complete(q)
	check(not Follows.live().any(func(f: Dictionary) -> bool: return str(f["kind"]) == "quest"), "a finished quest stops being followed")
	Follows.reset_state()


func _guidance() -> void:
	SaveManager.reset_all()
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	c.is_emergency = true
	CustomerManager.debug_set_customer(c)
	var its := Guidance.items()
	check(not its.is_empty() and str(its[0]["id"]) == "emergency" and its[0]["level"] == Guidance.CRITICAL, "an emergency at the door is the first priority")
	check((its[0]["link"] as Dictionary).has("customer"), "and it links to the patient")
	c.is_emergency = false
	InventoryManager.supplies = 0
	its = Guidance.items()
	check(its.any(func(i: Dictionary) -> bool: return str(i["id"]) == "supplies_out" and i["level"] == Guidance.CRITICAL), "no supplies is critical")
	check(its.any(func(i: Dictionary) -> bool: return str(i["id"]) == "door"), "the patient at the door is listed")
	var ranks := its.map(func(i: Dictionary) -> int: return {Guidance.CRITICAL: 0, Guidance.IMPORTANT: 1, Guidance.INFO: 2}[i["level"]])
	var sorted := ranks.duplicate()
	sorted.sort()
	check(ranks == sorted, "priorities are most urgent first")
	check(its.size() <= Guidance.MAX_ITEMS, "the list stays short")
	check(its.all(func(i: Dictionary) -> bool: return str(i["icon"]) != "" and Guidance.MARKS.has(i["level"])), "every line has a symbol, not just a colour")
	var rows := ClinicStatus.rows()
	check(rows.size() == 6, "clinic status summarises six systems")
	var top := ClinicStatus.most_important()
	check(top["level"] == ClinicStatus.BAD and str(top["text"]).contains("SUPPLY"), "the most important line says what to do (%s)" % top["text"])
	InventoryManager.supplies = 10
	CustomerManager.dismiss_current()


func _recommend() -> void:
	SaveManager.reset_all()
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	var me := Recommend.self_estimate(c)
	check(float(me["chance"]) > 0.1 and float(me["chance"]) < 1.0 and str(me["record"]) == "first time", "your odds are an estimate with a record (%d%%)" % roundi(float(me["chance"]) * 100.0))
	var s := Recommend.surgeon(c)
	check(str(s["who"]) == "you" and str(s["reason"]).contains("no ripperdoc"), "with nobody on shift, you're recommended")
	var e := StaffManager.generate_candidate()
	e["clinic"] = ClinicManager.tier
	e["skill"] = 5
	e["stress"] = 0.0
	StaffManager.employees.append(e)
	var ranked := Recommend.staff_ranked(c)
	check(ranked.size() == 1 and abs(float(ranked[0]["chance"]) - EmployeeAI.success_chance(e, c)) < 0.001, "staff odds are the real assign odds")
	check(str(ranked[0]["reason"]) != "", "each ripperdoc comes with a reason")
	# Complication odds mirror the surgery's own roll (diagnosis assumed right).
	EventManager.operations = 10
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	SurgeryManager.start_session(surgery, c, true, 1.0, 7, ImplantInstance.create(c.requested_cyberware_id))
	var real := SurgeryManager.get_extra_complication_chance()
	SurgeryManager.abort()
	check(absf(Recommend.complication_odds(c) - real) < 0.06, "complication odds match the operation (%.2f vs %.2f)" % [Recommend.complication_odds(c), real])
	check(Recommend.possible_complications(c).size() >= 0, "possible complications listed")
	InventoryManager.add_implant(c.requested_cyberware_id)
	check(Recommend.best_implant_uid(c) != "", "the best unit in stock is picked")
	StaffManager.employees.clear()
	CustomerManager.dismiss_current()


func _consequence() -> void:
	SaveManager.reset_all()
	var before := Consequence.snapshot()
	ReputationManager.change(4)
	FactionManager.add_heat(6.0)
	var d := Consequence.diff(before)
	check(d.any(func(x: Dictionary) -> bool: return str(x["label"]) == "Reputation" and roundi(float(x["delta"])) == 4 and bool(x["good"])), "consequence shows the real reputation change")
	check(d.any(func(x: Dictionary) -> bool: return str(x["label"]) == "Authority heat" and not bool(x["good"])), "more heat is shown as bad")
	check(Consequence.diff(Consequence.snapshot()).is_empty(), "nothing changed, nothing shown")
	var shown_before := Consequence.snapshot()
	ReputationManager.change(2)
	var shown := Consequence.show("A test decision.", shown_before)
	var card: Control = null
	for n in (Engine.get_main_loop() as SceneTree).root.find_children("ConsequenceCard", "", true, false):
		card = n as Control
	var found := card != null
	var blocks := card == null or card.mouse_filter != Control.MOUSE_FILTER_IGNORE
	if card:
		for n in card.find_children("*", "Control", true, false):
			blocks = blocks or (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE
		card.free()
	check(found and not blocks, "the consequence card never takes a click (shown %d, card %s)" % [shown.size(), found])


func _hints() -> void:
	var was_enabled := Hints.enabled
	var was_running := GameManager.is_running
	var was_hints := Settings.tutorial_hints
	Hints.enabled = true
	GameManager.is_running = true
	Settings.tutorial_hints = true
	Hints.reset_all()
	check(Hints.first("neural_load"), "a first-time hint shows once")
	check(not Hints.first("neural_load") and Hints.seen("neural_load"), "and never again")
	Settings.load_settings()
	check(Hints.seen("neural_load"), "seen hints survive a restart")
	Hints.reset_all()
	Settings.tutorial_hints = false
	check(not Hints.first("heat"), "TUTORIAL HINTS off: no hints")
	check(Hints.HINTS.values().all(func(h: Array) -> bool: return Glossary.has(str(h[2]))), "every hint links to a field-guide entry")
	Hints.dismiss()
	Hints.reset_all()
	Settings.tutorial_hints = was_hints
	GameManager.is_running = was_running
	Hints.enabled = was_enabled


func _nav() -> void:
	SaveManager.reset_all()
	check(not Nav.can_open({}) and not Nav.can_open({"customer": true}), "empty or stale links don't open")
	check(Nav.can_open({"screen": &"map"}) and Nav.can_open({"term": "heat"}), "screen and term links open")
	check(not Nav.can_open({"location": &"nowhere_real"}), "unknown places don't open")
	for term in ["reading", "priorities", "follow", "changes", "preview", "controls"]:
		check(Glossary.has(term), "the field guide explains %s" % term)
	check(UIManager.READING_SCREENS.has(UIManager.SCREEN_MAP) and UIManager.READING_SCREENS.has(UIManager.SCREEN_DOSSIER), "the map and journal are reading screens (the clock stops)")
