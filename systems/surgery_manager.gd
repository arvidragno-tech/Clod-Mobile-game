extends Node
## Runs an operation: stage progression, vitals simulation, mistakes,
## complications, emergency quick actions and the final result.
## Contains no UI. Stage scenes report into it; the SurgeryScreen listens to it.

signal session_started(surgery: SurgeryData, customer: CustomerData)
signal vitals_changed(vitals: SurgeryVitals)
signal stage_started(index: int, stage: SurgeryStageData)
signal stage_completed(index: int, quality: float)
signal mistake_made(kind: StringName, severity: float)
signal vital_warning(vital: StringName)
signal complication_started(complication: ComplicationData)
signal complication_resolved(complication: ComplicationData, handled: bool)
signal quick_action_used(action_id: StringName)
signal session_finished(result: SurgeryResult)

var surgeries: Dictionary = {}  # StringName -> SurgeryData
var complications: Dictionary = {}  # StringName -> ComplicationData

var is_active: bool = false
## False while the surgery screen is still loading; vitals don't tick.
var is_running: bool = false
var surgery: SurgeryData
var customer: CustomerData
var diagnosis_correct: bool = true
var vitals: SurgeryVitals
var stage_index: int = -1
var elapsed: float = 0.0
var mistake_count: int = 0
var stage_qualities: Array[float] = []
var implant_alignment: float = 1.0
var calibration_quality: float = 1.0
## Multiplier for the implant itself (salvaged units perform worse).
var implant_quality: float = 1.0
var active_complication: ComplicationData = null
var complication_time_left: float = 0.0
var complications_total: int = 0
var complications_handled: int = 0
var last_result: SurgeryResult

var _cooldowns: Dictionary = {}  # StringName -> seconds remaining
var _planned_complication_stages: Array[int] = []
var _pending_complication_delay: float = -1.0
var _used_complication_ids: Array[StringName] = []
var _warnings_active: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_load_catalogs()


func _load_catalogs() -> void:
	surgeries.clear()
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_SURGERIES, "surgeries"):
		var s := SurgeryData.from_dict(entry)
		surgeries[s.id] = s
	complications.clear()
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_COMPLICATIONS, "complications"):
		var c := ComplicationData.from_dict(entry)
		complications[c.id] = c


func get_surgery(id: StringName) -> SurgeryData:
	return surgeries.get(id) as SurgeryData


# --- Session lifecycle -------------------------------------------------------

func start_session(p_surgery: SurgeryData, p_customer: CustomerData, p_diagnosis_correct: bool, p_implant_quality: float = 1.0, rng_seed: int = -1) -> void:
	surgery = p_surgery
	implant_quality = p_implant_quality
	customer = p_customer
	diagnosis_correct = p_diagnosis_correct
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	vitals = SurgeryVitals.new()
	vitals.configure_for(customer)
	stage_index = -1
	elapsed = 0.0
	mistake_count = 0
	stage_qualities.clear()
	implant_alignment = 1.0
	calibration_quality = 1.0
	active_complication = null
	complications_total = 0
	complications_handled = 0
	_cooldowns.clear()
	_warnings_active.clear()
	_used_complication_ids.clear()
	_pending_complication_delay = -1.0
	_plan_complications()
	is_active = true
	is_running = false
	session_started.emit(surgery, customer)
	vitals_changed.emit(vitals)
	_advance_stage()


## Called by the surgery screen once it is ready for input.
func resume() -> void:
	is_running = is_active


func get_current_stage() -> SurgeryStageData:
	if surgery == null or stage_index < 0 or stage_index >= surgery.stages.size():
		return null
	return surgery.stages[stage_index]


func get_stage_count() -> int:
	return surgery.stages.size() if surgery else 0


## Called by stage scenes when their interaction is done.
## `data` may carry stage-specific outputs (dose, alignment, sync).
func complete_stage(quality: float, data: Dictionary = {}) -> void:
	if not is_active:
		return
	var stage := get_current_stage()
	quality = clampf(quality, 0.0, 1.0)
	stage_qualities.append(quality)
	_apply_stage_outputs(stage, data)
	stage_completed.emit(stage_index, quality)
	if not is_active:
		return
	if stage_index >= surgery.stages.size() - 1:
		_finish(true, &"")
	else:
		_advance_stage()


func abort() -> void:
	if is_active:
		_finish(false, &"aborted")


func _advance_stage() -> void:
	stage_index += 1
	var stage := get_current_stage()
	if _planned_complication_stages.has(stage_index):
		_pending_complication_delay = _rng.randf_range(GameConfig.COMPLICATION_DELAY_RANGE.x, GameConfig.COMPLICATION_DELAY_RANGE.y)
	stage_started.emit(stage_index, stage)


func _apply_stage_outputs(stage: SurgeryStageData, data: Dictionary) -> void:
	match stage.type:
		&"anesthesia":
			vitals.sedated = true
		&"incision":
			vitals.set_wound_open(true)
		&"install_implant":
			implant_alignment = float(data.get("alignment", 1.0))
		&"calibrate":
			calibration_quality = float(data.get("sync", 1.0))
		&"close_incision":
			vitals.set_wound_open(false)
	vitals_changed.emit(vitals)


func _finish(success: bool, reason: StringName) -> void:
	is_active = false
	is_running = false
	_pending_complication_delay = -1.0
	if active_complication:
		complication_resolved.emit(active_complication, false)
		active_complication = null
	var r := SurgeryResult.new()
	r.surgery_id = surgery.id
	r.surgery_name = surgery.display_name
	r.customer_name = customer.display_name if customer else "?"
	r.success = success
	r.failure_reason = reason
	r.elapsed_sec = elapsed
	r.target_time_sec = surgery.target_time_sec
	r.mistakes = mistake_count
	r.complications_total = complications_total
	r.complications_handled = complications_handled
	r.stage_quality = _average(stage_qualities, surgery.stages.size())
	r.implant_performance = get_implant_performance()
	r.final_health = vitals.health
	r.final_neural = vitals.neural
	r.final_blood_loss = vitals.blood_loss
	r.diagnosis_correct = diagnosis_correct
	SurgeryScoring.apply_rewards(r, surgery, customer)
	last_result = r
	session_finished.emit(r)


func get_implant_performance() -> float:
	var item := CyberwareManager.get_cyberware(surgery.cyberware_id) if surgery else null
	var base := item.base_performance if item else 1.0
	return clampf(base * implant_quality * (0.5 * implant_alignment + 0.5 * calibration_quality), 0.0, 1.0)


static func _average(values: Array[float], count: int) -> float:
	if count <= 0:
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(count)


# --- Simulation --------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_active or not is_running:
		return
	elapsed += delta
	vitals.tick(delta)
	_tick_cooldowns(delta)
	_tick_complications(delta)
	_check_warnings()
	vitals_changed.emit(vitals)
	var reason := vitals.get_failure_reason()
	if reason != &"":
		_finish(false, reason)


## Stages call this whenever the player makes an error.
func report_mistake(kind: StringName, severity: float = 1.0) -> void:
	if not is_active:
		return
	var effects: Dictionary = GameConfig.MISTAKE_EFFECTS.get(kind, {})
	if effects.is_empty():
		push_warning("SurgeryManager: unknown mistake '%s'" % kind)
	vitals.apply_effects(effects, severity)
	mistake_count += 1
	mistake_made.emit(kind, severity)
	vitals_changed.emit(vitals)


## Applies a raw effect without counting it as a mistake (e.g. cautery
## sealing vessels while it burns).
func apply_effect(effects: Dictionary, scale: float = 1.0) -> void:
	if is_active:
		vitals.apply_effects(effects, scale)
		vitals_changed.emit(vitals)


func _check_warnings() -> void:
	_update_warning(&"health", vitals.health <= GameConfig.WARN_HEALTH)
	_update_warning(&"blood_loss", vitals.blood_loss >= GameConfig.WARN_BLOOD_LOSS)
	_update_warning(&"pain", vitals.pain >= GameConfig.WARN_PAIN)
	_update_warning(&"neural", vitals.neural <= GameConfig.WARN_NEURAL)


func _update_warning(vital: StringName, active: bool) -> void:
	var was_active := bool(_warnings_active.get(vital, false))
	_warnings_active[vital] = active
	if active and not was_active:
		vital_warning.emit(vital)


func is_warning_active(vital: StringName) -> bool:
	return bool(_warnings_active.get(vital, false))


# --- Tools -------------------------------------------------------------------

func get_tool_for_category(category: StringName) -> ToolData:
	return InventoryManager.get_best_tool(category)


func get_tool_precision(category: StringName) -> float:
	var t := get_tool_for_category(category)
	return t.precision if t else 1.0


func get_tool_speed(category: StringName) -> float:
	var t := get_tool_for_category(category)
	return t.speed if t else 1.0


# --- Quick actions -----------------------------------------------------------

func get_cooldown_remaining(action_id: StringName) -> float:
	return float(_cooldowns.get(action_id, 0.0))


func get_cooldown_ratio(action_id: StringName) -> float:
	var cfg: Dictionary = GameConfig.QUICK_ACTIONS.get(action_id, {})
	var total := float(cfg.get("cooldown", 1.0))
	return clampf(get_cooldown_remaining(action_id) / total, 0.0, 1.0)


func use_quick_action(action_id: StringName) -> bool:
	if not is_active or get_cooldown_remaining(action_id) > 0.0:
		return false
	var cfg: Dictionary = GameConfig.QUICK_ACTIONS.get(action_id, {})
	if cfg.is_empty():
		return false
	var effects := {}
	for key: String in ["bleed_rate", "blood", "pain", "neural", "health", "pain_baseline"]:
		if cfg.has(key):
			effects[key] = cfg[key]
	vitals.apply_effects(effects)
	_cooldowns[action_id] = float(cfg.get("cooldown", 5.0))
	quick_action_used.emit(action_id)
	if active_complication and active_complication.counter_action == action_id:
		complications_handled += 1
		var resolved := active_complication
		active_complication = null
		complication_resolved.emit(resolved, true)
	vitals_changed.emit(vitals)
	return true


func _tick_cooldowns(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta)


# --- Complications -----------------------------------------------------------

func _plan_complications() -> void:
	_planned_complication_stages.clear()
	var windows: Array[int] = []
	for i in surgery.stages.size():
		if surgery.stages[i].complication_window:
			windows.append(i)
	if windows.is_empty():
		return
	var risk := customer.complication_risk if customer else 1.0
	if not diagnosis_correct:
		risk *= GameConfig.WRONG_DIAGNOSIS_RISK_MULT
	var count := GameConfig.GUARANTEED_COMPLICATIONS
	if _rng.randf() < GameConfig.EXTRA_COMPLICATION_BASE_CHANCE * risk:
		count += 1
	count = mini(count, windows.size())
	for i in count:
		var pick := windows[_rng.randi_range(0, windows.size() - 1)]
		windows.erase(pick)
		_planned_complication_stages.append(pick)


func _tick_complications(delta: float) -> void:
	if active_complication:
		complication_time_left -= delta
		if complication_time_left <= 0.0:
			var failed := active_complication
			active_complication = null
			vitals.apply_effects(failed.failure_effects)
			complication_resolved.emit(failed, false)
		return
	if _pending_complication_delay >= 0.0:
		_pending_complication_delay -= delta
		if _pending_complication_delay < 0.0:
			_start_complication()


func _start_complication() -> void:
	var pool: Array[ComplicationData] = []
	for c: ComplicationData in complications.values():
		if not _used_complication_ids.has(c.id):
			pool.append(c)
	if pool.is_empty():
		pool.assign(complications.values())
	if not pool.is_empty():
		_begin_complication(pool[_rng.randi_range(0, pool.size() - 1)])


func _begin_complication(c: ComplicationData) -> void:
	active_complication = c
	_used_complication_ids.append(c.id)
	complication_time_left = c.time_limit
	complications_total += 1
	vitals.apply_effects(c.onset_effects)
	complication_started.emit(c)


## Test / debug hook: forces a complication to start immediately.
func debug_trigger_complication(id: StringName) -> void:
	if is_active and active_complication == null and complications.has(id):
		_begin_complication(complications[id])


func get_complication_time_ratio() -> float:
	if active_complication == null:
		return 0.0
	return clampf(complication_time_left / active_complication.time_limit, 0.0, 1.0)
