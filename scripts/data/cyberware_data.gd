class_name CyberwareData
extends Resource
## An installable implant model. Loaded from data/cyberware.json.
## Individual physical units are ImplantInstance objects.

const CATEGORIES: Array[StringName] = [&"eyes", &"arms", &"legs", &"spine", &"neural", &"dermal", &"respiratory", &"internal"]
const TIER_NAMES := {1: "CIVILIAN", 2: "PROFESSIONAL", 3: "MILITARY", 4: "EXPERIMENTAL", 5: "PROTOTYPE"}
const RARITY_COLORS := {"common": Color("8e9aa8"), "uncommon": Color("6dff8a"), "rare": Color("3a8cff"), "epic": Color("c46aff"), "legendary": Color("ff3d81")}

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
@export var black_market: bool = false
@export var install_difficulty: int = 1
## Percentage points of neural load this implant adds.
@export var neural_load: float = 5.0
## Entries like "drill:1" (category:min_tier).
@export var required_tools: Array[String] = []
## Extra complication chance during installation (0..1).
@export var failure_risk: float = 0.0
@export var benefits: Array[String] = []
@export var complication_ids: Array[StringName] = []
@export var rarity: String = "common"
@export var origin: String = ""
## Number of hidden traits a black-market unit rolls.
@export var unknown_traits: int = 0


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
	c.install_difficulty = DataLoader.get_int(d, "install_difficulty", 1)
	c.neural_load = DataLoader.get_float(d, "neural_load", 5.0)
	for t: Variant in DataLoader.get_array(d, "required_tools"):
		c.required_tools.append(str(t))
	c.failure_risk = DataLoader.get_float(d, "failure_risk", 0.0)
	for b: Variant in DataLoader.get_array(d, "benefits"):
		c.benefits.append(str(b))
	for comp: Variant in DataLoader.get_array(d, "complications"):
		c.complication_ids.append(StringName(str(comp)))
	c.rarity = DataLoader.get_str(d, "rarity", "common")
	c.origin = DataLoader.get_str(d, "origin")
	c.unknown_traits = DataLoader.get_int(d, "unknown_traits", 0)
	return c


## Parsed required tools: Array of {"category": StringName, "tier": int}.
func get_tool_requirements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in required_tools:
		var parts := entry.split(":")
		out.append({"category": StringName(parts[0]), "tier": int(parts[1]) if parts.size() > 1 else 1})
	return out


func get_tier_name() -> String:
	return TIER_NAMES.get(tier, "?")


func get_rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)


## Multiplier applied to stage tolerances: harder installs are less forgiving.
func get_difficulty_factor() -> float:
	return 1.0 + GameConfig.DIFFICULTY_TOLERANCE_STEP * float(install_difficulty - 1)
