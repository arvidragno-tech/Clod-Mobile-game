class_name SurgeryScreen
extends BaseScreen
## The operating table. Hosts the current stage interaction on top of the
## persistent SurgicalSiteView, shows vitals, the tool tray and emergency
## quick actions, and turns SurgeryManager / stage events into feedback.

const QUICK_ICONS := {
	&"coag": "res://assets/sprites/ui/icons/coag.png",
	&"sedate": "res://assets/sprites/ui/icons/sedate.png",
	&"stabilize": "res://assets/sprites/ui/icons/stabilize.png",
}
const BLEEDING_MISTAKES: Array[StringName] = [&"cut_deviation", &"tissue_tear", &"bad_stitch"]
const BURN_SFX_INTERVAL := 0.15
const MISTAKE_SHAKE := 5.0

@onready var _stage_counter: Label = %StageCounter
@onready var _stage_title: Label = %StageTitle
@onready var _timer: Label = %Timer
@onready var _abort: Button = %AbortButton
@onready var _health_bar: VitalBar = %HealthBar
@onready var _blood_bar: VitalBar = %BloodBar
@onready var _pain_bar: VitalBar = %PainBar
@onready var _neural_bar: VitalBar = %NeuralBar
@onready var _instruction: Label = %Instruction
@onready var _field_area: Control = %FieldArea
@onready var _field_viewport: SubViewportContainer = %FieldViewport
@onready var _site: SurgicalSiteView = %SiteView
@onready var _stage_host: Control = %StageHost
@onready var _fx: FxLayer = %Fx
@onready var _fx_text: FxLayer = %FxText
@onready var _lighting: SurgeryLighting = %Lighting
@onready var _ecg: EcgStrip = %Ecg
@onready var _neural_load: Label = %NeuralLoad
@onready var _tray_scroll: ScrollContainer = %TrayScroll
@onready var _complication_banner: PanelContainer = %ComplicationBanner
@onready var _complication_title: Label = %ComplicationTitle
@onready var _complication_text: Label = %ComplicationText
@onready var _complication_timer: ProgressBar = %ComplicationTimer
@onready var _stamp: Label = %Stamp
@onready var _controls_host: VBoxContainer = %ControlsHost
@onready var _quick_row: HBoxContainer = %QuickRow
@onready var _tool_tray: ToolTray = %ToolTray

var current_stage: SurgeryStage = null
var _quick_buttons: Dictionary = {}  # StringName -> QuickActionButton
var _burn_sfx_cooldown: float = 0.0
var _ended: bool = false


func on_enter(_params: Dictionary) -> void:
	if not SurgeryManager.is_active:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	_site.configure(SurgeryManager.customer, SurgeryManager.surgery, ClinicManager.get_surgery_backdrop_level())
	_fx.unit_scale = 1.0 / GameConfig.PIXEL_SCALE
	_tool_tray.build(_get_tray_categories())
	_tool_tray.tool_selected.connect(_on_tool_selected)
	_build_quick_actions()
	_abort.pressed.connect(_on_abort_pressed)
	SurgeryManager.stage_started.connect(_on_stage_started)
	SurgeryManager.mistake_made.connect(_on_mistake_made)
	SurgeryManager.vital_warning.connect(_on_vital_warning)
	SurgeryManager.complication_started.connect(_on_complication_started)
	SurgeryManager.complication_resolved.connect(_on_complication_resolved)
	SurgeryManager.session_finished.connect(_on_session_finished)
	_complication_banner.visible = false
	_stamp.visible = false
	_update_vitals(true)
	# Surgery start: lamps flicker on, the arm whirs into place, monitor beeps.
	_lighting.power_up()
	AudioManager.play_sfx(&"servo", 0.0)
	AudioManager.play_sfx(&"beep", 0.0)
	UIManager.haptic(&"ui")
	# The first stage started before this screen existed; load it now.
	_load_stage(SurgeryManager.stage_index, SurgeryManager.get_current_stage())
	SurgeryManager.resume()


func on_exit() -> void:
	for sig: Signal in [SurgeryManager.stage_started, SurgeryManager.mistake_made, SurgeryManager.vital_warning,
			SurgeryManager.complication_started, SurgeryManager.complication_resolved, SurgeryManager.session_finished]:
		for c: Dictionary in sig.get_connections():
			if c["callable"].get_object() == self:
				sig.disconnect(c["callable"])


## Surgery tool categories plus any extra tool the implant needs (drill).
func _get_tray_categories() -> Array[StringName]:
	return SurgeryManager.surgery.get_required_tool_categories()


## Field (pixel viewport) coordinates -> FieldArea UI coordinates.
func field_to_area(p: Vector2) -> Vector2:
	return _field_viewport.position + p * GameConfig.PIXEL_SCALE


## Field coordinates -> global viewport coordinates (used by tests).
func field_to_screen(p: Vector2) -> Vector2:
	return _field_viewport.get_global_rect().position + p * GameConfig.PIXEL_SCALE


func _build_quick_actions() -> void:
	for id: StringName in GameConfig.QUICK_ACTIONS:
		var cfg: Dictionary = GameConfig.QUICK_ACTIONS[id]
		var b := QuickActionButton.new()
		var icon_path: String = QUICK_ICONS.get(id, "")
		b.setup(id, str(cfg.get("label", id)), PixelArt.scaled(icon_path) if icon_path != "" else null)
		b.pressed.connect(_on_quick_pressed.bind(id))
		_quick_row.add_child(b)
		_quick_buttons[id] = b


# --- Stage lifecycle ---------------------------------------------------------

func _on_stage_started(index: int, stage: SurgeryStageData) -> void:
	_load_stage(index, stage)


func _load_stage(index: int, stage_data: SurgeryStageData) -> void:
	if current_stage:
		current_stage.queue_free()
		current_stage = null
	for child in _controls_host.get_children():
		child.queue_free()
	if stage_data == null:
		return
	_stage_counter.text = "%02d/%02d" % [index + 1, SurgeryManager.get_stage_count()]
	_stage_title.text = stage_data.title
	_instruction.text = stage_data.instruction
	var stage := SurgeryStageRegistry.create(stage_data.type)
	if stage == null:
		return
	var category := stage_data.tool_category
	stage.setup(stage_data, _site, SurgeryManager.customer,
			SurgeryManager.get_tool_precision(category), SurgeryManager.get_tool_speed(category), SurgeryManager.get_stage_context())
	stage.view_scale = GameConfig.PIXEL_SCALE
	stage.name = "Stage_%s" % stage_data.id
	stage.stage_finished.connect(_on_stage_finished)
	stage.mistake.connect(_on_stage_mistake)
	stage.effect_requested.connect(SurgeryManager.apply_effect)
	stage.feedback.connect(_on_stage_feedback)
	stage.hint.connect(func(text: String) -> void: UIManager.show_toast(text, &"warn"))
	_stage_host.add_child(stage)
	current_stage = stage
	_site.set_focus(stage.get_focus())
	stage.begin()
	var controls := stage.create_controls()
	if controls:
		_controls_host.add_child(controls)
	_controls_host.visible = controls != null
	_tool_tray.clear_selection()
	_tool_tray.set_hint(category)
	var hint_button := _tool_tray.get_button(category)
	if hint_button:
		_tray_scroll.ensure_control_visible.call_deferred(hint_button)
	_tray_scroll.visible = true
	_instruction.get_parent().modulate.a = 0.0
	create_tween().tween_property(_instruction.get_parent(), "modulate:a", 1.0, 0.25)


func _on_stage_finished(quality: float, data: Dictionary) -> void:
	AudioManager.play_sfx(&"stage", 0.0)
	var label := "CLEAN" if quality >= 0.85 else ("OK" if quality >= 0.55 else "ROUGH")
	var color := Palette.OK if quality >= 0.85 else (Palette.ACCENT if quality >= 0.55 else Palette.WARN)
	_fx_text.float_text(field_to_area(_site.get_visible_field_rect().get_center()), label, color, true)
	await get_tree().create_timer(GameConfig.STAGE_CLEAR_DELAY_SEC).timeout
	if SurgeryManager.is_active and not _ended:
		SurgeryManager.complete_stage(quality, data)


func _on_tool_selected(category: StringName) -> void:
	if current_stage:
		current_stage.set_selected_tool(category)


# --- Feedback ----------------------------------------------------------------

## Minor mistakes read amber ("careful"), major ones red ("damage").
static func is_major_mistake(kind: StringName, severity: float) -> bool:
	return GameConfig.MAJOR_MISTAKES.has(kind) or severity >= GameConfig.MAJOR_SEVERITY


func _on_stage_mistake(kind: StringName, severity: float, local_pos: Vector2) -> void:
	SurgeryManager.report_mistake(kind, severity)
	var major := is_major_mistake(kind, severity)
	var color := Palette.DANGER if major else Palette.WARN
	var label: String = GameConfig.MISTAKE_LABELS.get(kind, "MISTAKE")
	_fx_text.float_text(field_to_area(local_pos) + Vector2(0, -16), ("!! " if major else "! ") + label, color)
	_fx.ring(local_pos, color, 9.0)
	if BLEEDING_MISTAKES.has(kind):
		_fx.burst(local_pos, Palette.BLOOD, 14 if major else 6, 110.0, 3.0)
	else:
		_fx.burst(local_pos, color, 8 if major else 4, 70.0, 2.0, 60.0)


func _on_mistake_made(kind: StringName, severity: float) -> void:
	if is_major_mistake(kind, severity):
		AudioManager.play_sfx(&"mistake")
		UIManager.shake(MISTAKE_SHAKE)
		UIManager.flash(Palette.DANGER, 0.18)
		UIManager.haptic(&"mistake")
	else:
		AudioManager.play_sfx(&"denied", 0.02)
		UIManager.flash(Palette.WARN, 0.08)
		UIManager.haptic(&"warning")


func _on_stage_feedback(kind: StringName, local_pos: Vector2) -> void:
	match kind:
		&"cut":
			_fx.burst(local_pos, Palette.BLOOD, 4, 50.0, 2.0)
			AudioManager.play_sfx(&"cut", 0.15)
		&"burn":
			_fx.burst(local_pos, Palette.WARN, 3, 40.0, 2.0, -60.0)
			if _burn_sfx_cooldown <= 0.0:
				_burn_sfx_cooldown = BURN_SFX_INTERVAL
				AudioManager.play_sfx(&"burn", 0.2)
		&"spark":
			_fx.burst(local_pos, Palette.ACCENT, 10, 90.0, 2.0, 100.0)
			AudioManager.play_sfx(&"zap", 0.1)
		&"clamp":
			_fx.burst(local_pos, Palette.METAL, 6, 60.0, 2.0)
			_fx.ring(local_pos, Palette.ACCENT, 6.0)
			AudioManager.play_sfx(&"clamp")
		&"stitch":
			_fx.burst(local_pos, Palette.METAL, 5, 50.0, 2.0)
			_fx.ring(local_pos, Palette.ACCENT, 5.0)
			AudioManager.play_sfx(&"stitch")
		&"implant":
			_fx.burst(local_pos, Palette.ACCENT, 24, 130.0, 3.0, 80.0)
			_fx.ring(local_pos, Palette.ACCENT, 14.0, 0.5)
			AudioManager.play_sfx(&"implant", 0.0)
			AudioManager.play_sfx(&"activate", 0.0)
			UIManager.shake(2.0)
			UIManager.flash(Palette.ACCENT, 0.15)
			UIManager.haptic(&"implant")
		&"good":
			_fx_text.float_text(field_to_area(local_pos) + Vector2(0, -24), "+ LOCKED", Palette.ACCENT)
			_fx.ring(local_pos, Palette.ACCENT, 8.0)
			AudioManager.play_sfx(&"confirm", 0.0)
			UIManager.haptic(&"ui")
		&"drill":
			_fx.burst(local_pos, Palette.METAL, 3, 70.0, 2.0, 120.0)
			if _burn_sfx_cooldown <= 0.0:
				_burn_sfx_cooldown = BURN_SFX_INTERVAL
				AudioManager.play_sfx(&"drill", 0.15)
		&"bad":
			_fx.burst(local_pos, Palette.DANGER, 10, 90.0, 2.0, 60.0)
			AudioManager.play_sfx(&"zap", 0.1)


func _on_vital_warning(vital: StringName) -> void:
	AudioManager.play_sfx(&"warning", 0.0)
	var names := {&"health": "HEALTH CRITICAL", &"blood_loss": "HEAVY BLEEDING", &"pain": "PAIN SPIKING", &"neural": "NEURAL UNSTABLE"}
	UIManager.show_toast(names.get(vital, "WARNING"), &"danger")


func _on_quick_pressed(id: StringName) -> void:
	if SurgeryManager.use_quick_action(id):
		var b: QuickActionButton = _quick_buttons[id]
		var pos := b.get_global_rect().get_center() - _fx_text.get_global_rect().position
		_fx_text.burst(pos, Palette.WARN, 8, 80.0, 2.0)


func _on_complication_started(c: ComplicationData) -> void:
	_complication_title.text = "! %s" % c.title
	_complication_text.text = c.message
	_complication_banner.visible = true
	_complication_banner.modulate.a = 0.0
	create_tween().tween_property(_complication_banner, "modulate:a", 1.0, 0.15)
	AudioManager.play_sfx(&"warning", 0.0)
	UIManager.shake(4.0)
	UIManager.flash(Palette.DANGER, 0.25)
	UIManager.haptic(&"warning")
	if _quick_buttons.has(c.counter_action):
		(_quick_buttons[c.counter_action] as QuickActionButton).urgent = true
	_lighting.emergency = true


func _on_complication_resolved(c: ComplicationData, handled: bool) -> void:
	_complication_banner.visible = false
	_lighting.emergency = false
	for b: QuickActionButton in _quick_buttons.values():
		b.urgent = false
	if _ended:
		return
	if handled:
		UIManager.show_toast("%s contained" % c.title, &"success")
		_fx_text.float_text(field_to_area(_site.get_visible_field_rect().get_center()), "CONTAINED", Palette.OK, true)
	else:
		UIManager.show_toast("%s: too slow!" % c.title, &"danger")
		AudioManager.play_sfx(&"mistake")
		UIManager.shake(6.0)
		UIManager.flash(Palette.DANGER, 0.3)
		UIManager.haptic(&"mistake")


func _on_session_finished(result: SurgeryResult) -> void:
	_ended = true
	if current_stage:
		current_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		current_stage.is_finished = true
	_tray_scroll.visible = false
	_controls_host.visible = false
	_lighting.emergency = not result.success
	for b: QuickActionButton in _quick_buttons.values():
		b.disabled = true
	_abort.disabled = true
	_complication_banner.visible = false
	_stamp.visible = true
	_stamp.pivot_offset = _stamp.size / 2.0
	_stamp.scale = Vector2(2.0, 2.0)
	var t := create_tween()
	t.tween_property(_stamp, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if result.success:
		_stamp.text = "OPERATION\nCOMPLETE"
		_stamp.add_theme_color_override(&"font_color", Palette.OK)
		AudioManager.play_sfx(&"success", 0.0)
		UIManager.haptic(&"success")
		_fx.burst(_site.get_visible_field_rect().get_center(), Palette.ACCENT, 30, 160.0, 3.0, 120.0)
	else:
		_stamp.text = "PATIENT\nCRASHED" if result.failure_reason != &"aborted" else "OPERATION\nABORTED"
		_stamp.add_theme_color_override(&"font_color", Palette.DANGER)
		if result.failure_reason == &"aborted":
			AudioManager.play_sfx(&"failure", 0.0)
			UIManager.haptic(&"warning")
		else:
			# Critical failure: flatline tone, hard flash, strongest haptic.
			AudioManager.play_sfx(&"critical", 0.0)
			UIManager.shake(8.0)
			UIManager.flash(Palette.DANGER, 0.5)
			UIManager.haptic(&"critical")


func _on_abort_pressed() -> void:
	# Freeze the patient while the player decides (destructive action).
	var was_running := SurgeryManager.is_running
	SurgeryManager.is_running = false
	var resume := func() -> void:
		if was_running:
			SurgeryManager.resume()
	var buttons: Array[Dictionary] = [
		{"label": "KEEP GOING", "style": &"AccentButton", "name": "AbortCancel", "callback": resume},
		{"label": "ABORT", "style": &"DangerButton", "name": "AbortConfirm", "callback": GameManager.abort_surgery},
	]
	UIManager.show_dialog("ABORT OPERATION?", "The patient walks out unfinished. No pay, reputation loss.", buttons)


# --- Per-frame HUD -----------------------------------------------------------

func _process(delta: float) -> void:
	_burn_sfx_cooldown = maxf(0.0, _burn_sfx_cooldown - delta)
	if SurgeryManager.vitals == null:
		return
	_update_vitals(false)
	var secs := int(SurgeryManager.elapsed)
	_timer.text = "%02d:%02d" % [secs / 60, secs % 60]
	var over_time := SurgeryManager.elapsed > SurgeryManager.surgery.target_time_sec
	_timer.add_theme_color_override(&"font_color", Palette.WARN if over_time else Palette.TEXT)
	for id: StringName in _quick_buttons:
		(_quick_buttons[id] as QuickActionButton).cooldown_ratio = SurgeryManager.get_cooldown_ratio(id) if SurgeryManager.is_active else 1.0
	if _complication_banner.visible:
		_complication_timer.value = SurgeryManager.get_complication_time_ratio() * 100.0


func _update_vitals(immediate: bool) -> void:
	var v := SurgeryManager.vitals
	_health_bar.set_value(v.health, immediate)
	_blood_bar.set_value(v.blood_loss, immediate)
	_pain_bar.set_value(v.pain, immediate)
	_neural_bar.set_value(v.neural, immediate)
	_health_bar.set_warning(SurgeryManager.is_warning_active(&"health"))
	_blood_bar.set_warning(SurgeryManager.is_warning_active(&"blood_loss"))
	_pain_bar.set_warning(SurgeryManager.is_warning_active(&"pain"))
	_neural_bar.set_warning(SurgeryManager.is_warning_active(&"neural"))
	_site.bleed_intensity = v.bleed_rate if v.wound_open else 0.0
	_site.blood_level = v.blood_loss
	_ecg.health = v.health
	_ecg.heart_rate = 64.0 + v.pain * 0.5 + v.blood_loss * 0.8
	_site.heart_rate = _ecg.heart_rate
	_ecg.flatline = v.health <= 0.0
	var load := SurgeryManager.neural_load_after
	_neural_load.text = "LOAD %d%%" % roundi(load)
	_neural_load.add_theme_color_override(&"font_color", NeuralLoad.band(load)["color"])


# --- App suspension ------------------------------------------------------------

## iOS suspends the app on home-swipe / calls: freeze the patient and show a
## pause card so nothing happens while the player is away.
## Tests disable this so a desktop focus change can't stall the bot.
static var pause_on_suspend: bool = true


func _notification(what: int) -> void:
	if pause_on_suspend and what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		pause_operation()


func pause_operation() -> void:
	if _ended or not SurgeryManager.is_active or not SurgeryManager.is_running or UIManager.has_modal():
		return
	SurgeryManager.is_running = false
	var buttons: Array[Dictionary] = [{"label": "RESUME", "style": &"AccentButton", "name": "ResumeSurgery", "callback": func() -> void:
		SurgeryManager.resume()}]
	UIManager.show_dialog("OPERATION PAUSED", "The patient is stable while you're away. Vitals resume when you do.", buttons)


func is_paused() -> bool:
	return SurgeryManager.is_active and not SurgeryManager.is_running and not _ended
