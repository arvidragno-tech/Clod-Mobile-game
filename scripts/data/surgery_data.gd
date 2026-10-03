class_name SurgeryData
extends Resource
## A full operation: ordered stages, rewards and diagnosis options.
## Loaded from data/surgeries.json.

@export var id: StringName
@export var display_name: String
@export var code: String
@export_multiline var description: String
@export var cyberware_id: StringName
@export var base_pay: int
@export var base_xp: int
@export var target_time_sec: float = 150.0
@export var stages: Array[SurgeryStageData] = []
## Array of {id, name, description}.
@export var diagnosis_options: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> SurgeryData:
	var s := SurgeryData.new()
	s.id = StringName(DataLoader.get_str(d, "id"))
	s.display_name = DataLoader.get_str(d, "name")
	s.code = DataLoader.get_str(d, "code")
	s.description = DataLoader.get_str(d, "description")
	s.cyberware_id = StringName(DataLoader.get_str(d, "cyberware"))
	s.base_pay = DataLoader.get_int(d, "base_pay")
	s.base_xp = DataLoader.get_int(d, "base_xp")
	s.target_time_sec = DataLoader.get_float(d, "target_time_sec", 150.0)
	for stage_dict: Variant in DataLoader.get_array(d, "stages"):
		s.stages.append(SurgeryStageData.from_dict(stage_dict))
	for option: Variant in DataLoader.get_array(d, "diagnosis_options"):
		if typeof(option) == TYPE_DICTIONARY:
			s.diagnosis_options.append(option)
	return s


func get_diagnosis_name(diagnosis_id: StringName) -> String:
	for option in diagnosis_options:
		if StringName(str(option.get("id", ""))) == diagnosis_id:
			return str(option.get("name", diagnosis_id))
	return String(diagnosis_id)


## Tool categories needed by this surgery, in stage order, without duplicates.
func get_required_tool_categories() -> Array[StringName]:
	var out: Array[StringName] = []
	for stage in stages:
		if stage.tool_category != &"" and not out.has(stage.tool_category):
			out.append(stage.tool_category)
	return out
