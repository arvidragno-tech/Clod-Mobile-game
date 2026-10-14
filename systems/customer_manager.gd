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

## THE DAY'S SCHEDULE (data/time.json "pacing"): how many people come to the
## door today (jobs a day + a few spare, walk-ins on the bench included), the
## visit after which a story case may replace a routine patient, and how long
## the room stays quiet after each kind of case.
var schedule_day: int = -1
var visits_today: int = 0
var story_slot: int = 1
## What the last patient was: &"routine", &"character" (someone you know:
## returning, referred, a regular) or &"story" (a story case). Sets the
## breather before the next knock.
var last_kind: StringName = &""
## No walk-ins sit down before this clock minute (the quiet after a story case).
var quiet_until: int = -1
## Test harnesses set 0 so the next patient knocks at once.
var breather_scale: float = 1.0
## Emergencies: real seconds before an untreated patient crashes, then dies.
## Counts down wherever you are (clinic, file, plan) but not during surgery,
## dialogs or pauses; Settings > Emergency countdown scales or disables it.
signal emergency_crashed(name: String, died: bool)
const EMERGENCY_SECONDS := 75.0
const CRASH_SECONDS := 45.0
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
	EventBus.day_started.connect(func(_d: int) -> void: _ensure_schedule())


func reset_state() -> void:
	_arrival_timer.stop()
	current_customer = null
	queue.clear()
	history.clear()
	schedule_day = -1
	visits_today = 0
	story_slot = 1
	last_kind = &""
	quiet_until = -1


# --- The day's schedule ----------------------------------------------------------------------

func pacing() -> Dictionary:
	return TimeManager.data.get("pacing", {})


## People expected at the door today (jobs a day + spare).
func visit_budget() -> int:
	return BusinessManager.capacity() + int(pacing().get("spare_visits", 2))


func visits_left() -> int:
	_ensure_schedule()
	return maxi(0, visit_budget() - visits_today)


## A new business day gets a fresh schedule. Old saves (no schedule yet)
## count today's finished jobs as visits already used.
func _ensure_schedule() -> void:
	if schedule_day == BusinessManager.day:
		return
	var fresh := schedule_day >= 0 or BusinessManager.jobs_today == 0
	schedule_day = BusinessManager.day
	visits_today = 0 if fresh else BusinessManager.jobs_today
	quiet_until = -1
	# A story case never opens the day: a routine patient or two come first.
	story_slot = _rng.randi_range(1, maxi(1, visit_budget() - 2))


## Someone took a place in today's schedule (at the door or on the bench).
func count_visit() -> void:
	_ensure_schedule()
	visits_today += 1


## Someone you sent for or who is due back (queue) still comes on a quiet day.
func has_due_queue() -> bool:
	for q in queue:
		if int(q.get("due_day", 0)) <= BusinessManager.day and int(q["due_op"]) <= EventManager.operations:
			return true
	return false


## Nobody else is expected today: no visits left, nobody due, nobody waiting.
func day_is_quiet() -> bool:
	return visits_left() <= 0 and not has_customer() and not has_due_queue() and ClinicLifeManager.waiting.is_empty()


## Walk-ins may sit down (the schedule has room and it isn't a quiet stretch).
func walk_ins_allowed() -> bool:
	return visits_left() > 0 and TimeManager.minute >= quiet_until


## What kind of visit this was: story case, someone you know, or routine.
static func kind_of(c: CustomerData) -> StringName:
	if c == null:
		return &"routine"
	if c.case_id != &"":
		return &"story"
	if c.character_id != &"" or c.visits > 0 or c.referred_by != "":
		return &"character"
	return &"routine"


## Real seconds before the next knock: longer after a case that mattered.
func breather() -> float:
	var b: Dictionary = pacing().get("breather_sec", {})
	var key := String(last_kind) if last_kind != &"" else "first"
	return float(b.get(key, GameConfig.CUSTOMER_ARRIVAL_DELAY_SEC)) * breather_scale


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
	# Story cast look the same everywhere, including after story events.
	if CharacterManager.has_character(c.id):
		c.appearance = CharacterManager.appearance(c.id).duplicate(true)
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


## delay < 0: the schedule's breather (longer after a story case).
func request_next_customer(delay: float = -1.0) -> void:
	if has_customer() or is_customer_pending():
		return
	# Nobody new after closing time (the night's books come first).
	if BusinessManager.is_day_full():
		return
	# Today's schedule is spent: only people already on the bench or due back.
	if visits_left() <= 0 and ClinicLifeManager.waiting.is_empty() and not has_due_queue():
		return
	if delay < 0.0:
		delay = breather()
	# Nobody opens the door while you're out in the city.
	if LocationManager.is_away():
		return
	# CLOSE DOORS: no walk-ins until you open again.
	if not BusinessManager.doors_open:
		return
	if delay <= 0.0:
		_on_arrival_timer_timeout()
	else:
		_arrival_timer.start(delay)


func _notification(what: int) -> void:
	if not Settings.pause_focus_loss:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_arrivals_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and not DialogueManager.is_active():
		set_arrivals_paused(false)


## Going out: whoever was about to knock waits until you're back.
func stop_arrivals() -> void:
	if _arrival_timer:
		_arrival_timer.stop()


## Pause during dialogue / focus loss: nobody walks in meanwhile.
func set_arrivals_paused(on: bool) -> void:
	if _arrival_timer:
		_arrival_timer.paused = on


func dismiss_current() -> void:
	if current_customer == null:
		return
	var leaving := current_customer
	last_kind = kind_of(leaving)
	current_customer = null
	EventBus.customer_left.emit(leaving)


func _on_arrival_timer_timeout() -> void:
	if LocationManager.is_away() or not BusinessManager.doors_open:
		return
	# Whoever has been waiting on the bench goes first.
	var seated := ClinicLifeManager.take_next()
	current_customer = seated if seated else next_visit()
	if current_customer:
		if seated:
			TimeManager.advance(2)
		else:
			TimeManager.on_customer_arrived(current_customer.is_emergency)
		if current_customer.character_id != &"":
			StoryManager.meet(current_customer.character_id)
		EventBus.customer_arrived.emit(current_customer)


## The next person at the door, counted against today's schedule.
func next_visit() -> CustomerData:
	count_visit()
	return _next_customer()


func _next_customer() -> CustomerData:
	var op := EventManager.operations
	if op == 0 and TutorialManager.is_active():
		return tutorial_customer()
	for i in queue.size():
		if int(queue[i].get("due_day", 0)) > BusinessManager.day:
			continue
		if int(queue[i]["due_op"]) <= op:
			var entry: Dictionary = queue[i]
			queue.remove_at(i)
			return CustomerData.from_save_dict(entry["customer"])
	# A story case takes a routine patient's place (one a day at most).
	if visits_today >= story_slot and op > 0:
		var sc := StoryManager.due_case()
		if not sc.is_empty():
			var cc := make_case_customer(sc)
			if cc:
				return cc
	# People you've met before come back on their own schedule, changed.
	var due := PeopleManager.due_people()
	if not due.is_empty():
		var back := PeopleManager.make_customer(due[_rng.randi() % due.size()])
		if back:
			return back
	# Occasionally a recurring regular from the old days drops by.
	if _rng.randf() < 0.12:
		var regulars: Array[StringName] = []
		for id: StringName in characters:
			if str(characters[id].get("role", "")) == "regular":
				regulars.append(id)
		if not regulars.is_empty():
			return get_customer(regulars[_rng.randi_range(0, regulars.size() - 1)])
	return generator.generate()


## A story case (data/cases.json) as a patient: generated like anyone else
## (so they look and pay like the street), then given the case's identity,
## words, history and the clue the scan can find. Someone you've treated
## before keeps their face.
func make_case_customer(sc: Dictionary) -> CustomerData:
	var p: Dictionary = sc.get("patient", {})
	var ctx := {}
	for k: String in ["archetype", "faction", "category"]:
		if p.has(k):
			ctx[k] = str(p[k])
	var c := generator.generate(ctx)
	if c == null:
		return null
	c.id = StringName("case_%s" % str(p.get("id", sc["id"])))
	c.case_id = StringName(str(sc["id"]))
	c.display_name = str(p.get("name", c.display_name))
	c.alias = str(p.get("alias", ""))
	c.age = int(p.get("age", c.age))
	c.occupation = str(p.get("occupation", c.occupation))
	c.patience = maxi(c.patience, 70)
	var person := PeopleManager.get_person(c.id)
	if not person.is_empty():
		c.visits = int(person.get("visits", 0))
		if not (person.get("appearance", {}) as Dictionary).is_empty():
			c.appearance = (person["appearance"] as Dictionary).duplicate(true)
	c.dialogue = StoryManager.case_text(sc, "line", c.dialogue)
	var hist := StoryManager.case_text(sc, "history", "")
	if hist != "":
		c.medical_history.push_front(hist)
	var clue := StoryManager.case_text(sc, "clue", "")
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	if clue != "" and surgery:
		var region := String(surgery.scan_region)
		c.scan_findings[region] = ("%s %s" % [str(c.scan_findings.get(region, "")), clue]).strip_edges()
	StoryManager.case_arrived(sc)
	return c


## The first patient: Mara, a simple NX-1 neural job with no surprises.
func tutorial_customer() -> CustomerData:
	var c := get_customer(&"mara_quill")
	if c:
		for cid in c.hidden_conditions.duplicate():
			c.hidden_conditions.erase(cid)
		c.patience = maxi(c.patience, 90)
	return c


## Emergency walk-in (event): replaces whoever is waiting.
func spawn_emergency() -> CustomerData:
	var cat: StringName = [&"dermal", &"arms", &"internal"][_rng.randi_range(0, 2)]
	var c := generator.generate({"archetype": "gang_member", "faction": "street_gangs", "category": cat})
	c.is_emergency = true
	c.pay_multiplier *= 1.8
	c.bleed_multiplier *= 1.4
	c.complication_risk *= 1.3
	c.dialogue = "They're bleeding through a rag and their chrome is sparking. No time to talk."
	generator.roll_budget(c)
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
		"grade": result.grade, "op": EventManager.operations, "surgery": result.surgery_name, "implant": result.implant_name, "visits": visits, "regular": regular, "character": String(c.character_id)})
	if history.size() > 60:
		history = history.slice(history.size() - 60)
	notes["regular"] = regular
	var outcome := "success" if result.success else ("death" if result.failure_reason == &"flatline" else ("stopped" if result.failure_reason == &"aborted" else "failed"))
	PeopleManager.after_visit(c, outcome, result.pay)
	var person := PeopleManager.get_person(c.id)
	notes["returning"] = int(person.get("next_day", -1)) >= 0
	if result.success and _rng.randf() < get_post_op_risk(c, result.grade):
		# The patient comes back with a failing wound: handled as a story event.
		EventManager.queue_event(&"post_op_return")
		notes["post_op"] = true
		return notes
	if result.success and result.grade in ["S", "A", "B"]:
		# Word of mouth: people who like you send friends.
		var chance := GameConfig.REFERRAL_CHANCE + float(person.get("rel", 0)) / 300.0
		if PeopleManager.rel_state(c.id) != "hostile" and _rng.randf() < chance:
			var friend := PeopleManager.referral(c)
			queue.append({"customer": friend.to_save_dict(), "due_op": EventManager.operations + _rng.randi_range(1, 3)})
			notes["referral"] = true
	elif not result.success and _rng.randf() < GameConfig.COMPLAINT_CHANCE:
		EventManager.queue_event(&"angry_relative")
	return notes


## Chance that a successful operation goes bad after the patient leaves.
## Earlier operations on this customer (newest first) from the clinic log.
func get_previous_operations(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c == null:
		return out
	for i in range(history.size() - 1, -1, -1):
		var h: Dictionary = history[i]
		if str(h.get("uid", "")) == String(c.id) or (c.character_id != &"" and str(h.get("character", "")) == String(c.character_id)):
			out.append(h)
	return out


func get_post_op_risk(c: CustomerData, grade: String) -> float:
	if not Difficulty.hidden_conditions_allowed() and c.hidden_conditions.is_empty():
		return 0.0  # no post-op surprises while learning
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
		"schedule": {"day": schedule_day, "visits": visits_today, "story_slot": story_slot, "last_kind": String(last_kind), "quiet_until": quiet_until},
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
	# Saves from before 3.11 have no schedule: one is made for today on demand.
	var sch: Variant = data.get("schedule", {})
	if sch is Dictionary and not (sch as Dictionary).is_empty():
		schedule_day = int(sch.get("day", -1))
		visits_today = int(sch.get("visits", 0))
		story_slot = int(sch.get("story_slot", 1))
		last_kind = StringName(str(sch.get("last_kind", "")))
		quiet_until = int(sch.get("quiet_until", -1))



func emergency_total(c: CustomerData) -> float:
	return (CRASH_SECONDS if c.crashes > 0 else EMERGENCY_SECONDS) * maxf(0.1, Settings.time_pressure_mult())


## Seconds left for the patient at the door (stored on them, so it survives
## screen changes and saves).
func emergency_seconds_left() -> float:
	var c := current_customer
	if c == null or not c.is_emergency:
		return -1.0
	if c.emergency_deadline < 0:
		c.emergency_deadline = int(emergency_total(c) * 1000.0)
	return c.emergency_deadline / 1000.0


func _process(delta: float) -> void:
	var c := current_customer
	if c == null or not c.is_emergency or not GameManager.is_running or Settings.time_pressure_mult() <= 0.0:
		return
	if SurgeryManager.is_active or UIManager.has_modal() or UIManager.is_transitioning() or UIManager.is_reading() or (_arrival_timer and _arrival_timer.paused):
		return
	emergency_seconds_left()
	c.emergency_deadline -= int(delta * 1000.0)
	if c.emergency_deadline > 0:
		return
	var who := c.display_name
	var died := GameManager.emergency_crash()
	if not died:
		c.emergency_deadline = int(emergency_total(c) * 1000.0)
	AudioManager.play_sfx(&"failure" if died else &"warning", 0.0)
	CommsManager.notify(("%s died waiting." % who) if died else ("%s is crashing: neural stability dropping, bleeding faster." % who))
	emergency_crashed.emit(who, died)
