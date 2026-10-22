extends RefCounted
## Each manager owns its state: no other script assigns to the debt, the
## day or the cash drawer, or to who is at the door. They ask the owner
## (BusinessManager.charge / add_debt, EconomyManager.spend / add_money,
## CustomerManager.take_from_door / quiet_for). Scans the game's scripts.
## Run by tests/test_runner.gd.

const OWNED := {
	"BusinessManager": ["debt", "day", "jobs_today", "today", "days_in_debt"],
	"EconomyManager": ["money"],
	"CustomerManager": ["current_customer", "quiet_until", "visits_today"],
}

var t: Node


func run(runner: Node) -> void:
	t = runner
	var hits: Array[String] = []
	for dir in ["res://systems", "res://scripts"]:
		_scan(dir, hits)
	t.check(hits.is_empty(), "no script writes another manager's money, debt or door state %s" % str(hits))


func _scan(dir: String, hits: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			_scan_file(dir.path_join(f), hits)
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), hits)


func _scan_file(path: String, hits: Array[String]) -> void:
	var src := FileAccess.get_file_as_string(path)
	for owner: String in OWNED:
		if path.get_file() == owner.to_snake_case() + ".gd":
			continue  # the owner itself
		for field: String in OWNED[owner]:
			var re := RegEx.create_from_string("\\b%s\\.%s\\s*([-+*/]?=)(?!=)" % [owner, field])
			for _m in re.search_all(src):
				hits.append("%s: %s.%s" % [path.get_file(), owner, field])
