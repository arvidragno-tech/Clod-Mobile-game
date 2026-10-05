extends Node
## Local persistence. Each saveable system implements get_save_data(),
## load_save_data(data) and reset_state(); this manager collects them into one
## versioned JSON file in user:// (the app's sandboxed Documents dir on iOS).
## Writes go to a temp file first and the previous save is kept as a backup.
## Each file ends with an MD5 line over the JSON text, so a truncated or
## bit-flipped save is detected (and the backup / temp copy used instead).

const CHECKSUM_PREFIX := "\n#md5:"

signal save_failed(reason: String)

## Autoload names whose state is persisted, in load order.
const SAVEABLE_SYSTEMS: Array[String] = [
	"EconomyManager",
	"ReputationManager",
	"ProgressionManager",
	"FactionManager",
	"SkillManager",
	"ClinicManager",
	"WorldManager",
	"BusinessManager",
	"CharacterManager",
	"StaffManager",
	"QuestManager",
	"CommsManager",
	"DialogueManager",
	"CyberwareManager",
	"InventoryManager",
	"StoryManager",
	"EventManager",
	"BlackMarketManager",
	"CustomerManager",
	"MemoryManager",
	"PeopleManager",
	"StaffLifeManager",
	"TimeManager",
	"ClinicLifeManager",
	"WorldEventManager",
	"SupplierManager",
	"SecurityManager",
	"LocationManager",
	"WorldSimulationManager",
	"TutorialManager",
]

## Whether gameplay has started (so app-backgrounding should autosave).
var autosave_enabled: bool = false
var save_path: String = GameConfig.SAVE_PATH
var last_saved_unix: int = 0
## Active slot (1..SAVE_SLOTS); 0 = custom path (tests).
var slot: int = 0
## Folder holding the slot files (tests point this at a scratch folder).
var save_dir: String = GameConfig.SAVE_DIR


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	_migrate_legacy_file()
	use_slot(Settings.last_slot)


func slot_path(n: int) -> String:
	return "%s/slot_%d.json" % [save_dir, n]


func use_slot(n: int) -> void:
	slot = clampi(n, 1, GameConfig.SAVE_SLOTS)
	save_path = slot_path(slot)
	if Settings.last_slot != slot:
		Settings.set_value("last_slot", slot)


## Moves a pre-PC user://savegame.json (and backup) into slot 1 once.
func _migrate_legacy_file() -> void:
	if FileAccess.file_exists(GameConfig.SAVE_PATH) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.rename_absolute(GameConfig.SAVE_PATH, slot_path(1))
		if FileAccess.file_exists(GameConfig.SAVE_PATH + ".bak"):
			DirAccess.rename_absolute(GameConfig.SAVE_PATH + ".bak", slot_path(1) + ".bak")


## Summary of a slot for the Load screen ({} if empty / unreadable).
func get_slot_info(n: int) -> Dictionary:
	var path := slot_path(n)
	var data := _read_save(path)
	if data.is_empty():
		data = _read_save(path + ".bak")
	if data.is_empty():
		return {}
	var meta: Dictionary = data.get("meta", {})
	var sys: Dictionary = data.get("systems", {})
	if meta.is_empty():
		meta = {"money": int(sys.get("EconomyManager", {}).get("money", 0))}
	meta["saved_at"] = int(data.get("saved_at", 0))
	meta["version"] = int(data.get("version", 0))
	return meta


## Most recently written slot (0 if none).
func latest_slot() -> int:
	var best := 0
	var best_t := -1
	for n in range(1, GameConfig.SAVE_SLOTS + 1):
		var info := get_slot_info(n)
		if not info.is_empty() and int(info["saved_at"]) > best_t:
			best_t = int(info["saved_at"])
			best = n
	return best


func has_any_save() -> bool:
	return latest_slot() > 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			# Never persist a half-finished operation; the last save is from
			# before it started, which is the state the player returns to.
			if autosave_enabled and not SurgeryManager.is_active:
				save_game(&"manual")


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_backup_path()) or FileAccess.file_exists(_tmp_path())


## reason: &"auto" (after jobs / purchases), &"night" (closing the clinic),
## &"manual" (quick save, pause menu, quitting). Settings.autosave decides
## which automatic saves happen: 0 off, 1 every job, 2 nightly only.
func save_game(reason: StringName = &"auto") -> bool:
	if reason == &"auto" and Settings.autosave != 1:
		return false
	if reason == &"night" and Settings.autosave == 0:
		return false
	return _write_save()


func _write_save() -> bool:
	var systems := {}
	for system_name in SAVEABLE_SYSTEMS:
		var system := _get_system(system_name)
		if system:
			systems[system_name] = system.call("get_save_data")
	last_saved_unix = int(Time.get_unix_time_from_system())
	var payload := {
		"version": GameConfig.SAVE_VERSION,
		"saved_at": last_saved_unix,
		"meta": {
			"money": EconomyManager.money, "level": ProgressionManager.level, "rep": ReputationManager.reputation,
			"ops": EventManager.operations, "clinic": ClinicManager.get_tier_name(),
		},
		"systems": systems,
	}
	var tmp := _tmp_path()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		var reason := error_string(FileAccess.get_open_error())
		push_error("SaveManager: cannot write '%s' (%s)" % [tmp, reason])
		save_failed.emit(reason)
		return false
	var text := JSON.stringify(payload, "\t")
	file.store_string(text + CHECKSUM_PREFIX + text.md5_text())
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		save_failed.emit(error_string(write_error))
		return false
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
		# Killed between writing the temp file and swapping it in.
		data = _read_save(_tmp_path())
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
	var mark := text.rfind(CHECKSUM_PREFIX)
	if mark != -1:
		var body := text.substr(0, mark)
		if text.substr(mark + CHECKSUM_PREFIX.length()).strip_edges() != body.md5_text():
			push_warning("SaveManager: '%s' failed its checksum, ignoring" % path)
			return {}
		text = body
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
		systems["ClinicManager"] = {"tier": 1}  # legacy tier index (mapped in v4)
		var ops := 0
		for rec: Variant in systems.get("ProgressionManager", {}).get("surgery_records", {}).values():
			ops += int(rec.get("completed", 0)) + int(rec.get("failed", 0))
		systems["EventManager"] = {"operations": ops}
		var cm: Dictionary = systems.get("CustomerManager", {})
		if cm.has("current_customer"):
			cm["current"] = cm["current_customer"]
		systems["CustomerManager"] = cm
		data["systems"] = systems
	if version < 3:
		# v2 -> v3: settings moved to user://settings.cfg; the tutorial is
		# new, so existing players count as having finished it.
		systems.erase("AudioManager")
		systems["TutorialManager"] = {"completed": true, "active": false, "step": -1}
		data["systems"] = systems
	if version < 4:
		# v3 -> v4: six clinic tiers became seven purchasable clinics in
		# districts (ClinicManager maps the old tier); business days, the
		# world, characters, staff, story acts and quests are new and start
		# from their defaults.
		systems["ClinicManager"] = ClinicManager.migrate_legacy(systems.get("ClinicManager", {}))
		data["systems"] = systems
	if version < 5:
		# v4 -> v5: the living world (people, memories, staff lives, the
		# clock, the waiting room and wall, world events, suppliers, security)
		# is new and starts from its defaults; patients from the old clinic
		# log are remembered as people you've met.
		var people := {}
		for h: Variant in systems.get("CustomerManager", {}).get("history", []):
			if h is Dictionary and str(h.get("character", "")) == "":
				var uid := str(h.get("uid", ""))
				if uid != "" and not people.has(uid):
					people[uid] = {"id": uid, "name": str(h.get("name", "")).get_slice(" \"", 0), "rel": 5, "visits": int(h.get("visits", 1)),
						"faction": str(h.get("faction", "")), "status": "alive" if str(h.get("outcome", "")) != "flatline" else "dead",
						"history": ["Treated before the clinic kept proper files."], "links": {}, "cyber": [], "traits": [], "appearance": {},
						"paid_total": 0, "last_price": 0, "loyal": false, "first_day": 1, "last_day": 1, "dependency": 0, "favor": false,
						"next_day": -1, "refused": 0, "finance": "working", "wealth": 1, "archetype": "civilian", "occupation": "", "age": 30, "alias": "", "personality": "calm"}
		if not people.is_empty() and not systems.has("PeopleManager"):
			systems["PeopleManager"] = {"people": people, "debts": [], "next_debt": 1}
		data["systems"] = systems
	data["version"] = GameConfig.SAVE_VERSION
	return data


func _get_system(system_name: String) -> Node:
	return get_node_or_null("/root/" + system_name)


func _tmp_path() -> String:
	return save_path + ".tmp"


func _backup_path() -> String:
	return save_path + ".bak"
