extends Node
## Owned tools, implant units (ImplantInstance) and consumable resources:
## medical supplies, salvaged parts and black-market tokens.

var tool_catalog: Dictionary = {}  # StringName -> ToolData
var owned_tools: Array[StringName] = []
var instances: Array[ImplantInstance] = []
var supplies: int = 0
var parts: int = 0
var tokens: int = 0


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
	if not EconomyManager.spend(tool_price(t)):
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
	if not EconomyManager.spend(implant_price(item)):
		return false
	return add_implant(id)


# --- Resources -----------------------------------------------------------------

func add_supplies(n: int) -> void:
	supplies = clampi(supplies + n, 0, ClinicManager.get_supplies_capacity())
	EventBus.resources_changed.emit()


func buy_supply_pack() -> bool:
	if supplies >= ClinicManager.get_supplies_capacity():
		return false
	if not EconomyManager.spend(int(round(GameConfig.SUPPLY_PACK_PRICE * ModifierManager.mult(&"price.buy")))):
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


# --- Save ----------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var tools: Array[String] = []
	for id in owned_tools:
		tools.append(String(id))
	var inst := []
	for i in instances:
		inst.append(i.to_dict())
	return {"owned_tools": tools, "instances": inst, "supplies": supplies, "parts": parts, "tokens": tokens}


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
	supplies = int(data.get("supplies", GameConfig.STARTING_SUPPLIES))
	parts = int(data.get("parts", GameConfig.STARTING_PARTS))
	tokens = int(data.get("tokens", GameConfig.STARTING_TOKENS))
	EventBus.inventory_changed.emit()
	EventBus.modifiers_changed.emit()
