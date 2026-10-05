extends Node
## Clinic staff: the hiring board, hiring and firing, salaries, which
## clinic each person works in, assigning customers to them, and how they
## change day by day. Each employee is a Dictionary:
##   id, name, age, presentation, appearance (v2), background, personality,
##   anim, specialization, skill (1..5), speed, precision, reliability
##   (1..5), salary, ethics[], traits[], loyalty, stress, ambition (0..100),
##   relationships {employee id -> -100..100}, clinic (index), xp,
##   jobs_today, jobs_done, deaths, hired_day, status (working / resting /
##   gone), secret_faction, secret_known, raise_pending, history[].
## EmployeeAI holds the decision logic.

signal staff_changed()
signal employee_event(id: StringName, text: String)

const MAX_SKILL := 5
const CANDIDATES_BASE := 3
const TEO := &"teo_marr"

var specializations: Dictionary = {}
var traits: Dictionary = {}
var ethics: Dictionary = {}
var district_specs: Dictionary = {}
var backgrounds: Dictionary = {}
var personalities: Array = []

var employees: Array[Dictionary] = []
var candidates: Array[Dictionary] = []
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_STAFF)
	if d is Dictionary:
		specializations = d.get("specializations", {})
		traits = d.get("traits", {})
		ethics = d.get("ethics", {})
		district_specs = d.get("district_specs", {})
		backgrounds = d.get("backgrounds", {})
		personalities = d.get("personalities", ["calm"])
	EventBus.day_started.connect(func(_day: int) -> void: refresh_candidates())
	reset_state()


func reset_state() -> void:
	employees.clear()
	candidates.clear()
	_next_id = 1


# --- Queries -----------------------------------------------------------------------

func count() -> int:
	return employees.size()


func get_employee(id: StringName) -> Dictionary:
	for e in employees:
		if StringName(str(e["id"])) == id:
			return e
	return {}


func at_clinic(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in employees:
		if int(e.get("clinic", 0)) == index:
			out.append(e)
	return out


func capacity_total() -> int:
	var n := 0
	for i in ClinicManager.owned:
		n += ClinicManager.staff_capacity(i)
	return n


func clinic_with_room() -> int:
	if at_clinic(ClinicManager.tier).size() < ClinicManager.staff_capacity():
		return ClinicManager.tier
	for i in ClinicManager.owned:
		if at_clinic(i).size() < ClinicManager.staff_capacity(i):
			return i
	return -1


func daily_salaries() -> int:
	var n := 0
	for e in employees:
		n += int(e.get("salary", 0))
	return n


func spec_label(e: Dictionary) -> String:
	var s: Dictionary = specializations.get(str(e.get("specialization", "general")), {})
	return "%s ripperdoc · skill %d" % [str(s.get("short", "GENERAL")).capitalize(), int(e.get("skill", 1))]


func loyalty_label(e: Dictionary) -> String:
	var l := float(e.get("loyalty", 50))
	if l >= 80:
		return "loyal"
	if l >= 60:
		return "respectful"
	if l >= 40:
		return "neutral"
	if l >= 20:
		return "suspicious"
	return "hostile"


func visible_traits(e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t: Variant in e.get("traits", []):
		var td: Dictionary = traits.get(str(t), {})
		if bool(td.get("visible", true)) or (str(t) == "secret_agent" and bool(e.get("secret_known", false))):
			out.append(str(td.get("name", t)))
	return out


# --- Candidates --------------------------------------------------------------------

func refresh_candidates() -> void:
	candidates.clear()
	var n := CANDIDATES_BASE + mini(2, ClinicManager.owned.size() - 1)
	for i in n:
		candidates.append(generate_candidate())
	# Teo, the first hire the story offers.
	if get_employee(TEO).is_empty() and not StoryManager.has_flag(&"teo_gone") and BusinessManager.day >= 2:
		candidates.push_front(cast_candidate(TEO))


func cast_candidate(id: StringName) -> Dictionary:
	var c := CharacterManager.get_character(id)
	if c == null:
		return {}
	var st: Dictionary = c.staff
	var e := {
		"id": String(id), "name": c.display_name, "age": c.age, "presentation": c.presentation,
		"appearance": CharacterManager.appearance(id).duplicate(true), "background": c.background,
		"personality": "nervous", "anim": c.anim_profile, "specialization": str(st.get("specialization", "general")),
		"skill": int(st.get("skill", 2)), "speed": int(st.get("speed", 2)), "precision": int(st.get("precision", 3)),
		"reliability": int(st.get("reliability", 3)), "salary": int(st.get("salary", 35)),
		"ethics": (st.get("ethics", []) as Array).duplicate(), "traits": (st.get("traits", []) as Array).duplicate(),
		"loyalty": 55.0, "stress": 10.0, "ambition": 40.0, "cast": true,
	}
	return _finish(e)


func generate_candidate(spec: String = "") -> Dictionary:
	var district := String(WorldManager.current_district_id())
	if spec == "":
		spec = str(CustomerGenerator.new(_rng).pick_weighted(district_specs.get(district, {"general": 1})))
	var sd: Dictionary = specializations.get(spec, {})
	var names: Dictionary = CustomerManager.names
	var first := str(names.get("first", ["Sam"])[_rng.randi() % (names.get("first", ["Sam"]) as Array).size()])
	var last := str(names.get("last", ["Doe"])[_rng.randi() % (names.get("last", ["Doe"]) as Array).size()])
	var age := _rng.randi_range(22, 64)
	var personality := str(personalities[_rng.randi() % personalities.size()])
	var skill := clampi(1 + _rng.randi_range(0, 2) + (1 if ClinicManager.tier >= 4 else 0) + (1 if age > 45 and _rng.randf() < 0.5 else 0), 1, 4)
	var faction := "none"
	if spec == "black_market":
		faction = "black_market"
	elif spec == "military":
		faction = "independent_mercs"
	elif spec == "experimental":
		faction = "lyra_biocomp"
	var app := CharacterAppearanceManager.generate({"occupation": str(sd.get("occupation", "street_ripper")), "faction": faction,
		"age": age, "personality": personality, "wealth": 1}, _rng)
	var tr: Array = []
	var pool := traits.keys()
	for k in _rng.randi_range(1, 2):
		var t := str(pool[_rng.randi() % pool.size()])
		if not tr.has(t) and t != "secret_agent":
			tr.append(t)
	var secret := ""
	if _rng.randf() < 0.14:
		tr.append("secret_agent")
		secret = ["corporate_security", "lyra_biocomp", "street_gangs", "medical_authorities"][_rng.randi() % 4]
	var eth: Array = []
	for k: String in ["no_minors", "no_harvest", "no_corps"]:
		if _rng.randf() < (0.45 if k == "no_minors" else 0.18):
			eth.append(k)
	var bgs: Array = backgrounds.get(spec, ["Worked wherever the work was."])
	var e := {
		"id": "staff_%d_%d" % [Time.get_ticks_usec() % 1000000, _rng.randi() % 1000],
		"name": "%s %s" % [first, last], "age": age, "presentation": str(app.get("presentation", "masc")), "appearance": app,
		"background": str(bgs[_rng.randi() % bgs.size()]), "personality": personality,
		"anim": String(CharacterPortraitManager.PROFILE_BY_PERSONALITY.get(StringName(personality), &"calm")),
		"specialization": spec, "skill": skill, "speed": _rng.randi_range(1, 5), "precision": _rng.randi_range(1, 5),
		"reliability": _rng.randi_range(1, 5), "ethics": eth, "traits": tr, "secret_faction": secret,
		"loyalty": _rng.randf_range(35.0, 60.0), "stress": _rng.randf_range(0.0, 25.0), "ambition": _rng.randf_range(10.0, 80.0),
	}
	if (tr as Array).has("ambitious"):
		e["ambition"] = maxf(float(e["ambition"]), 70.0)
	return _finish(e)


func _finish(e: Dictionary) -> Dictionary:
	if not e.has("salary") or int(e["salary"]) <= 0:
		e["salary"] = EmployeeAI.market_salary(e)
	for k: String in ["xp", "jobs_today", "jobs_done", "deaths", "hired_day"]:
		e[k] = int(e.get(k, 0))
	e["status"] = str(e.get("status", "working"))
	e["relationships"] = e.get("relationships", {})
	e["history"] = e.get("history", [])
	e["secret_faction"] = str(e.get("secret_faction", ""))
	e["secret_known"] = bool(e.get("secret_known", false))
	e["raise_pending"] = bool(e.get("raise_pending", false))
	e["clinic"] = int(e.get("clinic", 0))
	return e


func signing_fee(e: Dictionary) -> int:
	return int(e.get("salary", 30)) * 2


# --- Hiring / firing ---------------------------------------------------------------

func hire_block_reason(e: Dictionary) -> String:
	if clinic_with_room() < 0:
		return "No room: upgrade STAFF or buy a clinic"
	if not EconomyManager.can_afford(signing_fee(e)):
		return "Signing fee %d" % signing_fee(e)
	return ""


func hire(index: int) -> bool:
	if index < 0 or index >= candidates.size():
		return false
	var e: Dictionary = candidates[index]
	if hire_block_reason(e) != "" or not EconomyManager.spend(signing_fee(e), &"salaries"):
		return false
	candidates.remove_at(index)
	e["clinic"] = clinic_with_room()
	e["hired_day"] = BusinessManager.day
	for other in employees:
		var v := _rng.randi_range(-20, 30)
		other["relationships"][str(e["id"])] = v
		e["relationships"][str(other["id"])] = v
	employees.append(e)
	_log(e, "Hired on day %d." % BusinessManager.day)
	if StringName(str(e["id"])) == TEO:
		StoryManager.set_flag(&"hired_teo")
		CharacterManager.change_relationship(TEO, 10)
	staff_changed.emit()
	StoryManager.check()
	return true


## Lets someone go: one day's severance, the others notice.
func fire(id: StringName) -> bool:
	var e := get_employee(id)
	if e.is_empty():
		return false
	EconomyManager.spend(mini(int(e["salary"]), EconomyManager.money), &"salaries")
	employees.erase(e)
	for other in employees:
		other["loyalty"] = clampf(float(other["loyalty"]) - 4.0 - float(other["relationships"].get(str(id), 0)) / 20.0, 0.0, 100.0)
	if id == TEO:
		StoryManager.set_flag(&"teo_gone")
		CharacterManager.change_relationship(TEO, -40)
	if str(e.get("secret_faction", "")) != "" and not bool(e.get("secret_known", false)):
		# An unexposed informant leaves with everything they saw.
		FactionManager.add_heat(4.0)
	if float(e["loyalty"]) < 25.0:
		StoryManager.schedule_consequence(&"fired_grudge", 3, {"name": e["name"]})
	staff_changed.emit()
	return true


func transfer(id: StringName, clinic_index: int) -> bool:
	var e := get_employee(id)
	if e.is_empty() or not ClinicManager.owns(clinic_index) or at_clinic(clinic_index).size() >= ClinicManager.staff_capacity(clinic_index):
		return false
	e["clinic"] = clinic_index
	staff_changed.emit()
	return true


func give_raise(id: StringName, accept: bool = true) -> void:
	var e := get_employee(id)
	if e.is_empty():
		return
	e["raise_pending"] = false
	if accept:
		e["salary"] = int(round(int(e["salary"]) * 1.15)) + 2
		e["loyalty"] = minf(100.0, float(e["loyalty"]) + 12.0)
		e["ambition"] = maxf(0.0, float(e["ambition"]) - 20.0)
		_log(e, "Got a raise to %d/day." % int(e["salary"]))
		StaffLifeManager.on_raise(e)
	else:
		e["loyalty"] = maxf(0.0, float(e["loyalty"]) - 15.0)
		_log(e, "Asked for a raise. Refused.")
	staff_changed.emit()


# --- Work ----------------------------------------------------------------------------

## Employees at the active clinic who could take this customer, with their
## odds and any refusal: [{employee, chance, refusal}].
func options_for(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in at_clinic(ClinicManager.tier):
		out.append({"employee": e, "chance": EmployeeAI.success_chance(e, c), "refusal": EmployeeAI.refusal(e, c)})
	return out


## Runs the job. insist = override an ethical refusal (costs loyalty and
## stress, and they remember). Returns the EmployeeAI.perform result plus
## {refused, employee_id}.
func assign(id: StringName, c: CustomerData, insist: bool = false) -> Dictionary:
	var e := get_employee(id)
	if e.is_empty() or c == null:
		return {"refused": true, "text": "Nobody to do it."}
	var why := EmployeeAI.refusal(e, c)
	if why != "":
		var hard := why.begins_with("\"")
		if not insist or not hard:
			return {"refused": true, "text": why}
		e["loyalty"] = maxf(0.0, float(e["loyalty"]) - 12.0)
		e["stress"] = minf(100.0, float(e["stress"]) + 15.0)
		_log(e, "Was made to do a job they refused.")
		StaffLifeManager.on_forced(e)
		MemoryManager.remember(id, &"PLAYER_FORCED_MY_HAND")
		if id == TEO:
			CharacterManager.change_relationship(TEO, -15)
			StoryManager.set_flag(&"teo_crossed_line")
	var r := EmployeeAI.perform(e, c, _rng)
	r["refused"] = false
	r["employee_id"] = String(id)
	e["jobs_today"] = int(e["jobs_today"]) + 1
	e["jobs_done"] = int(e["jobs_done"]) + 1
	e["stress"] = clampf(float(e["stress"]) + float(r["stress"]), 0.0, 100.0)
	_gain_xp(e, int(r["xp"]))
	if bool(r["death"]):
		e["deaths"] = int(e["deaths"]) + 1
		e["loyalty"] = maxf(0.0, float(e["loyalty"]) - 5.0)
		_appearance(e, "expr:sad")
		StaffLifeManager.on_patient_death(e)
	elif bool(r["success"]):
		e["loyalty"] = minf(100.0, float(e["loyalty"]) + 1.0)
	_log(e, str(r["text"]))
	staff_changed.emit()
	return r


func _gain_xp(e: Dictionary, xp: int) -> void:
	e["xp"] = int(e["xp"]) + xp
	while int(e["skill"]) < MAX_SKILL and int(e["xp"]) >= 60 * int(e["skill"]):
		e["xp"] = int(e["xp"]) - 60 * int(e["skill"])
		e["skill"] = int(e["skill"]) + 1
		e["precision"] = mini(5, int(e["precision"]) + (1 if _rng.randf() < 0.5 else 0))
		_on_skill_up(e)


## Growth shows: better coat, a loupe, precision optics, steadier chrome.
func _on_skill_up(e: Dictionary) -> void:
	var s := int(e["skill"])
	var app: Dictionary = e["appearance"]
	match s:
		3:
			if str(app.get("outfit", "")) in ["technician", "medic", "civilian", "worker"]:
				_appearance(e, "upgrade_outfit:ripperdoc")
		4:
			_appearance(e, "accessory:monocle")
		5:
			_appearance(e, "cyber:twin_optics")
			_appearance(e, "wealth_up")
	_log(e, "Reached skill %d." % s)
	employee_event.emit(StringName(str(e["id"])), "%s is now a skill %d surgeon." % [e["name"], s])
	if EmployeeAI.has_trait(e, "ambitious") or float(e["ambition"]) > 60.0:
		e["raise_pending"] = true
		employee_event.emit(StringName(str(e["id"])), "%s wants a raise." % e["name"])
		CommsManager.send(&"c_staff_raise", {"name": e["name"]})


# --- Days ----------------------------------------------------------------------------

## Called by BusinessManager when the clinic closes. Returns note strings.
func end_of_day() -> Array[String]:
	var notes: Array[String] = []
	notes.append_array(_run_other_clinics())
	for e in employees.duplicate():
		var worked := int(e["jobs_today"])
		var st := float(e["stress"])
		st += -12.0 if worked == 0 else -4.0
		if str(e["status"]) == "resting":
			e["status"] = "working"
			st -= 20.0
		e["stress"] = clampf(st, 0.0, 100.0)
		var l := float(e["loyalty"])
		l += 1.0 if int(e["salary"]) >= EmployeeAI.market_salary(e) else -2.0
		if float(e["stress"]) > 70.0:
			l -= 3.0
		if bool(e["raise_pending"]):
			l -= 2.0
		l = maxf(l, trait_floor(e))
		e["loyalty"] = clampf(l, 0.0, 100.0)
		if float(e["stress"]) >= 90.0:
			e["status"] = "resting"
			_appearance(e, "expr:fear")
			notes.append("%s is burnt out and takes tomorrow off." % e["name"])
		elif float(e["stress"]) < 40.0 and str(e["appearance"].get("expr", "")) in ["fear", "sad"]:
			_appearance(e, "expr:neutral")
		# Hidden traits do their work at night.
		if EmployeeAI.has_trait(e, "secret_agent") and not bool(e["secret_known"]):
			if _rng.randf() < 0.1:
				FactionManager.add_heat(3.0)
				FactionManager.change(StringName(str(e["secret_faction"])), 1)
			if _rng.randf() < 0.03 + 0.04 * maxi(0, ClinicManager.security_rating() - 2):
				e["secret_known"] = true
				notes.append("Camera footage: %s has been reporting to %s." % [e["name"], FactionManager.get_name_of(StringName(str(e["secret_faction"])))])
				StoryManager.set_flag(&"informant_found")
				CommsManager.send(&"c_informant", {"name": e["name"], "faction": FactionManager.get_name_of(StringName(str(e["secret_faction"])))})
		if EmployeeAI.has_trait(e, "gambler") and _rng.randf() < 0.08:
			var gone := mini(EconomyManager.money, _rng.randi_range(30, 90))
			if gone > 0:
				EconomyManager.spend(gone, &"other")
				notes.append("%d is missing from the till." % gone if ClinicManager.security_rating() < 3 else "%s took %d from the till. The camera saw it." % [e["name"], gone])
		if float(e["loyalty"]) <= 5.0 or (bool(e["raise_pending"]) and float(e["loyalty"]) < 20.0):
			notes.append("%s quit. Their locker is empty." % e["name"])
			employees.erase(e)
			if StringName(str(e["id"])) == TEO:
				StoryManager.set_flag(&"teo_gone")
			continue
		e["jobs_today"] = 0
	staff_changed.emit()
	return notes


## Appearance changes stick (and for cast members, follow them into the
## story through CharacterManager).
func _appearance(e: Dictionary, event: String) -> void:
	var id := StringName(str(e["id"]))
	if CharacterManager.has_character(id):
		CharacterManager.apply_appearance_event(id, event)
		e["appearance"] = CharacterManager.appearance(id).duplicate(true)
	else:
		e["appearance"] = CharacterAppearanceManager.apply_event(e["appearance"], event)


func trait_floor(e: Dictionary) -> float:
	return EmployeeAI.trait_value(e, "loyalty_floor")


## Owned clinics you don't work in earn money if someone runs them.
func _run_other_clinics() -> Array[String]:
	var notes: Array[String] = []
	for i in ClinicManager.owned:
		if i == ClinicManager.tier:
			continue
		var staff := at_clinic(i)
		if staff.is_empty():
			continue
		var t := ClinicManager.get_tier_data(i)
		var wealth := float(WorldManager.get_district(StringName(str(t.get("district", "")))).get("wealth", 1.0))
		var jobs := mini(staff.size() * 2, ClinicManager.surgery_capacity(i))
		var income := 0
		var fails := 0
		for k in jobs:
			var e: Dictionary = staff[k % staff.size()]
			var p := clampf(0.55 + 0.08 * float(e["skill"]) - 0.2 * float(e["stress"]) / 100.0, 0.1, 0.95)
			if _rng.randf() < p:
				income += int((150 + 45 * i) * wealth)
				_gain_xp(e, 8)
			else:
				fails += 1
			e["stress"] = minf(100.0, float(e["stress"]) + 5.0)
		if income > 0:
			EconomyManager.add_money(income, &"staff_revenue")
		if fails > 0:
			ReputationManager.change(-fails)
		notes.append("%s: %d jobs, +%d%s." % [str(t["name"]), jobs, income, (", %d went wrong" % fails) if fails else ""])
	return notes


func _log(e: Dictionary, text: String) -> void:
	var h: Array = e["history"]
	h.append("D%d %s" % [BusinessManager.day, text])
	while h.size() > 20:
		h.pop_front()


# --- Save ------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"employees": employees.duplicate(true), "candidates": candidates.duplicate(true), "next_id": _next_id}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for e: Variant in data.get("employees", []):
		if e is Dictionary:
			var d: Dictionary = _finish((e as Dictionary).duplicate(true))
			d["appearance"] = CharacterAppearanceManager.normalize(d.get("appearance", {}))
			if not ClinicManager.owns(int(d["clinic"])):
				d["clinic"] = ClinicManager.tier
			employees.append(d)
	for c: Variant in data.get("candidates", []):
		if c is Dictionary:
			candidates.append(_finish((c as Dictionary).duplicate(true)))
	_next_id = int(data.get("next_id", 1))
