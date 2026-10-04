class_name ToolData
extends Resource
## A surgical tool. Tools of the same category are interchangeable; the
## highest-tier owned tool of a category is used. Loaded from data/tools.json.

@export var id: StringName
@export var display_name: String
@export var category: StringName
@export var tier: int = 1
@export_multiline var description: String
@export var price: int
@export var icon_path: String
## Multiplies interaction tolerances (e.g. how far a cut may drift).
@export var precision: float = 1.0
## Multiplies work speed (e.g. how fast the cauteriser burns tissue).
@export var speed: float = 1.0
## Multiplies complication chance while this tool is in use (<1 = safer).
@export var risk: float = 1.0
@export var unlock_level: int = 1
@export var starter: bool = false
## Passive modifiers granted while owned (ModifierManager keys).
@export var modifiers: Dictionary = {}


static func from_dict(d: Dictionary) -> ToolData:
	var t := ToolData.new()
	t.id = StringName(DataLoader.get_str(d, "id"))
	t.display_name = DataLoader.get_str(d, "name")
	t.category = StringName(DataLoader.get_str(d, "category"))
	t.tier = DataLoader.get_int(d, "tier", 1)
	t.description = DataLoader.get_str(d, "description")
	t.price = DataLoader.get_int(d, "price")
	t.icon_path = DataLoader.get_str(d, "icon")
	t.precision = DataLoader.get_float(d, "precision", 1.0)
	t.speed = DataLoader.get_float(d, "speed", 1.0)
	t.risk = DataLoader.get_float(d, "risk", 1.0)
	t.unlock_level = DataLoader.get_int(d, "unlock_level", 1)
	t.starter = bool(d.get("starter", false))
	t.modifiers = DataLoader.get_dict(d, "modifiers")
	return t
