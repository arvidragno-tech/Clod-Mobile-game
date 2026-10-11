class_name SurgeryStageData
extends Resource
## One step of a surgery. `type` selects the interaction scene (see
## SurgeryStageRegistry); `params` tunes that interaction.

@export var id: StringName
@export var type: StringName
@export var title: String
@export var instruction: String
## Tool category the player must select ("" = no tool, stage has own controls).
@export var tool_category: StringName
@export var params: Dictionary = {}
## Whether a complication may trigger while this stage is active.
@export var complication_window: bool = false


static func from_dict(d: Dictionary) -> SurgeryStageData:
	var s := SurgeryStageData.new()
	s.id = StringName(DataLoader.get_str(d, "id"))
	s.type = StringName(DataLoader.get_str(d, "type"))
	s.title = DataLoader.get_str(d, "title")
	s.instruction = DataLoader.get_str(d, "instruction")
	s.tool_category = StringName(DataLoader.get_str(d, "tool"))
	s.params = DataLoader.get_dict(d, "params")
	s.complication_window = bool(d.get("complication_window", false))
	return s


func param_float(key: String, fallback: float) -> float:
	return float(params.get(key, fallback))


func param_int(key: String, fallback: int) -> int:
	return int(params.get(key, fallback))


func param_vec2(key: String, fallback: Vector2) -> Vector2:
	var v: Variant = params.get(key)
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


func param_vec2_array(key: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v: Variant in params.get(key, []):
		if typeof(v) == TYPE_ARRAY and v.size() >= 2:
			out.append(Vector2(float(v[0]), float(v[1])))
	return out
