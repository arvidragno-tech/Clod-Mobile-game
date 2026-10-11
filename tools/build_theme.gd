extends SceneTree
## Generates res://ui/theme/main_theme.tres from code so the visual language
## (palette, pixel-art 9-slice frames, fonts) is defined in one place.
## Frame textures come from tools/art/ui_art.py (drawn at 2x = game density).
## Run:  godot --headless --path . --script res://tools/build_theme.gd

const P := preload("res://scripts/core/palette.gd")
const OUT_PATH := "res://ui/theme/main_theme.tres"
const FRAMES := "res://assets/sprites/ui/frames/"
## Texture margins in texture pixels (= 3x art pixels, the PC density).
const PANEL_MARGIN := 18
const BUTTON_MARGIN := 12

var theme := Theme.new()
var font_body: Font
var font_body_bold: Font
var font_title: Font
var font_mono: Font
## Keyboard focus ring: a hard 2 px cyan outline just outside the control.
var focus_box := StyleBoxFlat.new()


func _init() -> void:
	# Straight, squared and readable: Chakra Petch for text and titles,
	# Share Tech Mono for numbers; DejaVu Sans fills in symbols (✓ ≈ → ▲).
	font_body = _face("chakra_petch_medium.woff2", "ui_body.tres")
	font_body_bold = _face("chakra_petch_semibold.woff2", "ui_bold.tres")
	font_title = _face("chakra_petch_bold.woff2", "ui_title.tres", 1)
	font_mono = _face("share_tech_mono.woff2", "ui_mono.tres")
	focus_box.draw_center = false
	focus_box.anti_aliasing = false
	focus_box.border_color = P.ACCENT
	focus_box.set_border_width_all(2)
	focus_box.set_expand_margin_all(3)
	theme.default_font = font_body
	theme.default_font_size = 21
	_build_panels()
	_build_buttons()
	_build_labels()
	_build_misc()
	var err := ResourceSaver.save(theme, OUT_PATH)
	print("Theme saved to %s (%s)" % [OUT_PATH, error_string(err)])
	quit(0 if err == OK else 1)


## A font variation with the symbol fallback (and optional letter
## spacing), saved next to the font so the theme can reference it.
func _face(file: String, out: String, spacing: int = 0) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/" + file)
	fv.fallbacks = [load("res://assets/fonts/dejavu_sans_fallback.ttf")]
	if spacing != 0:
		fv.spacing_glyph = spacing
	var path := "res://assets/fonts/" + out
	ResourceSaver.save(fv, path)
	return load(path)


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


func panel(type: StringName, frame: String, content := Vector4(18, 16, 18, 16)) -> void:
	if type != &"PanelContainer" and type != &"Panel":
		theme.set_type_variation(type, &"PanelContainer")
	theme.set_stylebox(&"panel", type, tex_box(frame, PANEL_MARGIN, content))


func _build_panels() -> void:
	panel(&"Panel", "panel")
	panel(&"PanelContainer", "panel")
	panel(&"AccentPanel", "panel_accent")
	panel(&"CardPanel", "panel_card", Vector4(14, 12, 14, 12))
	panel(&"DangerPanel", "panel_danger", Vector4(16, 12, 16, 12))
	panel(&"ToastPanel", "panel_toast", Vector4(18, 10, 18, 10))
	panel(&"HudPanel", "panel_hud", Vector4(12, 9, 12, 9))
	panel(&"BMPanel", "panel_bm")
	panel(&"BMCardPanel", "panel_bm_card", Vector4(14, 12, 14, 12))
	panel(&"GreenPanel", "panel_green")
	theme.set_type_variation(&"FlatPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"FlatPanel", StyleBoxEmpty.new())


func button(type: StringName, frame: String, font: Color, font_pressed: Color, content := Vector4(18, 10, 18, 10)) -> void:
	if type != &"Button":
		theme.set_type_variation(type, &"Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(StringName(state), type, tex_box("%s_%s" % [frame, state], BUTTON_MARGIN, content))
	theme.set_stylebox(&"hover_pressed", type, tex_box(frame + "_pressed", BUTTON_MARGIN, content))
	theme.set_stylebox(&"focus", type, focus_box)
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
	# One readable face for every button (Silkscreen stays for titles).
	theme.set_font(&"font", &"Button", font_body_bold)
	theme.set_font_size(&"font_size", &"Button", 21)
	theme.set_constant(&"h_separation", &"Button", 8)
	theme.set_constant(&"outline_size", &"Button", 0)
	button(&"AccentButton", "btn_accent", P.TEXT_DARK, P.TEXT_DARK)
	button(&"BrandButton", "btn_brand", P.TEXT_DARK, P.TEXT)
	button(&"DangerButton", "btn_danger", P.TEXT, P.TEXT_DARK)
	button(&"GhostButton", "btn_ghost", P.TEXT_DIM, P.ACCENT)
	# Square icon-sized danger button (abort): tight padding keeps it 44px.
	button(&"CompactDangerButton", "btn_danger", P.TEXT, P.TEXT_DARK, Vector4(4, 4, 4, 4))
	button(&"BMButton", "btn_bm", Color("ffb0cc"), P.TEXT_DARK)
	button(&"ToolButton", "btn_tool", P.TEXT_DIM, P.ACCENT, Vector4(6, 6, 6, 6))
	theme.set_font(&"font", &"ToolButton", font_mono)
	theme.set_font_size(&"font_size", &"ToolButton", 21)
	button(&"QuickButton", "btn_quick", P.WARN, P.TEXT, Vector4(10, 6, 10, 8))
	theme.set_font(&"font", &"QuickButton", font_body_bold)
	theme.set_font_size(&"font_size", &"QuickButton", 18)
	button(&"NavButton", "btn_ghost", P.TEXT_DIM, P.ACCENT, Vector4(14, 8, 14, 8))
	theme.set_font(&"font", &"NavButton", font_body_bold)
	theme.set_font_size(&"font_size", &"NavButton", 18)
	theme.set_constant(&"h_separation", &"NavButton", 12)
	button(&"TabButton", "btn_tool", P.TEXT_DIM, P.ACCENT, Vector4(12, 8, 12, 8))
	theme.set_font(&"font", &"TabButton", font_body_bold)
	theme.set_font_size(&"font_size", &"TabButton", 18)
	for t in [&"AccentButton", &"BrandButton", &"DangerButton", &"GhostButton", &"CompactDangerButton", &"BMButton"]:
		theme.set_font(&"font", t, font_body_bold)
		theme.set_font_size(&"font_size", t, 21)
	# Help "?" chips and small info buttons.
	button(&"InfoButton", "btn_ghost", P.ACCENT, P.TEXT_DARK, Vector4(6, 2, 6, 2))
	theme.set_font(&"font", &"InfoButton", font_body_bold)
	theme.set_font_size(&"font_size", &"InfoButton", 16)


func label(type: StringName, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(type, &"Label")
	if font:
		theme.set_font(&"font", type, font)
	theme.set_font_size(&"font_size", type, size)
	theme.set_color(&"font_color", type, color)


func _build_labels() -> void:
	theme.set_color(&"font_color", &"Label", P.TEXT)
	theme.set_constant(&"line_spacing", &"Label", 2)
	label(&"TitleLabel", font_title, 66, P.ACCENT)
	theme.set_color(&"font_shadow_color", &"TitleLabel", Color(P.ACCENT_DIM, 0.6))
	theme.set_constant(&"shadow_offset_x", &"TitleLabel", 0)
	theme.set_constant(&"shadow_offset_y", &"TitleLabel", 6)
	label(&"HeaderLabel", font_title, 27, P.ACCENT)
	label(&"SubHeaderLabel", font_body_bold, 17, P.TEXT_DIM)
	label(&"DimLabel", null, 19, P.TEXT_DIM)
	label(&"MonoLabel", font_mono, 23, P.TEXT)
	label(&"BigMonoLabel", font_mono, 40, P.ACCENT)
	# Text drawn inside the pixel field (sizes are passed by the caller).
	label(&"PixelLabel", font_title, 14, P.TEXT)
	label(&"BMLabel", font_title, 26, P.BRAND)
	# Section titles (with a coloured bar from UIKit.section) and big values.
	label(&"SectionLabel", font_body_bold, 17, P.ACCENT)
	label(&"ValueLabel", font_mono, 30, P.TEXT)
	label(&"HintLabel", font_body, 17, P.TEXT_DIM)
	theme.set_font(&"normal_font", &"RichTextLabel", font_body)
	theme.set_font(&"mono_font", &"RichTextLabel", font_mono)
	theme.set_font(&"bold_font", &"RichTextLabel", font_body_bold)
	theme.set_color(&"default_color", &"RichTextLabel", P.TEXT)
	theme.set_font_size(&"normal_font_size", &"RichTextLabel", 21)
	theme.set_font_size(&"bold_font_size", &"RichTextLabel", 21)
	theme.set_font_size(&"mono_font_size", &"RichTextLabel", 22)


func _build_misc() -> void:
	var bar_bg := StyleBoxFlat.new()
	bar_bg.anti_aliasing = false
	bar_bg.bg_color = P.BG_1
	bar_bg.border_color = P.LINE
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.anti_aliasing = false
	bar_fill.bg_color = P.ACCENT
	theme.set_stylebox(&"background", &"ProgressBar", bar_bg)
	theme.set_stylebox(&"fill", &"ProgressBar", bar_fill)
	theme.set_font(&"font", &"ProgressBar", font_mono)
	theme.set_font_size(&"font_size", &"ProgressBar", 20)

	var sep := StyleBoxLine.new()
	sep.color = P.LINE
	sep.thickness = 2
	theme.set_stylebox(&"separator", &"HSeparator", sep)
	theme.set_constant(&"separation", &"HSeparator", 8)

	var grab := StyleBoxFlat.new()

	grab.anti_aliasing = false
	grab.bg_color = P.LINE_HI
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(StringName(s), &"VScrollBar", grab)
		theme.set_stylebox(StringName(s), &"HScrollBar", grab)
	var track := StyleBoxFlat.new()
	track.anti_aliasing = false
	track.bg_color = Color(P.BG_1, 0.5)
	track.content_margin_left = 2
	track.content_margin_right = 2
	theme.set_stylebox(&"scroll", &"VScrollBar", track)
	theme.set_stylebox(&"scroll", &"HScrollBar", track)
	# Tooltips (hover details on PC).
	var tip := StyleBoxFlat.new()
	tip.anti_aliasing = false
	tip.bg_color = Color("0b0f16")
	tip.border_color = P.ACCENT_DIM
	tip.set_border_width_all(2)
	tip.set_content_margin_all(10)
	theme.set_stylebox(&"panel", &"TooltipPanel", tip)
	theme.set_font_size(&"font_size", &"TooltipLabel", 19)
	theme.set_font(&"font", &"TooltipLabel", font_body)
	theme.set_color(&"font_color", &"TooltipLabel", P.TEXT)
	# Dropdowns and checkboxes for the PC settings.
	theme.set_font_size(&"font_size", &"OptionButton", 20)
	theme.set_font(&"font", &"OptionButton", font_body_bold)
	theme.set_font_size(&"font_size", &"PopupMenu", 20)
	var popup := StyleBoxFlat.new()
	popup.anti_aliasing = false
	popup.bg_color = Color("0d1017")
	popup.border_color = P.LINE_HI
	popup.set_border_width_all(2)
	popup.set_content_margin_all(6)
	theme.set_stylebox(&"panel", &"PopupMenu", popup)
	var hl := StyleBoxFlat.new()
	hl.anti_aliasing = false
	hl.bg_color = Color(P.ACCENT, 0.25)
	theme.set_stylebox(&"hover", &"PopupMenu", hl)

	# Pixel sliders (settings): thick track, chunky grabber, generous height.
	var slider_track := tex_box("slider_track", 2, Vector4(0, 6, 0, 6))
	var fill := tex_box("slider_fill", 2, Vector4(0, 6, 0, 6))
	theme.set_stylebox(&"slider", &"HSlider", slider_track)
	theme.set_stylebox(&"grabber_area", &"HSlider", fill)
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	theme.set_icon(&"grabber", &"HSlider", load(FRAMES + "grabber_normal.png"))
	theme.set_icon(&"grabber_highlight", &"HSlider", load(FRAMES + "grabber_hover.png"))
	theme.set_icon(&"grabber_disabled", &"HSlider", load(FRAMES + "grabber_normal.png"))
	theme.set_constant(&"center_grabber", &"HSlider", 0)
	theme.set_constant(&"grabber_offset", &"HSlider", 0)

	theme.set_constant(&"separation", &"VBoxContainer", 10)
	theme.set_constant(&"separation", &"HBoxContainer", 10)
