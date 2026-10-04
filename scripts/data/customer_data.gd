class_name CustomerData
extends Resource
## A customer: either generated procedurally (CustomerGenerator) or a
## hand-authored recurring character (data/characters.json). Stats below are
## the *effective* values (hidden conditions included); the UI only shows
## what the player has discovered.

@export var id: StringName
@export var display_name: String
@export var alias: String
@export var age: int
@export var occupation: String
@export var archetype_id: StringName
@export var faction_id: StringName
@export var personality: StringName = &"calm"
## 0 broke, 1 getting by, 2 comfortable, 3 loaded.
@export var wealth: int = 1
## The customer's own street notoriety (0..100).
@export var street_rep: int = 10
@export_multiline var dialogue: String
@export var medical_history: Array[String] = []
@export var existing_cyberware: Array[StringName] = []
@export var requested_cyberware_id: StringName
@export var requested_surgery_id: StringName
@export var true_diagnosis_id: StringName
@export var hidden_conditions: Array[StringName] = []
@export var revealed_conditions: Array[StringName] = []
## region_id -> finding text revealed on the diagnosis scan.
@export var scan_findings: Dictionary = {}
## Baseline neural stability (start value of the NEURAL vital).
@export var neural_stability: float = 100.0
@export var patience: int = 50
## 0..1: willingness to accept risky, substituted or black-market chrome.
@export var risk_tolerance: float = 0.5
@export var pay_multiplier: float = 1.0
@export var bleed_multiplier: float = 1.0
## > 1.0 tolerates pain better (the sedation window shifts down).
@export var pain_tolerance: float = 1.0
## > 1.0 loses neural stability faster.
@export var neural_sensitivity: float = 1.0
@export var complication_risk: float = 1.0
@export var health_drain_multiplier: float = 1.0
@export var post_op_risk: float = 0.0
@export var extra_damaged_tissue: int = 0
@export var min_reputation: int = 0
## Part ids + palette choices consumed by CharacterArt.
@export var appearance: Dictionary = {}
@export var character_id: StringName = &""
@export var is_story: bool = false
@export var is_emergency: bool = false
@export var visits: int = 0
@export var referred_by: String = ""


## Authored recurring character (data/characters.json).
static func from_dict(d: Dictionary) -> CustomerData:
	var c := CustomerData.new()
	c.id = StringName(DataLoader.get_str(d, "id"))
	c.character_id = c.id
	c.display_name = DataLoader.get_str(d, "name")
	c.alias = DataLoader.get_str(d, "alias")
	c.age = DataLoader.get_int(d, "age")
	c.occupation = DataLoader.get_str(d, "occupation")
	c.archetype_id = StringName(DataLoader.get_str(d, "archetype", "civilian"))
	c.faction_id = StringName(DataLoader.get_str(d, "faction", "independent_mercs"))
	c.personality = StringName(DataLoader.get_str(d, "personality", "calm"))
	c.wealth = DataLoader.get_int(d, "wealth", 1)
	c.dialogue = DataLoader.get_str(d, "dialogue")
	c.requested_cyberware_id = StringName(DataLoader.get_str(d, "requested_cyberware", "nx1_neural_bridge"))
	c.true_diagnosis_id = StringName(DataLoader.get_str(d, "true_diagnosis", "clean_site"))
	c.scan_findings = DataLoader.get_dict(d, "scan_findings")
	for e: Variant in DataLoader.get_array(d, "existing_cyberware"):
		c.existing_cyberware.append(StringName(str(e)))
	c.appearance = CharacterAppearanceManager.normalize(DataLoader.get_dict(d, "appearance"))
	c.is_story = bool(d.get("story", false))
	var mods := DataLoader.get_dict(d, "modifiers")
	c.pay_multiplier = DataLoader.get_float(mods, "pay", 1.0)
	c.bleed_multiplier = DataLoader.get_float(mods, "bleed", 1.0)
	c.pain_tolerance = DataLoader.get_float(mods, "pain_tolerance", 1.0)
	c.neural_sensitivity = DataLoader.get_float(mods, "neural_sensitivity", 1.0)
	c.complication_risk = DataLoader.get_float(mods, "complication_risk", 1.0)
	c.extra_damaged_tissue = DataLoader.get_int(mods, "extra_damaged_tissue", 0)
	c.min_reputation = DataLoader.get_int(d, "min_reputation", 0)
	c.patience = DataLoader.get_int(d, "patience", 60)
	c.risk_tolerance = DataLoader.get_float(d, "risk_tolerance", 0.5)
	return c


## Applies a hidden condition's modifiers to the effective stats.
func apply_condition(condition: Dictionary) -> void:
	var mods: Dictionary = condition.get("modifiers", {})
	bleed_multiplier += float(mods.get("bleed", 0.0))
	neural_sensitivity += float(mods.get("neural_sensitivity", 0.0))
	pain_tolerance = maxf(0.3, pain_tolerance + float(mods.get("pain_tolerance", 0.0)))
	complication_risk += float(mods.get("complication_risk", 0.0))
	health_drain_multiplier += float(mods.get("health_drain", 0.0))
	neural_stability = clampf(neural_stability + float(mods.get("start_neural", 0.0)), 20.0, 100.0)
	post_op_risk += float(mods.get("post_op", 0.0))


func get_neural_load() -> float:
	return NeuralLoad.compute(self)


## Coarse 1-3 risk rating from what the doctor can see.
func get_risk_level() -> int:
	var risk := (bleed_multiplier + neural_sensitivity + complication_risk + 1.0 / maxf(pain_tolerance, 0.1)) / 4.0
	risk += maxf(0.0, get_neural_load() - 50.0) / 100.0
	if risk < 0.95:
		return 1
	if risk < 1.15:
		return 2
	return 3


func get_display_title() -> String:
	return "%s \"%s\"" % [display_name, alias] if alias != "" else display_name


func to_save_dict() -> Dictionary:
	var d := {}
	for prop in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = get(prop["name"])
			if typeof(v) == TYPE_STRING_NAME:
				v = String(v)
			elif typeof(v) == TYPE_ARRAY:
				var arr := []
				for e: Variant in v:
					arr.append(String(e) if typeof(e) == TYPE_STRING_NAME else e)
				v = arr
			d[prop["name"]] = v
	return d


static func from_save_dict(d: Dictionary) -> CustomerData:
	var c := CustomerData.new()
	for prop in c.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) or not d.has(prop["name"]):
			continue
		var name: String = prop["name"]
		var current: Variant = c.get(name)
		var value: Variant = d[name]
		match typeof(current):
			TYPE_STRING_NAME:
				c.set(name, StringName(str(value)))
			TYPE_ARRAY:
				var arr: Array = c.get(name)
				arr.clear()
				for e: Variant in value:
					if arr.get_typed_builtin() == TYPE_STRING_NAME:
						arr.append(StringName(str(e)))
					else:
						arr.append(str(e))
			TYPE_INT:
				c.set(name, int(value))
			TYPE_FLOAT:
				c.set(name, float(value))
			TYPE_BOOL:
				c.set(name, bool(value))
			_:
				c.set(name, value)
	return c
