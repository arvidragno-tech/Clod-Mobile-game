extends RefCounted
## What a decision card says it will do to street reputation, faction
## standing and heat is what it does: every event choice and conversation
## line in the data is previewed, applied for real, and the two compared, at
## Faction Relations ranks 0-3, with the street seeing you as criminal (more
## heat) or corporate (less), at low, middling and high street reputation
## (gains shrink as it rises), and next to the caps (standing near +100,
## heat near 0 and near the top). Rivals' losses are compared too.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	var cs_was := CutscenePlayer.enabled
	GameManager.is_running = true
	CutscenePlayer.enabled = false
	SaveManager.reset_all()
	_known_cases()
	_all_event_choices()
	_all_conversation_lines()
	_caps()
	_rep_levels()
	SaveManager.reset_all()
	CutscenePlayer.enabled = cs_was
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


## A state to preview in: Faction Relations rank, criminal and corporate
## street reputation, heat, street reputation.
func _state(rank: int, criminal: int, corporate: int, heat: float, street: int = 0) -> void:
	SaveManager.reset_all()
	ReputationManager.reputation = street
	SkillManager.ranks[&"faction_relations"] = rank
	ReputationManager.dims[&"criminal"] = criminal
	ReputationManager.dims[&"corporate"] = corporate
	EventBus.modifiers_changed.emit()
	FactionManager.heat = heat


const STATES := [
	[0, 0, 0, 20.0, 0], [1, 0, 0, 20.0, 12], [2, 0, 0, 20.0, 40], [3, 0, 0, 20.0, 70],
	[3, 60, 0, 20.0, -60], [0, 0, 80, 20.0, 90], [2, 40, 0, 5.0, 99], [3, 90, 0, 95.0, 100],
	[0, 0, 0, 20.0, -100], [0, 0, 0, 20.0, 1],
]


func _state_text(s: Array) -> String:
	return "Faction Relations %d, criminal %d, corporate %d, heat %d, REP %d" % [int(s[0]), int(s[1]), int(s[2]), int(s[3]), int(s[4])]


## The standing and heat parts of a preview: {"REP": n, "Name": n, "heat": n}.
func _parts(preview: String) -> Dictionary:
	var out := {}
	var p := preview.trim_prefix("if it works: ")
	if p == "":
		return out
	for part in p.split(", "):
		part = part.trim_suffix(" (rivals)")
		var sp := part.rfind(" ")
		if sp < 0:
			continue
		var name := part.substr(0, sp)
		var num := part.substr(sp + 1)
		if not (num.begins_with("+") or num.begins_with("-")) or num.ends_with("cr"):
			continue
		out[name] = int(num)
	return out


func _snapshot() -> Dictionary:
	return {"rep": FactionManager.rep.duplicate(), "heat": FactionManager.heat, "street": ReputationManager.reputation}


## What really changed since `before`, in the preview's terms.
func _diff(before: Dictionary) -> Dictionary:
	var out := {}
	if ReputationManager.reputation != int(before["street"]):
		out["REP"] = ReputationManager.reputation - int(before["street"])
	for id: StringName in FactionManager.order:
		var d := FactionManager.get_rep(id) - int(before["rep"].get(id, 0))
		if d != 0:
			out[FactionManager.get_name_of(id)] = d
	var h := FactionManager.heat - float(before["heat"])
	if absf(h) >= 0.5:
		out["heat"] = roundi(h)
	return out


## Previews `o`, applies it, and returns "" if they agree, else the two.
func _compare_event(o: Dictionary) -> String:
	var said := _parts(Standing.preview(o))
	var before := _snapshot()
	EventManager.apply_outcomes(o)
	var did := _diff(before)
	return "" if said == did else "preview %s, applied %s" % [said, did]


func _restore(before: Dictionary) -> void:
	FactionManager.rep = before["rep"].duplicate()
	FactionManager.heat = float(before["heat"])
	ReputationManager.reputation = int(before["street"])


# --- The cases the audit reproduced --------------------------------------------------------

func _known_cases() -> void:
	var sell: Dictionary = EventManager.get_event(&"case_lieutenant_after")["choices"][1]["outcomes"]
	_state(3, 60, 0, 20.0)
	var p := Standing.preview(sell)
	var said := _parts(p)
	check(int(said.get(FactionManager.get_name_of(&"corporate_security"), 0)) == 9, "preview: Faction Relations 3 shows selling Hook as Aegis +9, not +6 (%s)" % p)
	var before := _snapshot()
	EventManager.apply_outcomes(sell)
	var did := _diff(before)
	check(said == did, "preview: selling Hook to Aegis, previewed = applied, rivals included (%s / %s)" % [said, did])
	# A small gain the skill lifts to the rivals' threshold.
	_state(3, 0, 0, 20.0)
	var small := {"faction": {"street_gangs": 2}}
	p = Standing.preview(small)
	check(p.contains("(rivals)"), "preview: +2 for the Crews at Faction Relations 3 is +3, so Aegis notices (%s)" % p)
	check(_compare_event(small) == "", "preview: and the numbers are the ones applied")
	# Heat: criminal street reputation draws more of it.
	_state(0, 60, 0, 20.0)
	var hot := {"heat": 10}
	p = Standing.preview(hot)
	check(p == "heat +%d" % roundi(10.0 * ReputationManager.heat_gain_mult()) and p != "heat +10", "preview: heat +10 seen as a criminal shows more (%s)" % p)
	check(_compare_event(hot) == "", "preview: and it's the heat applied")
	_state(0, 0, 80, 20.0)
	check(_compare_event(hot) == "", "preview: seen as corporate, heat gains show smaller and match")
	SkillManager.ranks[&"smuggling"] = 3
	EventBus.modifiers_changed.emit()
	check(_compare_event(hot) == "", "preview: Smuggling's lower heat gain shows and matches")
	check(_compare_event({"heat": -10}) == "", "preview: cooling down is never scaled")


# --- Every choice in the data --------------------------------------------------------------

func _all_event_choices() -> void:
	for s: Array in STATES:
		_state(int(s[0]), int(s[1]), int(s[2]), float(s[3]), int(s[4]))
		var checked := 0
		var bad: Array[String] = []
		for id: StringName in EventManager.order:
			var choices: Array = EventManager.get_event(id).get("choices", [])
			for i in choices.size():
				var o: Dictionary = choices[i].get("outcomes", {})
				if o.has("risk"):
					continue  # a gamble: each branch is a plain outcome, compared below
				var before := _snapshot()
				var why := _compare_event(o)
				_restore(before)
				checked += 1
				if why != "":
					bad.append("%s #%d: %s" % [id, i, why])
		# The two branches of every risky choice, each as it would land.
		for id: StringName in EventManager.order:
			for c: Dictionary in EventManager.get_event(id).get("choices", []):
				var o: Dictionary = c.get("outcomes", {})
				if not o.has("risk"):
					continue
				for branch in ["success", "fail"]:
					var before := _snapshot()
					var why := _compare_event(o["risk"][branch])
					_restore(before)
					checked += 1
					if why != "":
						bad.append("%s (%s): %s" % [id, branch, why])
		check(checked > 50 and bad.is_empty(), "preview = applied for all %d event outcomes at %s%s" % [checked, _state_text(s), "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 4))])


func _all_conversation_lines() -> void:
	for s: Array in [STATES[0], STATES[3], STATES[4], STATES[7]]:
		_state(int(s[0]), int(s[1]), int(s[2]), float(s[3]), int(s[4]))
		var checked := 0
		var bad: Array[String] = []
		for did: Variant in DialogueManager.dialogues:
			var nodes: Dictionary = DialogueManager.dialogues[did].get("nodes", {})
			for nid: Variant in nodes:
				for o: Dictionary in nodes[nid].get("options", []):
					var e: Dictionary = o.get("effects", {})
					if not (e.has("faction") or e.has("heat") or e.has("rep")):
						continue
					var said := _parts(DialogueManager.known_effects(o))
					var before := _snapshot()
					StoryManager.apply_effects(e)
					var done := _diff(before)
					_restore(before)
					checked += 1
					if said != done:
						bad.append("%s/%s: preview %s, applied %s" % [did, nid, said, done])
		check(checked > 10 and bad.is_empty(), "preview = applied for all %d conversation lines that move REP, standing or heat at %s%s" % [checked, _state_text(s), "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 4))])


# --- At the caps ---------------------------------------------------------------------------

func _caps() -> void:
	_state(3, 0, 0, 3.0)
	FactionManager.rep[&"street_gangs"] = 98
	var o := {"faction": {"street_gangs": 6}, "heat": -10}
	var p := Standing.preview(o)
	check(p.contains("%s +2" % FactionManager.get_name_of(&"street_gangs")) and p.contains("heat -3"), "preview: next to the caps it shows what's left (+2 to 100, heat -3 to 0) (%s)" % p)
	check(not p.contains("(rivals)"), "preview: a +2 that's all that's left is too small for rivals to notice (%s)" % p)
	check(_compare_event(o) == "", "preview: and that's what happens")
	_state(0, 90, 0, 95.0)
	o = {"heat": 10}
	p = Standing.preview(o)
	check(p == "heat +%d" % roundi(GameConfig.MAX_HEAT - 95.0), "preview: heat stops at the top (%s)" % p)
	check(_compare_event(o) == "", "preview: and so does the real heat")
	_state(0, 0, 0, 20.0)
	FactionManager.rep[&"street_gangs"] = 100
	check(Standing.preview({"faction": {"street_gangs": 5}}) == "", "preview: a gain at +100 changes nothing, and says nothing")


# --- Street reputation at every level ------------------------------------------------------

func _rep_levels() -> void:
	# Gains shrink as reputation rises (each point harder to earn), losses
	# hit in full, and both stop at -100..100.
	_state(0, 0, 0, 20.0, 70)
	var p := Standing.preview({"reputation": 5})
	check(p == "REP +3", "REP preview: +5 at 70 shows +3, the gain you'd really get (%s)" % p)
	check(_compare_event({"reputation": 5}) == "", "REP preview: and +3 is applied")
	_state(0, 0, 0, 20.0, 99)
	p = Standing.preview({"reputation": 10})
	check(p == "REP +1", "REP preview: +10 at 99 shows the last point to 100 (%s)" % p)
	_state(0, 0, 0, 20.0, 100)
	check(Standing.preview({"reputation": 3}) == "", "REP preview: at 100 a gain changes nothing and says nothing")
	_state(0, 0, 0, 20.0, -98)
	p = Standing.preview({"reputation": -6})
	check(p == "REP -2", "REP preview: a loss stops at -100 (%s)" % p)
	_state(0, 0, 0, 20.0, 90)
	p = Standing.preview({"reputation": -6})
	check(p == "REP -6", "REP preview: losses hit in full however high you are (%s)" % p)
	var bad: Array[String] = []
	var checked := 0
	for street in [-100, -99, -50, -1, 0, 1, 10, 25, 40, 50, 69, 70, 80, 90, 98, 99, 100]:
		for d in [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, -1, -3, -6, -10, -25]:
			_state(0, 0, 0, 20.0, street)
			var why := _compare_event({"reputation": d})
			checked += 1
			if why != "":
				bad.append("REP %d %+d: %s" % [street, d, why])
	check(bad.is_empty(), "REP preview = applied for %d gains and losses from -100 to 100%s" % [checked, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 4))])
	# REP alongside standing and heat, and twice in one outcome (the choice's
	# own and its story effects): the second gain starts where the first ended.
	_state(3, 60, 0, 20.0, 60)
	var o := {"reputation": 6, "faction": {"street_gangs": 5}, "heat": 8, "effects": {"rep": 6}}
	p = Standing.preview(o)
	check(_compare_event(o) == "", "REP preview: REP, standing and heat in one choice all match (%s)" % p)
	# The same line in a conversation.
	_state(0, 0, 0, 20.0, 80)
	var line := {"text": "x", "effects": {"rep": 4, "heat": 2}}
	var said := _parts(DialogueManager.known_effects(line))
	var before := _snapshot()
	StoryManager.apply_effects(line["effects"])
	check(said == _diff(before), "REP preview: a conversation line at REP 80 shows the REP it gives (%s / %s)" % [said, _diff(before)])
