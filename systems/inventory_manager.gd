extends Node
## Owned tools and implant stock.

var tool_catalog: Dictionary = {}  # StringName -> ToolData
var owned_tools: Array[StringName] = []
var implant_stock: Dictionary = {}  # StringName -> int


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
	implant_stock = GameConfig.STARTING_IMPLANT_STOCK.duplicate()


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


func has_tool_category(category: StringName) -> bool:
	return get_best_tool(category) != null


## Tools that can be bought at the supply terminal and are not owned yet.
func get_purchasable_tools() -> Array[ToolData]:
	var out: Array[ToolData] = []
	for t: ToolData in tool_catalog.values():
		if not t.starter and t.price > 0 and not owns_tool(t.id):
			out.append(t)
	return out


func buy_tool(id: StringName) -> bool:
	var t := get_tool(id)
	if t == null or owns_tool(id) or not EconomyManager.spend(t.price):
		return false
	owned_tools.append(id)
	EventBus.inventory_changed.emit()
	return true


func get_implant_count(id: StringName) -> int:
	return int(implant_stock.get(id, 0))


func add_implant(id: StringName, amount: int = 1) -> void:
	implant_stock[id] = get_implant_count(id) + amount
	EventBus.inventory_changed.emit()


func consume_implant(id: StringName) -> bool:
	if get_implant_count(id) <= 0:
		return false
	implant_stock[id] = get_implant_count(id) - 1
	EventBus.inventory_changed.emit()
	return true


func buy_implant(id: StringName) -> bool:
	var item := CyberwareManager.get_cyberware(id)
	if item == null or not EconomyManager.spend(item.price):
		return false
	add_implant(id)
	return true


func get_save_data() -> Dictionary:
	var tools: Array[String] = []
	for id in owned_tools:
		tools.append(String(id))
	var stock := {}
	for id: StringName in implant_stock:
		stock[String(id)] = implant_stock[id]
	return {"owned_tools": tools, "implant_stock": stock}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for id: Variant in data.get("owned_tools", []):
		var sid := StringName(str(id))
		if tool_catalog.has(sid) and not owned_tools.has(sid):
			owned_tools.append(sid)
	var stock: Variant = data.get("implant_stock", null)
	if typeof(stock) == TYPE_DICTIONARY:
		implant_stock.clear()
		for key: Variant in stock:
			implant_stock[StringName(str(key))] = int(stock[key])
	EventBus.inventory_changed.emit()
