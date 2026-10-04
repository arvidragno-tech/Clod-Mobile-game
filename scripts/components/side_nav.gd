class_name SideNav
extends PanelContainer
## Left workstation navigation (PC): icon + label + hotkey per section, the
## active section highlighted, locked sections dimmed with a reason tooltip.
## Button names (Nav_<id>) are stable for tests and tutorials.

signal nav_pressed(id: StringName)

## id, label, icon, hotkey action ("" = none)
const ITEMS := [
	[&"clinic", "CLINIC", "res://assets/sprites/ui/icons/menu.png", ""],
	[&"inventory", "INVENTORY", "res://assets/sprites/ui/icons/supplies.png", "inventory"],
	[&"database", "CYBERWARE DB", "res://assets/sprites/ui/icons/neural.png", "database"],
	[&"supply", "SUPPLY", "res://assets/sprites/ui/icons/supply.png", ""],
	[&"skills", "SKILLS", "res://assets/sprites/ui/icons/skills.png", ""],
	[&"upgrades", "FACILITY", "res://assets/sprites/ui/icons/upgrade.png", "map"],
	[&"dossier", "JOURNAL", "res://assets/sprites/ui/icons/dossier.png", "journal"],
	[&"blackmarket", "BLACK MARKET", "res://assets/sprites/ui/icons/blackmarket.png", ""],
	[&"settings", "SETTINGS", "res://assets/sprites/ui/icons/lock.png", ""],
]

var active: StringName = &""
var _buttons: Dictionary = {}


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	custom_minimum_size.x = 250
	var col := UIKit.vbox(6)
	add_child(col)
	for item: Array in ITEMS:
		var b := Button.new()
		b.name = "Nav_%s" % item[0]
		var hk: String = item[3]
		b.text = str(item[1]) + (("  [%s]" % Controls.key_name(hk)) if hk != "" else "")
		b.icon = PixelArt.scaled(item[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = &"NavButton"
		b.custom_minimum_size = Vector2(0, 52)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: nav_pressed.emit(item[0]))
		col.add_child(b)
		_buttons[item[0]] = b
	col.add_child(UIKit.expand(Control.new(), false, true))
	var hint := UIKit.label("[%s] pause   [%s] cycle panels" % [Controls.key_name("pause"), Controls.key_name("cycle_panel")], &"SubHeaderLabel", true)
	col.add_child(hint)
	refresh()


func set_active(id: StringName) -> void:
	active = id
	refresh()


func refresh() -> void:
	for id: StringName in _buttons:
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(id == active)
	var locked := not BlackMarketManager.is_unlocked()
	var bm: Button = _buttons.get(&"blackmarket")
	if bm:
		bm.modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE
		bm.tooltip_text = "No contact yet. Build street rep (%d) or meet a fixer." % GameConfig.BLACK_MARKET_REPUTATION if locked else "The Undermarket"
	_badge(&"skills", SkillManager.points > 0, "%d skill point(s) to spend" % SkillManager.points)
	_badge(&"upgrades", ClinicManager.get_upgrade_block_reason() == "", "Clinic upgrade available")


func _badge(id: StringName, on: bool, tip: String) -> void:
	var b: Button = _buttons.get(id)
	if b:
		b.add_theme_color_override(&"font_color", Palette.WARN if on else Palette.TEXT_DIM)
		b.tooltip_text = tip if on else ""


func get_button(id: StringName) -> Button:
	return _buttons.get(id)
