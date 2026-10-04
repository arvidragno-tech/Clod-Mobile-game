extends Node
## Loads every script and scene in the project (except tools/) so parse errors
## surface even in code the E2E run doesn't reach. Exit code 1 on failure.
## Usage: godot --headless --path . res://tests/compile_check.tscn


func _ready() -> void:
	var paths: Array[String] = []
	_walk("res://", paths)
	var bad := 0
	for p in paths:
		if load(p) == null:
			bad += 1
			print("FAILED ", p)
	print("compile check: %d files, %d failed" % [paths.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)


func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with(".") and sub != "tools":
			_walk(dir.path_join(sub), out)
