extends Node
## The Undermarket: rotating stock of illegal / stolen / experimental chrome
## with hidden traits, plus STUDY, MODIFY, SELL and mystery cases.

var config: Dictionary = {}
var traits: Dictionary = {}  # StringName -> Dictionary
## Array of {"instance": ImplantInstance, "price": int}
var stock: Array[Dictionary] = []
var ops_since_refresh: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var parsed: Variant = DataLoader.load_json(GameConfig.DATA_BLACK_MARKET)
	if typeof(parsed) == TYPE_DICTIONARY:
		config = parsed
		for t: Variant in config.get("traits", []):
			traits[StringName(str(t["id"]))] = t
	reset_state()


func reset_state() -> void:
	stock.clear()
	ops_since_refresh = 0


func is_unlocked() -> bool:
	return StoryManager.has_flag(&"bm_access") or ReputationManager.reputation >= GameConfig.BLACK_MARKET_REPUTATION


func get_trait(id: StringName) -> Dictionary:
	return traits.get(id, {})


## Rolls hidden traits for a unit according to its model's unknown_traits.
func roll_traits(inst: ImplantInstance, rng: RandomNumberGenerator = null) -> void:
	var r := rng if rng else _rng
	var data := inst.get_data()
	if data == null or data.unknown_traits <= 0 or not inst.traits.is_empty():
		return
	# Draw distinct traits (seeded Fisher-Yates, so rolls stay reproducible).
	var ids: Array = traits.keys()
	for i in range(ids.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	for i in mini(data.unknown_traits, ids.size()):
		inst.traits.append(StringName(ids[i]))


func refresh_stock() -> void:
	stock.clear()
	var pool: Array[CyberwareData] = []
	for c: CyberwareData in CyberwareManager.catalog.values():
		if c.black_market or c.tier >= 3:
			pool.append(c)
	var size := int(config.get("stock_size", 4)) + int(ModifierManager.value(&"bm.stock"))
	for i in mini(size, pool.size()):
		var data := pool[_rng.randi_range(0, pool.size() - 1)]
		var cond := _rng.randf_range(float(config.get("min_condition", 40)), float(config.get("max_condition", 100)))
		var inst := ImplantInstance.create(data.id, cond, &"black_market")
		if not data.black_market and _rng.randf() < 0.5:
			inst.traits.append(StringName(traits.keys()[_rng.randi_range(0, traits.size() - 1)]))
		roll_traits(inst)
		stock.append({"instance": inst, "price": price_for(inst)})
	ops_since_refresh = 0
	EventBus.black_market_changed.emit()


func price_for(inst: ImplantInstance) -> int:
	var data := inst.get_data()
	var base := float(data.price) if data else 100.0
	var p := base * (0.55 + 0.45 * inst.condition / 100.0)
	p *= FactionManager.price_multiplier(&"black_market") * ModifierManager.mult(&"bm.price") * TimeManager.bm_price_mult()
	return maxi(10, int(round(p)))


func sell_value(inst: ImplantInstance) -> int:
	var data := inst.get_data()
	var value := int(round((data.price if data else 50) * float(config.get("sell_ratio", 0.45)) * inst.condition / 100.0))
	# Never more than 80% of what the market would charge for it: no
	# buy-low / sell-high loop, whatever discounts stack up.
	return mini(value, int(price_for(inst) * 0.8))


func study_cost_parts() -> int:
	return maxi(1, int(round(int(config.get("study_cost_parts", 2)) * ModifierManager.mult(&"bm.modify"))))


func modify_cost_parts() -> int:
	return maxi(1, int(round(int(config.get("modify_cost_parts", 3)) * ModifierManager.mult(&"bm.modify"))))


## Position of the offer whose implant has this uid (-1 if it's gone).
func index_of(uid: String) -> int:
	for i in stock.size():
		var inst: ImplantInstance = stock[i]["instance"]
		if inst and inst.uid == uid:
			return i
	return -1


## Records why standing changes in here (ChangeLog standing history).
func buy(index: int) -> bool:
	ChangeLog.push_cause("Black-market purchase")
	var r: bool = _buy_impl(index)
	ChangeLog.pop_cause()
	return r


func _buy_impl(index: int) -> bool:
	if not is_unlocked() or index < 0 or index >= stock.size():
		return false
	var offer: Dictionary = stock[index]
	if not EconomyManager.spend(int(offer["price"]), &"black_market"):
		return false
	stock.remove_at(index)
	InventoryManager.add_instance(offer["instance"])
	FactionManager.change(&"black_market", 2)
	FactionManager.add_heat(3.0)
	EventBus.black_market_changed.emit()
	return true


func sell(uid: String) -> int:
	var inst := InventoryManager.get_instance(uid)
	if inst == null:
		return 0
	var value := sell_value(inst)
	InventoryManager.remove_instance(uid)
	EconomyManager.add_money(value, &"black_market")
	StoryManager.bump(&"bm_sell")
	if InventoryManager.tokens < 99 and inst.source == &"black_market":
		InventoryManager.add_tokens(1)
	EventBus.black_market_changed.emit()
	return value


## Reveals one unknown trait. Pays with parts if possible, else credits.
func study(uid: String) -> bool:
	var inst := InventoryManager.get_instance(uid)
	if inst == null or not inst.has_unknown_traits():
		return false
	if InventoryManager.parts >= study_cost_parts():
		InventoryManager.add_parts(-study_cost_parts())
	elif not EconomyManager.spend(int(config.get("study_cost_money", 120)), &"black_market"):
		return false
	for t in inst.traits:
		if not inst.revealed.has(t):
			inst.revealed.append(t)
			break
	ProgressionManager.add_xp(10)
	InventoryManager.notify_changed()
	return true


## Spends parts: purges a known bad trait if any, otherwise repairs condition.
func modify(uid: String) -> String:
	var inst := InventoryManager.get_instance(uid)
	if inst == null or InventoryManager.parts < modify_cost_parts():
		return ""
	InventoryManager.add_parts(-modify_cost_parts())
	inst.modified += 1
	for t in inst.revealed:
		if not bool(get_trait(t).get("positive", true)):
			inst.traits.erase(t)
			inst.revealed.erase(t)
			InventoryManager.notify_changed()
			return "Purged: %s" % str(get_trait(t).get("name", t))
	inst.condition = minf(100.0, inst.condition + float(config.get("modify_condition_gain", 18)))
	InventoryManager.notify_changed()
	return "Condition %d%%" % roundi(inst.condition)


func open_mystery_case() -> ImplantInstance:
	var cost := int(config.get("mystery_case_tokens", 2))
	if InventoryManager.tokens < cost:
		return null
	InventoryManager.add_tokens(-cost)
	var pool: Array[CyberwareData] = []
	for c: CyberwareData in CyberwareManager.catalog.values():
		if c.black_market or c.tier >= 3:
			pool.append(c)
	var data := pool[_rng.randi_range(0, pool.size() - 1)]
	var inst := ImplantInstance.create(data.id, _rng.randf_range(35.0, 100.0), &"black_market")
	roll_traits(inst)
	if inst.traits.is_empty() and _rng.randf() < 0.6:
		inst.traits.append(StringName(traits.keys()[_rng.randi_range(0, traits.size() - 1)]))
	InventoryManager.add_instance(inst)
	return inst


func scrap(uid: String) -> int:
	if InventoryManager.get_instance(uid) == null:
		return 0
	InventoryManager.remove_instance(uid)
	var n := int(config.get("parts_from_scrap", 3))
	InventoryManager.add_parts(n)
	return n


## A favour repaid with a name: one more supplier you can call ("" = none left).
func reveal_random_supplier_lead() -> String:
	return SupplierManager.reveal_random_lead("favour")


func on_operation_completed() -> void:
	ops_since_refresh += 1
	if is_unlocked() and (stock.is_empty() or ops_since_refresh >= int(config.get("refresh_every_ops", 2))):
		refresh_stock()


func get_save_data() -> Dictionary:
	var s := []
	for offer in stock:
		s.append({"instance": (offer["instance"] as ImplantInstance).to_dict(), "price": offer["price"]})
	return {"stock": s, "ops_since_refresh": ops_since_refresh}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for o: Variant in data.get("stock", []):
		if typeof(o) == TYPE_DICTIONARY:
			stock.append({"instance": ImplantInstance.from_dict(o["instance"]), "price": int(o["price"])})
	ops_since_refresh = int(data.get("ops_since_refresh", 0))
