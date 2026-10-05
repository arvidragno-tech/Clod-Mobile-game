extends Node
## Everyone who has walked through the door, as people rather than tickets.
##
## A person keeps their identity, look (which changes between visits),
## traits, finances, relationship with you, visits, what they paid, what
## they owe, their cyberware, who they are connected to (referred, family,
## friend, rival) and a short history. MemoryManager holds what they
## remember. After each visit the person may come back days later, changed:
## richer or poorer, a new scar, chrome from someone else, a new crew, a new
## job, and the implant you put in. Their friends can be sent to you, or
## warned away. Patient debts and cyberware dependency live here too.

signal person_changed(id: StringName)
signal debt_changed()
## Every visit's outcome (success, failed, death, refused, deferred, left).
signal visit_recorded(id: StringName, outcome: String)

const RETURN_BASE := 0.32
const MAX_PEOPLE := 160
## Dependency: 0 none, 1 craving, 2 strain, 3 escalation, 4 crisis.
const DEPENDENCY_LABELS := ["", "Craving more", "Body under strain", "Escalating", "Crisis"]

var patients: Dictionary = {}  # data/patients.json
var people: Dictionary = {}  # id (String) -> Dictionary
var debts: Array[Dictionary] = []
var _next_debt: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_PATIENTS)
	if d is Dictionary:
		patients = d
	EventBus.day_started.connect(_on_day_started)
	reset_state()


func reset_state() -> void:
	people.clear()
	debts.clear()
	_next_debt = 1


func has_person(id: StringName) -> bool:
	return people.has(String(id))


func get_person(id: StringName) -> Dictionary:
	return people.get(String(id), {})


func trait_label(t: StringName) -> String:
	return str(patients.get("traits", {}).get(String(t), {}).get("label", String(t).capitalize()))


func finance_label(f: StringName) -> String:
	return str(patients.get("finances", {}).get(String(f), {}).get("label", String(f).capitalize()))


func rel_state(id: StringName) -> String:
	var p := get_person(id)
	if p.is_empty():
		return "stranger"
	var r := int(p.get("rel", 0))
	if bool(p.get("loyal", false)):
		return "loyal"
	if r <= -40:
		return "hostile"
	if r <= -10:
		return "wary"
	if r >= 35:
		return "grateful"
	if r >= 12:
		return "friendly"
	return "neutral"


# --- Registration ----------------------------------------------------------------

## Creates (or refreshes) the person behind a customer.
func register(c: CustomerData) -> Dictionary:
	if c == null or c.character_id != &"" and CharacterManager.has_character(c.character_id):
		return {}
	var key := String(c.id)
	var p: Dictionary = people.get(key, {})
	if p.is_empty():
		p = {"id": key, "rel": 0, "visits": 0, "paid_total": 0, "last_price": 0, "loyal": false, "status": "alive",
			"history": [], "links": {}, "cyber": [], "first_day": BusinessManager.day, "last_day": BusinessManager.day,
			"dependency": 0, "favor": false, "next_day": -1, "refused": 0}
		var tr := 0
		for t in c.traits:
			tr += int(patients.get("traits", {}).get(String(t), {}).get("rel", 0))
		p["rel"] = tr
	p["name"] = c.display_name
	p["alias"] = c.alias
	p["age"] = c.age
	p["archetype"] = String(c.archetype_id)
	p["occupation"] = c.occupation
	p["faction"] = String(c.faction_id)
	p["traits"] = c.traits.map(func(t: StringName) -> String: return String(t))
	p["finance"] = String(c.finance)
	p["wealth"] = c.wealth
	p["appearance"] = CharacterAppearanceManager.normalize(c.appearance).duplicate(true)
	p["personality"] = String(c.personality)
	p["dependency"] = maxi(int(p.get("dependency", 0)), c.dependency)
	if (p["cyber"] as Array).is_empty():
		for e in c.existing_cyberware:
			(p["cyber"] as Array).append(String(e))
	people[key] = p
	_trim()
	return p


func _trim() -> void:
	if people.size() <= MAX_PEOPLE:
		return
	# Forget the least memorable strangers first (never debtors).
	var keys := people.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _weight(a) < _weight(b))
	for k: String in keys:
		if people.size() <= MAX_PEOPLE:
			break
		if owed_by(StringName(k)) == 0:
			people.erase(k)


func _weight(k: String) -> float:
	var p: Dictionary = people[k]
	return absf(float(p.get("rel", 0))) + float(p.get("visits", 0)) * 10.0 + MemoryManager.of(StringName(k)).size() * 8.0 + float(p.get("last_day", 0)) * 0.5


func change_rel(id: StringName, delta: int) -> void:
	var p := get_person(id)
	if p.is_empty():
		return
	p["rel"] = clampi(int(p["rel"]) + delta, -100, 100)
	if int(p["rel"]) >= 45 and (p["traits"] as Array).has("loyal") or int(p["rel"]) >= 60:
		p["loyal"] = true
	elif int(p["rel"]) < 0:
		p["loyal"] = false
	person_changed.emit(id)


func note(id: StringName, text: String) -> void:
	var p := get_person(id)
	if p.is_empty():
		return
	var h: Array = p["history"]
	h.append("D%d %s" % [BusinessManager.day, text])
	while h.size() > 14:
		h.pop_front()


func link(a: StringName, b: StringName, kind: String) -> void:
	if has_person(a) and has_person(b) and a != b:
		get_person(a)["links"][String(b)] = kind
		get_person(b)["links"][String(a)] = kind


# --- Visits ------------------------------------------------------------------------

## After you dealt with them. outcome: success, failed, death, refused,
## deferred, left. paid: credits received now. Records memories, shifts the
## relationship and decides whether (and when) they'll be back.
func after_visit(c: CustomerData, outcome: String, paid: int = 0) -> void:
	var p := register(c)
	if p.is_empty():
		return
	var id := c.id
	p["visits"] = int(p["visits"]) + (1 if outcome in ["success", "failed"] else 0)
	p["last_day"] = BusinessManager.day
	p["paid_total"] = int(p["paid_total"]) + paid
	p["last_price"] = paid
	match outcome:
		"success":
			MemoryManager.remember(id, &"PLAYER_INSTALLED_CYBERWARE", String(c.requested_cyberware_id))
			if c.is_emergency:
				MemoryManager.remember(id, &"PLAYER_SAVED_ME")
			_add_installed(p, c)
			note(id, "Installed %s." % _item_name(c.requested_cyberware_id))
		"failed":
			MemoryManager.remember(id, &"PLAYER_FAILED_OPERATION")
			note(id, "Operation went wrong.")
		"death":
			p["status"] = "dead"
			note(id, "Died on the table.")
			# The people who loved them remember.
			for other: String in p["links"]:
				if has_person(StringName(other)):
					MemoryManager.remember(StringName(other), &"PLAYER_KILLED_FRIEND", String(id))
		"refused":
			p["refused"] = int(p.get("refused", 0)) + 1
			MemoryManager.remember(id, &"PLAYER_REFUSED_TREATMENT")
			note(id, "Refused treatment.")
			# Some have nowhere else to go and try again.
			if _rng.randf() < 0.22 + (0.2 if c.traits.has(&"desperate") else 0.0):
				p["next_day"] = BusinessManager.day + _rng.randi_range(2, 5)
		"deferred":
			note(id, "Told to come back tomorrow.")
		"stabilized":
			p["visits"] = int(p["visits"]) + 1
			note(id, "Stabilised, no new chrome.")
		"stopped":
			note(id, "You stopped the operation and closed them up.")
		"left":
			MemoryManager.remember(id, &"PLAYER_MADE_ME_WAIT")
			note(id, "Gave up waiting and left.")
	_apply_terms_memory(c)
	if outcome in ["success", "failed"]:
		_schedule_return(p, outcome)
	visit_recorded.emit(id, outcome)
	# Grudges travel: hostile people warn their friends away.
	if rel_state(id) == "hostile" and outcome != "death":
		ReputationManager.change_dim(&"civilian", -2)
		note(id, "Warning people away from your door.")
	person_changed.emit(id)


func _apply_terms_memory(c: CustomerData) -> void:
	match c.terms:
		&"discount":
			MemoryManager.remember(c.id, &"PLAYER_GAVE_DISCOUNT")
		&"free":
			MemoryManager.remember(c.id, &"PLAYER_TREATED_FREE")
		&"overcharge":
			MemoryManager.remember(c.id, &"PLAYER_OVERCHARGED_ME")


func _add_installed(p: Dictionary, c: CustomerData) -> void:
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item == null:
		return
	(p["cyber"] as Array).append(String(item.id))
	var ev := ""
	match String(item.category):
		"arms":
			ev = "cyber_arm"
		"eyes":
			ev = "cyber_eye"
		"legs":
			ev = "cyber_legs"
		_:
			var opts: Dictionary = CharacterAppearanceManager.rules.get("cyber_by_category", {}).get(String(item.category), {})
			if not opts.is_empty():
				ev = "cyber:" + str(opts.keys()[_rng.randi() % opts.size()])
	if ev != "":
		p["appearance"] = CharacterAppearanceManager.apply_event(p["appearance"], ev)


func _schedule_return(p: Dictionary, outcome: String) -> void:
	if str(p["status"]) != "alive":
		return
	var chance := RETURN_BASE + float(p["rel"]) / 200.0 + (0.25 if bool(p["loyal"]) else 0.0) + 0.12 * int(p["dependency"])
	if outcome == "failed":
		chance -= 0.15
	if _rng.randf() < chance:
		p["next_day"] = BusinessManager.day + _rng.randi_range(1, 4)


## Someone they know comes because of them (good care) or stays away (bad).
func referral(from: CustomerData) -> CustomerData:
	var friend := CustomerManager.generator.generate({"faction": String(from.faction_id), "referred_by": from.display_name})
	register(friend)
	link(from.id, friend.id, ["friend", "family", "crew"][_rng.randi() % 3])
	MemoryManager.remember(from.id, &"PLAYER_REFERRED", String(friend.id))
	note(friend.id, "Sent by %s." % from.display_name)
	return friend


# --- Payment ---------------------------------------------------------------------------

func terms_def(t: StringName) -> Dictionary:
	return patients.get("terms", {}).get(String(t), {})


## Which payment terms can be offered to this customer (backer pays only
## when someone backs them).
func available_terms(c: CustomerData) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: String in patients.get("terms", {}):
		if k == "faction" and (c == null or c.backer == &""):
			continue
		out.append(StringName(k))
	return out


## Turns a finished job's fee into money now and money owed, by the agreed
## terms and what the patient can actually pay. Records the debt; the
## caller adds `paid` to the till. {fee, price, paid, debt, lines}
func settle(c: CustomerData, fee: int) -> Dictionary:
	var out := {"fee": fee, "price": fee, "paid": fee, "debt": 0, "lines": [] as Array[String]}
	if c == null or fee <= 0:
		return out
	var t := c.terms if terms_def(c.terms).size() > 0 else &"full"
	var price := int(round(fee * float(terms_def(t).get("mult", 1.0))))
	var lines: Array[String] = out["lines"]
	if t == &"full" and c.traits.has(&"greedy"):
		price = int(round(price * 0.85))
		lines.append("%s haggled the fee down 15%%." % c.display_name)
	out["price"] = price
	var cast := c.character_id != &"" and CharacterManager.has_character(c.character_id)
	match t:
		&"free":
			out["paid"] = 0
		&"faction":
			out["paid"] = price
			FactionManager.change(c.backer, 1)
			ReputationManager.change_dim(&"corporate" if c.backer == &"corporate_security" else &"criminal", 2)
			if c.backer == &"street_gangs":
				FactionManager.add_heat(1.0)
			lines.append("%s covered the bill. They'll remember you took their money." % FactionManager.get_name_of(c.backer))
		&"plan":
			var now := mini(int(round(price * float(terms_def(t).get("upfront", 0.3)))), c.budget) if not cast else int(round(price * 0.3))
			out["paid"] = now
			out["debt"] = price - now
		_:
			out["paid"] = price if cast else mini(price, c.budget)
			out["debt"] = price - int(out["paid"])
	if int(out["debt"]) > 0 and not cast:
		register(c)
		var d := add_debt(c.id, int(out["debt"]), "payment plan" if t == &"plan" else "couldn't cover the fee")
		if t == &"plan":
			set_plan(int(d["id"]))
		lines.append("%s owes you %d cr." % [c.display_name, int(out["debt"])])
	elif cast:
		out["paid"] = price
		out["debt"] = 0
	return out


# --- Returning visitors -------------------------------------------------------------

## People due today (they join the door queue in CustomerManager).
func due_people() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: String in people:
		var p: Dictionary = people[k]
		if str(p["status"]) == "alive" and int(p.get("next_day", -1)) >= 0 and int(p["next_day"]) <= BusinessManager.day:
			out.append(StringName(k))
	return out


## Builds the returning person as today's customer: same face (changed by
## life since), same history, a new need.
func make_customer(id: StringName) -> CustomerData:
	var p := get_person(id)
	if p.is_empty():
		return null
	p["next_day"] = -1
	var c := CustomerManager.generator.generate({"archetype": str(p["archetype"]), "faction": str(p["faction"]), "full_difficulty": true})
	c.id = id
	c.display_name = str(p["name"])
	c.alias = str(p["alias"])
	c.age = int(p["age"])
	c.occupation = str(p["occupation"])
	c.visits = int(p["visits"])
	c.traits.clear()
	for t: Variant in p["traits"]:
		c.traits.append(StringName(str(t)))
	c.changes.clear()
	_evolve(p, c)
	c.faction_id = StringName(str(p["faction"]))
	c.occupation = str(p["occupation"])
	c.wealth = int(p["wealth"])
	c.finance = StringName(str(p["finance"]))
	var fd: Dictionary = patients.get("finances", {}).get(str(p["finance"]), {})
	c.backer = StringName(str(fd.get("backer", "")))
	c.pay_multiplier = 0.8 + 0.15 * c.wealth
	c.existing_cyberware.clear()
	for e: Variant in p["cyber"]:
		if CyberwareManager.get_cyberware(StringName(str(e))):
			c.existing_cyberware.append(StringName(str(e)))
	c.dependency = int(p["dependency"])
	if c.dependency > 0:
		_dependency_request(c)
	CustomerManager.generator.roll_budget(c)
	c.appearance = (p["appearance"] as Dictionary).duplicate(true)
	if owed_by(id) > 0:
		c.changes.append("Still owes you %d cr." % owed_by(id))
	if bool(p.get("favor", false)):
		c.changes.append(redeem_favor(id))
	var parts: Array[String] = []
	var line := MemoryManager.recall_line(id)
	var dl: Dictionary = CustomerManager.dialogue
	var greet: Array = ["Back again, doc.", "Me again. You remember me.", "Same chair as last time?", "Doc. Been a while."]
	parts.append(line if line != "" else str(greet[_rng.randi() % greet.size()]))
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if item:
		var reasons: Array = dl.get("reason", {}).get(String(item.category), [])
		if not reasons.is_empty():
			parts.append(str(reasons[_rng.randi() % reasons.size()]))
	if c.dependency >= 2:
		parts.append("I need more. The last one isn't enough anymore.")
	c.dialogue = " ".join(parts)
	if bool(p["loyal"]):
		c.pay_multiplier *= 1.1
		c.patience = mini(100, c.patience + 20)
	return c


## What happened to them since you last saw them.
func _evolve(p: Dictionary, c: CustomerData) -> void:
	var days := maxi(1, BusinessManager.day - int(p.get("last_day", BusinessManager.day)))
	var r := minf(1.0, 0.35 + days * 0.08)
	var app: Dictionary = p["appearance"]
	if _rng.randf() < 0.22 * r and int(p["wealth"]) < 3 and int(p["rel"]) >= 0:
		p["wealth"] = int(p["wealth"]) + 1
		p["finance"] = {1: "working", 2: "comfortable", 3: "wealthy"}.get(int(p["wealth"]), p["finance"])
		app = CharacterAppearanceManager.apply_event(app, "wealth_up")
		c.changes.append("Better clothes, better chrome: things are going well.")
	elif _rng.randf() < 0.15 * r and int(p["wealth"]) > 0:
		p["wealth"] = int(p["wealth"]) - 1
		p["finance"] = {0: "poor", 1: "working", 2: "comfortable"}.get(int(p["wealth"]), p["finance"])
		app = CharacterAppearanceManager.apply_event(app, "wealth_down")
		c.changes.append("Thinner, cheaper coat. Money ran out somewhere.")
	if _rng.randf() < 0.2 * r:
		app = CharacterAppearanceManager.apply_event(app, "injury", _rng)
		c.changes.append("A new scar since last time.")
	if _rng.randf() < 0.12 * r:
		var cy: Array = ["temple_ports", "jaw_plate", "cheek_leds", "serial_marks", "skull_plate"]
		var pick: String = cy[_rng.randi() % cy.size()]
		app = CharacterAppearanceManager.apply_event(app, "cyber:" + pick)
		c.changes.append("Had chrome put in somewhere else.")
	if _rng.randf() < 0.07 * r:
		var fac: Array = ["street_gangs", "independent_mercs", "black_market"]
		fac.erase(str(p["faction"]))
		var nf: String = fac[_rng.randi() % fac.size()]
		p["faction"] = nf
		app = CharacterAppearanceManager.apply_event(app, "faction:" + nf)
		c.changes.append("Runs with %s now." % FactionManager.get_name_of(StringName(nf)))
	if _rng.randf() < 0.06 * r:
		var arch := CustomerManager.archetypes[_rng.randi() % CustomerManager.archetypes.size()] as Dictionary
		p["occupation"] = str((arch["occupations"] as Array)[0])
		c.changes.append("New job: %s." % str(p["occupation"]).to_lower())
	p["appearance"] = app


# --- Dependency -----------------------------------------------------------------------

## Dependent people come back wanting more of the same thing, stronger.
func _dependency_request(c: CustomerData) -> void:
	var cat: StringName = &""
	for e in c.existing_cyberware:
		var it := CyberwareManager.get_cyberware(e)
		if it:
			cat = it.category
	if cat == &"":
		return
	var best: CyberwareData = null
	for it: CyberwareData in CyberwareManager.catalog.values():
		if it.category == cat and CyberwareManager.is_valid(it.id) and not c.existing_cyberware.has(it.id):
			if best == null or it.tier > best.tier:
				best = it
	if best:
		c.requested_cyberware_id = best.id
		var s := SurgeryManager.get_surgery(best.install_surgery_id)
		if s:
			c.requested_surgery_id = s.id
			if not s.has_diagnosis(c.true_diagnosis_id):
				c.true_diagnosis_id = StringName(str(s.diagnosis_options[0]["id"]))
			CustomerManager.generator._build_findings(c)
	c.neural_stability = maxf(30.0, c.neural_stability - 8.0 * c.dependency)
	c.changes.append("Dependency: %s." % DEPENDENCY_LABELS[clampi(c.dependency, 0, 4)].to_lower())


## You fed it (installed more), or you stabilised them instead.
func dependency_choice(c: CustomerData, fed: bool) -> void:
	var p := register(c)
	if p.is_empty():
		return
	if fed:
		p["dependency"] = mini(4, int(p["dependency"]) + 1)
		MemoryManager.remember(c.id, &"PLAYER_FED_DEPENDENCY")
		if int(p["dependency"]) >= 4:
			StoryManager.schedule_consequence(&"c_dependency_crisis", 2, {"name": c.display_name})
	else:
		p["dependency"] = maxi(0, int(p["dependency"]) - 2)
		MemoryManager.remember(c.id, &"PLAYER_STABILIZED_ME")
	c.dependency = int(p["dependency"])


# --- Debts --------------------------------------------------------------------------------

func add_debt(person: StringName, amount: int, reason: String) -> Dictionary:
	if amount <= 0:
		return {}
	var d := {"id": _next_debt, "person": String(person), "amount": amount, "original": amount, "reason": reason,
		"day": BusinessManager.day, "status": "open", "plan": 0, "history": ["D%d owes %d (%s)" % [BusinessManager.day, amount, reason]]}
	_next_debt += 1
	debts.append(d)
	note(person, "Owes %d (%s)." % [amount, reason])
	debt_changed.emit()
	return d


func open_debts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in debts:
		if str(d["status"]) in ["open", "plan"]:
			out.append(d)
	return out


func owed_by(person: StringName) -> int:
	var n := 0
	for d in open_debts():
		if str(d["person"]) == String(person):
			n += int(d["amount"])
	return n


func total_owed_to_you() -> int:
	var n := 0
	for d in open_debts():
		n += int(d["amount"])
	return n


func get_debt(id: int) -> Dictionary:
	for d in debts:
		if int(d["id"]) == id:
			return d
	return {}


func _pay(d: Dictionary, amount: int, how: String) -> int:
	amount = mini(amount, int(d["amount"]))
	if amount <= 0:
		return 0
	d["amount"] = int(d["amount"]) - amount
	EconomyManager.add_money(amount, &"revenue")
	(d["history"] as Array).append("D%d paid %d (%s)" % [BusinessManager.day, amount, how])
	if int(d["amount"]) <= 0:
		d["status"] = "paid"
		change_rel(StringName(str(d["person"])), 4)
	debt_changed.emit()
	return amount


## DEMAND: they pay what they can (more if they like you), and resent it.
func demand(id: int) -> int:
	var d := get_debt(id)
	if d.is_empty() or not str(d["status"]) in ["open", "plan"]:
		return 0
	var p := get_person(StringName(str(d["person"])))
	var can := 0.35 + float(p.get("rel", 0)) / 250.0 + 0.1 * int(p.get("wealth", 1))
	var paid := _pay(d, int(round(int(d["amount"]) * clampf(can, 0.1, 1.0))), "demanded")
	change_rel(StringName(str(d["person"])), -6)
	return paid


## PAYMENT PLAN: a share every night until it's gone.
func set_plan(id: int) -> void:
	var d := get_debt(id)
	if d.is_empty() or str(d["status"]) != "open":
		return
	d["status"] = "plan"
	d["plan"] = maxi(10, int(ceil(int(d["amount"]) / 4.0)))
	(d["history"] as Array).append("D%d payment plan: %d a night" % [BusinessManager.day, int(d["plan"])])
	change_rel(StringName(str(d["person"])), 3)
	debt_changed.emit()


func write_off(id: int) -> void:
	var d := get_debt(id)
	if d.is_empty() or not str(d["status"]) in ["open", "plan"]:
		return
	d["status"] = "written_off"
	(d["history"] as Array).append("D%d written off" % BusinessManager.day)
	MemoryManager.remember(StringName(str(d["person"])), &"PLAYER_LET_DEBT_GO")
	debt_changed.emit()


## A fixer collects: you get 60%, they get hurt, the street hears about it.
func send_collector(id: int) -> int:
	var d := get_debt(id)
	if d.is_empty() or not str(d["status"]) in ["open", "plan"]:
		return 0
	var got := int(round(int(d["amount"]) * 0.6))
	d["amount"] = 0
	d["status"] = "collected"
	EconomyManager.add_money(got, &"revenue")
	(d["history"] as Array).append("D%d collected by a fixer: %d to you" % [BusinessManager.day, got])
	var who := StringName(str(d["person"]))
	MemoryManager.remember(who, &"PLAYER_SENT_COLLECTOR")
	var p := get_person(who)
	if not p.is_empty():
		p["appearance"] = CharacterAppearanceManager.apply_event(p["appearance"], "injury", _rng)
	FactionManager.add_heat(2.0)
	debt_changed.emit()
	return got


## Trade the debt for a favour they'll repay in kind on their next visit.
func favor(id: int) -> void:
	var d := get_debt(id)
	if d.is_empty() or not str(d["status"]) in ["open", "plan"]:
		return
	d["status"] = "favor"
	(d["history"] as Array).append("D%d exchanged for a favour" % BusinessManager.day)
	var who := StringName(str(d["person"]))
	var p := get_person(who)
	if not p.is_empty():
		p["favor"] = true
		if int(p.get("next_day", -1)) < 0:
			p["next_day"] = BusinessManager.day + _rng.randi_range(2, 5)
	MemoryManager.remember(who, &"PLAYER_HELD_FAVOR")
	debt_changed.emit()


## They repay the favour: supplies, a part, or something they overheard.
func redeem_favor(id: StringName) -> String:
	var p := get_person(id)
	if p.is_empty() or not bool(p.get("favor", false)):
		return ""
	p["favor"] = false
	match _rng.randi() % 3:
		0:
			InventoryManager.add_supplies(4)
			return "%s drops off a box of sterile packs. Favour repaid." % p["name"]
		1:
			InventoryManager.add_parts(3)
			return "%s brings salvaged parts. Favour repaid." % p["name"]
		_:
			if BlackMarketManager.has_method(&"reveal_random_supplier_lead") and BlackMarketManager.call(&"reveal_random_supplier_lead") != "":
				return "%s tells you who's selling military chrome now. Favour repaid." % p["name"]
			var cash := 150 + 100 * int(p.get("wealth", 1))
			EconomyManager.add_money(cash, &"revenue")
			return "%s pays you back with a job on the side: %d cr. Favour repaid." % [p["name"], cash]


func _on_day_started(_day: int) -> void:
	for d in debts:
		if str(d["status"]) == "plan":
			var p := get_person(StringName(str(d["person"])))
			# Plans are usually kept; poorer people miss payments.
			if _rng.randf() < 0.65 + 0.1 * int(p.get("wealth", 1)) + float(p.get("rel", 0)) / 300.0:
				_pay(d, int(d["plan"]), "instalment")
			else:
				(d["history"] as Array).append("D%d missed an instalment" % BusinessManager.day)
	# Unpaid debts sour the relationship slowly.
	for d in open_debts():
		if str(d["status"]) == "open" and BusinessManager.day - int(d["day"]) > 5 and _rng.randf() < 0.2:
			change_rel(StringName(str(d["person"])), -2)


func _item_name(id: StringName) -> String:
	var it := CyberwareManager.get_cyberware(id)
	return it.display_name if it else String(id)


# --- Save -----------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"people": people.duplicate(true), "debts": debts.duplicate(true), "next_debt": _next_debt}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var p: Dictionary = data.get("people", {})
	for k: Variant in p:
		if p[k] is Dictionary:
			var d: Dictionary = (p[k] as Dictionary).duplicate(true)
			d["appearance"] = CharacterAppearanceManager.normalize(d.get("appearance", {}))
			people[str(k)] = d
	for d: Variant in data.get("debts", []):
		if d is Dictionary:
			debts.append(d)
	_next_debt = int(data.get("next_debt", debts.size() + 1))
