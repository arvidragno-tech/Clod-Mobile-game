extends Node
## Street reputation. Gates harder customers and (later) the black market.

const TIERS := [
	[-100, "Butcher"],
	[0, "Unknown"],
	[10, "Back-alley"],
	[25, "Known Cutter"],
	[50, "Trusted Ripper"],
	[80, "Legend"],
]

var reputation: int = 0


func _ready() -> void:
	reset_state()


func reset_state() -> void:
	reputation = GameConfig.STARTING_REPUTATION


func change(delta: int) -> void:
	var old := reputation
	reputation = clampi(reputation + delta, GameConfig.MIN_REPUTATION, GameConfig.MAX_REPUTATION)
	if reputation != old:
		EventBus.reputation_changed.emit(reputation, reputation - old)


func get_tier_name() -> String:
	var tier_name := String(TIERS[0][1])
	for tier: Array in TIERS:
		if reputation >= int(tier[0]):
			tier_name = String(tier[1])
	return tier_name


func is_black_market_unlocked() -> bool:
	return reputation >= GameConfig.BLACK_MARKET_REPUTATION


func get_save_data() -> Dictionary:
	return {"reputation": reputation}


func load_save_data(data: Dictionary) -> void:
	reputation = int(data.get("reputation", GameConfig.STARTING_REPUTATION))
	EventBus.reputation_changed.emit(reputation, 0)
