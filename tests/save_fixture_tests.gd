extends RefCounted
## Saves written by earlier releases (tests/fixtures/saves, see its
## README for where each came from) load in this build with what they
## held: money, day, operations and level. A loaded old save saves and
## reloads again. Run by tests/test_runner.gd.

const FIXTURES := {
	"3.10.0": "res://tests/fixtures/saves/save_3.10.0.json",
	"3.11.0": "res://tests/fixtures/saves/save_3.11.0.json",
	"3.12.0": "res://tests/fixtures/saves/save_3.12.0.json",
}
const WORK := "user://fixture_tests"

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was_path := SaveManager.save_path
	var was_dir := SaveManager.save_dir
	DirAccess.make_dir_recursive_absolute(WORK)
	SaveManager.save_dir = WORK
	SaveManager.save_path = WORK + "/save.json"
	for v: String in FIXTURES:
		_check_fixture(v, FIXTURES[v])
	SaveManager.delete_save()
	SaveManager.save_path = was_path
	SaveManager.save_dir = was_dir
	SaveManager.reset_all()


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _check_fixture(v: String, path: String) -> void:
	SaveManager.delete_save()
	var text := FileAccess.get_file_as_string(path)
	check(text != "", "%s save fixture is in the repository" % v)
	var body := text.substr(0, text.rfind("\n#md5:"))
	var raw: Variant = JSON.parse_string(body)
	check(raw is Dictionary and (raw as Dictionary).has("systems"), "%s save fixture is a save" % v)
	if not raw is Dictionary:
		return
	var meta: Dictionary = raw.get("meta", {})
	var day := int(raw["systems"].get("BusinessManager", {}).get("day", -1))
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	check(SaveManager.load_game(), "%s save loads in this build" % v)
	check(EconomyManager.money == int(meta["money"]) and EventManager.operations == int(meta["ops"]) and ProgressionManager.level == int(meta["level"])
		and BusinessManager.day == day, "%s save: money %d, %d operations, level %d and day %d come back (got %d, %d, %d, day %d)"
		% [v, int(meta["money"]), int(meta["ops"]), int(meta["level"]), day, EconomyManager.money, EventManager.operations, ProgressionManager.level, BusinessManager.day])
	var money := EconomyManager.money
	check(SaveManager.save_game(&"manual"), "%s save: the loaded game saves" % v)
	SaveManager.reset_all()
	check(SaveManager.load_game() and EconomyManager.money == money and BusinessManager.day == day, "%s save: and reloads the same" % v)
