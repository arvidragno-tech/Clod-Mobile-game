class_name CustomerData
extends Resource
## A customer archetype. Loaded from data/customers.json.

@export var id: StringName
@export var display_name: String
@export var alias: String
@export var age: int
@export var occupation: String
@export_multiline var dialogue: String
@export var portrait_path: String
@export var sprite_path: String
@export var skin_color: Color = Color("b07a5a")
@export var requested_surgery_id: StringName
@export var true_diagnosis_id: StringName
## region_id -> finding text revealed on the diagnosis scan.
@export var scan_findings: Dictionary = {}
@export var pay_multiplier: float = 1.0
@export var bleed_multiplier: float = 1.0
## > 1.0 tolerates pain better (the sedation window shifts down).
@export var pain_tolerance: float = 1.0
## > 1.0 loses neural stability faster.
@export var neural_sensitivity: float = 1.0
@export var complication_risk: float = 1.0
@export var extra_damaged_tissue: int = 0
@export var min_reputation: int = 0


static func from_dict(d: Dictionary) -> CustomerData:
	var c := CustomerData.new()
	c.id = StringName(DataLoader.get_str(d, "id"))
	c.display_name = DataLoader.get_str(d, "name")
	c.alias = DataLoader.get_str(d, "alias")
	c.age = DataLoader.get_int(d, "age")
	c.occupation = DataLoader.get_str(d, "occupation")
	c.dialogue = DataLoader.get_str(d, "dialogue")
	c.portrait_path = DataLoader.get_str(d, "portrait")
	c.sprite_path = DataLoader.get_str(d, "sprite")
	c.skin_color = Color(DataLoader.get_str(d, "skin_color", "b07a5a"))
	c.requested_surgery_id = StringName(DataLoader.get_str(d, "requested_surgery"))
	c.true_diagnosis_id = StringName(DataLoader.get_str(d, "true_diagnosis"))
	c.scan_findings = DataLoader.get_dict(d, "scan_findings")
	var mods := DataLoader.get_dict(d, "modifiers")
	c.pay_multiplier = DataLoader.get_float(mods, "pay", 1.0)
	c.bleed_multiplier = DataLoader.get_float(mods, "bleed", 1.0)
	c.pain_tolerance = DataLoader.get_float(mods, "pain_tolerance", 1.0)
	c.neural_sensitivity = DataLoader.get_float(mods, "neural_sensitivity", 1.0)
	c.complication_risk = DataLoader.get_float(mods, "complication_risk", 1.0)
	c.extra_damaged_tissue = DataLoader.get_int(mods, "extra_damaged_tissue", 0)
	c.min_reputation = DataLoader.get_int(d, "min_reputation", 0)
	return c


## A coarse 1-3 risk rating used by the UI.
func get_risk_level() -> int:
	var risk := (bleed_multiplier + neural_sensitivity + complication_risk + 1.0 / maxf(pain_tolerance, 0.1)) / 4.0
	if risk < 0.95:
		return 1
	if risk < 1.15:
		return 2
	return 3
