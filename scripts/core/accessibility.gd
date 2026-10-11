class_name Accessibility
extends RefCounted
## Applies text-size and contrast settings to the shared project theme at
## runtime (screens rebuild from the theme when they open), and exposes the
## colour helpers code-built UI uses. Called by Main on start and on every
## Settings change.

## Theme types whose font size scales with "Large text".
const SCALED_TYPES: Array[StringName] = [&"Label", &"DimLabel", &"MonoLabel", &"SubHeaderLabel", &"Button", &"TabButton", &"NavButton", &"QuickButton",
	&"AccentButton", &"BrandButton", &"DangerButton", &"GhostButton", &"BMButton", &"InfoButton", &"SectionLabel", &"HintLabel", &"ValueLabel", &"TooltipLabel"]
const DIM_NORMAL := Color("6b7c8c")
const DIM_HIGH := Color("a3b3c2")

static var _base_sizes: Dictionary = {}


static func apply(theme: Theme) -> void:
	if theme == null:
		return
	if _base_sizes.is_empty():
		for t in SCALED_TYPES:
			_base_sizes[t] = theme.get_font_size(&"font_size", t) if theme.has_font_size(&"font_size", t) else theme.default_font_size
		_base_sizes[&"__default"] = theme.default_font_size
		_base_sizes[&"__rich"] = theme.get_font_size(&"normal_font_size", &"RichTextLabel")
	var bonus := Settings.font_bonus()
	var sc := Settings.font_scale()
	for t in SCALED_TYPES:
		theme.set_font_size(&"font_size", t, roundi(int(_base_sizes[t]) * sc) + bonus)
	theme.default_font_size = roundi(int(_base_sizes[&"__default"]) * sc) + bonus
	for k in [&"normal_font_size", &"bold_font_size"]:
		theme.set_font_size(k, &"RichTextLabel", roundi(int(_base_sizes[&"__rich"]) * sc) + bonus)
	var dim := DIM_HIGH if Settings.high_contrast else DIM_NORMAL
	for t in [&"DimLabel", &"SubHeaderLabel", &"HintLabel"]:
		theme.set_color(&"font_color", t, dim)
	for t in [&"Button", &"GhostButton", &"NavButton", &"TabButton", &"ToolButton"]:
		theme.set_color(&"font_disabled_color", t, Color(dim, 0.8))
	theme.set_color(&"font_color", &"GhostButton", dim)


## Secondary text colour honouring high contrast.
static func dim() -> Color:
	return DIM_HIGH if Settings.high_contrast else DIM_NORMAL


## Maps a requested label colour through the contrast setting.
static func text_color(c: Color) -> Color:
	if Settings.high_contrast and c.is_equal_approx(DIM_NORMAL):
		return DIM_HIGH
	return c


## Colour-blind indicator: a text marker added to colour-coded values when
## the setting is on (good / caution / bad never rely on hue alone).
static func tag(level: StringName) -> String:
	if not Settings.colorblind:
		return ""
	match level:
		&"good":
			return "[+] "
		&"warn":
			return "[~] "
		&"bad":
			return "[!] "
	return ""
