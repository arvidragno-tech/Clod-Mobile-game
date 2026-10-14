extends Node
## Narrative state and the story engine.
##
## Five acts (data/story.json): I SURVIVAL, II REPUTATION, III POWER,
## IV CONSPIRACY, V CONSEQUENCE. Each act has beats - conversations, comms
## and quests that fire once when their conditions hold - and a condition
## to advance. Choices write flags, shift relationships and factions, add
## to seven endgame paths (respected, kingpin, corporate, network,
## investigator, creator, feared) and can schedule consequences that land
## days later. Also keeps rumours, met characters and counters
## (implants installed, black-market sales) that quests read.
##
## STORY CASES (data/cases.json): the mystery also walks in through the
## door. A case is a patient with a name, words, a history line and a clue
## the scan can find; it takes a routine patient's place in the day's
## schedule (CustomerManager), at most one every few days. Its outcome sets
## flags and queues a short decision (an event) whose effects echo later.
##
## CUTSCENES (data/cutscenes.json): a handful of short, skippable in-engine
## scenes for the opening, chapter changes, key introductions and
## revelations. Queued here, played by the clinic (CutscenePlayer), each at
## most once per save.

signal act_changed(act: int)
signal talk_queued(dialogue_id: StringName)
signal ending_reached(ending_id: StringName)
signal cutscene_queued(cutscene_id: StringName)

const PATHS: Array[StringName] = [&"respected", &"kingpin", &"corporate", &"network", &"investigator", &"creator", &"feared"]

var flags: Dictionary = {}  # StringName -> bool
var rumors: Dictionary = {}  # StringName -> Dictionary (data)
var rumor_order: Array[StringName] = []
var unlocked_rumors: Array[StringName] = []
var met_characters: Array[StringName] = []
## Story act (1 SURVIVAL .. 5 CONSEQUENCE).
var act: int = 1
var act_started_day: int = 1
## Delayed consequences: [{id, due_day, data}] fired at the start of a day.
var pending: Array[Dictionary] = []
## Conversations waiting to happen (dialogue ids, oldest first).
var talk_queue: Array[String] = []
var fired_beats: Array[String] = []
var paths: Dictionary = {}  # StringName -> int
var counters: Dictionary = {}  # StringName -> int
var ending: StringName = &""

var acts: Array = []
var beats: Array = []
var endings: Dictionary = {}

## Story cases: data, and what happened to each (id -> "arrived" | "done" |
## "failed" | "declined" | "missed").
var cases: Array = []
var case_state: Dictionary = {}
var last_case_day: int = -99
## Cutscenes: data (id -> scene), waiting to play, already played.
var cutscenes: Dictionary = {}
var cutscene_queue: Array[String] = []
var seen_cutscenes: Array[String] = []


func _ready() -> void:
	for r: Variant in DataLoader.load_entries(GameConfig.DATA_RUMORS, "rumors"):
		var id := StringName(str(r["id"]))
		rumors[id] = r
		rumor_order.append(id)
	var s: Variant = DataLoader.load_json(GameConfig.DATA_STORY)
	if s is Dictionary:
		acts = s.get("acts", [])
		beats = s.get("beats", [])
		endings = s.get("endings", {})
	cases = DataLoader.load_entries(GameConfig.DATA_CASES, "cases")
	for cs: Variant in DataLoader.load_entries(GameConfig.DATA_CUTSCENES, "cutscenes"):
		cutscenes[str(cs["id"])] = cs
	EventBus.day_started.connect(_on_day_started)
	reset_state()


func reset_state() -> void:
	act = 1
	act_started_day = 1
	pending.clear()
	talk_queue.clear()
	fired_beats.clear()
	flags.clear()
	unlocked_rumors.clear()
	met_characters.clear()
	paths.clear()
	counters.clear()
	ending = &""
	case_state.clear()
	last_case_day = -99
	cutscene_queue.clear()
	seen_cutscenes.clear()


# --- Flags, rumours, people ----------------------------------------------------------

func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: StringName, value: bool = true) -> void:
	if has_flag(flag) == value:
		return
	flags[flag] = value
	EventBus.story_flag_changed.emit(flag, value)


func meet(character_id: StringName) -> void:
	if character_id != &"" and not met_characters.has(character_id):
		met_characters.append(character_id)


func unlock_rumor(id: StringName) -> void:
	if rumors.has(id) and not unlocked_rumors.has(id):
		unlocked_rumors.append(id)
		EventBus.rumor_unlocked.emit(id)


## Unlocks every rumor whose conditions are now met.
func update_rumors() -> void:
	for id in rumor_order:
		if not unlocked_rumors.has(id) and EventManager.conditions_met(rumors[id].get("conditions", {})):
			unlock_rumor(id)


func get_rumor_text(id: StringName) -> String:
	return str(rumors.get(id, {}).get("text", ""))


func get_latest_rumor() -> String:
	return get_rumor_text(unlocked_rumors[unlocked_rumors.size() - 1]) if not unlocked_rumors.is_empty() else ""


func bump(counter: StringName, n: int = 1) -> void:
	counters[counter] = int(counters.get(counter, 0)) + n


func counter(id: StringName) -> int:
	return int(counters.get(id, 0))


func add_path(p: StringName, n: int) -> void:
	paths[p] = int(paths.get(p, 0)) + n


func path_score(p: StringName) -> int:
	return int(paths.get(p, 0))


# --- Acts -------------------------------------------------------------------------------

func act_data(n: int = -1) -> Dictionary:
	var i := (act if n < 0 else n) - 1
	return acts[i] if i >= 0 and i < acts.size() else {}


func act_title(n: int = -1) -> String:
	return str(act_data(n).get("title", "ACT %d" % (act if n < 0 else n)))


func days_in_act() -> int:
	return BusinessManager.day - act_started_day


func advance_act() -> void:
	if act >= 5:
		return
	act += 1
	act_started_day = BusinessManager.day
	queue_cutscene(StringName("cs_act_%d" % act))
	act_changed.emit(act)
	check()


# --- Consequences -----------------------------------------------------------------------

## Something the player did comes back `days` later (choices echo).
func schedule_consequence(id: StringName, days: int, data: Dictionary = {}) -> void:
	pending.append({"id": String(id), "due_day": BusinessManager.day + maxi(1, days), "data": data})


## Consequences due today (removed from the queue).
func take_due(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(pending.size() - 1, -1, -1):
		if int(pending[i]["due_day"]) <= day:
			out.push_front(pending[i])
			pending.remove_at(i)
	return out


func _on_day_started(day: int) -> void:
	_drop_missed_cases()
	for c in take_due(day):
		var id := StringName(str(c["id"]))
		if DialogueManager.has_dialogue(id):
			queue_talk(id)
		elif EventManager.events.has(id):
			EventManager.queue_event(id)
		elif CommsManager.templates.has(id):
			CommsManager.send(id, c.get("data", {}))
	check()


# --- Conversations ------------------------------------------------------------------------

func queue_talk(id: StringName) -> void:
	if not talk_queue.has(String(id)) and DialogueManager.has_dialogue(id):
		talk_queue.append(String(id))
		talk_queued.emit(id)


func has_talk() -> bool:
	return not talk_queue.is_empty()


func peek_talk() -> StringName:
	return StringName(talk_queue[0]) if not talk_queue.is_empty() else &""


func pop_talk() -> StringName:
	return StringName(talk_queue.pop_front()) if not talk_queue.is_empty() else &""


# --- Beats --------------------------------------------------------------------------------

## Fires every beat of the current (and earlier) acts whose conditions hold,
## then advances the act if its condition is met. Cheap; call it after
## anything that changes the world.
func check() -> void:
	if not GameManager.is_running:
		return
	var guard := 0
	var again := true
	while again and guard < 4:
		again = false
		guard += 1
		for b: Variant in beats:
			var id := str(b["id"])
			if fired_beats.has(id) or int(b.get("act", 1)) > act:
				continue
			if not cond(b.get("when", {})):
				continue
			fired_beats.append(id)
			for a: Variant in b.get("do", []):
				_do(a)
		var adv: Dictionary = act_data().get("advance", {})
		if act < 5 and not adv.is_empty() and cond(adv):
			act += 1
			act_started_day = BusinessManager.day
			queue_cutscene(StringName("cs_act_%d" % act))
			act_changed.emit(act)
			again = true
	# Owing money is its own story.
	if BusinessManager.debt > 0:
		QuestManager.start(&"q_landlord_debt")
	QuestManager.check_all()


func _do(a: Dictionary) -> void:
	if a.has("talk"):
		queue_talk(StringName(str(a["talk"])))
	if a.has("comms"):
		CommsManager.send(StringName(str(a["comms"])))
	if a.has("quest"):
		QuestManager.start(StringName(str(a["quest"])))
	if a.has("flag"):
		set_flag(StringName(str(a["flag"])))
	if a.has("cutscene"):
		queue_cutscene(StringName(str(a["cutscene"])))


## Story / quest condition dictionary.
func cond(w: Dictionary) -> bool:
	if w.has("min_day") and BusinessManager.day < int(w["min_day"]):
		return false
	if w.has("min_day_in_act") and days_in_act() < int(w["min_day_in_act"]):
		return false
	if w.has("min_ops") and EventManager.operations < int(w["min_ops"]):
		return false
	if w.has("min_rep") and ReputationManager.reputation < int(w["min_rep"]):
		return false
	if w.has("min_heat") and FactionManager.heat < float(w["min_heat"]):
		return false
	if w.has("min_level") and ProgressionManager.level < int(w["min_level"]):
		return false
	if w.has("flag") and not has_flag(StringName(str(w["flag"]))):
		return false
	if w.has("not_flag") and has_flag(StringName(str(w["not_flag"]))):
		return false
	if w.has("flag_any"):
		var any := false
		for f: Variant in w["flag_any"]:
			any = any or has_flag(StringName(str(f)))
		if not any:
			return false
	if w.has("clinics") and ClinicManager.owned.size() < int(w["clinics"]):
		return false
	if w.has("staff") and StaffManager.count() < int(w["staff"]):
		return false
	if w.has("staff_skill"):
		var e := StaffManager.get_employee(StringName(str(w["staff_skill"]["id"])))
		if e.is_empty() or int(e.get("skill", 0)) < int(w["staff_skill"]["n"]):
			return false
	var fm: Dictionary = w.get("faction_min", {})
	for f: Variant in fm:
		if FactionManager.get_rep(StringName(str(f))) < int(fm[f]):
			return false
	return true


# --- Effects (dialogue choices, comms actions) ------------------------------------------------

## Applies a choice's effects. char_id = who you were talking to (rel/fear).
## Returns a short summary of what changed (for the dialogue log).
func apply_effects(e: Dictionary, char_id: StringName = &"") -> Array[String]:
	var out: Array[String] = []
	if e.has("rel") and char_id != &"":
		CharacterManager.change_relationship(char_id, int(e["rel"]), int(e.get("fear", 0)))
		out.append("%s %+d" % [CharacterManager.get_character(char_id).display_name if CharacterManager.has_character(char_id) else "relationship", int(e["rel"])])
	elif e.has("fear") and char_id != &"":
		CharacterManager.change_relationship(char_id, 0, int(e["fear"]))
	var ro: Dictionary = e.get("rel_other", {})
	for id: Variant in ro:
		CharacterManager.change_relationship(StringName(str(id)), int(ro[id]))
	if e.has("flag"):
		var fl: Variant = e["flag"]
		for f: Variant in (fl if fl is Array else [fl]):
			set_flag(StringName(str(f)))
	if e.has("money"):
		var m := int(e["money"])
		if m > 0:
			EconomyManager.add_money(m, &"events")
			out.append("+%d cr" % m)
		elif m < 0:
			var paid := mini(-m, EconomyManager.money)
			EconomyManager.spend(paid, &"events")
			if -m > paid:
				BusinessManager.debt += -m - paid
			out.append("%d cr" % m)
	if e.has("debt"):
		BusinessManager.debt += int(e["debt"])
		out.append("debt +%d" % int(e["debt"]))
	if e.has("rep"):
		ReputationManager.change(int(e["rep"]))
		out.append("rep %+d" % int(e["rep"]))
	var fa: Dictionary = e.get("faction", {})
	for f: Variant in fa:
		FactionManager.change(StringName(str(f)), int(fa[f]))
		out.append("%s %+d" % [str(FactionManager.factions.get(StringName(str(f)), {}).get("short", f)), int(fa[f])])
	if e.has("heat"):
		FactionManager.add_heat(float(e["heat"]))
		out.append("heat %+d" % int(e["heat"]))
	var pa: Dictionary = e.get("path", {})
	for p: Variant in pa:
		add_path(StringName(str(p)), int(pa[p]))
	if e.has("quest"):
		QuestManager.start(StringName(str(e["quest"])))
	if e.has("consequence"):
		var c: Dictionary = e["consequence"]
		schedule_consequence(StringName(str(c["id"])), int(c.get("days", 2)), c.get("data", {}))
	if e.has("appearance_char"):
		var ac: Dictionary = e["appearance_char"]
		CharacterManager.apply_appearance_event(StringName(str(ac["id"])), str(ac["event"]))
	if e.has("supplies"):
		InventoryManager.add_supplies(int(e["supplies"]))
	if e.has("appearance_player"):
		# You got hurt: your own hands are worse for the next few jobs.
		EventManager.temp_modifiers.append({"key": "surgery.precision", "value": -0.15, "ops": 3, "source": "injury"})
		EventBus.modifiers_changed.emit()
		out.append("you're hurt: shaky hands for 3 jobs")
	if e.has("dims"):
		ReputationManager.change_dims(e["dims"])
		for d: Variant in e["dims"]:
			out.append("%s rep %+d" % [str(ReputationManager.DIMENSION_LABELS.get(StringName(str(d)), d)).to_lower(), int(e["dims"][d])])
	if e.has("memory") and char_id != &"":
		MemoryManager.remember(char_id, StringName(str(e["memory"])))
	if e.has("discover"):
		var ds: Variant = e["discover"]
		for l: Variant in (ds if ds is Array else [ds]):
			LocationManager.discover(StringName(str(l)), "You were told where to find it.")
	var cn: Dictionary = e.get("counters", {})
	for k: Variant in cn:
		bump(StringName(str(k)), int(cn[k]))
	if e.has("wall"):
		var w: Dictionary = e["wall"]
		ClinicLifeManager.pin(str(w.get("kind", "clipping")), str(w.get("title", "")), str(w.get("text", "")), str(w.get("ref", "")))
	if e.has("news"):
		WorldEventManager.post(str(e["news"]), "")
	if e.has("cutscene"):
		queue_cutscene(StringName(str(e["cutscene"])))
	if e.has("ending"):
		choose_ending(StringName(str(e["ending"])))
	return out


# --- Story cases ----------------------------------------------------------------------------------

func get_case(id: StringName) -> Dictionary:
	for c: Dictionary in cases:
		if str(c["id"]) == String(id):
			return c
	return {}


## The next story case that may walk in now, or {}. Cases come in order,
## within their acts, a few days apart.
func due_case() -> Dictionary:
	var gap := int(TimeManager.data.get("pacing", {}).get("story_case_gap_days", 2))
	if BusinessManager.day - last_case_day < gap:
		return {}
	for c: Dictionary in cases:
		var id := str(c["id"])
		if case_state.has(id) or int(c.get("act", 1)) > act or act > int(c.get("last_act", 5)):
			continue
		if not cond(c.get("when", {})):
			continue
		# Someone who died can't come back.
		if str(PeopleManager.get_person(StringName("case_%s" % str(c.get("patient", {}).get("id", id)))).get("status", "")) == "dead":
			case_state[id] = "missed"
			continue
		return c
	return {}


## A case's text: the first variant whose condition holds ({if: cond, text}),
## else the plain text.
func case_text(c: Dictionary, key: String, fallback: String = "") -> String:
	for v: Variant in c.get(key + "_variants", []):
		if v is Dictionary and cond(v.get("if", {})):
			return str(v.get("text", ""))
	return str(c.get(key, fallback))


func case_arrived(c: Dictionary) -> void:
	case_state[str(c["id"])] = "arrived"
	last_case_day = BusinessManager.day
	apply_effects(c.get("on_arrive", {}))


## The case's patient left your table. outcome: "success" | "failed" | "death".
## The decision that follows (an event) is queued unless something else is
## already waiting, in which case it comes tomorrow.
func case_finished(c: CustomerData, outcome: String) -> void:
	var sc := get_case(c.case_id) if c else {}
	if sc.is_empty() or str(case_state.get(str(sc["id"]), "")) in ["done", "failed"]:
		return
	case_state[str(sc["id"])] = "done" if outcome == "success" else "failed"
	apply_effects(sc.get("on_" + outcome, sc.get("on_failed", {}) if outcome == "death" else {}))
	var after := StringName(str(sc.get("after" if outcome == "success" else "after_failed", "")))
	if after != &"" and EventManager.events.has(after):
		if EventManager.has_pending():
			schedule_consequence(after, 1)
		else:
			EventManager.queue_event(after)
	# The room stays quiet for a while after a case like that.
	CustomerManager.quiet_until = TimeManager.minute + int(TimeManager.data.get("pacing", {}).get("quiet_minutes_after_story", 60))


func case_declined(c: CustomerData) -> void:
	var sc := get_case(c.case_id) if c else {}
	if sc.is_empty():
		return
	case_state[str(sc["id"])] = "declined"
	set_flag(StringName("%s_declined" % str(sc["id"])))
	apply_effects(sc.get("on_declined", {}))


## A case patient who never got seen (gone overnight) is a missed case.
func _drop_missed_cases() -> void:
	var present := {}
	if CustomerManager.current_customer:
		present[String(CustomerManager.current_customer.case_id)] = true
	for q: Dictionary in CustomerManager.queue:
		present[str(q.get("customer", {}).get("case_id", ""))] = true
	for id: Variant in case_state.keys():
		if str(case_state[id]) == "arrived" and not present.has(str(id)):
			case_state[id] = "missed"


func cases_seen() -> int:
	return case_state.size()


# --- Cutscenes ------------------------------------------------------------------------------------

## Queues a scene to play in the clinic (once per save; never when the
## player turned story cutscenes off).
func queue_cutscene(id: StringName) -> void:
	var key := String(id)
	if not cutscenes.has(key) or seen_cutscenes.has(key) or cutscene_queue.has(key):
		return
	if not Settings.story_cutscenes or not CutscenePlayer.enabled:
		seen_cutscenes.append(key)
		return
	cutscene_queue.append(key)
	cutscene_queued.emit(id)


func has_cutscene() -> bool:
	return not cutscene_queue.is_empty()


## The next scene to play (marked as seen, so a crash mid-scene can't loop it).
func pop_cutscene() -> StringName:
	if cutscene_queue.is_empty():
		return &""
	var id: String = cutscene_queue.pop_front()
	if not seen_cutscenes.has(id):
		seen_cutscenes.append(id)
	return StringName(id)


func get_cutscene(id: StringName) -> Dictionary:
	return cutscenes.get(String(id), {})


# --- Endings -----------------------------------------------------------------------------------

func ending_available(id: StringName) -> bool:
	var d: Dictionary = endings.get(String(id), {})
	if d.is_empty():
		return false
	if not cond(d.get("requires", {})):
		return false
	# The path has to be one you actually walked (the feared path is
	# always open: the city can always decide to fear you).
	return id == &"feared" or path_score(StringName(str(d.get("path", id)))) > 0


## Endings ranked by how far you walked each path.
func ranked_endings() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in endings:
		if ending_available(StringName(str(id))):
			out.append(StringName(str(id)))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return path_score(a) > path_score(b))
	return out


func choose_ending(id: StringName) -> void:
	ending = id
	set_flag(&"ending_chosen")
	ending_reached.emit(id)


func ending_text(id: StringName = &"") -> Dictionary:
	return endings.get(String(id if id != &"" else ending), {})


# --- Save -----------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var f := {}
	for k: StringName in flags:
		f[String(k)] = flags[k]
	var p := {}
	for k: Variant in paths:
		p[String(k)] = paths[k]
	var c := {}
	for k: Variant in counters:
		c[String(k)] = counters[k]
	return {"flags": f, "rumors": unlocked_rumors.map(func(x: StringName) -> String: return String(x)),
			"met": met_characters.map(func(x: StringName) -> String: return String(x)), "act": act,
			"act_started_day": act_started_day, "pending": pending.duplicate(true), "talks": talk_queue.duplicate(),
			"beats": fired_beats.duplicate(), "paths": p, "counters": c, "ending": String(ending),
			"cases": case_state.duplicate(), "last_case_day": last_case_day,
			"cutscenes": cutscene_queue.duplicate(), "seen_cutscenes": seen_cutscenes.duplicate()}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	var f: Dictionary = data.get("flags", {})
	for k: Variant in f:
		flags[StringName(str(k))] = bool(f[k])
	for r: Variant in data.get("rumors", []):
		if rumors.has(StringName(str(r))):
			unlocked_rumors.append(StringName(str(r)))
	for m: Variant in data.get("met", []):
		met_characters.append(StringName(str(m)))
	act = clampi(int(data.get("act", 1)), 1, 5)
	act_started_day = int(data.get("act_started_day", 1))
	for p: Variant in data.get("pending", []):
		if p is Dictionary:
			pending.append(p)
	for t: Variant in data.get("talks", []):
		talk_queue.append(str(t))
	for b: Variant in data.get("beats", []):
		fired_beats.append(str(b))
	var p2: Dictionary = data.get("paths", {})
	for k: Variant in p2:
		paths[StringName(str(k))] = int(p2[k])
	var c2: Dictionary = data.get("counters", {})
	for k: Variant in c2:
		counters[StringName(str(k))] = int(c2[k])
	ending = StringName(str(data.get("ending", "")))
	# 3.11: story cases and cutscenes (absent in older saves: nothing seen yet).
	var cs: Variant = data.get("cases", {})
	if cs is Dictionary:
		for k: Variant in cs:
			case_state[str(k)] = str(cs[k])
	last_case_day = int(data.get("last_case_day", -99))
	for q: Variant in data.get("cutscenes", []):
		if cutscenes.has(str(q)):
			cutscene_queue.append(str(q))
	for q: Variant in data.get("seen_cutscenes", []):
		seen_cutscenes.append(str(q))
