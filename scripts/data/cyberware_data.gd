class_name CyberwareData
extends Resource
## An installable implant. Loaded from data/cyberware.json.

@export var id: StringName
@export var display_name: String
@export var manufacturer: String
@export var category: StringName
@export var tier: int = 1
@export_multiline var description: String
@export var price: int
@export var icon_path: String
@export var install_surgery_id: StringName
@export var base_performance: float = 1.0
## Hidden from the supply terminal until the black market opens (Step 2+).
@export var black_market: bool = false


static func from_dict(d: Dictionary) -> CyberwareData:
	var c := CyberwareData.new()
	c.id = StringName(DataLoader.get_str(d, "id"))
	c.display_name = DataLoader.get_str(d, "name")
	c.manufacturer = DataLoader.get_str(d, "manufacturer")
	c.category = StringName(DataLoader.get_str(d, "category"))
	c.tier = DataLoader.get_int(d, "tier", 1)
	c.description = DataLoader.get_str(d, "description")
	c.price = DataLoader.get_int(d, "price")
	c.icon_path = DataLoader.get_str(d, "icon")
	c.install_surgery_id = StringName(DataLoader.get_str(d, "install_surgery"))
	c.base_performance = DataLoader.get_float(d, "base_performance", 1.0)
	c.black_market = bool(d.get("black_market", false))
	return c
