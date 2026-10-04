extends SceneTree
## Generates res://ui/theme/main_theme.tres from code so the visual language
## (palette, pixel-art 9-slice frames, fonts) is defined in one place.
## Frame textures come from tools/art/ui_art.py (drawn at 2x = game density).
## Run:  godot --headless --path . --script res://tools/build_theme.gd

const P := preload("res://scripts/core/palette.gd")
const OUT_PATH := "res://ui/theme/main_theme.tres"
const FRAMES := "res://assets/sprites/ui/frames/"
## Texture margins in texture pixels (= 2x art pixels).
const PANEL_MARGIN := 12
const BUTTON_MARGIN := 8

var theme := Theme.new()
var font_body: FontFile
var font_body_bold: FontFile
var font_title: FontFile
var font_mono: FontFile


func _init() -> void:
	font_body = load("res://assets/fonts/pixelify_sans_regular.woff2")
	font_body_bold = load("res://assets/fonts/pixelify_sans_bold.woff2")
	font_title = load("res://assets/fonts/silkscreen_bold.woff2")
	font_mono = load("res://assets/fonts/vt323_regular.woff2")
	theme.default_font = font_body
	theme.default_font_size = 17
	_build_panels()
	_build_buttons()
	_build_labels()
	_build_misc()
	var err := ResourceSaver.save(theme, OUT_PATH)
	print("Theme saved to %s (%s)" % [OUT_PATH, error_string(err)])
	quit(0 if err == OK else 1)


func tex_box(name: String, margin: int, content: Vector4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(FRAMES + name + ".png")
	s.texture_margin_left = margin
	s.texture_margin_top = margin
	s.texture_margin_right = margin
	s.texture_margin_bottom = margin
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	return s


func panel(type: StringName, frame: String, content := Vector4(12, 12, 12, 12)) -> void:
	if type != &"PanelContainer" and type != &"Panel":
		theme.set_type_variation(type, &"PanelContainer")
	theme.set_stylebox(&"panel", type, tex_box(frame, PANEL_MARGIN, content))


func _build_panels() -> void:
	panel(&"Panel", "panel")
	panel(&"PanelContainer", "panel")
	panel(&"AccentPanel", "panel_accent")
	panel(&"CardPanel", "panel_card", Vector4(10, 8, 10, 8))
	panel(&"DangerPanel", "panel_danger", Vector4(12, 8, 12, 8))
	panel(&"ToastPanel", "panel_toast", Vector4(12, 8, 12, 8))
	panel(&"HudPanel", "panel_hud", Vector4(8, 6, 8, 6))
	panel(&"BMPanel", "panel_bm")
	panel(&"BMCardPanel", "panel_bm_card", Vector4(10, 8, 10, 8))
	panel(&"GreenPanel", "panel_green")
	theme.set_type_variation(&"FlatPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"FlatPanel", StyleBoxEmpty.new())


func button(type: StringName, frame: String, font: Color, font_pressed: Color, content := Vector4(14, 12, 14, 12)) -> void:
	if type != &"Button":
		theme.set_type_variation(type, &"Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(StringName(state), type, tex_box("%s_%s" % [frame, state], BUTTON_MARGIN, content))
	theme.set_stylebox(&"hover_pressed", type, tex_box(frame + "_pressed", BUTTON_MARGIN, content))
	theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())
	theme.set_color(&"font_color", type, font)
	theme.set_color(&"font_hover_color", type, font)
	theme.set_color(&"font_focus_color", type, font)
	theme.set_color(&"font_pressed_color", type, font_pressed)
	theme.set_color(&"font_hover_pressed_color", type, font_pressed)
	theme.set_color(&"font_disabled_color", type, P.TEXT_DIM)
	for c in ["icon_normal_color", "icon_pressed_color", "icon_hover_color", "icon_hover_pressed_color", "icon_focus_color"]:
		theme.set_color(StringName(c), type, Color.WHITE)
	theme.set_color(&"icon_disabled_color", type, Color(1, 1, 1, 0.35))


func _build_buttons() -> void:
	button(&"Button", "btn", P.TEXT, P.ACCENT)
	theme.set_font(&"font", &"Button", font_title)
	theme.set_font_size(&"font_size", &"Button", 16)
	theme.set_constant(&"h_separation", &"Button", 8)
	button(&"AccentButton", "btn_accent", P.TEXT_DARK, P.TEXT_DARK)
	button(&"BrandButton", "btn_brand", P.TEXT_DARK, P.TEXT)
	button(&"DangerButton", "btn_danger", P.TEXT, P.TEXT_DARK)
	button(&"GhostButton", "btn_ghost", P.TEXT_DIM, P.ACCENT)
	# Square icon-sized danger button (abort): tight padding keeps it 44px.
	button(&"CompactDangerButton", "btn_danger", P.TEXT, P.TEXT_DARK, Vector4(4, 4, 4, 4))
	button(&"BMButton", "btn_bm", Color("ffb0cc"), P.TEXT_DARK)
	button(&"ToolButton", "btn_tool", P.TEXT_DIM, P.ACCENT, Vector4(4, 4, 4, 4))
	theme.set_font(&"font", &"ToolButton", font_mono)
	theme.set_font_size(&"font_size", &"ToolButton", 18)
	button(&"QuickButton", "btn_quick", P.WARN, P.TEXT, Vector4(6, 4, 6, 6))
	theme.set_font(&"font", &"QuickButton", font_body_bold)
	theme.set_font_size(&"font_size", &"QuickButton", 13)
	button(&"NavButton", "btn_ghost", P.TEXT_DIM, P.ACCENT, Vector4(2, 6, 2, 4))
	theme.set_font(&"font", &"NavButton", font_body_bold)
	theme.set_font_size(&"font_size", &"NavButton", 11)
	theme.set_constant(&"h_separation", &"NavButton", 0)
	button(&"TabButton", "btn_tool", P.TEXT_DIM, P.ACCENT, Vector4(6, 8, 6, 8))
	theme.set_font(&"font", &"TabButton", font_body_bold)
	theme.set_font_size(&"font_size", &"TabButton", 12)


func label(type: StringName, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(type, &"Label")
	if font:
		theme.set_font(&"font", type, font)
	theme.set_font_size(&"font_size", type, size)
	theme.set_color(&"font_color", type, color)


func _build_labels() -> void:
	theme.set_color(&"font_color", &"Label", P.TEXT)
	theme.set_constant(&"line_spacing", &"Label", 2)
	label(&"TitleLabel", font_title, 40, P.ACCENT)
	theme.set_color(&"font_shadow_color", &"TitleLabel", Color(P.ACCENT_DIM, 0.6))
	theme.set_constant(&"shadow_offset_x", &"TitleLabel", 0)
	theme.set_constant(&"shadow_offset_y", &"TitleLabel", 4)
	label(&"HeaderLabel", font_title, 16, P.ACCENT)
	label(&"SubHeaderLabel", font_body_bold, 12, P.TEXT_DIM)
	label(&"DimLabel", null, 15, P.TEXT_DIM)
	label(&"MonoLabel", font_mono, 22, P.TEXT)
	label(&"BigMonoLabel", font_mono, 36, P.ACCENT)
	# Silkscreen at its native 8px: used for text drawn inside the pixel field.
	label(&"PixelLabel", font_title, 8, P.TEXT)
	label(&"BMLabel", font_title, 16, P.BRAND)
	theme.set_font(&"normal_font", &"RichTextLabel", font_body)
	theme.set_font(&"mono_font", &"RichTextLabel", font_mono)
	theme.set_font(&"bold_font", &"RichTextLabel", font_body_bold)
	theme.set_color(&"default_color", &"RichTextLabel", P.TEXT)
	theme.set_font_size(&"normal_font_size", &"RichTextLabel", 16)
	theme.set_font_size(&"bold_font_size", &"RichTextLabel", 16)
	theme.set_font_size(&"mono_font_size", &"RichTextLabel", 20)


func _build_misc() -> void:
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = P.BG_1
	bar_bg.border_color = P.LINE
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = P.ACCENT
	theme.set_stylebox(&"background", &"ProgressBar", bar_bg)
	theme.set_stylebox(&"fill", &"ProgressBar", bar_fill)
	theme.set_font(&"font", &"ProgressBar", font_mono)
	theme.set_font_size(&"font_size", &"ProgressBar", 16)

	var sep := StyleBoxLine.new()
	sep.color = P.LINE
	sep.thickness = 2
	theme.set_stylebox(&"separator", &"HSeparator", sep)
	theme.set_constant(&"separation", &"HSeparator", 8)

	var grab := StyleBoxFlat.new()
	grab.bg_color = P.LINE_HI
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(StringName(s), &"VScrollBar", grab)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(P.BG_1, 0.5)
	track.content_margin_left = 2
	track.content_margin_right = 2
	theme.set_stylebox(&"scroll", &"VScrollBar", track)

	theme.set_constant(&"separation", &"VBoxContainer", 8)
	theme.set_constant(&"separation", &"HBoxContainer", 8)
