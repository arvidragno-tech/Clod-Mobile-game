extends Node
## Random and story events between operations. Events are data
## (data/events.json): conditions decide eligibility, each choice has
## requirements and outcomes. Some outcomes are timed modifiers that last
## for the next N operations.

var events: Dictionary = {}  # StringName -> Dictionary
var order: Array[StringName] = []
## event id -> {"count": int, "last_op": int}
var history: Dictionary = {}
## Array of {"key": String, "value": float, "ops": int, "source": String}
var temp_modifiers: Array[Dictionary] = []
var pending_event: StringName = &""
## Events that came while another was waiting, oldest first. Each becomes
## pending in turn as the one before it is answered.
var waiting: Array[StringName] = []
var operations: int = 0
var last_result_text: String = ""
## Random incidents today (capped by time.json pacing.max_incidents_per_day,
## so a day has room between them). Story and scheduled events don't count.
var incident_day: int = -1
var incidents_today: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for e: Variant in DataLoader.load_entries(GameConfig.DATA_EVENTS, "events"):
		var id := StringName(str(e["id"]))
		events[id] = e
		order.append(id)
	reset_state()


func reset_state() -> void:
	history.clear()
	temp_modifiers.clear()
	pending_event = &""
	waiting.clear()
	operations = 0
	incident_day = -1
	incidents_today = 0
	EventBus.modifiers_changed.emit()


func get_event(id: StringName) -> Dictionary:
	return events.get(id, {})


func has_pending() -> bool:
	return pending_event != &""


## Queues an event. If another is already waiting for an answer, this one
## waits behind it (first come, first answered) instead of replacing it. A
## one-time event that is already waiting is not queued twice.
func queue_event(id: StringName) -> void:
	if not events.has(id):
		return
	if bool(get_event(id).get("once", false)) and (pending_event == id or waiting.has(id)):
		return
	if pending_event == &"":
		pending_event = id
	else:
		waiting.append(id)
	EventBus.event_queued.emit(id)


## The next waiting event, or "".
func _next_waiting() -> StringName:
	return waiting.pop_front() if not waiting.is_empty() else &""


## Called once per finished operation.
func on_operation_completed() -> void:
	operations += 1
	var changed := false
	for m in temp_modifiers:
		m["ops"] = int(m["ops"]) - 1
		changed = true
	temp_modifiers = temp_modifiers.filter(func(m: Dictionary) -> bool: return int(m["ops"]) > 0)
	if changed:
		EventBus.modifiers_changed.emit()


## Maybe queue a random event (if none is pending).
func roll_random_event(force: bool = false) -> StringName:
	if has_pending():
		return pending_event
	if not force and (not Difficulty.events_allowed() or _rng.randf() > GameConfig.EVENT_CHANCE):
		return &""
	if incident_day != BusinessManager.day:
		incident_day = BusinessManager.day
		incidents_today = 0
	if not force and incidents_today >= int(TimeManager.data.get("pacing", {}).get("max_incidents_per_day", 99)):
		return &""
	var id := pick_event()
	if id != &"":
		incidents_today += 1
		queue_event(id)
	return id


func pick_event() -> StringName:
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for id in order:
		var e: Dictionary = events[id]
		var w := float(e.get("weight", 0)) * WorldManager.event_weight(id) * TimeManager.event_weight(id) * WorldEventManager.event_weight(id)
		if w > 0.0 and is_eligible(id):
			pool.append(id)
			weights.append(w)
	if pool.is_empty():
		return &""
	var total := 0.0
	for w in weights:
		total += w
	var r := _rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


func is_eligible(id: StringName) -> bool:
	var e := get_event(id)
	if e.is_empty():
		return false
	var h: Dictionary = history.get(id, {})
	if bool(e.get("once", false)) and int(h.get("count", 0)) > 0:
		return false
	if h.has("last_op") and operations - int(h["last_op"]) < int(e.get("cooldown", 0)):
		return false
	return conditions_met(e.get("conditions", {}))


## Shared condition checker (events and rumors).
func conditions_met(c: Dictionary) -> bool:
	if c.has("min_rep") and ReputationManager.reputation < int(c["min_rep"]):
		return false
	if c.has("max_rep") and ReputationManager.reputation > int(c["max_rep"]):
		return false
	if c.has("min_ops") and operations < int(c["min_ops"]):
		return false
	if c.has("min_heat") and FactionManager.heat < float(c["min_heat"]):
		return false
	if c.has("min_level") and ProgressionManager.level < int(c["min_level"]):
		return false
	if c.has("min_tier") and ClinicManager.tier < int(c["min_tier"]):
		return false
	if c.has("district") and WorldManager.current_district_id() != StringName(str(c["district"])):
		return false
	if c.has("min_day") and BusinessManager.day < int(c["min_day"]):
		return false
	if c.has("act") and StoryManager.act < int(c["act"]):
		return false
	if c.has("flag") and not StoryManager.has_flag(StringName(str(c["flag"]))):
		return false
	if c.has("not_flag") and StoryManager.has_flag(StringName(str(c["not_flag"]))):
		return false
	if c.has("min_stock") and InventoryManager.get_instances().size() < int(c["min_stock"]):
		return false
	var fac: Dictionary = c.get("faction", {})
	for f: Variant in fac:
		var r := FactionManager.get_rep(StringName(str(f)))
		var rng: Array = fac[f]
		if r < int(rng[0]) or r > int(rng[1]):
			return false
	# The story's own conditions (trust, reputation types, flags...).
	if c.has("story") and not StoryManager.cond(c["story"]):
		return false
	return true


## "" if the choice can be taken, otherwise why not.
func get_choice_block_reason(choice: Dictionary) -> String:
	var req: Dictionary = choice.get("requires", {})
	if req.has("money") and not EconomyManager.can_afford(int(req["money"])):
		return "Need %s" % EconomyManager.format_money(int(req["money"]))
	if req.has("parts") and InventoryManager.parts < int(req["parts"]):
		return "Need %d parts" % int(req["parts"])
	if req.has("supplies") and InventoryManager.supplies < int(req["supplies"]):
		return "Need %d supplies" % int(req["supplies"])
	if req.has("tokens") and InventoryManager.tokens < int(req["tokens"]):
		return "Need %d token" % int(req["tokens"])
	if req.has("flag") and not StoryManager.has_flag(StringName(str(req["flag"]))):
		return "Unavailable"
	return ""


## Applies a choice of the pending event; returns the result text.
## Records why standing changes in here (ChangeLog standing history).
func resolve(choice_index: int) -> String:
	ChangeLog.push_cause("Event: %s" % str(get_event(pending_event).get("title", String(pending_event).capitalize())))
	var r: String = _resolve_impl(choice_index)
	ChangeLog.pop_cause()
	return r


func _resolve_impl(choice_index: int) -> String:
	var id := pending_event
	var e := get_event(id)
	var choices: Array = e.get("choices", [])
	if e.is_empty() or choice_index < 0 or choice_index >= choices.size():
		return ""
	var choice: Dictionary = choices[choice_index]
	if get_choice_block_reason(choice) != "":
		return ""
	pending_event = &""
	var h: Dictionary = history.get(id, {"count": 0})
	h["count"] = int(h.get("count", 0)) + 1
	h["last_op"] = operations
	history[id] = h
	# The next event in line comes up; anything this answer queues waits
	# behind it.
	pending_event = _next_waiting()
	if e.has("character"):
		StoryManager.meet(StringName(str(e["character"])))
	var text := apply_outcomes(choice.get("outcomes", {}))
	last_result_text = text
	StoryManager.update_rumors()
	EventBus.event_resolved.emit(id, text)
	return text


func apply_outcomes(o: Dictionary) -> String:
	if o.has("risk"):
		var risk: Dictionary = o["risk"]
		var branch: Dictionary = risk["success"] if _rng.randf() < float(risk.get("chance", 0.5)) else risk["fail"]
		return apply_outcomes(branch)
	if o.has("money"):
		var m := int(o["money"])
		if m >= 0:
			EconomyManager.add_money(m, &"events")
		else:
			EconomyManager.spend(mini(-m, EconomyManager.money), &"events")
	if o.has("reputation"):
		ReputationManager.change(int(o["reputation"]))
	var fac: Dictionary = o.get("faction", {})
	for f: Variant in fac:
		FactionManager.change_by_choice(StringName(str(f)), int(fac[f]))
	if o.has("heat"):
		FactionManager.add_heat(float(o["heat"]))
	if o.has("xp"):
		ProgressionManager.add_xp(int(o["xp"]))
	if o.has("supplies"):
		InventoryManager.add_supplies(int(o["supplies"]))
	if o.has("parts"):
		InventoryManager.add_parts(int(o["parts"]))
	if o.has("tokens"):
		InventoryManager.add_tokens(int(o["tokens"]))
	if o.has("skill_points"):
		SkillManager.add_points(int(o["skill_points"]))
	if o.has("flag"):
		StoryManager.set_flag(StringName(str(o["flag"])))
	if o.has("unflag"):
		StoryManager.set_flag(StringName(str(o["unflag"])), false)
	if o.has("rumor"):
		StoryManager.unlock_rumor(StringName(str(o["rumor"])))
	if o.has("item"):
		_grant_item(o["item"])
	if bool(o.get("lose_bm_item", false)):
		InventoryManager.remove_first_where(func(i: ImplantInstance) -> bool: return i.source == &"black_market")
	if bool(o.get("lose_stock_item", false)):
		InventoryManager.remove_first_where(func(_i: ImplantInstance) -> bool: return true)
	if o.has("modifier"):
		var m: Dictionary = o["modifier"]
		temp_modifiers.append({"key": str(m["key"]), "value": float(m["value"]), "ops": int(m.get("ops", 1)), "source": "event"})
		EventBus.modifiers_changed.emit()
	# Story effects (paths, flags, delayed consequences, the Wall, cutscenes):
	# the same vocabulary as conversations (StoryManager.apply_effects).
	if o.has("effects"):
		StoryManager.apply_effects(o["effects"], StringName(str(o.get("character", ""))))
	if o.has("customer"):
		var c := str(o["customer"])
		if c == "emergency":
			CustomerManager.spawn_emergency()
		else:
			CustomerManager.spawn_character(StringName(c))
	return str(o.get("text", ""))


func _grant_item(spec: Dictionary) -> void:
	var cond: Array = spec.get("condition", [80, 100])
	var condition := _rng.randf_range(float(cond[0]), float(cond[1]))
	var item_id := StringName(str(spec.get("id", "")))
	if item_id == &"":
		var pool: Array[CyberwareData] = []
		for c: CyberwareData in CyberwareManager.catalog.values():
			if bool(spec.get("black_market", false)):
				if c.black_market:
					pool.append(c)
			elif not c.black_market and c.tier == int(spec.get("random_tier", 1)):
				pool.append(c)
		if pool.is_empty():
			return
		item_id = pool[_rng.randi_range(0, pool.size() - 1)].id
	var inst := ImplantInstance.create(item_id, condition, &"black_market" if bool(spec.get("black_market", false)) else &"event")
	BlackMarketManager.roll_traits(inst, _rng)
	InventoryManager.add_instance(inst)


func get_temp_modifiers() -> Dictionary:
	var out := {}
	for m in temp_modifiers:
		out[m["key"]] = float(out.get(m["key"], 0.0)) + float(m["value"])
	return out


func get_save_data() -> Dictionary:
	var h := {}
	for k: StringName in history:
		h[String(k)] = history[k]
	return {"history": h, "temp_modifiers": temp_modifiers, "pending": String(pending_event),
		"waiting": waiting.map(func(w: StringName) -> String: return String(w)), "operations": operations,
		"incident_day": incident_day, "incidents_today": incidents_today}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var h: Dictionary = data.get("history", {})
	for k: Variant in h:
		history[StringName(str(k))] = h[k]
	for m: Variant in data.get("temp_modifiers", []):
		if typeof(m) == TYPE_DICTIONARY:
			temp_modifiers.append(m)
	var p := StringName(str(data.get("pending", "")))
	for w: Variant in data.get("waiting", []):
		if events.has(StringName(str(w))):
			waiting.append(StringName(str(w)))
	pending_event = p if events.has(p) else _next_waiting()
	operations = int(data.get("operations", 0))
	incident_day = int(data.get("incident_day", -1))
	incidents_today = int(data.get("incidents_today", 0))
	EventBus.modifiers_changed.emit()
