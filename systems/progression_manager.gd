extends Node
## XP, levels and the record of completed operations.

var total_xp: int = 0
var level: int = 1
## surgery_id (String) -> {"completed": int, "failed": int, "best_grade": String}
var surgery_records: Dictionary = {}
var customers_served: int = 0


func _ready() -> void:
	reset_state()


func reset_state() -> void:
	total_xp = 0
	level = 1
	surgery_records = {}
	customers_served = 0


static func xp_required_for_level(target_level: int) -> int:
	## Total XP needed to *reach* target_level from level 1.
	var total := 0
	for l in range(1, target_level):
		total += GameConfig.XP_BASE_TO_LEVEL + GameConfig.XP_GROWTH_PER_LEVEL * (l - 1)
	return total


func get_xp_into_level() -> int:
	return total_xp - xp_required_for_level(level)


func get_xp_for_next_level() -> int:
	return xp_required_for_level(level + 1) - xp_required_for_level(level)


func get_level_progress() -> float:
	return clampf(float(get_xp_into_level()) / float(maxi(get_xp_for_next_level(), 1)), 0.0, 1.0)


## Adds XP and returns the number of levels gained.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	total_xp += amount
	var gained := 0
	while total_xp >= xp_required_for_level(level + 1):
		level += 1
		gained += 1
		EventBus.level_up.emit(level)
	EventBus.xp_changed.emit(total_xp, level)
	return gained


func record_surgery(surgery_id: StringName, success: bool, grade: String) -> void:
	var key := String(surgery_id)
	var rec: Dictionary = surgery_records.get(key, {"completed": 0, "failed": 0, "best_grade": ""})
	if success:
		rec["completed"] = int(rec["completed"]) + 1
		if _grade_rank(grade) > _grade_rank(str(rec["best_grade"])):
			rec["best_grade"] = grade
	else:
		rec["failed"] = int(rec["failed"]) + 1
	surgery_records[key] = rec
	customers_served += 1


func get_total_completed() -> int:
	var total := 0
	for rec: Dictionary in surgery_records.values():
		total += int(rec.get("completed", 0))
	return total


static func _grade_rank(grade: String) -> int:
	return ["", "F", "D", "C", "B", "A", "S"].find(grade)


func get_save_data() -> Dictionary:
	return {
		"total_xp": total_xp,
		"level": level,
		"surgery_records": surgery_records,
		"customers_served": customers_served,
	}


func load_save_data(data: Dictionary) -> void:
	total_xp = int(data.get("total_xp", 0))
	level = maxi(int(data.get("level", 1)), 1)
	var records: Variant = data.get("surgery_records", {})
	surgery_records = records if typeof(records) == TYPE_DICTIONARY else {}
	customers_served = int(data.get("customers_served", 0))
	EventBus.xp_changed.emit(total_xp, level)
