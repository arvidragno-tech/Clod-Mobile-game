extends Node
## Staff are people too (data/staff_life.json). Every employee gets a
## life outside the clinic: family, money, a fear and a dream. Colleagues
## form bonds (friendly, professional, suspicious, competitive, resentful,
## loyal, fearful, respectful, involved) that shift with time, events and
## what you make them do. Once in a while a life event lands in COMMS with
## choices: a sick father, a loan shark at the door, an ethical objection,
## a prototype they want in their own head, a romance, a shouting match.
## Bonds matter at work: friends steady each other, grudges cost focus.
##
## State lives on the employee dictionaries (e["life"], e["bonds"]) so it
## saves with StaffManager; only the event cooldowns are kept here.

const DAILY_EVENT_CHANCE := 0.4
const EVENT_COOLDOWN_DAYS := 6
const FIRST_EVENT_DAY := 2

var data: Dictionary = {}
var events: Array = []
var bond_states: Dictionary = {}
## event id -> day it last fired
var last_fired: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_STAFF_LIFE)
	if d is Dictionary:
		data = d
		events = d.get("events", [])
		bond_states = d.get("bond_states", {})
	EventBus.day_started.connect(_on_day_started)
	StaffManager.staff_changed.connect(_on_staff_changed)
	# Staff news (skill-ups, raises, who stood up for whom) reaches the player.
	StaffManager.employee_event.connect(func(_id: StringName, text: String) -> void: CommsManager.notify(text))
	reset_state()


func reset_state() -> void:
	last_fired.clear()


# --- Lives ---------------------------------------------------------------------------------

## Gives an employee a life if they don't have one yet (new hires, old saves).
func ensure_life(e: Dictionary) -> Dictionary:
	if not (e.get("life", null) is Dictionary) or (e["life"] as Dictionary).is_empty():
		var fam := str(_weighted(data.get("families", {})))
		var fears: Array = data.get("fears", ["The dark"])
		var dreams: Array = data.get("dreams", ["A way out"])
		e["life"] = {"family": fam, "money": str(_weighted(data.get("money", {}))),
			"fear": str(fears[_rng.randi() % fears.size()]), "dream": str(dreams[_rng.randi() % dreams.size()])}
	if not (e.get("bonds", null) is Dictionary):
		e["bonds"] = {}
	return e["life"]


func family_label(e: Dictionary) -> String:
	return str(data.get("families", {}).get(str(ensure_life(e).get("family", "none")), {}).get("label", ""))


func money_label(e: Dictionary) -> String:
	return str(data.get("money", {}).get(str(ensure_life(e).get("money", "")), {}).get("label", ""))


func _weighted(table: Dictionary) -> String:
	var w := {}
	for k: String in table:
		w[k] = float((table[k] as Dictionary).get("weight", 1))
	return str(CustomerGenerator.new(_rng).pick_weighted(w)) if not w.is_empty() else ""


# --- Bonds ---------------------------------------------------------------------------------

func rel(a: Dictionary, b: Dictionary) -> int:
	return int(a.get("relationships", {}).get(str(b["id"]), 0))


func change_rel(a: Dictionary, b: Dictionary, delta: int) -> void:
	var v := clampi(rel(a, b) + delta, -100, 100)
	a["relationships"][str(b["id"])] = v
	b["relationships"][str(a["id"])] = v


## How `a` feels about `b`. An explicit bond from events wins while the
## numbers still agree with it; otherwise it follows from regard, skill
## and what they know.
func bond(a: Dictionary, b: Dictionary) -> String:
	ensure_life(a)
	var r := rel(a, b)
	var explicit := str(a["bonds"].get(str(b["id"]), ""))
	if explicit == "involved" and r > -20:
		return explicit
	if explicit in ["resentful", "suspicious"] and r < 25:
		return explicit
	if explicit in ["competitive", "professional"] and r > -35 and r < 45:
		return explicit
	if bool(b.get("secret_known", false)):
		return "suspicious"
	if r >= 50:
		return "loyal"
	if r <= -40:
		return "resentful"
	if r <= -15:
		return "suspicious"
	if int(b.get("skill", 1)) >= int(a.get("skill", 1)) + 2:
		return "fearful" if EmployeeAI.has_trait(b, "butcher") else "respectful"
	if r >= 20:
		return "friendly"
	return "professional"


func set_bond(a: Dictionary, b: Dictionary, state: String) -> void:
	ensure_life(a)
	ensure_life(b)
	a["bonds"][str(b["id"])] = state
	b["bonds"][str(a["id"])] = state


func bond_label(state: String) -> String:
	return str(bond_states.get(state, {}).get("label", state.capitalize()))


func bond_color(state: String) -> Color:
	match str(bond_states.get(state, {}).get("color", "dim")):
		"ok":
			return Palette.OK
		"warn":
			return Palette.WARN
		"danger":
			return Palette.DANGER
		"brand":
			return Palette.BRAND
	return Palette.TEXT_DIM


## Colleagues at the same clinic.
func colleagues(e: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in StaffManager.at_clinic(int(e.get("clinic", 0))):
		if str(o["id"]) != str(e["id"]):
			out.append(o)
	return out


## Effect of the team on someone's work: friends and partners steady the
## hands, grudges and fear cost focus. Small on purpose.
func team_modifier(e: Dictionary) -> float:
	var m := 0.0
	for o in colleagues(e):
		match bond(e, o):
			"loyal", "friendly", "involved":
				m += 0.02
			"respectful":
				m += 0.01
			"resentful":
				m -= 0.04
			"suspicious", "fearful":
				m -= 0.02
	if bool(ensure_life(e).get("stims", false)):
		m -= 0.03
	return clampf(m, -0.1, 0.06)


# --- Days --------------------------------------------------------------------------------

func _on_staff_changed() -> void:
	for e in StaffManager.employees:
		ensure_life(e)


func _on_day_started(day: int) -> void:
	var staff := StaffManager.employees
	if staff.is_empty():
		return
	for e in staff:
		ensure_life(e)
		var life: Dictionary = e["life"]
		if bool(life.get("stims", false)):
			e["stress"] = maxf(0.0, float(e["stress"]) - 4.0)
	_drift()
	if day >= FIRST_EVENT_DAY and _rng.randf() < DAILY_EVENT_CHANCE:
		roll_event()


## Working side by side changes people a little every day.
func _drift() -> void:
	var staff := StaffManager.employees
	for i in staff.size():
		for j in range(i + 1, staff.size()):
			var a: Dictionary = staff[i]
			var b: Dictionary = staff[j]
			if int(a["clinic"]) != int(b["clinic"]):
				continue
			var d := 0
			if float(a["stress"]) < 40.0 and float(b["stress"]) < 40.0:
				d += 1
			if float(a["stress"]) > 70.0 or float(b["stress"]) > 70.0:
				d -= 1
			if str(a.get("personality", "")) == str(b.get("personality", "")):
				d += 1
			if d != 0 and _rng.randf() < 0.5:
				change_rel(a, b, d)


## Picks one fitting life event and sends it. Returns its id ("" = none).
func roll_event() -> String:
	var options: Array[Dictionary] = []
	var weights := {}
	for ev: Dictionary in events:
		var id := str(ev["id"])
		if BusinessManager.day - int(last_fired.get(id, -100)) < EVENT_COOLDOWN_DAYS:
			continue
		for cand in _candidates(ev):
			weights[options.size()] = float(ev.get("weight", 1))
			options.append({"event": ev, "a": cand[0], "b": cand[1]})
	if options.is_empty():
		return ""
	var pick: Dictionary = options[int(CustomerGenerator.new(_rng).pick_weighted(weights))]
	fire(StringName(str(pick["event"]["id"])), pick["a"], pick["b"])
	return str(pick["event"]["id"])


## Who an event could happen to: [[a, b-or-{}], ...].
func _candidates(ev: Dictionary) -> Array:
	var out: Array = []
	var cond: Dictionary = ev.get("cond", {})
	for a in StaffManager.employees:
		if str(a.get("status", "working")) == "gone":
			continue
		ensure_life(a)
		if str(ev.get("kind", "single")) == "single":
			if _single_ok(a, cond):
				out.append([a, {}])
		else:
			for b in colleagues(a):
				if _pair_ok(a, b, cond):
					out.append([a, b])
	return out


func _single_ok(a: Dictionary, cond: Dictionary) -> bool:
	var life: Dictionary = a["life"]
	if cond.has("family") and not (cond["family"] as Array).has(str(life.get("family", ""))):
		return false
	if cond.has("money") and not (cond["money"] as Array).has(str(life.get("money", ""))):
		return false
	if cond.has("ethics_any") and not (cond["ethics_any"] as Array).any(func(x: String) -> bool: return EmployeeAI.has_ethic(a, x)):
		return false
	if cond.has("trait_any") and not (cond["trait_any"] as Array).any(func(x: String) -> bool: return EmployeeAI.has_trait(a, x)):
		return false
	if cond.has("spec_any") and not (cond["spec_any"] as Array).has(str(a.get("specialization", ""))):
		return false
	if cond.has("min_stress") and float(a["stress"]) < float(cond["min_stress"]):
		return false
	if cond.has("counter") and StoryManager.counter(StringName(str(cond["counter"]))) <= 0:
		return false
	return true


func _pair_ok(a: Dictionary, b: Dictionary, cond: Dictionary) -> bool:
	var r := rel(a, b)
	if cond.has("min_rel") and r < int(cond["min_rel"]):
		return false
	if cond.has("max_rel") and r > int(cond["max_rel"]):
		return false
	if cond.has("bond") and str(a["bonds"].get(str(b["id"]), "")) != str(cond["bond"]):
		return false
	if cond.has("trait_any") and not (cond["trait_any"] as Array).any(func(x: String) -> bool: return EmployeeAI.has_trait(a, x)):
		return false
	if bool(cond.get("b_secret", false)) and not (EmployeeAI.has_trait(b, "secret_agent") and not bool(b.get("secret_known", false))):
		return false
	if cond.get("bond", "") != "involved" and str(a["bonds"].get(str(b["id"]), "")) == "involved" and cond.has("min_rel"):
		return false  # already together
	return true


func get_event(id: StringName) -> Dictionary:
	for ev: Dictionary in events:
		if str(ev["id"]) == String(id):
			return ev
	return {}


## Sends the event as a COMMS message with its choices.
func fire(id: StringName, a: Dictionary, b: Dictionary = {}) -> int:
	var ev := get_event(id)
	if ev.is_empty() or a.is_empty():
		return -1
	last_fired[String(id)] = BusinessManager.day
	var vars := {"name": str(a["name"]), "other": str(b.get("name", "")), "who": _who(a)}
	var acts: Array = []
	for act: Dictionary in ev.get("actions", []):
		var x := act.duplicate(true)
		x["label"] = _fill(str(act["label"]), vars)
		acts.append(x)
	var uid := CommsManager.send_raw("message", str(a["name"]), _fill(str(ev["subject"]), vars), _fill(str(ev["body"]), vars), acts, "staff_" + String(id))
	var m := CommsManager.get_message(uid)
	m["vars"] = {"kind": "staff_life", "event": String(id), "a": str(a["id"]), "b": str(b.get("id", ""))}
	return uid


func _who(e: Dictionary) -> String:
	return str(data.get("families", {}).get(str(ensure_life(e).get("family", "")), {}).get("who", "family"))


func _fill(s: String, vars: Dictionary) -> String:
	for k: String in vars:
		s = s.replace("{%s}" % k, str(vars[k])).replace("{%s}" % k.to_upper(), str(vars[k]).to_upper())
	return s


## Applies an action's "staff" block. vars from the message: {a, b}.
func apply_staff(fx: Dictionary, vars: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var a := StaffManager.get_employee(StringName(str(vars.get("a", ""))))
	var b := StaffManager.get_employee(StringName(str(vars.get("b", ""))))
	if not a.is_empty() and fx.has("a"):
		out.append_array(_apply_one(a, fx["a"]))
	if not b.is_empty() and fx.has("b"):
		out.append_array(_apply_one(b, fx["b"]))
	if fx.has("all"):
		for e in StaffManager.employees:
			_apply_one(e, fx["all"])
	if not a.is_empty() and not b.is_empty():
		if fx.has("rel"):
			change_rel(a, b, int(fx["rel"]))
		if fx.has("bond"):
			set_bond(a, b, str(fx["bond"]))
			out.append("%s & %s: %s" % [a["name"], b["name"], bond_label(str(fx["bond"])).to_lower()])
		if bool(fx.get("reveal_b", false)) and EmployeeAI.has_trait(b, "secret_agent"):
			b["secret_known"] = true
			StoryManager.set_flag(&"informant_found")
			out.append("%s was reporting to %s" % [b["name"], FactionManager.get_name_of(StringName(str(b["secret_faction"])))])
	StaffManager.staff_changed.emit()
	return out


func _apply_one(e: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	ensure_life(e)
	if f.has("loyalty"):
		e["loyalty"] = clampf(float(e["loyalty"]) + float(f["loyalty"]), 0.0, 100.0)
		out.append("%s loyalty %+d" % [e["name"], int(f["loyalty"])])
	if f.has("stress"):
		e["stress"] = clampf(float(e["stress"]) + float(f["stress"]), 0.0, 100.0)
	if bool(f.get("rest", false)):
		e["status"] = "resting"
		out.append("%s takes a day off" % e["name"])
	if f.has("appearance"):
		StaffManager._appearance(e, str(f["appearance"]))
	if f.has("precision"):
		e["precision"] = mini(5, int(e["precision"]) + int(f["precision"]))
	if f.has("xp"):
		StaffManager._gain_xp(e, int(f["xp"]))
	if f.has("ethic") and not (e["ethics"] as Array).has(str(f["ethic"])):
		(e["ethics"] as Array).append(str(f["ethic"]))
	if f.has("life"):
		var life: Dictionary = e["life"]
		var lf: Dictionary = f["life"]
		for k: String in lf:
			life[k] = lf[k]
	if f.has("memory"):
		MemoryManager.remember(StringName(str(e["id"])), StringName(str(f["memory"])))
	if not out.is_empty():
		StaffManager._log(e, ", ".join(out) + ".")
	return out


# --- Reactions -----------------------------------------------------------------------------

## A patient died under them: friends defend them, rivals don't.
func on_patient_death(e: Dictionary) -> void:
	for o in colleagues(e):
		match bond(o, e):
			"loyal", "friendly", "involved":
				e["loyalty"] = minf(100.0, float(e["loyalty"]) + 3.0)
				change_rel(o, e, 5)
				StaffManager.employee_event.emit(StringName(str(o["id"])), "%s stood up for %s in front of the family." % [o["name"], e["name"]])
			"resentful", "competitive":
				e["stress"] = minf(100.0, float(e["stress"]) + 8.0)
				change_rel(o, e, -5)
				StaffManager.employee_event.emit(StringName(str(o["id"])), "%s is telling people %s is a butcher." % [o["name"], e["name"]])


## You made them do a job they refused: their friends saw it.
func on_forced(e: Dictionary) -> void:
	for o in colleagues(e):
		if bond(o, e) in ["loyal", "friendly", "involved", "respectful"]:
			o["loyalty"] = maxf(0.0, float(o["loyalty"]) - 4.0)
			StaffManager.employee_event.emit(StringName(str(o["id"])), "%s saw what you made %s do." % [o["name"], e["name"]])


## Someone got a raise: rivals notice.
func on_raise(e: Dictionary) -> void:
	for o in colleagues(e):
		if bond(o, e) in ["competitive", "resentful"]:
			o["loyalty"] = maxf(0.0, float(o["loyalty"]) - 4.0)
			o["raise_pending"] = true
			StaffManager.employee_event.emit(StringName(str(o["id"])), "%s heard about %s's raise and wants one too." % [o["name"], e["name"]])


# --- Save ----------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"last_fired": last_fired.duplicate()}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	var lf: Dictionary = d.get("last_fired", {})
	for k: Variant in lf:
		last_fired[str(k)] = int(lf[k])
	for e in StaffManager.employees:
		ensure_life(e)
