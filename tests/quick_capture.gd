extends Node
## Dev helper: boots the main scene, waits, saves a screenshot, quits.
## Usage: godot --path . res://tests/quick_capture.tscn -- --out=/path.png --wait=1.5

func _ready() -> void:
	var out := "user://capture.png"
	var wait := 1.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--wait="):
			wait = float(arg.trim_prefix("--wait="))
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
