extends Node
## Cyberware catalogue and which implants the player has unlocked.

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


func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


func unlock(id: StringName) -> void:
	if catalog.has(id) and not unlocked.has(id):
		unlocked.append(id)
		EventBus.cyberware_unlocked.emit(id)


## Implants visible in the clinic supply terminal.
func get_supply_catalog() -> Array[CyberwareData]:
	var out: Array[CyberwareData] = []
	for item: CyberwareData in catalog.values():
		if is_unlocked(item.id) and not item.black_market:
			out.append(item)
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
