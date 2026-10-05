extends Node
## Branching conversations (data/dialogues.json) with the story cast.
##
## A conversation is a graph of nodes; each node has a speaker line, an
## expression (the portrait changes with it) and either a `next` node or
## options. Options have a kind - plain, persuade, intimidate, bribe,
## empathy, lie, negotiate, refuse - and every kind except plain/refuse is
## a check whose odds come from who you are (reputation, heat, factions,
## level, money) and who you're talking to (relationship, fear). Success
## and failure lead to different nodes and effects (StoryManager.apply_effects).
## Every choice is logged and saved.

signal started(id: StringName)
signal node_changed(node: Dictionary)
signal ended(id: StringName)
signal check_rolled(kind: StringName, success: bool, chance: float)

const KIND_LABELS := {
	"plain": "", "refuse": "REFUSE", "persuade": "PERSUADE", "intimidate": "INTIMIDATE", "bribe": "BRIBE",
	"empathy": "EMPATHY", "lie": "LIE", "negotiate": "NEGOTIATE",
}
const KIND_COLORS := {
	"persuade": Color("6aa8ff"), "intimidate": Color("ff4d4d"), "bribe": Color("ffb43d"), "empathy": Color("6dff8a"),
	"lie": Color("c46aff"), "negotiate": Color("2ee6c8"), "refuse": Color("8e9aa8"), "plain": Color("c8ccd2"),
}

var dialogues: Dictionary = {}
var current_id: StringName = &""
var current_node_id: String = ""
var log_lines: Array[Dictionary] = []  # this conversation: {speaker, text, kind?}
var choices: Array[Dictionary] = []  # all-time: {dialogue, node, option, kind, success, day}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_DIALOGUES)
	if d is Dictionary:
		dialogues = d.get("dialogues", {})
	reset_state()


func reset_state() -> void:
	current_id = &""
	current_node_id = ""
	log_lines.clear()
	choices.clear()


func has_dialogue(id: StringName) -> bool:
	return dialogues.has(String(id))


func is_active() -> bool:
	return current_id != &""


func get_dialogue(id: StringName = &"") -> Dictionary:
	return dialogues.get(String(id if id != &"" else current_id), {})


func character_id() -> StringName:
	return StringName(str(get_dialogue().get("character", "")))


func current_node() -> Dictionary:
	return get_dialogue().get("nodes", {}).get(current_node_id, {})


func start(id: StringName) -> bool:
	if not has_dialogue(id):
		return false
	current_id = id
	log_lines.clear()
	CharacterManager.mark_met(character_id())
	CharacterPortraitManager.prewarm(character_id())
	started.emit(id)
	_enter(str(get_dialogue().get("start", "start")))
	return true


func _enter(node_id: String) -> void:
	current_node_id = node_id
	var n := current_node()
	if n.is_empty():
		end()
		return
	if n.has("effects"):
		StoryManager.apply_effects(n["effects"], character_id())
	log_lines.append({"speaker": str(n.get("speaker", "npc")), "text": str(n.get("text", ""))})
	node_changed.emit(n)


## Options the player can see: [{index, text, kind, label, chance, locked}]
func options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var opts: Array = current_node().get("options", [])
	for i in opts.size():
		var o: Dictionary = opts[i]
		var locked := lock_reason(o)
		# Ending options you haven't earned are simply not shown.
		if locked == "hidden":
			continue
		var kind := str(o.get("kind", "plain"))
		var ch := chance(o)
		var tag := str(KIND_LABELS.get(kind, kind.to_upper()))
		if is_check(kind):
			tag = "%s %d%%" % [tag, roundi(ch * 100.0)]
		var cost: int = int(o.get("cost", {}).get("money", 0))
		if cost > 0:
			tag = ("%s · %d cr" % [tag, cost]) if tag != "" else "%d cr" % cost
		out.append({"index": i, "text": str(o["text"]), "kind": kind, "label": tag, "chance": ch, "locked": locked})
	return out


static func is_check(kind: String) -> bool:
	return kind in ["persuade", "intimidate", "bribe", "empathy", "lie", "negotiate"]


## "" if the option can be picked; "hidden" if it shouldn't be shown.
func lock_reason(o: Dictionary) -> String:
	var r: Dictionary = o.get("requires", {})
	if r.has("ending") and not StoryManager.ending_available(StringName(str(r["ending"]))):
		return "hidden"
	if r.has("flag") and not StoryManager.has_flag(StringName(str(r["flag"]))):
		return "hidden"
	if r.has("flag_any"):
		var any := false
		for f: Variant in r["flag_any"]:
			any = any or StoryManager.has_flag(StringName(str(f)))
		if not any:
			return "hidden"
	var cost := int(o.get("cost", {}).get("money", 0))
	if cost > 0 and not EconomyManager.can_afford(cost):
		return "Not enough credits"
	if r.has("rel_min") and CharacterManager.relationship(character_id()) < int(r["rel_min"]):
		return "They don't trust you enough"
	return ""


## Odds for a check option (1.0 for plain / refuse).
func chance(o: Dictionary) -> float:
	var kind := str(o.get("kind", "plain"))
	if not is_check(kind):
		return 1.0
	var who := character_id()
	var rel := float(CharacterManager.relationship(who))
	var fear := float(CharacterManager.state.get(who, {}).get("fear", 0))
	var rep := float(ReputationManager.reputation)
	var lvl := float(ProgressionManager.level)
	var p := 0.5
	match kind:
		"persuade":
			p = 0.35 + rep / 200.0 + rel / 250.0 + lvl * 0.01
		"intimidate":
			p = 0.3 + FactionManager.heat / 200.0 + fear / 200.0 + float(FactionManager.get_rep(&"street_gangs")) / 300.0 + StoryManager.path_score(&"feared") * 0.03
		"bribe":
			p = 0.8 - maxf(0.0, rel) / 400.0
		"empathy":
			p = 0.45 + rel / 200.0 + StoryManager.path_score(&"respected") * 0.02
		"lie":
			p = 0.4 + lvl * 0.015 - (0.15 if CharacterManager.relationship_state(who) == "suspicious" else 0.0)
		"negotiate":
			p = 0.4 + lvl * 0.02 + rep / 300.0 + StoryManager.path_score(&"kingpin") * 0.02
	p += float(o.get("mod", 0.0))
	return clampf(p, 0.05, 0.95)


## Picks visible option `index` (the original option index from options()).
## Returns {success, summary[]} or {} if not allowed.
func choose(index: int) -> Dictionary:
	var opts: Array = current_node().get("options", [])
	if index < 0 or index >= opts.size():
		return {}
	var o: Dictionary = opts[index]
	if lock_reason(o) != "":
		return {}
	var kind := str(o.get("kind", "plain"))
	var cost := int(o.get("cost", {}).get("money", 0))
	if cost > 0 and not EconomyManager.spend(cost, &"bribes" if kind == "bribe" else &"events"):
		return {}
	var p := chance(o)
	var ok := not is_check(kind) or _rng.randf() < p
	if is_check(kind):
		check_rolled.emit(StringName(kind), ok, p)
	log_lines.append({"speaker": "you", "text": str(o["text"]), "kind": kind, "success": ok})
	choices.append({"dialogue": String(current_id), "node": current_node_id, "option": str(o["text"]), "kind": kind, "success": ok, "day": BusinessManager.day})
	while choices.size() > 200:
		choices.pop_front()
	var eff: Dictionary = o.get("effects", {}) if ok else o.get("fail_effects", {})
	var summary := StoryManager.apply_effects(eff, character_id())
	var nxt := str(o.get("next", "")) if ok else str(o.get("fail_next", o.get("next", "")))
	if nxt == "":
		end()
	else:
		_enter(nxt)
	return {"success": ok, "summary": summary}


## For nodes without options.
func advance() -> void:
	var n := current_node()
	if n.has("next"):
		_enter(str(n["next"]))
	else:
		end()


func is_end_node() -> bool:
	var n := current_node()
	return bool(n.get("end", false)) or (not n.has("next") and (n.get("options", []) as Array).is_empty())


func end() -> void:
	var id := current_id
	current_id = &""
	current_node_id = ""
	if id != &"":
		ended.emit(id)
		StoryManager.check()
		SaveManager.save_game()


func get_save_data() -> Dictionary:
	return {"choices": choices.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for c: Variant in data.get("choices", []):
		if c is Dictionary:
			choices.append(c)
