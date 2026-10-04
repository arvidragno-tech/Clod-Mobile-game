extends Node
## Clinic progression: which facility tier the player runs.

var tiers: Array[Dictionary] = []
var tier: int = 0


func _ready() -> void:
	for t: Variant in DataLoader.load_entries(GameConfig.DATA_CLINIC_TIERS, "tiers"):
		tiers.append(t)
	reset_state()


func reset_state() -> void:
	tier = 0


func get_tier_data(t: int = -1) -> Dictionary:
	var i := tier if t < 0 else t
	return tiers[clampi(i, 0, tiers.size() - 1)] if not tiers.is_empty() else {}


func get_tier_name() -> String:
	return str(get_tier_data().get("name", "Clinic"))


func is_max_tier() -> bool:
	return tier >= tiers.size() - 1


func get_next_tier() -> Dictionary:
	return {} if is_max_tier() else get_tier_data(tier + 1)


## "" if the next tier can be bought, otherwise the reason.
func get_upgrade_block_reason() -> String:
	if is_max_tier():
		return "Fully upgraded"
	var n := get_next_tier()
	if ProgressionManager.level < int(n.get("min_level", 1)):
		return "Requires LV %d" % int(n["min_level"])
	if ReputationManager.reputation < int(n.get("min_reputation", 0)):
		return "Requires REP %d" % int(n["min_reputation"])
	if not EconomyManager.can_afford(int(n.get("cost", 0))):
		return "Not enough credits"
	return ""


func upgrade() -> bool:
	if get_upgrade_block_reason() != "":
		return false
	if not EconomyManager.spend(int(get_next_tier().get("cost", 0))):
		return false
	tier += 1
	EventBus.clinic_upgraded.emit(tier)
	EventBus.modifiers_changed.emit()
	return true


func get_modifiers() -> Dictionary:
	return get_tier_data().get("modifiers", {})


func get_max_cyberware_tier() -> int:
	return int(get_tier_data().get("max_cyberware_tier", 2))


func get_supplies_capacity() -> int:
	return int(get_tier_data().get("supplies_capacity", 12))


func get_background_path() -> String:
	return str(get_tier_data().get("background", ""))


func get_surgery_backdrop_level() -> int:
	return int(get_tier_data().get("surgery_backdrop", 0))


func get_save_data() -> Dictionary:
	return {"tier": tier}


func load_save_data(data: Dictionary) -> void:
	tier = clampi(int(data.get("tier", 0)), 0, maxi(tiers.size() - 1, 0))
	EventBus.modifiers_changed.emit()
