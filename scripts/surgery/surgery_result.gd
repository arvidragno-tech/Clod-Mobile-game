class_name SurgeryResult
extends RefCounted
## Outcome of a finished (or failed/aborted) operation.

var surgery_id: StringName
var surgery_name: String
var customer_name: String
var success: bool = false
## &"" on success, otherwise &"flatline", &"neural_collapse" or &"aborted".
var failure_reason: StringName = &""
var grade: String = "F"
var score: float = 0.0
var pay: int = 0
var xp: int = 0
var reputation_delta: int = 0
var elapsed_sec: float = 0.0
var target_time_sec: float = 0.0
var mistakes: int = 0
var complications_total: int = 0
var complications_handled: int = 0
var stage_quality: float = 0.0
var implant_performance: float = 0.0
var final_health: float = 0.0
var final_neural: float = 0.0
var final_blood_loss: float = 0.0
var diagnosis_correct: bool = false
var implant_id: StringName
var implant_name: String = ""
var implant_price: int = 0
var install_difficulty: int = 1
var neural_load_before: float = 0.0
var neural_load_after: float = 0.0
var black_market_implant: bool = false
var implant_pay_mult: float = 1.0
## Filled in by GameManager after rewards are applied.
var levels_gained: int = 0
var faction_id: StringName
var faction_delta: int = 0
var heat_delta: float = 0.0
var neural_break: bool = false
## Customer consequences: {"referral": bool, "returning": bool, "regular": bool}
var consequences: Dictionary = {}


func get_failure_text() -> String:
	match failure_reason:
		&"flatline":
			return "Patient flatlined. Trauma crew hauled them out the back."
		&"neural_collapse":
			return "Neural link collapsed. The implant fried the relay."
		&"aborted":
			return "You aborted the operation and patched the patient up."
	return ""
