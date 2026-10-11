class_name SurgeryScoring
extends RefCounted
## Pure functions turning an operation's raw performance into a grade and
## rewards. Kept separate from SurgeryManager so balance can be unit-tested.


static func grade_for_score(score: float) -> String:
	for threshold: Array in GameConfig.GRADE_THRESHOLDS:
		if score >= float(threshold[0]):
			return String(threshold[1])
	return "D"


static func time_modifier(elapsed: float, target: float) -> float:
	if target <= 0.0:
		return 0.0
	if elapsed <= target:
		return GameConfig.TIME_BONUS_MAX * (1.0 - elapsed / target)
	var over := (elapsed - target) / GameConfig.TIME_PENALTY_SPAN_SEC
	return -GameConfig.TIME_PENALTY_MAX * clampf(over, 0.0, 1.0)


static func compute_score(stage_quality: float, health: float, neural: float, implant_performance: float, elapsed: float, target: float) -> float:
	var score := stage_quality * GameConfig.SCORE_WEIGHT_STAGES
	score += (health / GameConfig.VITAL_MAX) * GameConfig.SCORE_WEIGHT_HEALTH
	score += (neural / GameConfig.VITAL_MAX) * GameConfig.SCORE_WEIGHT_NEURAL
	score += clampf(implant_performance, 0.0, 1.0) * GameConfig.SCORE_WEIGHT_IMPLANT
	score += time_modifier(elapsed, target)
	return clampf(score, 0.0, 1.0)


## Fills grade, pay, xp and reputation on `result` from its raw fields.
static func apply_rewards(result: SurgeryResult, surgery: SurgeryData, customer: CustomerData) -> void:
	var pay_mult := customer.pay_multiplier if customer else 1.0
	if not result.success:
		result.grade = "F"
		result.score = 0.0
		result.pay = 0
		result.xp = int(round(surgery.base_xp * GameConfig.FAILED_XP_FRACTION))
		result.reputation_delta = int(GameConfig.GRADE_REPUTATION["F"])
		return
	result.score = compute_score(result.stage_quality, result.final_health, result.final_neural,
			result.implant_performance, result.elapsed_sec, result.target_time_sec)
	result.grade = grade_for_score(result.score)
	if not result.diagnosis_correct:
		pay_mult *= GameConfig.WRONG_DIAGNOSIS_PAY_MULT
	pay_mult *= result.implant_pay_mult * ModifierManager.mult(&"pay")
	# Your service (scaled by how well it went) plus the part, which the
	# patient pays for at their means (not scaled by your score).
	var service := surgery.base_pay * pay_mult * (0.5 + result.score)
	var part := result.implant_price * GameConfig.IMPLANT_PRICE_MARKUP * minf(pay_mult, 1.0)
	result.pay = int(round(service + part))
	var xp_mult := (0.5 + result.score) * (1.0 + 0.15 * (result.install_difficulty - 1)) * ModifierManager.mult(&"xp")
	if result.diagnosis_correct:
		xp_mult += GameConfig.CORRECT_DIAGNOSIS_XP_BONUS
	result.xp = int(round(surgery.base_xp * xp_mult))
	result.reputation_delta = int(GameConfig.GRADE_REPUTATION.get(result.grade, 0))
