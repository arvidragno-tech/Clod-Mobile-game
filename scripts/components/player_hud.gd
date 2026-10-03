class_name PlayerHud
extends PanelContainer
## Top bar showing money, level/XP and reputation. Updates from EventBus.

@onready var _money: Label = %Money
@onready var _level: Label = %Level
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _rep: Label = %Rep
@onready var _rep_tier: Label = %RepTier

var _shown_money: int = 0
var _money_tween: Tween


func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.xp_changed.connect(func(_xp: int, _lvl: int) -> void: _refresh_xp())
	EventBus.reputation_changed.connect(func(_v: int, _d: int) -> void: _refresh_rep())
	_shown_money = EconomyManager.money
	_set_money_text(_shown_money)
	_refresh_xp()
	_refresh_rep()


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
