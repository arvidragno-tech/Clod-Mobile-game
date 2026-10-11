extends Node
## Skill tree: points earned per level, spent on ranks; ranks feed
## ModifierManager.

var categories: Array[Dictionary] = []
var skills: Dictionary = {}  # StringName -> Dictionary
var order: Array[StringName] = []
var ranks: Dictionary = {}  # StringName -> int
var points: int = 0


func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(GameConfig.DATA_SKILLS)
	if typeof(parsed) == TYPE_DICTIONARY:
		for c: Variant in parsed.get("categories", []):
			categories.append(c)
		for s: Variant in parsed.get("skills", []):
			var id := StringName(str(s["id"]))
			skills[id] = s
			order.append(id)
	EventBus.level_up.connect(_on_level_up)
	reset_state()


func reset_state() -> void:
	ranks.clear()
	points = GameConfig.STARTING_SKILL_POINTS


func get_skill(id: StringName) -> Dictionary:
	return skills.get(id, {})


func get_rank(id: StringName) -> int:
	return int(ranks.get(id, 0))


func get_skills_in(category: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if StringName(str(skills[id]["category"])) == category:
			out.append(id)
	return out


func next_cost(id: StringName) -> int:
	var s := get_skill(id)
	var r := get_rank(id)
	var costs: Array = s.get("costs", [1])
	return int(costs[r]) if r < costs.size() else -1


## "" if upgradable, otherwise the reason.
func get_block_reason(id: StringName) -> String:
	var s := get_skill(id)
	if s.is_empty():
		return "Unknown skill"
	if get_rank(id) >= int(s.get("max_rank", 3)):
		return "Maxed"
	if ProgressionManager.level < int(s.get("unlock_level", 1)):
		return "Requires LV %d" % int(s["unlock_level"])
	if points < next_cost(id):
		return "Need %d point%s" % [next_cost(id), "s" if next_cost(id) > 1 else ""]
	return ""


func upgrade(id: StringName) -> bool:
	if get_block_reason(id) != "":
		return false
	points -= next_cost(id)
	ranks[id] = get_rank(id) + 1
	EventBus.skills_changed.emit()
	EventBus.modifiers_changed.emit()
	return true


func add_points(n: int) -> void:
	points += n
	EventBus.skills_changed.emit()


func get_modifiers() -> Dictionary:
	var out := {}
	for id: StringName in ranks:
		var r := get_rank(id)
		var eff: Dictionary = get_skill(id).get("effect_per_rank", {})
		for key: Variant in eff:
			out[key] = float(out.get(key, 0.0)) + float(eff[key]) * r
	return out


func _on_level_up(_lvl: int) -> void:
	add_points(GameConfig.SKILL_POINTS_PER_LEVEL)


func get_save_data() -> Dictionary:
	var r := {}
	for id: StringName in ranks:
		r[String(id)] = ranks[id]
	return {"ranks": r, "points": points}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	points = int(data.get("points", GameConfig.STARTING_SKILL_POINTS))
	var r: Dictionary = data.get("ranks", {})
	for key: Variant in r:
		if skills.has(StringName(str(key))):
			ranks[StringName(str(key))] = int(r[key])
	EventBus.modifiers_changed.emit()
