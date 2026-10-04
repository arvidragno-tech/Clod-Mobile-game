extends Node
## Local persistence. Each saveable system implements get_save_data(),
## load_save_data(data) and reset_state(); this manager collects them into one
## versioned JSON file in user:// (the app's sandboxed Documents dir on iOS).
## Writes go to a temp file first and the previous save is kept as a backup.

## Autoload names whose state is persisted, in load order.
const SAVEABLE_SYSTEMS: Array[String] = [
	"EconomyManager",
	"ReputationManager",
	"ProgressionManager",
	"FactionManager",
	"SkillManager",
	"ClinicManager",
	"CyberwareManager",
	"InventoryManager",
	"StoryManager",
	"EventManager",
	"BlackMarketManager",
	"CustomerManager",
	"AudioManager",
]

## Whether gameplay has started (so app-backgrounding should autosave).
var autosave_enabled: bool = false
var save_path: String = GameConfig.SAVE_PATH
var last_saved_unix: int = 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			# Never persist a half-finished operation; the last save is from
			# before it started, which is the state the player returns to.
			if autosave_enabled and not SurgeryManager.is_active:
				save_game()


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_backup_path())


func save_game() -> bool:
	var systems := {}
	for system_name in SAVEABLE_SYSTEMS:
		var system := _get_system(system_name)
		if system:
			systems[system_name] = system.call("get_save_data")
	last_saved_unix = int(Time.get_unix_time_from_system())
	var payload := {
		"version": GameConfig.SAVE_VERSION,
		"saved_at": last_saved_unix,
		"systems": systems,
	}
	var tmp := _tmp_path()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write '%s' (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(_backup_path())
		DirAccess.rename_absolute(save_path, _backup_path())
	var err := DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		push_error("SaveManager: rename failed (%s)" % error_string(err))
		return false
	EventBus.game_saved.emit()
	return true


## Loads the save (falling back to the backup). Returns false if none usable.
func load_game() -> bool:
	var data := _read_save(save_path)
	if data.is_empty():
		data = _read_save(_backup_path())
	if data.is_empty():
		return false
	data = _migrate(data)
	reset_all()
	var systems: Dictionary = data.get("systems", {})
	for system_name in SAVEABLE_SYSTEMS:
		var system := _get_system(system_name)
		var system_data: Variant = systems.get(system_name, {})
		if system and typeof(system_data) == TYPE_DICTIONARY:
			system.call("load_save_data", system_data)
	last_saved_unix = int(data.get("saved_at", 0))
	EventBus.game_loaded.emit()
	return true


func reset_all() -> void:
	for system_name in SAVEABLE_SYSTEMS:
		var system := _get_system(system_name)
		if system and system.has_method("reset_state"):
			system.call("reset_state")


func delete_save() -> void:
	for path in [save_path, _backup_path(), _tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("systems"):
		push_warning("SaveManager: '%s' is corrupt, ignoring" % path)
		return {}
	return parsed


## Upgrades older save formats to SAVE_VERSION. Add steps here as the format
## evolves; never silently drop player progress.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > GameConfig.SAVE_VERSION:
		push_warning("SaveManager: save is from a newer version (%d)" % version)
	var systems: Dictionary = data.get("systems", {})
	if version < 2:
		# v1 -> v2: count-based implant stock became individual units, the
		# Step 1 clinic was the Backroom tier, resources were introduced.
		var inv: Dictionary = systems.get("InventoryManager", {})
		var units := []
		var stock: Dictionary = inv.get("implant_stock", {})
		for id: Variant in stock:
			for i in int(stock[id]):
				units.append({"uid": "imp_v1_%s_%d" % [id, i], "id": str(id), "condition": 100.0, "traits": [], "revealed": [], "source": "supply"})
		inv["instances"] = units
		inv.erase("implant_stock")
		inv["supplies"] = GameConfig.STARTING_SUPPLIES
		systems["InventoryManager"] = inv
		systems["ClinicManager"] = {"tier": 1}
		var ops := 0
		for rec: Variant in systems.get("ProgressionManager", {}).get("surgery_records", {}).values():
			ops += int(rec.get("completed", 0)) + int(rec.get("failed", 0))
		systems["EventManager"] = {"operations": ops}
		var cm: Dictionary = systems.get("CustomerManager", {})
		if cm.has("current_customer"):
			cm["current"] = cm["current_customer"]
		systems["CustomerManager"] = cm
		data["systems"] = systems
	data["version"] = GameConfig.SAVE_VERSION
	return data


func _get_system(system_name: String) -> Node:
	return get_node_or_null("/root/" + system_name)


func _tmp_path() -> String:
	return save_path + ".tmp"


func _backup_path() -> String:
	return save_path + ".bak"
