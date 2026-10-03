extends SceneTree
## Generates res://ui/theme/main_theme.tres from code so the visual language
## (palette, chamfered pixel panels, fonts) is defined in one reviewable place.
## Run:  godot --headless --path . --script res://tools/build_theme.gd

const P := preload("res://scripts/core/palette.gd")
const OUT_PATH := "res://ui/theme/main_theme.tres"
const CHAMFER := 6

var theme := Theme.new()
var font_body: FontFile
var font_title: FontFile
var font_mono: FontFile


func _init() -> void:
	font_body = load("res://assets/fonts/pixelify_sans_regular.woff2")
	font_title = load("res://assets/fonts/silkscreen_bold.woff2")
	font_mono = load("res://assets/fonts/vt323_regular.woff2")
	theme.default_font = font_body
	theme.default_font_size = 18
	_build_panels()
	_build_buttons()
	_build_labels()
	_build_misc()
	var err := ResourceSaver.save(theme, OUT_PATH)
	print("Theme saved to %s (%s)" % [OUT_PATH, error_string(err)])
	quit(0 if err == OK else 1)


func box(bg: Color, border: Color, border_w: int = 2, margin: Vector4 = Vector4(12, 10, 12, 10), chamfer: int = CHAMFER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(chamfer)
	s.corner_detail = 1  # 1 segment per corner = crisp 45° chamfer
	s.anti_aliasing = false
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	return s


func _build_panels() -> void:
	var panel := box(Color(P.PANEL, 0.94), P.LINE, 2, Vector4(12, 12, 12, 12))
	theme.set_stylebox(&"panel", &"Panel", panel)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	_variation(&"AccentPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"AccentPanel", box(Color(P.PANEL, 0.97), P.ACCENT_DIM, 2, Vector4(12, 12, 12, 12)))
	_variation(&"CardPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"CardPanel", box(P.PANEL_HI, P.LINE, 1, Vector4(10, 8, 10, 8), 4))
	_variation(&"DangerPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"DangerPanel", box(Color(P.DANGER_DIM, 0.95), P.DANGER, 2, Vector4(12, 8, 12, 8)))
	_variation(&"ToastPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"ToastPanel", box(Color(P.BG_1, 0.96), P.ACCENT_DIM, 2, Vector4(12, 8, 12, 8)))
	_variation(&"HudPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"HudPanel", box(Color(P.BG_1, 0.92), P.LINE, 1, Vector4(8, 6, 8, 6), 4))
	_variation(&"FlatPanel", &"PanelContainer")
	var flat := StyleBoxEmpty.new()
	theme.set_stylebox(&"panel", &"FlatPanel", flat)


func _button_styles(type: StringName, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat, font: Color, font_pressed: Color) -> void:
	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, pressed)
	theme.set_stylebox(&"hover_pressed", type, pressed)
	theme.set_stylebox(&"disabled", type, disabled)
	theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())
	theme.set_color(&"font_color", type, font)
	theme.set_color(&"font_hover_color", type, font)
	theme.set_color(&"font_pressed_color", type, font_pressed)
	theme.set_color(&"font_hover_pressed_color", type, font_pressed)
	theme.set_color(&"font_focus_color", type, font)
	theme.set_color(&"font_disabled_color", type, P.TEXT_DIM)
	theme.set_color(&"icon_normal_color", type, Color.WHITE)
	theme.set_color(&"icon_pressed_color", type, Color.WHITE)
	theme.set_color(&"icon_hover_color", type, Color.WHITE)
	theme.set_color(&"icon_hover_pressed_color", type, Color.WHITE)
	theme.set_color(&"icon_disabled_color", type, Color(1, 1, 1, 0.35))


func _build_buttons() -> void:
	var m := Vector4(14, 12, 14, 12)
	var disabled := box(P.PANEL, P.LINE, 2, m)
	_button_styles(&"Button",
		box(P.PANEL_HI, P.LINE_HI, 2, m),
		box(P.PANEL_HI, P.ACCENT_DIM, 2, m),
		box(P.ACCENT_DIM.darkened(0.35), P.ACCENT, 2, m),
		disabled, P.TEXT, P.ACCENT)
	theme.set_font(&"font", &"Button", font_title)
	theme.set_font_size(&"font_size", &"Button", 14)

	_variation(&"AccentButton", &"Button")
	_button_styles(&"AccentButton",
		box(P.ACCENT, P.ACCENT.lightened(0.3), 2, m),
		box(P.ACCENT.lightened(0.12), P.ACCENT.lightened(0.4), 2, m),
		box(P.ACCENT_DIM, P.ACCENT, 2, m),
		disabled, P.TEXT_DARK, P.TEXT_DARK)

	_variation(&"BrandButton", &"Button")
	_button_styles(&"BrandButton",
		box(P.BRAND, P.BRAND.lightened(0.3), 2, m),
		box(P.BRAND.lightened(0.12), P.BRAND.lightened(0.4), 2, m),
		box(P.BRAND_DIM, P.BRAND, 2, m),
		disabled, P.TEXT_DARK, P.TEXT)

	_variation(&"DangerButton", &"Button")
	_button_styles(&"DangerButton",
		box(P.DANGER_DIM, P.DANGER, 2, m),
		box(P.DANGER_DIM.lightened(0.1), P.DANGER, 2, m),
		box(P.DANGER, P.DANGER.lightened(0.3), 2, m),
		disabled, P.TEXT, P.TEXT_DARK)

	_variation(&"GhostButton", &"Button")
	_button_styles(&"GhostButton",
		box(Color(P.BG_1, 0.6), P.LINE, 2, m),
		box(Color(P.BG_1, 0.8), P.LINE_HI, 2, m),
		box(P.PANEL_HI, P.ACCENT_DIM, 2, m),
		disabled, P.TEXT_DIM, P.ACCENT)

	# Square tool / quick-action buttons. Selected = toggled "pressed".
	_variation(&"ToolButton", &"Button")
	var tm := Vector4(4, 4, 4, 4)
	_button_styles(&"ToolButton",
		box(P.PANEL, P.LINE, 2, tm, 4),
		box(P.PANEL_HI, P.LINE_HI, 2, tm, 4),
		box(Color(P.ACCENT_DIM, 0.45), P.ACCENT, 3, tm, 4),
		box(P.BG_1, P.LINE, 2, tm, 4), P.TEXT_DIM, P.ACCENT)
	theme.set_font(&"font", &"ToolButton", font_mono)
	theme.set_font_size(&"font_size", &"ToolButton", 18)

	_variation(&"QuickButton", &"Button")
	_button_styles(&"QuickButton",
		box(P.BG_1, P.WARN.darkened(0.45), 2, tm, 4),
		box(P.PANEL_HI, P.WARN.darkened(0.2), 2, tm, 4),
		box(P.WARN.darkened(0.55), P.WARN, 2, tm, 4),
		box(P.BG_1, P.LINE, 2, tm, 4), P.WARN, P.TEXT)
	theme.set_font(&"font", &"QuickButton", font_title)
	theme.set_font_size(&"font_size", &"QuickButton", 11)


func _build_labels() -> void:
	theme.set_color(&"font_color", &"Label", P.TEXT)
	theme.set_constant(&"line_spacing", &"Label", 2)

	_variation(&"TitleLabel", &"Label")
	theme.set_font(&"font", &"TitleLabel", font_title)
	theme.set_font_size(&"font_size", &"TitleLabel", 40)
	theme.set_color(&"font_color", &"TitleLabel", P.ACCENT)
	theme.set_color(&"font_shadow_color", &"TitleLabel", Color(P.ACCENT_DIM, 0.6))
	theme.set_constant(&"shadow_offset_x", &"TitleLabel", 0)
	theme.set_constant(&"shadow_offset_y", &"TitleLabel", 3)

	_variation(&"HeaderLabel", &"Label")
	theme.set_font(&"font", &"HeaderLabel", font_title)
	theme.set_font_size(&"font_size", &"HeaderLabel", 16)
	theme.set_color(&"font_color", &"HeaderLabel", P.ACCENT)

	_variation(&"SubHeaderLabel", &"Label")
	theme.set_font(&"font", &"SubHeaderLabel", font_title)
	theme.set_font_size(&"font_size", &"SubHeaderLabel", 11)
	theme.set_color(&"font_color", &"SubHeaderLabel", P.TEXT_DIM)

	_variation(&"DimLabel", &"Label")
	theme.set_font_size(&"font_size", &"DimLabel", 15)
	theme.set_color(&"font_color", &"DimLabel", P.TEXT_DIM)

	_variation(&"MonoLabel", &"Label")
	theme.set_font(&"font", &"MonoLabel", font_mono)
	theme.set_font_size(&"font_size", &"MonoLabel", 22)
	theme.set_color(&"font_color", &"MonoLabel", P.TEXT)

	_variation(&"BigMonoLabel", &"Label")
	theme.set_font(&"font", &"BigMonoLabel", font_mono)
	theme.set_font_size(&"font_size", &"BigMonoLabel", 36)
	theme.set_color(&"font_color", &"BigMonoLabel", P.ACCENT)

	theme.set_font(&"normal_font", &"RichTextLabel", font_body)
	theme.set_font(&"mono_font", &"RichTextLabel", font_mono)
	theme.set_color(&"default_color", &"RichTextLabel", P.TEXT)
	theme.set_font_size(&"normal_font_size", &"RichTextLabel", 17)
	theme.set_font_size(&"mono_font_size", &"RichTextLabel", 20)


func _build_misc() -> void:
	var bar_bg := box(P.BG_1, P.LINE, 1, Vector4.ZERO, 0)
	var bar_fill := box(P.ACCENT, P.ACCENT, 0, Vector4.ZERO, 0)
	theme.set_stylebox(&"background", &"ProgressBar", bar_bg)
	theme.set_stylebox(&"fill", &"ProgressBar", bar_fill)
	theme.set_font(&"font", &"ProgressBar", font_mono)
	theme.set_font_size(&"font_size", &"ProgressBar", 16)
	theme.set_color(&"font_color", &"ProgressBar", P.TEXT)

	var sep := StyleBoxLine.new()
	sep.color = P.LINE
	sep.thickness = 2
	theme.set_stylebox(&"separator", &"HSeparator", sep)
	theme.set_constant(&"separation", &"HSeparator", 8)

	var grab := StyleBoxFlat.new()
	grab.bg_color = P.LINE_HI
	theme.set_stylebox(&"grabber", &"VScrollBar", grab)
	theme.set_stylebox(&"grabber_highlight", &"VScrollBar", grab)
	theme.set_stylebox(&"grabber_pressed", &"VScrollBar", grab)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(P.BG_1, 0.5)
	track.content_margin_left = 3
	track.content_margin_right = 3
	theme.set_stylebox(&"scroll", &"VScrollBar", track)

	theme.set_constant(&"separation", &"VBoxContainer", 8)
	theme.set_constant(&"separation", &"HBoxContainer", 8)


func _variation(name: StringName, base: StringName) -> void:
	theme.set_type_variation(name, base)
