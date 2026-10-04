class_name PlayerHud
extends PanelContainer
## Top bar: credits, level/XP, street rep, plus a resource row (supplies,
## parts, black-market tokens, heat). Updates from EventBus.

const RESOURCES := [
	[&"supplies", "res://assets/sprites/ui/icons/supplies.png"],
	[&"parts", "res://assets/sprites/ui/icons/parts.png"],
	[&"tokens", "res://assets/sprites/ui/icons/tokens.png"],
	[&"heat", "res://assets/sprites/ui/icons/heat.png"],
]

@onready var _money: Label = %Money
@onready var _level: Label = %Level
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _rep: Label = %Rep
@onready var _rep_tier: Label = %RepTier

var _shown_money: int = 0
var _money_tween: Tween
var _res_labels: Dictionary = {}


func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.xp_changed.connect(func(_xp: int, _lvl: int) -> void: _refresh_xp())
	EventBus.reputation_changed.connect(func(_v: int, _d: int) -> void: _refresh_rep())
	EventBus.resources_changed.connect(_refresh_resources)
	EventBus.heat_changed.connect(func(_v: float, _d: float) -> void: _refresh_resources())
	_build_resource_row()
	_shown_money = EconomyManager.money
	_set_money_text(_shown_money)
	_refresh_xp()
	_refresh_rep()
	_refresh_resources()


func _build_resource_row() -> void:
	var outer: VBoxContainer = %Rows
	var row := UIKit.hbox(6)
	outer.add_child(row)
	for r: Array in RESOURCES:
		var cell := UIKit.hbox(3)
		UIKit.expand(cell)
		cell.add_child(UIKit.icon(r[1], 12))
		var l := UIKit.label("0", &"MonoLabel", false, null, 18)
		cell.add_child(l)
		row.add_child(cell)
		_res_labels[r[0]] = l


func _refresh_resources() -> void:
	if _res_labels.is_empty():
		return
	_res_labels[&"supplies"].text = "%d/%d" % [InventoryManager.supplies, ClinicManager.get_supplies_capacity()]
	_res_labels[&"supplies"].add_theme_color_override(&"font_color", Palette.WARN if InventoryManager.supplies < 2 else Palette.TEXT)
	_res_labels[&"parts"].text = str(InventoryManager.parts)
	_res_labels[&"tokens"].text = str(InventoryManager.tokens)
	_res_labels[&"heat"].text = "%d" % roundi(FactionManager.heat)
	var hot := FactionManager.heat >= 35.0
	_res_labels[&"heat"].add_theme_color_override(&"font_color", Palette.DANGER if hot else Palette.TEXT_DIM)


func _on_money_changed(amount: int, _delta: int) -> void:
	if _money_tween and _money_tween.is_valid():
		_money_tween.kill()
	_money_tween = create_tween()
	_money_tween.tween_method(_set_money_text, _shown_money, amount, 0.5)
	_shown_money = amount


func _set_money_text(v: int) -> void:
	_money.text = EconomyManager.format_money(v)


func _refresh_xp() -> void:
	_level.text = "LV %d" % ProgressionManager.level
	_xp_bar.value = ProgressionManager.get_level_progress() * 100.0


func _refresh_rep() -> void:
	_rep.text = "REP %d" % ReputationManager.reputation
	_rep_tier.text = ReputationManager.get_tier_name()
