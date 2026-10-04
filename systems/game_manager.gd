extends Node
## High-level game flow: new game / continue, the customer → diagnosis →
## plan → surgery → results loop, and applying rewards and consequences.
## Screens call into this; it coordinates the other systems and tells
## UIManager where to go next.

var is_running: bool = false
var chosen_diagnosis_id: StringName = &""
var diagnosis_correct: bool = false
var last_result: SurgeryResult = null
## uid of the implant chosen on the operation plan ("" = automatic).
var selected_implant_uid: String = ""

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	SurgeryManager.session_finished.connect(_on_surgery_finished)


# --- Session -----------------------------------------------------------------

func start_new_game() -> void:
	SaveManager.delete_save()
	SaveManager.reset_all()
	StoryManager.unlock_rumor(&"welcome")
	TutorialManager.start()
	_begin_play()
	SaveManager.save_game()
	EventBus.new_game_started.emit()
	UIManager.go_to(UIManager.SCREEN_CLINIC)


## Starts a new game in the given slot (1..3).
func start_new_game_in_slot(n: int) -> void:
	SaveManager.use_slot(n)
	start_new_game()


## Continue = the most recently saved slot.
func continue_game() -> void:
	var latest := SaveManager.latest_slot()
	if latest > 0:
		SaveManager.use_slot(latest)
	if not SaveManager.load_game():
		start_new_game()
		return
	_begin_play()
	UIManager.go_to(UIManager.SCREEN_CLINIC)


func load_slot(n: int) -> bool:
	SaveManager.use_slot(n)
	if not SaveManager.load_game():
		UIManager.show_toast("Slot %d could not be loaded" % n, &"danger")
		return false
	_begin_play()
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	return true


## F5: save to the active slot (never mid-surgery).
func quick_save() -> void:
	if not is_running or SurgeryManager.is_active:
		return
	if SaveManager.save_game():
		UIManager.show_toast("Saved to slot %d" % SaveManager.slot, &"success")


## F9: reload the active slot (or the latest one from the main menu).
func quick_load() -> void:
	if SurgeryManager.is_active:
		return
	var n := SaveManager.slot if is_running else SaveManager.latest_slot()
	if n <= 0 or SaveManager.get_slot_info(n).is_empty():
		UIManager.show_toast("No save to load", &"warn")
		return
	load_slot(n)


## Sidebar / hotkey navigation between workstation sections.
func navigate(id: StringName) -> void:
	match id:
		&"clinic":
			go_to_clinic()
		&"inventory":
			UIManager.go_to(UIManager.SCREEN_INVENTORY)
		&"database":
			UIManager.go_to(UIManager.SCREEN_DATABASE)
		&"supply":
			UIManager.go_to(UIManager.SCREEN_SHOP)
		&"skills":
			UIManager.go_to(UIManager.SCREEN_SKILLS)
		&"upgrades":
			UIManager.go_to(UIManager.SCREEN_UPGRADES)
		&"dossier":
			UIManager.go_to(UIManager.SCREEN_DOSSIER)
		&"business":
			UIManager.go_to(UIManager.SCREEN_BUSINESS)
		&"map":
			UIManager.go_to(UIManager.SCREEN_MAP)
		&"settings":
			UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.current_screen_id})
		&"blackmarket":
			if BlackMarketManager.is_unlocked():
				UIManager.go_to(UIManager.SCREEN_BLACK_MARKET)
			else:
				AudioManager.play_sfx(&"denied")
				UIManager.show_toast("No contact yet. Build street rep (%d) or find a fixer." % GameConfig.BLACK_MARKET_REPUTATION, &"warn")


## ESC / MENU: pause menu with save, load, settings, how to play, quit.
func open_pause_menu() -> void:
	if UIManager.has_modal() or not is_running:
		return
	var buttons: Array[Dictionary] = [
		{"label": "RESUME", "style": &"AccentButton", "name": "PauseResume"},
		{"label": "SAVE GAME (SLOT %d)" % SaveManager.slot, "style": &"", "name": "PauseSave", "callback": quick_save},
		{"label": "LOAD GAME", "style": &"", "name": "PauseLoad", "callback": func() -> void:
			UIManager.go_to(UIManager.SCREEN_LOAD, {"return_to": UIManager.current_screen_id})},
		{"label": "SETTINGS", "style": &"", "name": "PauseSettings", "callback": func() -> void:
			UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.current_screen_id})},
		{"label": "HOW TO PLAY", "style": &"", "name": "PauseHelp", "callback": func() -> void:
			var ok: Array[Dictionary] = [{"label": "GOT IT", "style": &"AccentButton", "name": "HelpClose"}]
			UIManager.show_dialog("HOW TO PLAY", TutorialManager.HELP_TEXT, ok)},
		{"label": "SAVE & MAIN MENU", "style": &"GhostButton", "name": "PauseQuit", "callback": quit_to_menu},
		{"label": "SAVE & QUIT TO DESKTOP", "style": &"DangerButton", "name": "PauseExit", "callback": quit_to_desktop},
	]
	UIManager.show_dialog("CLINIC PAUSED", "Autosaves after every job, purchase and upgrade.  F5 quick save · F9 quick load.", buttons)


## Tests turn this off so random input can't close the game under them.
var quit_enabled: bool = true


func quit_to_desktop() -> void:
	if is_running and not SurgeryManager.is_active:
		SaveManager.save_game()
	if not quit_enabled:
		UIManager.go_to(UIManager.SCREEN_MAIN_MENU)
		return
	AudioManager.stop_all()
	get_tree().quit()


func quit_to_menu() -> void:
	if SurgeryManager.is_active:
		return
	SaveManager.save_game()
	UIManager.go_to(UIManager.SCREEN_MAIN_MENU)


func _begin_play() -> void:
	is_running = true
	SaveManager.autosave_enabled = true
	chosen_diagnosis_id = &""
	last_result = null
	if BlackMarketManager.is_unlocked() and BlackMarketManager.stock.is_empty():
		BlackMarketManager.refresh_stock()


# --- Navigation helpers -------------------------------------------------------

func go_to_clinic() -> void:
	UIManager.go_to(UIManager.SCREEN_CLINIC)
	if BusinessManager.is_day_full() and not CustomerManager.has_customer() and not EventManager.has_pending():
		close_for_the_night()


## Ends the business day: settles rent, salaries and upkeep and shows the
## night's ledger. Also offered as a button on the clinic screen.
func close_for_the_night() -> void:
	if SurgeryManager.is_active or CustomerManager.has_customer():
		return
	var report := BusinessManager.end_day()
	SaveManager.save_game()
	UIManager.show_day_report(report)
	CustomerManager.request_next_customer()


## The single most useful next step for the player (clinic "NEXT" line).
## Returns {"text": String, "kind": &"info"|&"warn"}.
func get_next_objective() -> Dictionary:
	if EventManager.has_pending():
		return {"text": "Someone is waiting: deal with the incident", "kind": &"warn"}
	var c := get_current_customer()
	if c:
		return {"text": "See %s at the door%s" % [c.display_name, " (EMERGENCY)" if c.is_emergency else ""], "kind": &"warn" if c.is_emergency else &"info"}
	if SkillManager.points > 0:
		return {"text": "Spend %d skill point%s in SKILLS" % [SkillManager.points, "s" if SkillManager.points > 1 else ""], "kind": &"info"}
	if BusinessManager.is_day_full():
		return {"text": "Day's work done: CLOSE FOR THE NIGHT", "kind": &"info"}
	if BusinessManager.debt >= BusinessManager.DEBT_WARNING:
		return {"text": "You owe %d: pay it down in BUSINESS" % BusinessManager.debt, "kind": &"warn"}
	if ClinicManager.get_upgrade_block_reason() == "":
		return {"text": "A new clinic is within reach: open PROPERTY", "kind": &"info"}
	if InventoryManager.supplies < 2:
		return {"text": "Supplies low: restock in SUPPLY", "kind": &"warn"}
	return {"text": "Waiting for the next customer", "kind": &"info"}


func open_screen(screen_id: StringName) -> void:
	UIManager.go_to(screen_id)


# --- Customer flow -----------------------------------------------------------

func get_current_customer() -> CustomerData:
	return CustomerManager.current_customer


func get_requested_item() -> CyberwareData:
	var c := get_current_customer()
	return CyberwareManager.get_cyberware(c.requested_cyberware_id) if c else null


func get_current_surgery() -> SurgeryData:
	var c := get_current_customer()
	if c == null:
		return null
	var item := get_requested_item()
	var sid := item.install_surgery_id if item else c.requested_surgery_id
	return SurgeryManager.get_surgery(sid)


func open_customer() -> void:
	if CustomerManager.has_customer():
		UIManager.go_to(UIManager.SCREEN_CUSTOMER)


func decline_customer() -> void:
	var c := get_current_customer()
	ReputationManager.change(GameConfig.DECLINE_REPUTATION_PENALTY)
	if c:
		FactionManager.change(c.faction_id, -1)
	CustomerManager.dismiss_current()
	SaveManager.save_game()
	UIManager.go_to(UIManager.SCREEN_CLINIC)


func accept_customer() -> void:
	chosen_diagnosis_id = &""
	selected_implant_uid = ""
	UIManager.go_to(UIManager.SCREEN_DIAGNOSIS)


func submit_diagnosis(diagnosis_id: StringName) -> void:
	chosen_diagnosis_id = diagnosis_id
	var c := get_current_customer()
	diagnosis_correct = c != null and diagnosis_id == c.true_diagnosis_id


# --- Operation plan ----------------------------------------------------------

## Implant units that could go into the current customer (same category).
func get_implant_options() -> Array[ImplantInstance]:
	var item := get_requested_item()
	if item == null:
		return []
	var opts := InventoryManager.get_instances_of(item.category)
	opts.sort_custom(func(a: ImplantInstance, b: ImplantInstance) -> bool:
		var ar := 0 if a.cyberware_id == item.id else 1
		var br := 0 if b.cyberware_id == item.id else 1
		return ar < br or (ar == br and a.condition > b.condition))
	return opts


func select_implant(uid: String) -> void:
	selected_implant_uid = uid


## The unit that will be installed (null = none in stock).
func get_selected_implant() -> ImplantInstance:
	var opts := get_implant_options()
	if selected_implant_uid != "":
		for o in opts:
			if o.uid == selected_implant_uid:
				return o
	return opts[0] if not opts.is_empty() else null


## Whether the customer accepts a different / risky unit than requested.
func customer_accepts(inst: ImplantInstance) -> bool:
	var c := get_current_customer()
	if c == null or inst == null:
		return true
	# Heavily loaded patients get cold feet: severe / critical projected load
	# needs a matching appetite for risk, even for the unit they asked for.
	var needed_nerve := consent_risk_needed(NeuralLoad.projected(c, inst))
	if c.risk_tolerance < needed_nerve:
		return false
	if inst.cyberware_id == c.requested_cyberware_id and inst.traits.is_empty():
		return true
	var data := inst.get_data()
	var requested := get_requested_item()
	# Upgrades are always welcome; downgrades and shady chrome need nerve.
	if data and requested and data.tier > requested.tier and not data.black_market:
		return true
	return c.risk_tolerance >= (0.35 if not inst.has_unknown_traits() else 0.6)


## Minimum risk tolerance a customer needs to consent at a projected load.
func consent_risk_needed(projected_load: float) -> float:
	match NeuralLoad.band(projected_load)["id"]:
		&"severe":
			return GameConfig.CONSENT_RISK_SEVERE
		&"critical":
			return GameConfig.CONSENT_RISK_CRITICAL
	return 0.0


## Everything the plan screen needs to show and gate BEGIN OPERATION.
func get_surgery_readiness() -> Dictionary:
	var r := {"ok": false, "missing_tools": [] as Array[String], "implant_source": &"stock", "implant": null,
		"supplies_ok": true, "invalid": "", "accepts": true, "neural_now": 0.0, "neural_after": 0.0}
	var c := get_current_customer()
	var item := get_requested_item()
	var surgery := get_current_surgery()
	if c == null or item == null or surgery == null or not CyberwareManager.is_valid(item.id):
		r["invalid"] = "INVALID CYBERWARE REQUEST"
		return r
	var missing: Array[String] = []
	for category in surgery.get_required_tool_categories():
		if not InventoryManager.has_tool_category(category):
			missing.append(String(category).to_upper())
	for req in item.get_tool_requirements():
		if not InventoryManager.has_tool_category(req["category"], int(req["tier"])):
			var label := "%s T%d" % [String(req["category"]).to_upper(), int(req["tier"])]
			if not missing.has(label):
				missing.append(label)
	r["missing_tools"] = missing
	var inst := get_selected_implant()
	if inst:
		r["implant"] = inst
		r["implant_source"] = &"stock" if inst.cyberware_id == item.id else &"substitute"
		r["accepts"] = customer_accepts(inst)
	elif not item.black_market and CyberwareManager.is_tier_available(item.tier) and EconomyManager.can_afford(InventoryManager.implant_price(item)):
		r["implant_source"] = &"buy"
	else:
		r["implant_source"] = &"salvaged"
	r["supplies_ok"] = InventoryManager.supplies >= surgery.supplies
	r["neural_now"] = NeuralLoad.compute(c)
	var preview := inst if inst else ImplantInstance.create(item.id)
	r["neural_after"] = NeuralLoad.projected(c, preview)
	r["ok"] = missing.is_empty() and bool(r["accepts"])
	return r


func begin_surgery() -> void:
	var surgery := get_current_surgery()
	var readiness := get_surgery_readiness()
	if surgery == null or not readiness["ok"]:
		UIManager.show_toast(str(readiness.get("invalid", "")) if readiness.get("invalid", "") != "" else "Cannot operate: missing equipment", &"danger")
		return
	var implant_quality := 1.0
	var inst: ImplantInstance = readiness["implant"]
	match readiness["implant_source"]:
		&"buy":
			InventoryManager.buy_implant(get_requested_item().id)
			inst = InventoryManager.consume_implant(get_requested_item().id)
		&"salvaged":
			implant_quality = GameConfig.SALVAGED_IMPLANT_QUALITY
			inst = ImplantInstance.create(get_requested_item().id, 70.0, &"salvaged")
		_:
			InventoryManager.remove_instance(inst.uid)
	var session_mods := {}
	if not InventoryManager.use_supplies(surgery.supplies):
		session_mods = GameConfig.NO_SUPPLIES_MODIFIERS.duplicate()
	SurgeryManager.start_session(surgery, get_current_customer(), diagnosis_correct, implant_quality, -1, inst, session_mods)
	UIManager.go_to(UIManager.SCREEN_SURGERY)


func abort_surgery() -> void:
	SurgeryManager.abort()


# --- Results -----------------------------------------------------------------

func _on_surgery_finished(result: SurgeryResult) -> void:
	var c := SurgeryManager.customer
	_apply_patience(result, c)
	EconomyManager.add_money(result.pay, &"revenue")
	var tier_before := CyberwareManager.get_available_tier()
	result.levels_gained = ProgressionManager.add_xp(result.xp)
	if CyberwareManager.get_available_tier() > tier_before:
		result.unlocked_tier = CyberwareManager.get_available_tier()
	ReputationManager.change(result.reputation_delta)
	ProgressionManager.record_surgery(result.surgery_id, result.success, result.grade)
	_apply_faction_and_heat(result, c)
	if c:
		if result.success:
			c.existing_cyberware.append(result.implant_id)
		result.consequences = CustomerManager.record_outcome(c, result)
	CustomerManager.dismiss_current()
	BusinessManager.record_job()
	WorldManager.add_influence()
	EventManager.on_operation_completed()
	BlackMarketManager.on_operation_completed()
	if result.neural_break:
		EventManager.queue_event(&"static_fever")
	else:
		EventManager.roll_random_event()
	StoryManager.update_rumors()
	last_result = result
	SaveManager.save_game()
	EventBus.surgery_rewarded.emit(result)
	# Let the surgery screen play its success/failure moment first.
	await get_tree().create_timer(GameConfig.RESULTS_DELAY_SEC).timeout
	# Only the operating table leads to the report (never yank the player
	# off another screen, e.g. after an app resume or a headless session).
	if UIManager.current_screen_id == UIManager.SCREEN_SURGERY:
		UIManager.go_to(UIManager.SCREEN_RESULTS, {"result": result})


## Impatient customers pay less when the job runs long.
func _apply_patience(result: SurgeryResult, c: CustomerData) -> void:
	if c == null or not result.success or result.elapsed_sec <= result.target_time_sec:
		return
	var over := clampf((result.elapsed_sec - result.target_time_sec) / result.target_time_sec, 0.0, 1.0)
	var cut := over * (1.0 - c.patience / 100.0) * 0.4
	result.pay = int(round(result.pay * (1.0 - cut)))


func _apply_faction_and_heat(result: SurgeryResult, c: CustomerData) -> void:
	var heat := -GameConfig.HEAT_DECAY_PER_OP
	if c:
		result.faction_id = c.faction_id
		var delta := GameConfig.FACTION_REP_SUCCESS + (2 if result.grade in ["S", "A"] else 0)
		if not result.success:
			delta = GameConfig.FACTION_REP_DEATH if result.failure_reason == &"flatline" else GameConfig.FACTION_REP_FAILURE
		result.faction_delta = FactionManager.change(c.faction_id, delta)
	if result.black_market_implant:
		heat += GameConfig.HEAT_PER_BM_INSTALL
		var inst := SurgeryManager.implant
		if inst:
			heat += inst.trait_effect("heat")
	if result.failure_reason == &"flatline":
		heat += GameConfig.HEAT_PER_DEATH
	if result.success and _rng.randf() < NeuralLoad.break_chance(result.neural_load_after):
		result.neural_break = true
	var before := FactionManager.heat
	FactionManager.add_heat(heat)
	result.heat_delta = FactionManager.heat - before


func finish_results() -> void:
	go_to_clinic()
