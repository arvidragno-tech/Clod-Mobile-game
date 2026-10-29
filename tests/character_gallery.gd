extends Control
## QA gallery: the story cast (portraits + in-room bodies) and a batch of
## generated customers, rendered through the real compositor at 3x.
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1920x1080 res://tests/character_gallery.tscn -- --out=/abs/file.png [--page=customers]

func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(1920, 1080)
	var out := "user://gallery.png"
	var page := "cast"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--page="):
			page = a.trim_prefix("--page=")
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.position = Vector2(20, 20)
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	add_child(grid)
	if page == "cast":
		grid.columns = 5
		for id: StringName in CharacterManager.cast:
			grid.add_child(_cell_cast(id))
	else:
		grid.columns = 8
		var gen := CustomerGenerator.new(RandomNumberGenerator.new())
		gen.rng.seed = int(page.trim_prefix("customers")) if page.length() > 9 else 7
		for i in 16:
			var c := gen.generate({"full_difficulty": true})
			grid.add_child(_cell_app(c.appearance, c.occupation, &"street"))
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


func _cell_cast(id: StringName) -> Control:
	var c := CharacterManager.get_character(id)
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	var p := PixelPortrait.new()
	p.framing = PixelPortrait.Framing.BUST
	row.add_child(p)
	p.set_character(id)
	row.add_child(_body(CharacterManager.appearance(id)))
	var l := UIKit.label("%s · %s" % [c.title(), c.occupation], &"SubHeaderLabel", true)
	l.custom_minimum_size.x = 360
	box.add_child(l)
	return box


func _cell_app(app: Dictionary, label: String, bg: StringName) -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	var p := PixelPortrait.new()
	p.framing = PixelPortrait.Framing.HEAD
	row.add_child(p)
	p.set_appearance(app, Palette.ACCENT, bg)
	row.add_child(_body(app))
	var l := UIKit.label(label, &"SubHeaderLabel", true)
	l.custom_minimum_size.x = 220
	box.add_child(l)
	return box


func _body(app: Dictionary) -> Control:
	var t := TextureRect.new()
	t.texture = CharacterArt.body(CharacterAppearanceManager.normalize(app))
	t.custom_minimum_size = Vector2(CharacterArt.size_of(&"body")) * GameConfig.ART_SCALE * GameConfig.BODY_ART_W / float(CharacterArt.size_of(&"body").x)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t
