class_name StatusBar
extends PanelContainer
## Full-width workstation header (PC): clinic mark and location, credits,
## level + XP, street rep, heat, supplies, parts, tokens, operation count and
## a MENU button. Every value updates live from EventBus.

signal menu_pressed

var _money: Label
var _money_shown: int = 0
var _money_tween: Tween
var _level: Label
var _xp: ProgressBar
var _xp_text: Label
var _rep: Label
var _tier: Label
var _values: Dictionary = {}
var _location: Label
## Stat boxes by glossary term (hover = live explanation, click = more).
var _boxes: Dictionary = {}
var _seps: Dictionary = {}


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	custom_minimum_size.y = 72
	# Two parts: the stats (which may be clipped at the right edge with big
	# text) and MENU, which is always on screen.
	var outer := UIKit.hbox(18)
	add_child(outer)
	var clip := ScrollContainer.new()
	clip.name = "StatsClip"
	clip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	clip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	UIKit.expand(clip)
	outer.add_child(clip)
	var row := UIKit.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip.add_child(row)
	# Clinic mark + location
	var brand := UIKit.vbox(0)
	brand.custom_minimum_size.x = 230
	var title := UIKit.label("UNDERCITY: RIPPER", &"HeaderLabel")
	title.add_theme_color_override(&"font_color", Palette.BRAND)
	brand.add_child(title)
	_location = UIKit.label("", &"SubHeaderLabel")
	_location.name = "StatusClock"
	# Long clinic + district + clock lines are clipped (full text on hover)
	# so the bar never pushes MENU off-screen.
	_location.clip_text = true
	_location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_location.custom_minimum_size.x = 380
	_location.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_location.mouse_filter = Control.MOUSE_FILTER_PASS
	brand.add_child(_location)
	row.add_child(brand)
	row.add_child(_sep())
	_money = _stat(row, "CREDITS", "res://assets/sprites/ui/icons/money.png", Palette.WARN, 150, "credits")
	row.add_child(_sep())
	# Level + XP bar
	var lv := UIKit.vbox(2)
	lv.custom_minimum_size.x = 210
	var lv_row := UIKit.hbox(8)
	lv_row.add_child(UIKit.icon("res://assets/sprites/ui/icons/xp.png", 12))
	_level = UIKit.label("", &"MonoLabel", false, Palette.ACCENT)
	lv_row.add_child(_level)
	_xp_text = UIKit.label("", &"SubHeaderLabel")
	UIKit.expand(_xp_text)
	_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv_row.add_child(_xp_text)
	lv.add_child(lv_row)
	_xp = UIKit.meter(0.0, Palette.ACCENT, 8)
	lv.add_child(_xp)
	_explain(lv, "level")
	row.add_child(lv)
	_seps["level"] = _sep()
	row.add_child(_seps["level"])
	var rep := UIKit.vbox(0)
	rep.custom_minimum_size.x = 150
	var rep_row := UIKit.hbox(8)
	rep_row.add_child(UIKit.icon("res://assets/sprites/ui/icons/rep.png", 12))
	_rep = UIKit.label("", &"MonoLabel", false, Palette.BRAND)
	rep_row.add_child(_rep)
	rep.add_child(rep_row)
	_tier = UIKit.label("", &"SubHeaderLabel")
	rep.add_child(_tier)
	_explain(rep, "rep")
	row.add_child(rep)
	_seps["rep"] = _sep()
	row.add_child(_seps["rep"])
	_values[&"heat"] = _stat(row, "HEAT", "res://assets/sprites/ui/icons/heat.png", Palette.TEXT, 90, "heat")
	_values[&"supplies"] = _stat(row, "SUPPLIES", "res://assets/sprites/ui/icons/supplies.png", Palette.TEXT, 110, "supplies")
	_values[&"parts"] = _stat(row, "PARTS", "res://assets/sprites/ui/icons/parts.png", Palette.TEXT, 80, "parts")
	_values[&"tokens"] = _stat(row, "TOKENS", "res://assets/sprites/ui/icons/tokens.png", Palette.BRAND, 80, "tokens")
	_values[&"ops"] = _stat(row, "TODAY", "res://assets/sprites/ui/icons/dossier.png", Palette.TEXT, 90, "jobs")
	var menu := UIKit.button("MENU  [%s]" % Controls.key_name("pause"), &"GhostButton", menu_pressed.emit, "MenuButton")
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.tooltip_text = "Pause menu: save, load, settings, quit"
	outer.add_child(menu)
	EventBus.money_changed.connect(_on_money)
	EventBus.xp_changed.connect(func(_a: int, _b: int) -> void: _refresh())
	EventBus.reputation_changed.connect(func(_a: int, _b: int) -> void: _refresh())
	EventBus.resources_changed.connect(_refresh)
	EventBus.heat_changed.connect(func(_a: float, _b: float) -> void: _refresh())
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: _refresh())
	EventBus.day_started.connect(func(_d: int) -> void: _refresh())
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: _refresh())
	_money_shown = EconomyManager.money
	_money.text = EconomyManager.format_money(_money_shown)
	_refresh()


func _sep() -> Control:
	var s := ColorRect.new()
	s.color = Palette.LINE
	s.custom_minimum_size = Vector2(2, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Hover: what it means; click: the full explanation.
func _explain(box: Control, term: String) -> void:
	_boxes[term] = box
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_HELP
	box.tooltip_text = Glossary.short(term)
	box.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Glossary.show(term))


func _stat(row: HBoxContainer, caption: String, icon: String, color: Color, width: float, term: String = "") -> Label:
	var box := UIKit.vbox(0)
	box.custom_minimum_size.x = width
	box.add_child(UIKit.label(caption, &"SubHeaderLabel"))
	var line := UIKit.hbox(8)
	line.add_child(UIKit.icon(icon, 12))
	var v := UIKit.label("", &"MonoLabel", false, color)
	line.add_child(v)
	box.add_child(line)
	box.tooltip_text = caption.capitalize()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	if term != "":
		_explain(box, term)
	row.add_child(box)
	return v


func _on_money(amount: int, _delta: int) -> void:
	if _money_tween and _money_tween.is_valid():
		_money_tween.kill()
	_money_tween = create_tween()
	_money_tween.tween_method(func(v: int) -> void: _money.text = EconomyManager.format_money(v), _money_shown, amount, 0.5)
	_money_shown = amount


func _refresh() -> void:
	if LocationManager.is_away():
		var here := LocationManager.player_location
		_location.text = "%s · %s · %s" % [TimeManager.stamp(), LocationManager.location_name(here).to_upper(), WorldManager.district_name(LocationManager.district_of(here)).to_upper()]
	else:
		# At the clinic the room says where you are; the bar says when.
		_location.text = TimeManager.stamp()
	_location.tooltip_text = "%s · %s · %s" % [TimeManager.stamp(), ClinicManager.get_tier_name().to_upper(), WorldManager.district_name().to_upper()] if not LocationManager.is_away() else _location.text
	_level.text = "LV %d" % ProgressionManager.level
	var need := ProgressionManager.xp_required_for_level(ProgressionManager.level + 1)
	_xp_text.text = "%d / %d XP" % [ProgressionManager.total_xp, need]
	_xp.value = ProgressionManager.get_level_progress()
	_rep.text = "REP %d" % ReputationManager.reputation
	_tier.text = ReputationManager.get_tier_name().to_upper()
	_values[&"heat"].text = "%d" % roundi(FactionManager.heat)
	_values[&"heat"].add_theme_color_override(&"font_color", Palette.DANGER if FactionManager.heat >= 50.0 else (Palette.WARN if FactionManager.heat >= 25.0 else Palette.TEXT))
	_values[&"supplies"].text = "%d/%d" % [InventoryManager.supplies, ClinicManager.get_supplies_capacity()]
	_values[&"supplies"].add_theme_color_override(&"font_color", Palette.WARN if InventoryManager.supplies < 2 else Palette.TEXT)
	_values[&"parts"].text = str(InventoryManager.parts)
	_values[&"tokens"].text = str(InventoryManager.tokens)
	_values[&"ops"].text = "%d/%d" % [BusinessManager.jobs_today, BusinessManager.capacity()]
	_values[&"ops"].add_theme_color_override(&"font_color", Palette.OK if BusinessManager.is_day_full() else Palette.TEXT)
	# Stats appear with the part of the game that gives them meaning:
	# credits and supplies from the start; level with SKILLS; reputation and
	# today's jobs after the first job; heat once there is any (or the black
	# market is open); parts and tokens with the black market.
	var all := not Features.progressive()
	var first := Difficulty.ops() >= 1
	_show("level", all or Features.is_on(&"skills"))
	_show("rep", all or first)
	_show("jobs", all or first)
	_show("heat", all or FactionManager.heat > 0.0 or Features.is_on(&"blackmarket"))
	_show("parts", all or Features.is_on(&"blackmarket"))
	_show("tokens", all or Features.is_on(&"blackmarket"))
	_tip("credits", "%s. Tonight's bill: about %s." % [EconomyManager.format_money(EconomyManager.money), EconomyManager.format_money(BusinessManager.projected_total())])
	_tip("level", "Level %d: %d XP to the next. %s" % [ProgressionManager.level, maxi(0, need - ProgressionManager.total_xp), "%d skill point(s) to spend." % SkillManager.points if SkillManager.points > 0 else ""])
	_tip("rep", "Reputation %d. The street calls you: %s." % [ReputationManager.reputation, str(ReputationManager.identity().get("title", "nobody")).to_lower()])
	_tip("heat", "Heat %d (%s)." % [roundi(FactionManager.heat), SecurityManager.level_label()])
	_tip("supplies", "%d of %d. Each operation uses some." % [InventoryManager.supplies, ClinicManager.get_supplies_capacity()])
	_tip("jobs", "%d of %d jobs done today%s." % [BusinessManager.jobs_today, BusinessManager.capacity(), ": close for the night" if BusinessManager.is_day_full() else ""])


func _show(term: String, on: bool) -> void:
	var b: Control = _boxes.get(term)
	if b:
		b.visible = on
	if _seps.has(term):
		(_seps[term] as Control).visible = on


func _tip(term: String, live: String) -> void:
	var b: Control = _boxes.get(term)
	if b:
		b.tooltip_text = "%s\n%s\n(click for more)" % [live, Glossary.short(term)]
