extends Node
## High-level game flow: new game / continue, the customer → diagnosis →
## surgery → results loop, and applying rewards. Screens call into this;
## it coordinates the other systems and tells UIManager where to go next.

var is_running: bool = false
var chosen_diagnosis_id: StringName = &""
var diagnosis_correct: bool = false
var last_result: SurgeryResult = null


func _ready() -> void:
	SurgeryManager.session_finished.connect(_on_surgery_finished)


# --- Session -----------------------------------------------------------------

func start_new_game() -> void:
	SaveManager.delete_save()
	SaveManager.reset_all()
	_begin_play()
	SaveManager.save_game()
	EventBus.new_game_started.emit()
	UIManager.go_to(UIManager.SCREEN_CLINIC)


func continue_game() -> void:
	if not SaveManager.load_game():
		start_new_game()
		return
	_begin_play()
	UIManager.go_to(UIManager.SCREEN_CLINIC)


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


# --- Customer flow -----------------------------------------------------------

func get_current_customer() -> CustomerData:
	return CustomerManager.current_customer


func get_current_surgery() -> SurgeryData:
	var c := get_current_customer()
	return SurgeryManager.get_surgery(c.requested_surgery_id) if c else null


func open_customer() -> void:
	if CustomerManager.has_customer():
		UIManager.go_to(UIManager.SCREEN_CUSTOMER)


func decline_customer() -> void:
	ReputationManager.change(GameConfig.DECLINE_REPUTATION_PENALTY)
	CustomerManager.dismiss_current()
	SaveManager.save_game()
	UIManager.go_to(UIManager.SCREEN_CLINIC)


func accept_customer() -> void:
	chosen_diagnosis_id = &""
	UIManager.go_to(UIManager.SCREEN_DIAGNOSIS)


func submit_diagnosis(diagnosis_id: StringName) -> void:
	chosen_diagnosis_id = diagnosis_id
	var c := get_current_customer()
	diagnosis_correct = c != null and diagnosis_id == c.true_diagnosis_id


## Readiness check shown on the operation plan.
## Returns {"ok": bool, "missing_tools": Array[StringName], "implant_source": StringName}
## implant_source is &"stock", &"salvaged" (no stock, can't afford one) or &"buy".
func get_surgery_readiness() -> Dictionary:
	var surgery := get_current_surgery()
	var missing: Array[StringName] = []
	if surgery == null:
		return {"ok": false, "missing_tools": missing, "implant_source": &"stock"}
	for category in surgery.get_required_tool_categories():
		if not InventoryManager.has_tool_category(category):
			missing.append(category)
	var source := &"stock"
	if InventoryManager.get_implant_count(surgery.cyberware_id) <= 0:
		var item := CyberwareManager.get_cyberware(surgery.cyberware_id)
		source = &"buy" if item and EconomyManager.can_afford(item.price) else &"salvaged"
	return {"ok": missing.is_empty(), "missing_tools": missing, "implant_source": source}


func begin_surgery() -> void:
	var surgery := get_current_surgery()
	var readiness := get_surgery_readiness()
	if surgery == null or not readiness["ok"]:
		UIManager.show_toast("Cannot operate: missing equipment", &"danger")
		return
	var implant_quality := 1.0
	match readiness["implant_source"]:
		&"buy":
			InventoryManager.buy_implant(surgery.cyberware_id)
			InventoryManager.consume_implant(surgery.cyberware_id)
		&"salvaged":
			implant_quality = GameConfig.SALVAGED_IMPLANT_QUALITY
		_:
			InventoryManager.consume_implant(surgery.cyberware_id)
	SurgeryManager.start_session(surgery, get_current_customer(), diagnosis_correct, implant_quality)
	UIManager.go_to(UIManager.SCREEN_SURGERY)


func abort_surgery() -> void:
	SurgeryManager.abort()


func _on_surgery_finished(result: SurgeryResult) -> void:
	EconomyManager.add_money(result.pay)
	result.levels_gained = ProgressionManager.add_xp(result.xp)
	ReputationManager.change(result.reputation_delta)
	ProgressionManager.record_surgery(result.surgery_id, result.success, result.grade)
	CustomerManager.dismiss_current()
	last_result = result
	SaveManager.save_game()
	EventBus.surgery_rewarded.emit(result)
	# Let the surgery screen play its success/failure moment first.
	await get_tree().create_timer(GameConfig.RESULTS_DELAY_SEC).timeout
	UIManager.go_to(UIManager.SCREEN_RESULTS, {"result": result})


func finish_results() -> void:
	go_to_clinic()


func go_to_clinic() -> void:
	UIManager.go_to(UIManager.SCREEN_CLINIC)
