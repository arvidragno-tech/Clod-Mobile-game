extends Node
## Used by tests/runner_selftest.sh to prove tests/run_tests.sh catches what
## a suite's own checks can't: it prints the pass marker and exits 0 either way.
##   -- --case=clean     nothing wrong
##   -- --case=missing   loads a resource that doesn't exist (a missing asset)


func _ready() -> void:
	var which := "clean"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			which = arg.trim_prefix("--case=")
	if which == "missing":
		# Built at runtime so the compile check doesn't trip over it.
		var path := "res://assets/" + "missing_on_purpose.png"
		var r: Resource = load(path)
		print("loaded: ", r)
	print("SELFTEST PASSED")
	get_tree().quit(0)
