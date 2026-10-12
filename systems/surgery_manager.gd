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
## A decision complication stopped the operation (SurgicalDilemmas).
signal dilemma_started(dilemma: Dictionary)
signal dilemma_resolved(result: Dictionary)
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
## Bone-anchor quality (drill stage) feeds implant seating.
var anchor_quality: float = 1.0
## Multiplier for the implant itself (salvaged units perform worse).
var implant_quality: float = 1.0
var active_complication: ComplicationData = null
## Decision complication: the stage it stops at, the one on screen, and
## what the choices did to this operation.
var dilemma_stage: int = -1
var active_dilemma: Dictionary = {}
var dilemma_pay: float = 1.0
var dilemma_notes: Array[String] = []
## Whether the implant actually went in (an early abort can return it to stock).
var implant_installed: bool = false
var complication_time_left: float = 0.0
var complications_total: int = 0
var complications_handled: int = 0
var last_result: SurgeryResult
## The unit being installed (null = legacy/salvaged).
var implant: ImplantInstance = null
var implant_item: CyberwareData = null
var neural_load_before: float = 0.0
var neural_load_after: float = 0.0
## Extra modifiers for this session only (e.g. no supplies).
var session_modifiers: Dictionary = {}
var supplies_ok: bool = true

var _cooldowns: Dictionary = {}  # StringName -> seconds remaining
var _planned_complication_stages: Array[int] = []
var _pending_complication_delay: float = -1.0
var _queued_complications: int = 0
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

func start_session(p_surgery: SurgeryData, p_customer: CustomerData, p_diagnosis_correct: bool, p_implant_quality: float = 1.0,
		rng_seed: int = -1, p_implant: ImplantInstance = null, p_session_modifiers: Dictionary = {}) -> void:
	surgery = p_surgery
	implant_quality = p_implant_quality
	customer = p_customer
	diagnosis_correct = p_diagnosis_correct
	implant = p_implant
	session_modifiers = p_session_modifiers
	var item_id := implant.cyberware_id if implant else (customer.requested_cyberware_id if customer and customer.requested_cyberware_id != &"" else surgery.cyberware_id)
	implant_item = CyberwareManager.get_cyberware(item_id)
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	neural_load_before = NeuralLoad.compute(customer)
	neural_load_after = NeuralLoad.projected(customer, implant) if implant else neural_load_before + (implant_item.neural_load if implant_item else 0.0)
	vitals = SurgeryVitals.new()
	vitals.configure_for(customer)
	vitals.neural = clampf((customer.neural_stability if customer else 100.0) - NeuralLoad.start_penalty(neural_load_after), 15.0, 100.0)
	vitals.neural_multiplier *= NeuralLoad.drain_multiplier(neural_load_after)
	stage_index = -1
	elapsed = 0.0
	mistake_count = 0
	stage_qualities.clear()
	implant_alignment = 1.0
	calibration_quality = 1.0
	anchor_quality = 1.0
	active_complication = null
	complications_total = 0
	complications_handled = 0
	_cooldowns.clear()
	_warnings_active.clear()
	_used_complication_ids.clear()
	_pending_complication_delay = -1.0
	_queued_complications = 0
	_plan_complications()
	active_dilemma = {}
	implant_installed = false
	dilemma_pay = 1.0
	dilemma_notes.clear()
	dilemma_stage = SurgicalDilemmas.plan(self, _rng)
	is_active = true
	is_running = false
	session_started.emit(surgery, customer)
	vitals_changed.emit(vitals)
	_advance_stage()


## Called by the surgery screen once it is ready for input.
func resume() -> void:
	# A decision on screen keeps the patient frozen until it's made.
	is_running = is_active and active_dilemma.is_empty()


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


## Modifier value for this session: global stack + session-only extras.
func mod(key: StringName) -> float:
	return ModifierManager.value(key) + float(session_modifiers.get(String(key), 0.0))


func mod_mult(key: StringName) -> float:
	return 1.0 + mod(key)


func get_difficulty_factor() -> float:
	return implant_item.get_difficulty_factor() if implant_item else 1.0


## Context handed to stage interactions (keeps stages decoupled from systems).
func get_stage_context() -> Dictionary:
	return {
		"difficulty": get_difficulty_factor(),
		"neural_load": neural_load_after,
		"alignment_mult": mod_mult(&"surgery.alignment"),
		"sync_range_mult": mod_mult(&"calibrate.range") * NeuralLoad.sync_range_multiplier(neural_load_after),
		"implant_icon": implant_item.icon_path if implant_item else "",
		"implant_tier": implant_item.tier if implant_item else 1,
	}


func abort() -> void:
	if is_active:
		_finish(false, &"aborted")


func _advance_stage() -> void:
	stage_index += 1
	var stage := get_current_stage()
	if _planned_complication_stages.has(stage_index):
		_queued_complications += 1
	if _pending_complication_delay >= 0.0:
		# The player cleared the previous stage first: carry it over, soon
		# (almost immediately on the final stage so it is never skipped).
		var carry := GameConfig.COMPLICATION_CARRY_OVER_SEC
		if stage_index == surgery.stages.size() - 1:
			carry = GameConfig.COMPLICATION_FINAL_STAGE_SEC
		_pending_complication_delay = minf(_pending_complication_delay, carry)
	elif _queued_complications > 0 and active_complication == null:
		_schedule_next_complication()
	stage_started.emit(stage_index, stage)
	if stage_index == dilemma_stage and active_dilemma.is_empty() and is_active:
		_begin_dilemma(SurgicalDilemmas.pick(self, _rng))


func _begin_dilemma(d: Dictionary) -> void:
	if d.is_empty():
		return
	active_dilemma = d
	is_running = false
	dilemma_started.emit(d)


## Test / debug hook: stop the operation with a specific dilemma now.
func debug_trigger_dilemma(id: StringName) -> void:
	if is_active and active_dilemma.is_empty():
		_begin_dilemma(SurgicalDilemmas.get_dilemma(id))


## The player's choice. Returns {success, text, aborted}.
func resolve_dilemma(index: int) -> Dictionary:
	var choices: Array = active_dilemma.get("choices", [])
	if active_dilemma.is_empty() or index < 0 or index >= choices.size():
		return {}
	var ch: Dictionary = choices[index]
	if SurgicalDilemmas.block_reason(ch) != "":
		return {}
	var req: Dictionary = ch.get("requires", {})
	InventoryManager.add_parts(-int(req.get("parts", 0)))
	if int(req.get("supplies", 0)) > 0:
		InventoryManager.use_supplies(int(req["supplies"]))
	var helper := SurgicalDilemmas.helper(customer) if bool(req.get("staff", false)) else {}
	# A choice with no failure outcome can't go wrong.
	var ok := not ch.has("fail") or _rng.randf() < SurgicalDilemmas.odds(self, ch)
	var out: Dictionary = ch.get("success" if ok else "fail", ch.get("success", {}))
	if out.has("vitals"):
		vitals.apply_effects(out["vitals"])
	implant_quality *= float(out.get("perf", 1.0))
	dilemma_pay *= float(out.get("pay", 1.0))
	if out.has("heat"):
		FactionManager.add_heat(float(out["heat"]))
	if out.has("memory") and customer:
		PeopleManager.register(customer)  # first-time patients become people first
		MemoryManager.remember(customer.id, StringName(str(out["memory"])))
	if not helper.is_empty() and out.has("stress"):
		helper["stress"] = clampf(float(helper["stress"]) + float(out["stress"]), 0.0, 100.0)
	var text := str(out.get("text", ""))
	if not helper.is_empty():
		text = "%s comes in from the back. %s" % [helper["name"], text]
	if out.has("find"):
		var found := ImplantInstance.create(StringName(str(out["find"])), _rng.randf_range(55.0, 85.0), &"black_market")
		BlackMarketManager.roll_traits(found, _rng)
		InventoryManager.add_instance(found)
		text += " It's in your stash now."
	dilemma_notes.append("%s: %s" % [str(active_dilemma.get("title", "")), text])
	var r := {"success": ok, "text": text, "aborted": bool(out.get("abort", false)), "choice": str(ch.get("id", ""))}
	active_dilemma = {}
	dilemma_resolved.emit(r)
	vitals_changed.emit(vitals)
	if bool(r["aborted"]):
		_finish(false, &"aborted")
	# Otherwise the patient stays frozen until the result is dismissed
	# (DilemmaPanel calls resume()).
	return r


func _schedule_next_complication() -> void:
	_pending_complication_delay = _rng.randf_range(GameConfig.COMPLICATION_DELAY_RANGE.x, GameConfig.COMPLICATION_DELAY_RANGE.y)


func _apply_stage_outputs(stage: SurgeryStageData, data: Dictionary) -> void:
	match stage.type:
		&"anesthesia":
			vitals.sedated = true
		&"incision":
			vitals.set_wound_open(true)
		&"install_implant":
			implant_installed = true
			implant_alignment = float(data.get("alignment", 1.0)) * anchor_quality
		&"anchor_drill":
			anchor_quality = clampf(0.6 + 0.4 * float(data.get("anchor_quality", 1.0)), 0.3, 1.0)
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
	r.implant_id = implant_item.id if implant_item else &""
	r.implant_name = implant_item.display_name if implant_item else ""
	if implant and not implant.identified:
		# You find out what it was once it's in (or out).
		implant.identified = true
		r.implant_name = "%s (installed blind)" % r.implant_name
	r.install_difficulty = implant_item.install_difficulty if implant_item else 1
	r.neural_load_before = neural_load_before
	r.neural_load_after = neural_load_after
	r.black_market_implant = implant != null and implant.source == &"black_market"
	r.implant_pay_mult = (1.0 + (implant.trait_effect("pay") if implant else 0.0)) * dilemma_pay
	r.dilemma_notes = dilemma_notes.duplicate()
	r.implant_price = implant_item.price if implant_item else 0
	SurgeryScoring.apply_rewards(r, surgery, customer)
	if reason != &"aborted" or stage_index > 0:
		InventoryManager.wear_tools(surgery.get_required_tool_categories())
	last_result = r
	session_finished.emit(r)


func get_implant_performance() -> float:
	var base := implant_item.base_performance if implant_item else 1.0
	var unit := implant.get_quality() if implant else 1.0
	return clampf(base * unit * implant_quality * (0.5 * implant_alignment + 0.5 * calibration_quality), 0.0, 1.0)


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
	if Glossary.is_open():
		return  # reading the field guide never costs blood
	# A mistake that took a vital to zero ends it now: checking only after
	# tick() let a calm patient's recovery lift neural back above 0 first,
	# so the collapse the rules define never happened.
	var pre := vitals.get_failure_reason()
	if pre != &"":
		_finish(false, pre)
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
	var effects: Dictionary = GameConfig.MISTAKE_EFFECTS.get(kind, {}).duplicate()
	if effects.is_empty():
		push_warning("SurgeryManager: unknown mistake '%s'" % kind)
	# Skills / tools soften the consequences of mistakes.
	for key in ["bleed_rate", "blood"]:
		if effects.has(key):
			effects[key] = float(effects[key]) * maxf(0.1, mod_mult(&"surgery.bleed"))
	if effects.has("pain"):
		effects["pain"] = float(effects["pain"]) * maxf(0.1, mod_mult(&"surgery.pain"))
	if kind == &"wrong_connection" and effects.has("neural"):
		effects["neural"] = float(effects["neural"]) * maxf(0.1, mod_mult(&"neural.splice_penalty"))
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


## Effective precision: tool x skills/clinic, divided by install difficulty.
func get_tool_precision(category: StringName) -> float:
	var t := get_tool_for_category(category)
	var base := (t.precision * InventoryManager.tool_condition_factor(t.id)) if t else 1.0
	return maxf(0.3, base * mod_mult(&"surgery.precision") * Difficulty.assist() / get_difficulty_factor())


func get_tool_speed(category: StringName) -> float:
	var t := get_tool_for_category(category)
	return maxf(0.3, (t.speed if t else 1.0) * mod_mult(&"surgery.speed"))


func get_cooldown_total(action_id: StringName) -> float:
	var cfg: Dictionary = GameConfig.QUICK_ACTIONS.get(action_id, {})
	return float(cfg.get("cooldown", 5.0)) * maxf(0.3, mod_mult(&"quick.cooldown"))


# --- Quick actions -----------------------------------------------------------

func get_cooldown_remaining(action_id: StringName) -> float:
	return float(_cooldowns.get(action_id, 0.0))


func get_cooldown_ratio(action_id: StringName) -> float:
	return clampf(get_cooldown_remaining(action_id) / get_cooldown_total(action_id), 0.0, 1.0)


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
	if action_id == &"coag" and mod(&"coag.heal") > 0.0:
		effects["health"] = mod(&"coag.heal")
	vitals.apply_effects(effects)
	_cooldowns[action_id] = get_cooldown_total(action_id)
	quick_action_used.emit(action_id)
	if active_complication and active_complication.counter_action == action_id:
		complications_handled += 1
		var resolved := active_complication
		active_complication = null
		complication_resolved.emit(resolved, true)
		if _queued_complications > 0:
			_schedule_next_complication()
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
	var count := GameConfig.GUARANTEED_COMPLICATIONS
	if _rng.randf() < get_extra_complication_chance():
		count += 1
	count = mini(mini(count, windows.size()), Difficulty.max_complications())
	for i in count:
		var pick := windows[_rng.randi_range(0, windows.size() - 1)]
		windows.erase(pick)
		_planned_complication_stages.append(pick)


## Chance of a second complication from all risk sources.
func get_extra_complication_chance() -> float:
	var risk := customer.complication_risk if customer else 1.0
	if not diagnosis_correct:
		risk *= GameConfig.WRONG_DIAGNOSIS_RISK_MULT
	var chance := GameConfig.EXTRA_COMPLICATION_BASE_CHANCE * risk
	chance += NeuralLoad.complication_bonus(neural_load_after)
	chance += implant.get_extra_risk() if implant else (implant_item.failure_risk if implant_item else 0.0)
	var tool_risk := 1.0
	for cat in surgery.get_required_tool_categories():
		var t := get_tool_for_category(cat)
		if t:
			tool_risk *= t.risk
	chance *= tool_risk * maxf(0.1, mod_mult(&"complication.chance"))
	return clampf(chance, 0.0, 0.95)


func _tick_complications(delta: float) -> void:
	if active_complication:
		complication_time_left -= delta
		if complication_time_left <= 0.0:
			var failed := active_complication
			active_complication = null
			vitals.apply_effects(failed.failure_effects)
			complication_resolved.emit(failed, false)
			if _queued_complications > 0:
				_schedule_next_complication()
		return
	if _pending_complication_delay >= 0.0:
		_pending_complication_delay -= delta
		if _pending_complication_delay < 0.0:
			_start_complication()


func _start_complication() -> void:
	var pool: Array[ComplicationData] = []
	for c: ComplicationData in complications.values():
		if not _used_complication_ids.has(c.id) and c.is_eligible(customer, neural_load_after):
			pool.append(c)
			# Implant-specific complications are twice as likely.
			if implant_item and implant_item.complication_ids.has(c.id):
				pool.append(c)
	if pool.is_empty():
		for c: ComplicationData in complications.values():
			if c.is_eligible(customer, neural_load_after):
				pool.append(c)
	if not pool.is_empty():
		_queued_complications = maxi(_queued_complications - 1, 0)
		_begin_complication(pool[_rng.randi_range(0, pool.size() - 1)])


func _begin_complication(c: ComplicationData) -> void:
	active_complication = c
	_used_complication_ids.append(c.id)
	complication_time_left = c.time_limit * _complication_time_mult()
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
	return clampf(complication_time_left / (active_complication.time_limit * _complication_time_mult()), 0.0, 1.0)


## Skills/clinic modifier x the early-game grace period.
func _complication_time_mult() -> float:
	return maxf(0.4, mod_mult(&"complication.time")) * Difficulty.complication_time()
