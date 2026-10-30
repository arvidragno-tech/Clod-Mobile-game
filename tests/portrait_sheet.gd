extends Node
## Contact sheet of character art for review (not a test): the cast and a
## dozen generated customers, portrait (FACE x3 density) + expression row.
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/portrait_sheet.tscn -- --out=/abs/file.png

var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	get_window().size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color("0b0d12")
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(12, 12)
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	add_child(grid)
	var ids: Array[StringName] = []
	for id: StringName in CharacterManager.cast:
		ids.append(id)
	var n := 0
	for id in ids:
		if n >= 10:
			break
		var p := PixelPortrait.new()
		p.framing = PixelPortrait.Framing.FACE
		grid.add_child(p)
		p.set_character(id)
		n += 1
	for i in 14:
		var c := CustomerManager.generator.generate({})
		var p := PixelPortrait.new()
		p.framing = PixelPortrait.Framing.FACE
		grid.add_child(p)
		p.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
	# Bodies (the in-room sprite) at 4x, same people.
	var row := HBoxContainer.new()
	row.position = Vector2(12, 700)
	row.add_theme_constant_override(&"separation", 14)
	add_child(row)
	var apps: Array = []
	for id in ids.slice(0, 10):
		apps.append(CharacterManager.appearance(id))
	for i in 12:
		apps.append(CustomerManager.generator.generate({}).appearance)
	for app: Dictionary in apps:
		var t := TextureRect.new()
		t.texture = CharacterArt.body(CharacterAppearanceManager.normalize(app))
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.custom_minimum_size = Vector2(CharacterArt.size_of(&"body")) * 2.0 * GameConfig.BODY_ART_W / float(CharacterArt.size_of(&"body").x)
		row.add_child(t)
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img and _out != "":
		img.save_png(_out)
	print("sheet saved")
	get_tree().quit()
