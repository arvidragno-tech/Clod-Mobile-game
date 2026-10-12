extends Node
## Owned tools, implant units (ImplantInstance) and consumable resources:
## medical supplies, salvaged parts and black-market tokens.

var tool_catalog: Dictionary = {}  # StringName -> ToolData
var owned_tools: Array[StringName] = []
var instances: Array[ImplantInstance] = []
var supplies: int = 0
var parts: int = 0
var tokens: int = 0
## Tool id -> condition 0..100. Instruments wear a little each operation and
## lose a few percent of precision until serviced (Supply screen).
var tool_condition: Dictionary = {}

const WEAR_PER_OP := 3.0
const WORN_PRECISION := 0.92  # precision factor at 0% condition
const SERVICE_COST_PER_POINT := 0.6


func _ready() -> void:
	_load_catalog()
	reset_state()


func _load_catalog() -> void:
	tool_catalog.clear()
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_TOOLS, "tools"):
		var t := ToolData.from_dict(entry)
		tool_catalog[t.id] = t


func reset_state() -> void:
	owned_tools.clear()
	tool_condition.clear()
	for t: ToolData in tool_catalog.values():
		if t.starter:
			owned_tools.append(t.id)
	instances.clear()
	for id: StringName in GameConfig.STARTING_IMPLANT_STOCK:
		for i in int(GameConfig.STARTING_IMPLANT_STOCK[id]):
			instances.append(ImplantInstance.create(id))
	supplies = GameConfig.STARTING_SUPPLIES
	parts = GameConfig.STARTING_PARTS
	tokens = GameConfig.STARTING_TOKENS
	EventBus.modifiers_changed.emit()


func notify_changed() -> void:
	EventBus.inventory_changed.emit()


# --- Tools -----------------------------------------------------------------------

func get_tool(id: StringName) -> ToolData:
	return tool_catalog.get(id) as ToolData


func owns_tool(id: StringName) -> bool:
	return owned_tools.has(id)


## Highest-tier owned tool of a category, or null.
func get_best_tool(category: StringName) -> ToolData:
	var best: ToolData = null
	for id in owned_tools:
		var t := get_tool(id)
		if t != null and t.category == category and (best == null or t.tier > best.tier):
			best = t
	return best


func has_tool_category(category: StringName, min_tier: int = 1) -> bool:
	var t := get_best_tool(category)
	return t != null and t.tier >= min_tier


func get_tool_tier(category: StringName) -> int:
	var t := get_best_tool(category)
	return t.tier if t else 0


## Tools for sale: not owned yet and unlocked by player level.
func get_purchasable_tools(include_locked: bool = false) -> Array[ToolData]:
	var out: Array[ToolData] = []
	for t: ToolData in tool_catalog.values():
		if not t.starter and t.price > 0 and not owns_tool(t.id) and (include_locked or t.unlock_level <= ProgressionManager.level):
			out.append(t)
	out.sort_custom(func(a: ToolData, b: ToolData) -> bool: return a.price < b.price)
	return out


func tool_price(t: ToolData) -> int:
	return int(round(t.price * ModifierManager.mult(&"price.buy")))


func buy_tool(id: StringName) -> bool:
	var t := get_tool(id)
	if t == null or owns_tool(id) or t.unlock_level > ProgressionManager.level:
		return false
	if not EconomyManager.spend(tool_price(t), &"tools"):
		return false
	owned_tools.append(id)
	EventBus.inventory_changed.emit()
	EventBus.modifiers_changed.emit()
	return true


## Passive modifiers of the best tool in each category.
func get_tool_modifiers() -> Dictionary:
	var out := {}
	var seen := {}
	for id in owned_tools:
		var t := get_tool(id)
		if t == null:
			continue
		var best := get_best_tool(t.category)
		if best != t or seen.has(t.category):
			continue
		seen[t.category] = true
		for key: Variant in t.modifiers:
			out[key] = float(out.get(key, 0.0)) + float(t.modifiers[key])
	return out


## Condition 0..100 of an owned tool (new tools are 100).
func get_tool_condition(id: StringName) -> float:
	return float(tool_condition.get(id, 100.0))


## Precision factor from wear: 1.0 when new, WORN_PRECISION when worn out.
func tool_condition_factor(id: StringName) -> float:
	return lerpf(WORN_PRECISION, 1.0, get_tool_condition(id) / 100.0)


## Wears the best tool of each category used in an operation.
func wear_tools(categories: Array[StringName], amount: float = WEAR_PER_OP) -> void:
	for category in categories:
		var t := get_best_tool(category)
		if t:
			tool_condition[t.id] = maxf(0.0, get_tool_condition(t.id) - amount)
	EventBus.inventory_changed.emit()


func get_service_cost() -> int:
	var missing := 0.0
	for id in owned_tools:
		missing += 100.0 - get_tool_condition(id)
	return int(ceil(missing * SERVICE_COST_PER_POINT))


## Restores every owned tool to 100%.
func service_tools() -> bool:
	var cost := get_service_cost()
	if cost <= 0 or not EconomyManager.spend(cost, &"tools"):
		return false
	tool_condition.clear()
	EventBus.inventory_changed.emit()
	return true


# --- Implants ----------------------------------------------------------------------

func get_instances() -> Array[ImplantInstance]:
	return instances


func get_instance(uid: String) -> ImplantInstance:
	for i in instances:
		if i.uid == uid:
			return i
	return null


func get_instances_of(category: StringName) -> Array[ImplantInstance]:
	var out: Array[ImplantInstance] = []
	for i in instances:
		var d := i.get_data()
		if d and d.category == category:
			out.append(i)
	return out


func get_implant_count(id: StringName) -> int:
	var n := 0
	for i in instances:
		if i.cyberware_id == id:
			n += 1
	return n


## Adds a unit. Returns false for unknown cyberware ids.
func add_instance(inst: ImplantInstance) -> bool:
	if inst == null or CyberwareManager.get_cyberware(inst.cyberware_id) == null:
		push_warning("InventoryManager: rejected invalid implant '%s'" % (inst.cyberware_id if inst else &"null"))
		return false
	instances.append(inst)
	EventBus.inventory_changed.emit()
	return true


func add_implant(id: StringName, amount: int = 1) -> bool:
	var ok := true
	for i in amount:
		ok = add_instance(ImplantInstance.create(id)) and ok
	return ok


func remove_instance(uid: String) -> bool:
	for k in instances.size():
		if instances[k].uid == uid:
			instances.remove_at(k)
			EventBus.inventory_changed.emit()
			return true
	return false


func remove_first_where(predicate: Callable) -> bool:
	for i in instances:
		if predicate.call(i):
			return remove_instance(i.uid)
	return false


## Removes and returns a unit of `id` (pristine supply units first).
func consume_implant(id: StringName) -> ImplantInstance:
	var pick: ImplantInstance = null
	for i in instances:
		if i.cyberware_id == id and (pick == null or i.condition > pick.condition):
			pick = i
	if pick:
		remove_instance(pick.uid)
	return pick


func implant_price(item: CyberwareData) -> int:
	return int(round(item.price * ModifierManager.mult(&"price.buy")))


func buy_implant(id: StringName) -> bool:
	var item := CyberwareManager.get_cyberware(id)
	if item == null or item.black_market or not CyberwareManager.is_tier_available(item.tier):
		return false
	if not EconomyManager.spend(implant_price(item), &"cyberware"):
		return false
	return add_implant(id)


# --- Resources -----------------------------------------------------------------

func add_supplies(n: int) -> void:
	supplies = clampi(supplies + n, 0, ClinicManager.get_supplies_capacity())
	EventBus.resources_changed.emit()


func buy_supply_pack() -> bool:
	if supplies >= ClinicManager.get_supplies_capacity():
		return false
	if not EconomyManager.spend(int(round(GameConfig.SUPPLY_PACK_PRICE * ModifierManager.mult(&"price.buy"))), &"supplies"):
		return false
	add_supplies(GameConfig.SUPPLY_PACK_SIZE)
	return true


## Uses supplies for an operation. Returns false if there weren't enough.
func use_supplies(n: int) -> bool:
	var need := maxi(0, int(round(n * ModifierManager.mult(&"supplies.use"))))
	var enough := supplies >= need
	supplies = maxi(0, supplies - need)
	EventBus.resources_changed.emit()
	return enough


func add_parts(n: int) -> void:
	parts = maxi(0, parts + n)
	EventBus.resources_changed.emit()


func add_tokens(n: int) -> void:
	tokens = maxi(0, tokens + n)
	EventBus.resources_changed.emit()


# --- Selling from storage (3.10) -------------------------------------------------
## Unwanted stock goes back for the black market's own resale share
## (black_market.json sell_ratio) of the list price, x its condition, and
## never more than 80% of what you'd pay for it today: no buy-low /
## sell-high loop, whatever discounts stack up. Implant units use the black
## market's sell_value as is. Not sellable here: unidentified devices (they
## have their own routes), basic kit (no resale value), salvaged parts (the
## scrap stalls) and tokens (black-market currency), nor anything the job
## you're planning needs.

func resale_ratio() -> float:
	return float(BlackMarketManager.config.get("sell_ratio", 0.45))


## What one unit fetches (0 = no resale value).
func sell_value(kind: StringName, key: String) -> int:
	match kind:
		&"implant":
			var inst := get_instance(key)
			if inst == null or not inst.identified:
				return 0
			var v := BlackMarketManager.sell_value(inst)
			var data := inst.get_data()
			# Black-market units sell exactly as the market buys them back
			# (BlackMarketManager.sell); stock units also stay under 80% of
			# today's supply price.
			if data and inst.source != &"black_market" and not data.black_market:
				v = mini(v, int(implant_price(data) * 0.8))
			return maxi(0, v)
		&"tool":
			var t := get_tool(StringName(key))
			if t == null or t.starter or t.price <= 0:
				return 0
			var v := int(round(t.price * resale_ratio() * get_tool_condition(t.id) / 100.0))
			return maxi(0, mini(v, int(tool_price(t) * 0.8)))
		&"supplies":
			var unit := GameManager.supply_unit_cost()
			var v := int(round(unit * resale_ratio()))
			return maxi(1, mini(v, int(unit * ModifierManager.mult(&"price.buy") * 0.8)))
	return 0


## What the operation being planned needs from storage (empty when no job is
## planned or under way): {implant: uid, tools: {category: min tier}, supplies}.
func reserved_for_job() -> Dictionary:
	var out := {"implant": "", "tools": {}, "supplies": 0}
	var planning := GameManager.chosen_diagnosis_id != &"" or SurgeryManager.is_active
	var surgery := GameManager.get_current_surgery()
	var item := GameManager.get_requested_item()
	if not planning or surgery == null:
		return out
	var inst := GameManager.get_selected_implant()
	if inst:
		out["implant"] = inst.uid
	var tools: Dictionary = out["tools"]
	for cat in surgery.get_required_tool_categories():
		tools[cat] = maxi(int(tools.get(cat, 1)), 1)
	if item:
		for req in item.get_tool_requirements():
			tools[req["category"]] = maxi(int(tools.get(req["category"], 1)), int(req["tier"]))
	out["supplies"] = surgery.supplies
	return out


## Supplies you can sell without leaving the planned job short.
func spare_supplies() -> int:
	return maxi(0, supplies - int(reserved_for_job()["supplies"]))


## "" if it can be sold, else why not (player-facing).
func sell_block_reason(kind: StringName, key: String, qty: int = 1) -> String:
	var held := reserved_for_job()
	match kind:
		&"implant":
			var inst := get_instance(key)
			if inst == null:
				return "It's no longer in storage."
			if not inst.identified:
				return "Nobody knows what it is yet: analyse it or take it to the Undermarket first."
			if str(held["implant"]) == inst.uid:
				return "It's the unit for the operation you're planning."
		&"tool":
			var t := get_tool(StringName(key))
			if t == null or not owns_tool(t.id):
				return "It's no longer in storage."
			if t.starter or t.price <= 0:
				return "Basic kit has no resale value."
			var need: Dictionary = held["tools"]
			if need.has(t.category) and get_best_tool(t.category) == t:
				# Would what's left still do the planned job?
				var left := 0
				for id in owned_tools:
					var o := get_tool(id)
					if o and o != t and o.category == t.category:
						left = maxi(left, o.tier)
				if left < int(need[t.category]):
					return "The operation you're planning needs it."
		&"supplies":
			if qty < 1:
				return "Pick how many to sell."
			if qty > spare_supplies():
				return "You have %d spare (%d set aside for the operation you're planning)." % [spare_supplies(), int(held["supplies"])] if int(held["supplies"]) > 0 else "You only have %d." % supplies
		_:
			return "This can't be sold from storage."
	if sell_value(kind, key) <= 0:
		return "Nobody would pay for it."
	return ""


## Sells `qty` of an item from storage. Returns the credits received (0 if
## nothing was sold: the reason is sell_block_reason). One call is one sale,
## so a second click on a stale button finds nothing left to sell.
func sell(kind: StringName, key: String, qty: int = 1) -> int:
	if sell_block_reason(kind, key, qty) != "":
		return 0
	var each := sell_value(kind, key)
	var total := 0
	match kind:
		&"implant":
			var inst := get_instance(key)
			if inst.source == &"black_market":
				return BlackMarketManager.sell(key)  # tokens and the market's memory, as it always did
			total = each
			remove_instance(key)
			EconomyManager.add_money(total, &"cyberware")
		&"tool":
			var id := StringName(key)
			total = each
			owned_tools.erase(id)
			tool_condition.erase(id)
			EconomyManager.add_money(total, &"tools")
			EventBus.inventory_changed.emit()
			EventBus.modifiers_changed.emit()
		&"supplies":
			total = each * qty
			supplies -= qty
			EconomyManager.add_money(total, &"supplies")
			EventBus.resources_changed.emit()
	return total


# --- Save ----------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var tools: Array[String] = []
	for id in owned_tools:
		tools.append(String(id))
	var inst := []
	for i in instances:
		inst.append(i.to_dict())
	var cond := {}
	for id: StringName in tool_condition:
		cond[String(id)] = snappedf(float(tool_condition[id]), 0.1)
	return {"owned_tools": tools, "instances": inst, "supplies": supplies, "parts": parts, "tokens": tokens, "tool_condition": cond}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for id: Variant in data.get("owned_tools", []):
		var sid := StringName(str(id))
		if tool_catalog.has(sid) and not owned_tools.has(sid):
			owned_tools.append(sid)
	if data.has("instances"):
		instances.clear()
		for d: Variant in data["instances"]:
			if typeof(d) == TYPE_DICTIONARY:
				var inst := ImplantInstance.from_dict(d)
				if CyberwareManager.get_cyberware(inst.cyberware_id):
					instances.append(inst)
	var cond: Variant = data.get("tool_condition", {})
	if typeof(cond) == TYPE_DICTIONARY:
		for key: Variant in cond:
			var sid := StringName(str(key))
			if tool_catalog.has(sid):
				tool_condition[sid] = clampf(float(cond[key]), 0.0, 100.0)
	supplies = int(data.get("supplies", GameConfig.STARTING_SUPPLIES))
	parts = int(data.get("parts", GameConfig.STARTING_PARTS))
	tokens = int(data.get("tokens", GameConfig.STARTING_TOKENS))
	EventBus.inventory_changed.emit()
	EventBus.modifiers_changed.emit()
