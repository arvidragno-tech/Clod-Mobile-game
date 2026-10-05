extends BaseScreen
## Post-op debrief: grade, breakdown and rewards with count-up animations.

const COUNT_UP_SEC := 0.6
const GRADE_COLORS := {
	"S": Palette.BRAND, "A": Palette.OK, "B": Palette.ACCENT, "C": Palette.WARN, "D": Palette.WARN, "F": Palette.DANGER,
}

@onready var _verdict_card: PanelContainer = %VerdictCard
@onready var _grade: Label = %Grade
@onready var _verdict: Label = %Verdict
@onready var _customer_line: Label = %CustomerLine
@onready var _failure_text: Label = %FailureText
@onready var _stats: GridContainer = %Stats
@onready var _pay: Label = %Pay
@onready var _xp: Label = %Xp
@onready var _rep: Label = %Rep
@onready var _level_bar: ProgressBar = %LevelBar
@onready var _level_up: Label = %LevelUp
@onready var _continue: Button = %ContinueButton

var _result: SurgeryResult


func on_enter(params: Dictionary) -> void:
	_result = params.get("result", GameManager.last_result)
	if _result == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	_continue.pressed.connect(GameManager.finish_results)
	_continue.disabled = true
	_fill()
	_animate()


func _fill() -> void:
	var r := _result
	_grade.text = r.grade
	_grade.add_theme_color_override(&"font_color", GRADE_COLORS.get(r.grade, Palette.TEXT))
	_verdict.text = "SUCCESS" if r.success else "FAILED"
	_verdict.add_theme_color_override(&"font_color", Palette.OK if r.success else Palette.DANGER)
	if not r.success:
		_verdict_card.theme_type_variation = &"DangerPanel"
	_customer_line.text = "%s · %s" % [r.customer_name, r.surgery_name]
	_failure_text.text = r.get_failure_text()
	_failure_text.visible = not r.success
	var secs := int(r.elapsed_sec)
	var target := int(r.target_time_sec)
	_add_stat("TIME", "%d:%02d / %d:%02d" % [secs / 60, secs % 60, target / 60, target % 60], r.elapsed_sec <= r.target_time_sec)
	_add_stat("MISTAKES", str(r.mistakes), r.mistakes <= 1)
	_add_stat("COMPLICATIONS", "%d/%d handled" % [r.complications_handled, r.complications_total], r.complications_handled == r.complications_total)
	_add_stat("HEALTH", "%d" % roundi(r.final_health), r.final_health >= 60.0)
	_add_stat("NEURAL SYNC", "%d" % roundi(r.final_neural), r.final_neural >= 60.0)
	if r.success:
		_add_stat("IMPLANT PERF", "%d%%" % roundi(r.implant_performance * 100.0), r.implant_performance >= 0.75)
	_add_stat("DIAGNOSIS", "CORRECT" if r.diagnosis_correct else "WRONG", r.diagnosis_correct)
	if r.implant_name != "":
		_add_stat("IMPLANT", r.implant_name, not r.black_market_implant)
	_add_stat("NEURAL LOAD", "%d%% %s" % [roundi(r.neural_load_after), NeuralLoad.band(r.neural_load_after)["name"]], r.neural_load_after < 70.0)
	if r.faction_id != &"":
		_add_stat(FactionManager.get_faction(r.faction_id).get("short", "FACTION"), "%+d · %s" % [r.faction_delta, FactionManager.get_standing(r.faction_id)], r.faction_delta >= 0)
	if absf(r.heat_delta) >= 0.5:
		_add_stat("HEAT", "%+d" % roundi(r.heat_delta), r.heat_delta <= 0.0)
	_add_aftermath(r)
	_pay.text = "+%s" % EconomyManager.format_money(0)
	_xp.text = "+0 XP"
	_rep.text = "%+d" % 0
	_level_bar.value = ProgressionManager.get_level_progress() * 100.0
	_level_up.visible = false


func _add_aftermath(r: SurgeryResult) -> void:
	var notes: Array[String] = []
	if r.neural_break:
		notes.append("NEURAL BREAK: the patient's chrome overloaded after they left. People will talk.")
	if bool(r.consequences.get("post_op", false)):
		notes.append("POST-OP: the wound is turning. Expect them back at your door.")
	if bool(r.consequences.get("referral", false)):
		notes.append("They'll send a friend your way.")
	if bool(r.consequences.get("returning", false)):
		notes.append("They'll be back for more chrome.")
	if bool(r.consequences.get("regular", false)):
		notes.append("REGULAR: loyal customer, pays better.")
	for l: Variant in r.settlement.get("lines", []):
		notes.append(str(l))
	if r.levels_gained > 0:
		notes.append("+%d SKILL POINT%s to spend." % [r.levels_gained * GameConfig.SKILL_POINTS_PER_LEVEL, "S" if r.levels_gained > 1 else ""])
	if notes.is_empty():
		return
	var card := UIKit.panel(&"DangerPanel" if r.neural_break else &"CardPanel")
	var v := UIKit.vbox(4)
	card.add_child(v)
	v.add_child(UIKit.label("AFTERMATH", &"SubHeaderLabel"))
	for n in notes:
		v.add_child(UIKit.label(n, &"", true, Palette.DANGER if n.begins_with("NEURAL") else Palette.TEXT, 15))
	card.custom_minimum_size.x = 520
	%LeftCol.add_child(card)


func _add_stat(caption: String, value: String, good: bool) -> void:
	var c := Label.new()
	c.text = caption
	c.theme_type_variation = &"SubHeaderLabel"
	_stats.add_child(c)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = &"MonoLabel"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_color_override(&"font_color", Palette.TEXT if good else Palette.WARN)
	_stats.add_child(v)


func _animate() -> void:
	var r := _result
	_grade.pivot_offset = _grade.size / 2.0
	_grade.scale = Vector2(2.5, 2.5)
	_grade.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(_grade, "modulate:a", 1.0, 0.05)
	t.parallel().tween_property(_grade, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		UIManager.shake(4.0)
		AudioManager.play_sfx(&"success" if r.success else &"failure", 0.0))
	t.tween_interval(0.3)
	if r.pay > 0:
		t.tween_callback(AudioManager.play_sfx.bind(&"cash", 0.0))
	t.tween_method(func(v: int) -> void: _pay.text = "+%s" % EconomyManager.format_money(v), 0, r.pay, COUNT_UP_SEC)
	t.tween_method(func(v: int) -> void: _xp.text = "+%d XP" % v, 0, r.xp, COUNT_UP_SEC)
	t.tween_callback(func() -> void:
		_rep.text = "%+d" % r.reputation_delta
		_rep.add_theme_color_override(&"font_color", Palette.OK if r.reputation_delta >= 0 else Palette.DANGER))
	if r.levels_gained > 0:
		t.tween_callback(func() -> void:
			_level_up.text = "LEVEL UP! NOW LV %d" % ProgressionManager.level
			_level_up.visible = true
			AudioManager.play_sfx(&"levelup", 0.0)
			UIManager.flash(Palette.ACCENT, 0.2)
			UIManager.haptic(&"success"))
	if r.unlocked_tier > 0:
		t.tween_interval(0.4)
		t.tween_callback(func() -> void:
			UIManager.celebrate(&"unlock", "TIER %d CHROME NOW IN SUPPLY" % r.unlocked_tier))
	t.tween_callback(func() -> void:
		_continue.disabled = false
		_continue.grab_focus())


## ESC / ENTER skip the count-up, then continue.
func on_escape() -> bool:
	return true
