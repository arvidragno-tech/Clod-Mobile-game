class_name UIKit
extends RefCounted
## Small builder helpers so code-built screens share one consistent look.

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
		l.add_theme_font_size_override(&"font_size", size + Settings.font_bonus())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, variation: StringName = &"", on_press: Callable = Callable(), node_name: String = "", min_h: float = GameConfig.MIN_TOUCH) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size.y = min_h
	b.focus_mode = Control.FOCUS_NONE
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
	var back := button("<", &"GhostButton", on_back, "BackButton")
	back.custom_minimum_size = Vector2(GameConfig.MIN_TOUCH, GameConfig.MIN_TOUCH)
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
		var b := button(str(names[i]), &"TabButton", Callable(), "%s_%d" % [prefix, i], GameConfig.MIN_TOUCH)
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
	"customer.quality": "customer wealth",
}
const ABSOLUTE_MODIFIERS := ["coag.heal", "bm.stock", "customer.quality"]


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
