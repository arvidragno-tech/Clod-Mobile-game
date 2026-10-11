class_name ComplicationData
extends Resource
## A mid-surgery emergency. The player must trigger `counter_action` (one of
## GameConfig.QUICK_ACTIONS) within `time_limit` seconds.

@export var id: StringName
@export var title: String
@export var message: String
@export var counter_action: StringName
@export var time_limit: float = 6.0
## Applied immediately when the complication starts (same keys as mistakes).
@export var onset_effects: Dictionary = {}
## Applied if the player fails to counter in time.
@export var failure_effects: Dictionary = {}
## Eligibility: {"min_neural_load": float, "requires_condition": id}.
@export var conditions: Dictionary = {}


static func from_dict(d: Dictionary) -> ComplicationData:
	var c := ComplicationData.new()
	c.id = StringName(DataLoader.get_str(d, "id"))
	c.title = DataLoader.get_str(d, "title")
	c.message = DataLoader.get_str(d, "message")
	c.counter_action = StringName(DataLoader.get_str(d, "counter_action"))
	c.time_limit = DataLoader.get_float(d, "time_limit", 6.0)
	c.onset_effects = DataLoader.get_dict(d, "onset_effects")
	c.failure_effects = DataLoader.get_dict(d, "failure_effects")
	c.conditions = DataLoader.get_dict(d, "conditions")
	return c


## Whether this complication can happen to `customer` at `neural_load`.
func is_eligible(customer: CustomerData, neural_load: float) -> bool:
	if conditions.has("min_neural_load") and neural_load < float(conditions["min_neural_load"]):
		return false
	if conditions.has("requires_condition"):
		return customer != null and customer.hidden_conditions.has(StringName(str(conditions["requires_condition"])))
	return true
