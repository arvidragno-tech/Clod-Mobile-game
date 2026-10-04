extends Node
## Who walks in: procedural customers, recurring story characters,
## returning customers and referrals. Also keeps the customer history and
## hidden medical conditions.

var characters: Dictionary = {}  # StringName -> Dictionary (authored data)
var archetypes: Array = []
var names: Dictionary = {}
var dialogue: Dictionary = {}
var conditions: Dictionary = {}  # StringName -> Dictionary

var current_customer: CustomerData = null
## Returning customers / referrals: Array of {"customer": Dictionary, "due_op": int}
var queue: Array[Dictionary] = []
## Array of {"uid", "name", "faction", "outcome", "grade", "op", "visits", "regular"}
var history: Array[Dictionary] = []

var _arrival_timer: Timer
var _rng := RandomNumberGenerator.new()
var generator: CustomerGenerator
## Kept for Step 1 compatibility: authored characters by id.
var templates: Dictionary:
	get:
		var out := {}
		for id: StringName in characters:
			out[id] = CustomerData.from_dict(characters[id])
		return out


func _ready() -> void:
	_rng.randomize()
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_CHARACTERS, "characters"):
		characters[StringName(str(entry["id"]))] = entry
	archetypes = DataLoader.load_entries(GameConfig.DATA_ARCHETYPES, "archetypes")
	var n: Variant = DataLoader.load_json(GameConfig.DATA_NAMES)
	names = n if typeof(n) == TYPE_DICTIONARY else {}
	var dl: Variant = DataLoader.load_json(GameConfig.DATA_DIALOGUE)
	dialogue = dl if typeof(dl) == TYPE_DICTIONARY else {}
	for c: Variant in DataLoader.load_entries(GameConfig.DATA_CONDITIONS, "conditions"):
		conditions[StringName(str(c["id"]))] = c
	generator = CustomerGenerator.new(_rng)
	_arrival_timer = Timer.new()
	_arrival_timer.one_shot = true
	_arrival_timer.timeout.connect(_on_arrival_timer_timeout)
	add_child(_arrival_timer)


func reset_state() -> void:
	_arrival_timer.stop()
	current_customer = null
	queue.clear()
	history.clear()


func get_condition(id: StringName) -> Dictionary:
	return conditions.get(id, {})


func has_customer() -> bool:
	return current_customer != null


func is_customer_pending() -> bool:
	return not _arrival_timer.is_stopped()


## Authored character as a fresh CustomerData.
func get_customer(id: StringName) -> CustomerData:
	if not characters.has(id):
		return null
	var c := CustomerData.from_dict(characters[id])
	_finalize_character(c)
	return c


func _finalize_character(c: CustomerData) -> void:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item:
		c.requested_surgery_id = item.install_surgery_id
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	if surgery and not surgery.has_diagnosis(c.true_diagnosis_id):
		c.true_diagnosis_id = StringName(str(surgery.diagnosis_options[0]["id"]))
	if c.scan_findings.is_empty() or (surgery and not c.scan_findings.has(String(surgery.scan_region))):
		generator._build_findings(c)
	if c.medical_history.is_empty():
		generator._build_history(c)


func request_next_customer(delay: float = GameConfig.CUSTOMER_ARRIVAL_DELAY_SEC) -> void:
	if has_customer() or is_customer_pending():
		return
	if delay <= 0.0:
		_on_arrival_timer_timeout()
	else:
		_arrival_timer.start(delay)


func dismiss_current() -> void:
	if current_customer == null:
		return
	var leaving := current_customer
	current_customer = null
	EventBus.customer_left.emit(leaving)


func _on_arrival_timer_timeout() -> void:
	current_customer = _next_customer()
	if current_customer:
		if current_customer.character_id != &"":
			StoryManager.meet(current_customer.character_id)
		EventBus.customer_arrived.emit(current_customer)


func _next_customer() -> CustomerData:
	var op := EventManager.operations
	for i in queue.size():
		if int(queue[i]["due_op"]) <= op:
			var entry: Dictionary = queue[i]
			queue.remove_at(i)
			return CustomerData.from_save_dict(entry["customer"])
	# Occasionally a recurring regular from the old days drops by.
	if _rng.randf() < 0.12:
		var regulars: Array[StringName] = []
		for id: StringName in characters:
			if str(characters[id].get("role", "")) == "regular":
				regulars.append(id)
		if not regulars.is_empty():
			return get_customer(regulars[_rng.randi_range(0, regulars.size() - 1)])
	return generator.generate()


## Emergency walk-in (event): replaces whoever is waiting.
func spawn_emergency() -> CustomerData:
	var cat: StringName = [&"dermal", &"arms", &"internal"][_rng.randi_range(0, 2)]
	var c := generator.generate({"archetype": "gang_member", "faction": "street_gangs", "category": cat})
	c.is_emergency = true
	c.pay_multiplier *= 1.8
	c.bleed_multiplier *= 1.4
	c.complication_risk *= 1.3
	c.dialogue = "He's bleeding through a rag and his chrome is sparking. No time to talk."
	_replace_current(c)
	return c


func spawn_character(id: StringName) -> CustomerData:
	var c := get_customer(id)
	if c:
		_replace_current(c)
		StoryManager.meet(id)
	return c


## Test / debug hook: puts a specific customer at the door.
func debug_set_customer(c: CustomerData) -> void:
	_replace_current(c)


func _replace_current(c: CustomerData) -> void:
	_arrival_timer.stop()
	if current_customer and current_customer != c:
		queue.push_front({"customer": current_customer.to_save_dict(), "due_op": 0})
	current_customer = c
	EventBus.customer_arrived.emit(c)


## Rolls whether scanning `region` reveals hidden conditions there.
func try_reveal_conditions(customer: CustomerData, region: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for cid in customer.hidden_conditions:
		var cond := get_condition(cid)
		if customer.revealed_conditions.has(cid) or StringName(str(cond.get("scan_region", ""))) != region:
			continue
		var chance := 0.35 + ModifierManager.value(&"diagnosis.reveal") - float(cond.get("reveal_difficulty", 0.4)) * 0.4
		if _rng.randf() < chance:
			customer.revealed_conditions.append(cid)
			out.append(cid)
	return out


## Customer consequences after an operation.
func record_outcome(c: CustomerData, result: SurgeryResult) -> Dictionary:
	var notes := {"referral": false, "returning": false, "regular": false, "post_op": false}
	c.visits += 1
	var prior := 0
	for h in history:
		if str(h["uid"]) == String(c.id):
			prior = maxi(prior, int(h.get("visits", 0)))
	var visits := maxi(c.visits, prior + 1)
	var regular := visits >= GameConfig.REGULAR_VISITS
	history.append({"uid": String(c.id), "name": c.get_display_title(), "faction": String(c.faction_id), "outcome": "success" if result.success else String(result.failure_reason),
		"grade": result.grade, "op": EventManager.operations, "visits": visits, "regular": regular, "character": String(c.character_id)})
	if history.size() > 60:
		history = history.slice(history.size() - 60)
	notes["regular"] = regular
	if result.success and _rng.randf() < get_post_op_risk(c, result.grade):
		# The patient comes back with a failing wound: handled as a story event.
		EventManager.queue_event(&"post_op_return")
		notes["post_op"] = true
		return notes
	if result.success and result.grade in ["S", "A", "B"]:
		if _rng.randf() < GameConfig.REFERRAL_CHANCE:
			var friend := generator.generate({"faction": String(c.faction_id), "referred_by": c.display_name})
			queue.append({"customer": friend.to_save_dict(), "due_op": EventManager.operations + _rng.randi_range(1, 3)})
			notes["referral"] = true
		if c.character_id == &"" and _rng.randf() < GameConfig.RETURN_CHANCE + (0.2 if regular else 0.0):
			var again := CustomerData.from_save_dict(c.to_save_dict())
			again.existing_cyberware.append(c.requested_cyberware_id)
			again.revealed_conditions.clear()
			var arch := _get_archetype(again.archetype_id)
			if not arch.is_empty():
				generator._roll_request(again, arch, {})
				generator._roll_diagnosis(again)
				again.scan_findings.clear()
				generator._build_findings(again)
			again.visits = visits
			again.dialogue = str(dialogue.get("returning", ["Back again."])[0])
			if regular:
				again.pay_multiplier *= 1.0 + GameConfig.REGULAR_PAY_BONUS
			queue.append({"customer": again.to_save_dict(), "due_op": EventManager.operations + _rng.randi_range(GameConfig.RETURN_DELAY_OPS.x, GameConfig.RETURN_DELAY_OPS.y)})
			notes["returning"] = true
	elif not result.success and _rng.randf() < GameConfig.COMPLAINT_CHANCE:
		EventManager.queue_event(&"angry_relative")
	return notes


## Chance that a successful operation goes bad after the patient leaves.
func get_post_op_risk(c: CustomerData, grade: String) -> float:
	var base := float(GameConfig.POST_OP_RISK_BY_GRADE.get(grade, 0.0))
	return clampf(base + c.post_op_risk + ModifierManager.value(&"post_op.risk"), 0.0, 0.9)


func _get_archetype(id: StringName) -> Dictionary:
	for a: Dictionary in archetypes:
		if StringName(str(a["id"])) == id:
			return a
	return {}


func get_save_data() -> Dictionary:
	return {
		"current": current_customer.to_save_dict() if current_customer else {},
		"queue": queue,
		"history": history,
	}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var cur: Variant = data.get("current", data.get("current_customer", null))
	if typeof(cur) == TYPE_DICTIONARY and not cur.is_empty():
		current_customer = CustomerData.from_save_dict(cur)
	elif typeof(cur) == TYPE_STRING and characters.has(StringName(cur)):
		current_customer = get_customer(StringName(cur))  # v1 saves stored an id
	for q: Variant in data.get("queue", []):
		if typeof(q) == TYPE_DICTIONARY:
			queue.append(q)
	for h: Variant in data.get("history", []):
		if typeof(h) == TYPE_DICTIONARY:
			history.append(h)
