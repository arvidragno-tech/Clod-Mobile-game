extends Node
## Cyberware catalogue and tier availability (player level + clinic tier).

var catalog: Dictionary = {}  # StringName -> CyberwareData
var unlocked: Array[StringName] = []


func _ready() -> void:
	_load_catalog()
	reset_state()


func _load_catalog() -> void:
	catalog.clear()
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_CYBERWARE, "cyberware"):
		var item := CyberwareData.from_dict(entry)
		catalog[item.id] = item


func reset_state() -> void:
	unlocked = GameConfig.STARTING_UNLOCKED_CYBERWARE.duplicate()


func get_cyberware(id: StringName) -> CyberwareData:
	return catalog.get(id) as CyberwareData


func is_valid(id: StringName) -> bool:
	var c := get_cyberware(id)
	return c != null and SurgeryManager.get_surgery(c.install_surgery_id) != null


## Highest tier the player can buy/attract: limited by level (XP) and clinic.
func get_available_tier() -> int:
	var by_level := 1
	for t: int in GameConfig.CYBERWARE_TIER_LEVEL:
		if ProgressionManager.level >= int(GameConfig.CYBERWARE_TIER_LEVEL[t]):
			by_level = maxi(by_level, t)
	return mini(by_level, ClinicManager.get_max_cyberware_tier())


func is_tier_available(tier: int) -> bool:
	return tier <= get_available_tier()


func is_unlocked(id: StringName) -> bool:
	var c := get_cyberware(id)
	return c != null and (unlocked.has(id) or (not c.black_market and is_tier_available(c.tier)))


func unlock(id: StringName) -> void:
	if catalog.has(id) and not unlocked.has(id):
		unlocked.append(id)
		EventBus.cyberware_unlocked.emit(id)


func get_by_category(category: StringName, max_tier: int = 99, include_bm: bool = false) -> Array[CyberwareData]:
	var out: Array[CyberwareData] = []
	for c: CyberwareData in catalog.values():
		if c.category == category and c.tier <= max_tier and (include_bm or not c.black_market):
			out.append(c)
	return out


## Implants sold at the regular supply terminal.
func get_supply_catalog(include_locked: bool = false) -> Array[CyberwareData]:
	var out: Array[CyberwareData] = []
	for c: CyberwareData in catalog.values():
		if not c.black_market and (include_locked or is_tier_available(c.tier)):
			out.append(c)
	out.sort_custom(func(a: CyberwareData, b: CyberwareData) -> bool: return a.tier < b.tier or (a.tier == b.tier and a.price < b.price))
	return out


func get_save_data() -> Dictionary:
	var ids: Array[String] = []
	for id in unlocked:
		ids.append(String(id))
	return {"unlocked": ids}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for id: Variant in data.get("unlocked", []):
		var sid := StringName(str(id))
		if catalog.has(sid) and not unlocked.has(sid):
			unlocked.append(sid)
