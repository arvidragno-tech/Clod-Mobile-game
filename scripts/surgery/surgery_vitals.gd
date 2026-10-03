class_name SurgeryVitals
extends RefCounted
## Patient vital signs during an operation and how they evolve over time.
## Pure simulation: no nodes, no UI, fully unit-testable.

const MAX := GameConfig.VITAL_MAX

var health: float = GameConfig.START_HEALTH
var blood_loss: float = GameConfig.START_BLOOD_LOSS
var pain: float = GameConfig.START_PAIN
var neural: float = GameConfig.START_NEURAL
## Blood loss in % per second while the wound is open.
var bleed_rate: float = 0.0
var wound_open: bool = false
var sedated: bool = false
## Extra pain floor caused by underdosing sedation (reduced by SEDATE).
var pain_baseline_penalty: float = 0.0

var bleed_multiplier: float = 1.0
var pain_multiplier: float = 1.0
var neural_multiplier: float = 1.0


func configure_for(customer: CustomerData) -> void:
	if customer == null:
		return
	bleed_multiplier = customer.bleed_multiplier
	pain_multiplier = 1.0 / maxf(customer.pain_tolerance, 0.1)
	neural_multiplier = customer.neural_sensitivity


func get_pain_baseline() -> float:
	var base := GameConfig.SEDATION_PAIN_BASELINE_MIN if sedated else GameConfig.START_PAIN
	return clampf(base + pain_baseline_penalty, 0.0, MAX)


func set_wound_open(open: bool) -> void:
	wound_open = open
	if open:
		bleed_rate = maxf(bleed_rate, GameConfig.OPEN_WOUND_BLEED_RATE)
	else:
		bleed_rate = 0.0


func tick(delta: float) -> void:
	# Bleeding and clotting.
	if wound_open:
		blood_loss += bleed_rate * bleed_multiplier * delta
		bleed_rate = maxf(GameConfig.OPEN_WOUND_BLEED_RATE, bleed_rate - GameConfig.CLOT_RATE_PER_SEC * delta)
	# Heavy blood loss drains health.
	var excess_blood := maxf(0.0, blood_loss - GameConfig.BLOOD_LOSS_SAFE)
	health -= excess_blood * GameConfig.HEALTH_DRAIN_PER_BLOOD * delta
	# Pain settles toward the sedation baseline.
	pain = move_toward(pain, get_pain_baseline(), GameConfig.PAIN_SETTLE_RATE * delta)
	# Sustained pain destabilises the neural link; calm patients slowly recover.
	var excess_pain := maxf(0.0, pain - GameConfig.PAIN_SAFE)
	if excess_pain > 0.0:
		neural -= excess_pain * GameConfig.NEURAL_DRAIN_PER_PAIN * neural_multiplier * delta
	else:
		neural += GameConfig.NEURAL_RECOVERY_PER_SEC * delta
	_clamp_all()


## Applies an effect dictionary (keys: bleed_rate, blood, pain, health,
## neural, pain_baseline). Customer multipliers are applied to harmful deltas.
func apply_effects(effects: Dictionary, scale: float = 1.0) -> void:
	for key: Variant in effects:
		var value := float(effects[key]) * scale
		match String(key):
			"bleed_rate":
				if wound_open or value < 0.0:
					bleed_rate = clampf(bleed_rate + value * (bleed_multiplier if value > 0.0 else 1.0), 0.0, GameConfig.MAX_BLEED_RATE)
					if wound_open:
						bleed_rate = maxf(bleed_rate, GameConfig.OPEN_WOUND_BLEED_RATE)
			"blood":
				blood_loss += value * (bleed_multiplier if value > 0.0 else 1.0)
			"pain":
				pain += value * (pain_multiplier if value > 0.0 else 1.0)
			"health":
				health += value
			"neural":
				neural += value * (neural_multiplier if value < 0.0 else 1.0)
			"pain_baseline":
				pain_baseline_penalty = maxf(0.0, pain_baseline_penalty + value)
			_:
				push_warning("SurgeryVitals: unknown effect '%s'" % key)
	_clamp_all()


## Returns &"" while the patient is alive, otherwise the failure reason.
func get_failure_reason() -> StringName:
	if health <= 0.0:
		return &"flatline"
	if neural <= 0.0:
		return &"neural_collapse"
	return &""


func get_value(vital: StringName) -> float:
	match vital:
		&"health":
			return health
		&"blood_loss":
			return blood_loss
		&"pain":
			return pain
		&"neural":
			return neural
	return 0.0


func _clamp_all() -> void:
	health = clampf(health, 0.0, MAX)
	blood_loss = clampf(blood_loss, 0.0, MAX)
	pain = clampf(pain, 0.0, MAX)
	neural = clampf(neural, 0.0, MAX)
