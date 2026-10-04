extends Node
## Performance probe: visits every screen (and an active surgery) and reports
## screen load time, frame time, draw calls, node count and memory.
## Needs a real renderer (draw calls are 0 headless):
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/perf_probe.tscn
## Numbers from a CPU rasterizer (llvmpipe) are an upper bound; any real
## Windows GPU is far faster (see README "Performance").

const PERF_SAVE_PATH := "user://perf_savegame.json"
const SAMPLE_FRAMES := 120

var _rows: Array[String] = []


func _ready() -> void:
	var vp := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--viewport="):
			var parts := arg.trim_prefix("--viewport=").split("x")
			vp = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--effects="):
			Settings.effects_quality = int(arg.trim_prefix("--effects="))
	get_tree().root.content_scale_size = vp
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	SaveManager.save_dir = "user://test_saves"
	SaveManager.save_path = PERF_SAVE_PATH
	AudioManager.set_process(false)
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(10)
	GameManager.start_new_game()
	await _settle()
	StoryManager.set_flag(&"bm_access")
	EconomyManager.add_money(20000)
	print("effects quality: ", Settings.EFFECTS_NAMES[Settings.effects_quality])
	print("renderer: ", RenderingServer.get_video_adapter_name(), " / ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("%-14s %8s %8s %8s %7s %6s %8s %8s" % ["screen", "load ms", "avg ms", "max ms", "draws", "nodes", "mem MB", "tex MB"])
	for tier in [0, 5]:
		ClinicManager.tier = tier
		await _measure(&"clinic", "clinic_t%d" % tier)
	await _measure(&"shop", "shop")
	await _measure(&"inventory", "inventory")
	await _measure(&"database", "database")
	await _measure(&"black_market", "black_market")
	await _measure(&"clinic", "clinic")
	await _measure(&"black_market", "black_mkt 2nd")
	await _measure(&"skills", "skills")
	await _measure(&"upgrades", "upgrades")
	await _measure(&"dossier", "dossier")
	await _measure(&"settings", "settings")
	await _measure(&"main_menu", "main_menu")
	ClinicManager.tier = 0
	await _measure(&"clinic", "clinic")
	CustomerManager.debug_set_customer(CustomerManager.get_customer(&"mara_quill"))
	await _measure(&"customer", "customer")
	await _measure(&"diagnosis", "diagnosis")
	GameManager.submit_diagnosis(GameManager.get_current_customer().true_diagnosis_id)
	var t0 := Time.get_ticks_usec()
	GameManager.begin_surgery()
	await _settle()
	await _sample("surgery", (Time.get_ticks_usec() - t0) / 1000.0)
	print("\n".join(_rows))
	SurgeryManager.abort()
	SaveManager.delete_save()
	get_tree().quit()


func _measure(screen: StringName, label: String) -> void:
	var t0 := Time.get_ticks_usec()
	UIManager.go_to(screen)
	await _settle()
	await _sample(label, (Time.get_ticks_usec() - t0) / 1000.0)


## Waits for the screen transition (fades) to finish.
func _settle() -> void:
	await _frames(2)
	while UIManager.is_transitioning():
		await get_tree().process_frame
	await _frames(5)


func _sample(label: String, load_ms: float) -> void:
	# Load time includes the fixed fade-out/in tween; subtract it to get the
	# actual instantiate + build cost.
	var fades := (GameConfig.SCREEN_FADE_OUT_SEC + GameConfig.SCREEN_FADE_IN_SEC) * 1000.0
	var total := 0.0
	var worst := 0.0
	var draws := 0
	for i in SAMPLE_FRAMES:
		var t := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var dt := (Time.get_ticks_usec() - t) / 1000.0
		total += dt
		worst = maxf(worst, dt)
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_rows.append("%-14s %8.1f %8.2f %8.2f %7d %6d %8.1f %8.1f" % [label, maxf(0.0, load_ms - fades), total / SAMPLE_FRAMES, worst, draws, nodes, mem, tex])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
