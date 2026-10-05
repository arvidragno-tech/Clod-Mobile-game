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


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	custom_minimum_size.y = 72
	var row := UIKit.hbox(18)
	add_child(row)
	# Clinic mark + location
	var brand := UIKit.vbox(0)
	brand.custom_minimum_size.x = 230
	var title := UIKit.label("UNDERCITY: RIPPER", &"HeaderLabel")
	title.add_theme_color_override(&"font_color", Palette.BRAND)
	brand.add_child(title)
	_location = UIKit.label("", &"SubHeaderLabel")
	brand.add_child(_location)
	row.add_child(brand)
	row.add_child(_sep())
	_money = _stat(row, "CREDITS", "res://assets/sprites/ui/icons/money.png", Palette.WARN, 150)
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
	row.add_child(lv)
	row.add_child(_sep())
	var rep := UIKit.vbox(0)
	rep.custom_minimum_size.x = 150
	var rep_row := UIKit.hbox(8)
	rep_row.add_child(UIKit.icon("res://assets/sprites/ui/icons/rep.png", 12))
	_rep = UIKit.label("", &"MonoLabel", false, Palette.BRAND)
	rep_row.add_child(_rep)
	rep.add_child(rep_row)
	_tier = UIKit.label("", &"SubHeaderLabel")
	rep.add_child(_tier)
	row.add_child(rep)
	row.add_child(_sep())
	_values[&"heat"] = _stat(row, "HEAT", "res://assets/sprites/ui/icons/heat.png", Palette.TEXT, 90)
	_values[&"supplies"] = _stat(row, "SUPPLIES", "res://assets/sprites/ui/icons/supplies.png", Palette.TEXT, 110)
	_values[&"parts"] = _stat(row, "PARTS", "res://assets/sprites/ui/icons/parts.png", Palette.TEXT, 80)
	_values[&"tokens"] = _stat(row, "TOKENS", "res://assets/sprites/ui/icons/tokens.png", Palette.BRAND, 80)
	_values[&"ops"] = _stat(row, "JOBS", "res://assets/sprites/ui/icons/dossier.png", Palette.TEXT, 70)
	row.add_child(UIKit.expand(Control.new()))
	var menu := UIKit.button("MENU  [%s]" % Controls.key_name("pause"), &"GhostButton", menu_pressed.emit, "MenuButton")
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.tooltip_text = "Pause menu: save, load, settings, quit"
	row.add_child(menu)
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


func _stat(row: HBoxContainer, caption: String, icon: String, color: Color, width: float) -> Label:
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
	row.add_child(box)
	return v


func _on_money(amount: int, _delta: int) -> void:
	if _money_tween and _money_tween.is_valid():
		_money_tween.kill()
	_money_tween = create_tween()
	_money_tween.tween_method(func(v: int) -> void: _money.text = EconomyManager.format_money(v), _money_shown, amount, 0.5)
	_money_shown = amount


func _refresh() -> void:
	_location.text = "%s · %s · %s" % [ClinicManager.get_tier_name().to_upper(), WorldManager.district_name().to_upper(), TimeManager.stamp()]
	_level.text = "LV %d" % ProgressionManager.level
	var need := ProgressionManager.xp_required_for_level(ProgressionManager.level + 1)
	_xp_text.text = "%d / %d XP" % [ProgressionManager.total_xp, need]
	_xp.value = ProgressionManager.get_level_progress()
	_rep.text = "REP %d" % ReputationManager.reputation
	_tier.text = ReputationManager.get_tier_name().to_upper()
	_values[&"heat"].text = "%d" % roundi(FactionManager.heat)
	_values[&"heat"].add_theme_color_override(&"font_color", Palette.DANGER if FactionManager.heat >= 35.0 else Palette.TEXT)
	_values[&"supplies"].text = "%d/%d" % [InventoryManager.supplies, ClinicManager.get_supplies_capacity()]
	_values[&"supplies"].add_theme_color_override(&"font_color", Palette.WARN if InventoryManager.supplies < 2 else Palette.TEXT)
	_values[&"parts"].text = str(InventoryManager.parts)
	_values[&"tokens"].text = str(InventoryManager.tokens)
	_values[&"ops"].text = str(EventManager.operations)
