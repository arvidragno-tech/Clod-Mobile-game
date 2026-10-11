class_name UIKit
extends RefCounted
## Small builder helpers so code-built screens share one consistent look.

## Scales a font size written for the old layouts to the 1080p design size
## (plus the Large Text bonus).
static func fs(size: int) -> int:
	return roundi(size * GameConfig.TEXT_SCALE * Settings.font_scale()) + Settings.font_bonus()


## Desktop workstation frame: status bar on top, section navigation on the
## left, and the returned content column on the right. Wires navigation,
## the MENU button and records the panels TAB cycles through.
static func workstation(screen: Control, nav_id: StringName) -> VBoxContainer:
	var root := vbox(0)
	full_rect(root)
	screen.add_child(root)
	var bar := StatusBar.new()
	bar.name = "StatusBar"
	bar.menu_pressed.connect(GameManager.open_pause_menu)
	root.add_child(bar)
	var body := hbox(0)
	expand(body, true, true)
	root.add_child(body)
	var nav := SideNav.new()
	nav.name = "SideNav"
	nav.nav_pressed.connect(GameManager.navigate)
	body.add_child(nav)
	nav.set_active(nav_id)
	var m := margin(24, 18, 24, 18)
	expand(m, true, true)
	body.add_child(m)
	var content := vbox(14)
	content.name = "Content"
	m.add_child(content)
	return content


## A titled section panel (PC workstation look). Returns the inner column.
static func section(parent: Control, title: String, variation: StringName = &"CardPanel", hint: String = "", term: String = "") -> VBoxContainer:
	var p := panel(variation)
	parent.add_child(p)
	var v := vbox(10)
	p.add_child(v)
	v.add_child(section_head(title, hint, term))
	return v


## Section title row: a coloured bar, the title, an optional hint and an
## optional "?" (glossary term), with a thin rule under it.
static func section_head(title: String, hint: String = "", term: String = "", color: Color = Palette.ACCENT) -> VBoxContainer:
	var wrap := vbox(4)
	var head := hbox(8)
	wrap.add_child(head)
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(4, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(bar)
	var t := label(title, &"SectionLabel")
	t.add_theme_color_override(&"font_color", color)
	expand(t)
	head.add_child(t)
	if hint != "":
		head.add_child(label(hint, &"SubHeaderLabel"))
	if term != "":
		head.add_child(info(term))
	var rule := ColorRect.new()
	rule.color = Color(color, 0.22)
	rule.custom_minimum_size.y = 2
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(rule)
	return wrap


## A small "?" chip that explains a game term (data/glossary.json): hover
## for the short version, click for the full explanation.
static func info(term: String) -> Button:
	var b := Button.new()
	b.text = "?"
	b.theme_type_variation = &"InfoButton"
	b.name = "Info_%s" % term
	# A full-size click target (GameConfig.MIN_CONTROL), small glyph.
	b.custom_minimum_size = Vector2.ONE * (GameConfig.MIN_CONTROL - 4.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_HELP
	b.tooltip_text = Glossary.short(term)
	b.pressed.connect(func() -> void: Glossary.show(term))
	return b


## A stat caption. If the glossary explains it, hovering shows what it
## means and clicking opens the full explanation (help cursor).
static func caption(text: String, variation: StringName = &"SubHeaderLabel") -> Label:
	var l := label(text, variation)
	var term := Glossary.term_for(text)
	if term != "" and Glossary.has(term):
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_HELP
		l.tooltip_text = Glossary.short(term) + "\n(click for more)"
		l.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				Glossary.show(term))
	return l


## A label plus its "?" in one row.
static func label_with_info(text: String, term: String, variation: StringName = &"SubHeaderLabel", color: Variant = null) -> HBoxContainer:
	var h := hbox(6)
	h.add_child(label(text, variation, false, color))
	h.add_child(info(term))
	return h


## Expandable section: a header button toggles the body. Returns the body.
## PC: click the header (or focus it and press ENTER) to fold / unfold.
static func collapsible(parent: Control, title: String, expanded: bool = true, variation: StringName = &"CardPanel", hint: String = "") -> VBoxContainer:
	var p := panel(variation)
	p.name = "Section_%s" % title.replace(" ", "_")
	parent.add_child(p)
	var v := vbox(8)
	p.add_child(v)
	var head := button("", &"GhostButton", Callable(), "Toggle_%s" % title.replace(" ", "_"), 40)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.toggle_mode = true
	head.button_pressed = expanded
	head.add_theme_color_override(&"font_color", Palette.ACCENT)
	head.add_theme_font_size_override(&"font_size", fs(13))
	v.add_child(head)
	var body := vbox(6)
	body.visible = expanded
	v.add_child(body)
	var refresh := func() -> void:
		head.text = "%s  %s%s" % ["▾" if body.visible else "▸", title, ("   " + hint) if hint != "" else ""]
	refresh.call()
	head.toggled.connect(func(on: bool) -> void:
		body.visible = on
		refresh.call())
	return body


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", sep)
	return h


static func margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_left", l)
	m.add_theme_constant_override(&"margin_top", t)
	m.add_theme_constant_override(&"margin_right", r)
	m.add_theme_constant_override(&"margin_bottom", b)
	return m


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func label(text: String, variation: StringName = &"", wrap: bool = false, color: Variant = null, size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != null:
		l.add_theme_color_override(&"font_color", Accessibility.text_color(color))
	if size > 0:
		l.add_theme_font_size_override(&"font_size", fs(size))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, variation: StringName = &"", on_press: Callable = Callable(), node_name: String = "", min_h: float = GameConfig.MIN_CONTROL) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size.y = min_h
	# PC: every button is keyboard-focusable and shows the hand cursor.
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if node_name != "":
		b.name = node_name
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func panel(variation: StringName = &"CardPanel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


## Icon at exact game pixel density (art pixels x PIXEL_SCALE).
static func icon(path: String, art_size: int = 0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = PixelArt.scaled(path)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if art_size > 0:
		t.custom_minimum_size = Vector2.ONE * art_size * GameConfig.PIXEL_SCALE
	return t


## Screen header: back button + step caption + title.
static func header(step: String, title: String, on_back: Callable) -> HBoxContainer:
	var h := hbox(10)
	var back := button("<  BACK", &"GhostButton", on_back, "BackButton")
	back.custom_minimum_size = Vector2(130, GameConfig.MIN_CONTROL)
	back.tooltip_text = "Back  [%s]" % Controls.key_name("pause")
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(back)
	var titles := vbox(0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_child(label(step, &"SubHeaderLabel"))
	var t := label(title, &"HeaderLabel")
	t.name = "Title"
	titles.add_child(t)
	h.add_child(titles)
	return h


## Purchase / action guard: true the first time `key` fires, false again
## until `sec` has passed. A double-click (two presses ~0.1 s apart) on a BUY
## button is one purchase; a deliberate second click a moment later is not
## blocked.
static var _last_action: Dictionary = {}


static func debounce(key: String, sec: float = 0.4) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_action.get(key, -100000)) < int(sec * 1000.0):
		return false
	_last_action[key] = now
	return true


static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func expand(c: Control, h: bool = true, v: bool = false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Row of toggle tabs; calls on_select(index).
static func tabs(names: Array, on_select: Callable, prefix: String = "Tab") -> HBoxContainer:
	var row := hbox(4)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := button(str(names[i]), &"TabButton", Callable(), "%s_%d" % [prefix, i], GameConfig.MIN_CONTROL)
		b.toggle_mode = true
		# Tabs share the row equally; long labels clip instead of pushing the
		# row off-screen on narrow phones.
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == 0
		b.pressed.connect(on_select.bind(i))
		row.add_child(b)
	return row


## "■■□" rank pips.
static func pips(value: int, max_value: int) -> String:
	return "■".repeat(value) + "□".repeat(maxi(0, max_value - value))


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Removes every child after the first `keep` (e.g. a section title).
static func clear_after(node: Node, keep: int) -> void:
	var kids := node.get_children()
	for i in range(keep, kids.size()):
		node.remove_child(kids[i])
		kids[i].queue_free()


## Small horizontal meter (0..1) drawn as a ProgressBar with custom colour.
static func meter(ratio: float, color: Color, height: float = 6.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.max_value = 1.0
	p.step = 0.001
	p.value = ratio
	var fill := StyleBoxFlat.new()
	fill.anti_aliasing = false
	fill.bg_color = color
	p.add_theme_stylebox_override(&"fill", fill)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


const MODIFIER_LABELS := {
	"surgery.precision": "precision", "surgery.speed": "work speed", "surgery.bleed": "bleeding from mistakes",
	"surgery.pain": "pain from mistakes", "surgery.alignment": "alignment window", "neural.splice_penalty": "bad-splice shock",
	"neural.load": "neural load added", "calibrate.range": "sync window", "complication.chance": "complication chance",
	"complication.time": "complication timer", "quick.cooldown": "emergency cooldowns", "coag.heal": "health per COAG",
	"diagnosis.reveal": "condition reveal", "pay": "pay", "price.buy": "shop prices", "bm.price": "market prices",
	"bm.modify": "study/modify cost", "bm.stock": "market offers", "faction.gain": "faction rep gains",
	"heat.gain": "heat gained", "supplies.use": "supplies used", "xp": "XP", "post_op.risk": "post-op risk",
	"customer.quality": "customer wealth", "staff.stress": "staff stress", "staff.skill": "staff skill",
	"reputation.daily": "reputation per day",
}
const ABSOLUTE_MODIFIERS := ["coag.heal", "bm.stock", "customer.quality", "reputation.daily"]


## "+12% precision, -10% emergency cooldowns"
static func describe_modifiers(mods: Dictionary, scale: float = 1.0) -> String:
	var parts: Array[String] = []
	for key: Variant in mods:
		var k := str(key)
		var v := float(mods[key]) * scale
		var name: String = MODIFIER_LABELS.get(k, k)
		if k in ABSOLUTE_MODIFIERS:
			parts.append("%+d %s" % [roundi(v), name])
		else:
			parts.append("%+d%% %s" % [roundi(v * 100.0), name])
	return ", ".join(parts)
