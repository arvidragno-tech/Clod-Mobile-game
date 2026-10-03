extends Node
## Owns the player's money. All money changes go through here.

var money: int = 0


func _ready() -> void:
	reset_state()


func reset_state() -> void:
	money = GameConfig.STARTING_MONEY


func can_afford(amount: int) -> bool:
	return money >= amount


func add_money(amount: int) -> void:
	if amount == 0:
		return
	money += amount
	EventBus.money_changed.emit(money, amount)


## Returns false (and changes nothing) if the player cannot afford it.
func spend(amount: int) -> bool:
	if amount < 0 or not can_afford(amount):
		return false
	money -= amount
	EventBus.money_changed.emit(money, -amount)
	return true


static func format_money(amount: int) -> String:
	return "%d%s" % [amount, GameConfig.CURRENCY_SUFFIX]


func get_save_data() -> Dictionary:
	return {"money": money}


func load_save_data(data: Dictionary) -> void:
	money = int(data.get("money", GameConfig.STARTING_MONEY))
	EventBus.money_changed.emit(money, 0)
