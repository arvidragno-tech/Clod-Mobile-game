class_name SurgeryScreen
extends BaseScreen
## The operating table (PC workstation layout). Left: patient, vitals and the
## procedure checklist. Centre: the zoomable operating field with the current
## stage on top of the persistent SurgicalSiteView. Right: instrument rack,
## emergency actions and the implant being installed. Bottom: key hints.
## Turns SurgeryManager / stage events into feedback.
##
## Mouse: left = use tool / drag, right = put the tool down (or return a held
## implant), wheel = zoom (or rotate / tune when the stage uses it).
## Keys: 1-9 tools, Q/R cycle, Z/X/V emergency actions, SPACE/E stage action,
## , . rotate, + - zoom, ESC pause.

const QUICK_ICONS := {
	&"coag": "res://assets/sprites/ui/icons/coag.png",
	&"sedate": "res://assets/sprites/ui/icons/sedate.png",
	&"stabilize": "res://assets/sprites/ui/icons/stabilize.png",
}
const BLEEDING_MISTAKES: Array[StringName] = [&"cut_deviation", &"tissue_tear", &"bad_stitch", &"vessel_tear", &"plate_overlap"]
## What to do differently, per mistake (the first time it happens in an
## operation; what it cost comes from GameConfig.MISTAKE_EFFECTS).
## wrong_tool is left out: its own hint already names the right tool.
const MISTAKE_TIPS := {
	&"cut_deviation": "Keep the blade on the guide line, and slower.",
	&"tissue_tear": "Clamp right on the bracket markers.",
	&"nerve_burn": "Keep the burner off the nerve lines.",
	&"implant_drop": "Drop the implant inside the socket ring.",
	&"misalignment": "Line up the notch before you seat it.",
	&"wrong_connection": "Each wire goes to the terminal of its own colour.",
	&"poor_calibration": "Match the slider to the target, then lock.",
	&"bad_stitch": "Stitch the points in order: the next one is numbered.",
	&"underdose": "Hold longer: let go inside the green zone.",
	&"overdose": "Let go sooner: inside the green zone.",
	&"bone_crack": "Too deep: release inside the depth zone.",
	&"loose_anchor": "Too shallow: hold until the depth is inside the zone.",
	&"nerve_misfire": "Map the nodes in order: the next one pulses.",
	&"cord_nick": "Thread the bus down the spine in order, top to bottom.",
	&"plate_overlap": "Lay the plates in their numbered order.",
	&"vessel_tear": "Clamp from the heart outwards: the next vessel pulses.",
	&"retina_scuff": "Stay on the ring as the eye drifts.",
	&"tendon_slip": "Keep your hold on the tendon ring as it pulls.",
	&"joint_buckle": "Follow the knee ring while it takes the weight.",
	&"air_leak": "Keep the seal ring under your hold until it sets.",
}
const BURN_SFX_INTERVAL := 0.15
const MISTAKE_SHAKE := 5.0
## Operating-field magnification (integer, art px -> screen px).
const ZOOM_MIN := 3
const ZOOM_MAX := 6
const QUICK_KEYS := {&"coag": "quick_coag", &"sedate": "quick_sedate", &"stabilize": "quick_stabilize"}

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
@onready var _quick_row: VBoxContainer = %QuickRow
@onready var _tool_tray: ToolTray = %ToolTray
@onready var _procedure: Label = %Procedure
@onready var _zoom_label: Label = %ZoomLabel
@onready var _hover: FieldHover = %Hover
@onready var _patient_box: VBoxContainer = %PatientBox
@onready var _step_list: VBoxContainer = %StepList
@onready var _tool_detail: Label = %ToolDetail
@onready var _implant_box: VBoxContainer = %ImplantBox
@onready var _key_hints: Label = %KeyHints

## Current field magnification; set by the wheel / + - keys.
var field_scale: int = 4
var _user_zoomed: bool = false

var current_stage: SurgeryStage = null
var _quick_buttons: Dictionary = {}  # StringName -> QuickActionButton
var _burn_sfx_cooldown: float = 0.0
var _ended: bool = false
## Presentation only: mistake kinds already explained this operation, and
## mistakes in the current stage (for its CLEAN / OK / ROUGH line).
var _explained: Dictionary = {}
var _stage_mistakes: int = 0


func on_enter(_params: Dictionary) -> void:
	if not SurgeryManager.is_active:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	keyboard_nav = false
	_site.configure(SurgeryManager.customer, SurgeryManager.surgery, ClinicManager.get_surgery_backdrop_level())
	_tool_tray.build(_get_tray_categories())
	_tool_tray.tool_selected.connect(_on_tool_selected)
	_tool_tray.tool_hovered.connect(_show_tool_detail)
	_abort.text = "ABORT"
	_abort.tooltip_text = "Abort the operation (asks first)"
	_build_quick_actions()
	_build_side_panels()
	_set_zoom(_fit_zoom(), true)
	# Until the player zooms by hand, follow the largest magnification that
	# fits (window resizes / resolution changes re-fit it).
	_field_area.resized.connect(func() -> void:
		if not _user_zoomed or field_scale > _fit_zoom():
			_set_zoom(_fit_zoom(), true))
	_abort.pressed.connect(_on_abort_pressed)
	SurgeryManager.stage_started.connect(_on_stage_started)
	SurgeryManager.mistake_made.connect(_on_mistake_made)
	SurgeryManager.vital_warning.connect(_on_vital_warning)
	SurgeryManager.complication_started.connect(_on_complication_started)
	SurgeryManager.dilemma_started.connect(_on_dilemma_started)
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
			SurgeryManager.complication_started, SurgeryManager.complication_resolved, SurgeryManager.session_finished,
			SurgeryManager.dilemma_started]:
		for c: Dictionary in sig.get_connections():
			if c["callable"].get_object() == self:
				sig.disconnect(c["callable"])


## Surgery tool categories plus any extra tool the implant needs (drill).
func _get_tray_categories() -> Array[StringName]:
	return SurgeryManager.surgery.get_required_tool_categories()


## Field (pixel viewport) coordinates -> FieldArea UI coordinates.
func field_to_area(p: Vector2) -> Vector2:
	return _field_viewport.position + p * field_scale


## Field coordinates -> global viewport coordinates (used by tests).
func field_to_screen(p: Vector2) -> Vector2:
	return _field_viewport.get_global_rect().position + p * field_scale


## Largest magnification that still shows the whole 160 px field.
func _fit_zoom() -> int:
	var area := _field_area.size
	if area.x <= 0.0:
		return field_scale
	var fit := floori(minf(area.x, area.y) / SurgicalSiteView.FIELD_SIZE)
	return clampi(fit, ZOOM_MIN, ZOOM_MAX)


## Changes the field magnification (never mid-gesture: positions would jump).
func _set_zoom(z: int, force: bool = false) -> void:
	z = clampi(z, ZOOM_MIN, ZOOM_MAX)
	if (z == field_scale and not force) or (current_stage and current_stage.is_pointer_down):
		return
	field_scale = z
	_field_viewport.stretch_shrink = z
	_fx.unit_scale = 1.0 / z
	if current_stage:
		current_stage.view_scale = z
	_zoom_label.text = "ZOOM %dx  [%s/%s]" % [z, Controls.key_name("zoom_out"), Controls.key_name("zoom_in")]
	if not force:
		AudioManager.play_sfx(&"hover", 0.0)


func _build_quick_actions() -> void:
	for id: StringName in GameConfig.QUICK_ACTIONS:
		var cfg: Dictionary = GameConfig.QUICK_ACTIONS[id]
		var b := QuickActionButton.new()
		var icon_path: String = QUICK_ICONS.get(id, "")
		b.setup(id, "%s   [%s]" % [str(cfg.get("label", id)), Controls.key_name(QUICK_KEYS.get(id, ""))], PixelArt.scaled(icon_path) if icon_path != "" else null)
		b.custom_minimum_size.y = 58
		b.tooltip_text = str(cfg.get("hint", "%s: emergency action with a cooldown" % str(cfg.get("label", id))))
		b.pressed.connect(_on_quick_pressed.bind(id))
		_quick_row.add_child(b)
		_quick_buttons[id] = b


# --- Stage lifecycle ---------------------------------------------------------

func _on_stage_started(index: int, stage: SurgeryStageData) -> void:
	_stage_mistakes = 0
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
	stage.view_scale = field_scale
	stage.mouse_default_cursor_shape = Control.CURSOR_CROSS
	stage.name = "Stage_%s" % stage_data.id
	stage.stage_finished.connect(_on_stage_finished)
	stage.mistake.connect(_on_stage_mistake)
	stage.effect_requested.connect(SurgeryManager.apply_effect)
	stage.feedback.connect(_on_stage_feedback)
	stage.hint.connect(func(text: String) -> void: UIManager.show_toast(text, &"warn"))
	_stage_host.add_child(stage)
	current_stage = stage
	_hover.stage = stage
	_refresh_steps(index)
	_show_tool_detail(category)
	_site.set_focus(stage.get_focus())
	stage.begin()
	var controls := stage.create_controls()
	if controls:
		_controls_host.add_child(controls)
	_controls_host.visible = controls != null
	_tool_tray.clear_selection()
	_tool_tray.set_hint(category)
	# The step's instrument goes straight into your hand: picking the one
	# glowing tool every stage was busywork, not a decision. (Unowned or
	# worn-out tools still have to be dealt with; other tools stay a click
	# or a number key away.)
	if category != &"":
		_tool_tray.select_category(category)
	var hint_button := _tool_tray.get_button(category)
	if hint_button:
		_tray_scroll.ensure_control_visible.call_deferred(hint_button)
	_instruction.get_parent().modulate.a = 0.0
	create_tween().tween_property(_instruction.get_parent(), "modulate:a", 1.0, 0.25)


func _on_stage_finished(quality: float, data: Dictionary) -> void:
	AudioManager.play_sfx(&"stage", 0.0)
	var label := "CLEAN" if quality >= 0.85 else ("OK" if quality >= 0.55 else "ROUGH")
	if quality < 0.85 and _stage_mistakes > 0:
		label += " · %d MISTAKE%s" % [_stage_mistakes, "" if _stage_mistakes == 1 else "S"]
	var color := Palette.OK if quality >= 0.85 else (Palette.ACCENT if quality >= 0.55 else Palette.WARN)
	_fx_text.float_text(field_to_area(_site.get_visible_field_rect().get_center()), label, color, true)
	await get_tree().create_timer(GameConfig.STAGE_CLEAR_DELAY_SEC).timeout
	if SurgeryManager.is_active and not _ended:
		SurgeryManager.complete_stage(quality, data)


func _on_tool_selected(category: StringName) -> void:
	if current_stage:
		current_stage.set_selected_tool(category)
	if category != &"":
		_show_tool_detail(category)


# --- Side panels ---------------------------------------------------------------

func _build_side_panels() -> void:
	var c := SurgeryManager.customer
	var surgery := SurgeryManager.surgery
	var it := SurgeryManager.implant_item
	var unit_name := ""
	if it:
		unit_name = "unidentified device" if SurgeryManager.implant and not SurgeryManager.implant.identified else it.display_name
	_procedure.text = "%s  ·  %s%s" % [surgery.display_name.to_upper(), c.display_name if c else "?", ("  ·  " + unit_name) if unit_name != "" else ""]
	# During the operation only the procedure matters: who the patient is and
	# the implant's specs were decided in the plan (the header names both).
	(_patient_box.get_parent() as Control).visible = false
	(_implant_box.get_parent() as Control).visible = false
	# Patient
	_patient_box.add_child(UIKit.section_head("PATIENT", "", "vitals"))
	var row := UIKit.hbox(12)
	_patient_box.add_child(row)
	if c:
		var portrait := PixelPortrait.new()
		portrait.name = "Portrait"
		row.add_child(portrait)
		portrait.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
		var info := UIKit.vbox(2)
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIKit.expand(info)
		row.add_child(info)
		info.add_child(UIKit.label(c.display_name.to_upper(), &"MonoLabel", true, Palette.ACCENT))
		info.add_child(UIKit.label("%d yrs · %s" % [c.age, c.occupation.capitalize()], &"DimLabel", true))
		info.add_child(UIKit.label(FactionManager.get_name_of(c.faction_id).to_upper(), &"SubHeaderLabel", true, FactionManager.get_color(c.faction_id)))
	# Implant
	var item := SurgeryManager.implant_item
	_implant_box.add_child(UIKit.section_head("IMPLANT", "", "neural_load"))
	if item and SurgeryManager.implant and not SurgeryManager.implant.identified:
		_implant_box.add_child(UIKit.label("UNIDENTIFIED DEVICE", &"", true, Palette.BRAND, 16))
		_implant_box.add_child(UIKit.label("Installing blind: model and properties unknown.", &"SubHeaderLabel", true, Palette.WARN))
	elif item:
		var irow := UIKit.hbox(12)
		_implant_box.add_child(irow)
		irow.add_child(CyberwareIcon.make(item))
		var iv := UIKit.vbox(2)
		UIKit.expand(iv)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		irow.add_child(iv)
		iv.add_child(UIKit.label(item.display_name, &"", true, item.get_rarity_color(), 16))
		iv.add_child(UIKit.label("T%d %s · DIFF %d/5" % [item.tier, item.get_tier_name(), item.install_difficulty], &"SubHeaderLabel", true))
		var load := UIKit.label("NEURAL LOAD %d%% → %d%%" % [roundi(SurgeryManager.neural_load_before), roundi(SurgeryManager.neural_load_after)], &"SubHeaderLabel", true, NeuralLoad.band(SurgeryManager.neural_load_after)["color"])
		_implant_box.add_child(load)
		if SurgeryManager.implant and SurgeryManager.implant.source == &"black_market":
			_implant_box.add_child(UIKit.label("BLACK-MARKET UNIT · unknown traits", &"SubHeaderLabel", true, Palette.BRAND))
	else:
		_implant_box.add_child(UIKit.label("No implant in this procedure.", &"DimLabel", true))
	# Key hints
	# The instrument and emergency buttons show their own keys.
	_key_hints.text = "[RMB] put the tool down   [WHEEL] zoom   [%s] pause" % Controls.key_name("pause")


## Procedure checklist: done (green), current (cyan, pulsing marker), next (dim).
func _refresh_steps(current: int) -> void:
	UIKit.clear(_step_list)
	_step_list.add_child(UIKit.section_head("PROCEDURE", "", "vitals"))
	var stages := SurgeryManager.surgery.stages
	for i in stages.size():
		var st: SurgeryStageData = stages[i]
		var mark := "✓" if i < current else ("▶" if i == current else "·")
		var color: Color = Palette.OK if i < current else (Palette.ACCENT if i == current else Palette.TEXT_DIM)
		var tool := "  [%s]" % String(st.tool_category).to_upper() if st.tool_category != &"" else ""
		var l := UIKit.label("%s %02d  %s%s" % [mark, i + 1, st.title, tool], &"DimLabel", false, color)
		if i == current:
			l.add_theme_font_size_override(&"font_size", UIKit.fs(15))
		l.name = "Step_%d" % i
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_step_list.add_child(l)


func _show_tool_detail(category: StringName) -> void:
	if category == &"":
		_tool_detail.text = ""
		return
	var t := InventoryManager.get_best_tool(category)
	if t == null:
		_tool_detail.text = "%s: not owned. Buy one at SUPPLY." % String(category).to_upper()
		return
	var needed := current_stage != null and current_stage.stage.tool_category == category
	_tool_detail.text = "%s%s\n%s" % [t.display_name.to_upper(), "  ·  NEEDED NOW" if needed else "", t.description]


# --- PC input ------------------------------------------------------------------

## Wheel and right-click over the field are handled before the stage sees
## them (the stage lives inside the field SubViewport).
func _input(event: InputEvent) -> void:
	if _ended or UIManager.has_modal() or not is_visible_in_tree():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var over_field := _field_area.get_global_rect().has_point(mb.position)
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not over_field:
				return
			var steps := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if not (current_stage and current_stage.wheel_steps(steps)):
				_user_zoomed = true
				_set_zoom(field_scale - steps)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			_cancel()
			get_viewport().set_input_as_handled()


## Right-click: undo a held gesture, otherwise put the tool down.
func _cancel() -> void:
	if current_stage and current_stage.cancel():
		AudioManager.play_sfx(&"denied", 0.0)
		return
	if _tool_tray.selected != &"":
		_tool_tray.clear_selection()
		AudioManager.play_sfx(&"tool", 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _ended or UIManager.has_modal() or not SurgeryManager.is_active:
		return
	var k := event as InputEventKey
	if k == null:
		return
	# Stage actions get press AND release (hold-to-infuse) and echo (nudge).
	for action: StringName in [&"context", &"interact", &"rotate_left", &"rotate_right", &"ui_left", &"ui_right"]:
		if event.is_action(action):
			if k.echo and action != &"ui_left" and action != &"ui_right":
				get_viewport().set_input_as_handled()
				return
			if current_stage and current_stage.key_action(action, k.pressed):
				get_viewport().set_input_as_handled()
				return
	if not k.pressed or k.echo:
		return
	for i in 9:
		if event.is_action("tool_%d" % (i + 1)):
			_tool_tray.select_index(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action("tool_next") or event.is_action("tool_prev"):
		_tool_tray.cycle(1 if event.is_action("tool_next") else -1)
	elif event.is_action("zoom_in") or event.is_action("zoom_out"):
		_user_zoomed = true
		_set_zoom(field_scale + (1 if event.is_action("zoom_in") else -1))
	else:
		for id: StringName in QUICK_KEYS:
			if event.is_action(QUICK_KEYS[id]):
				_on_quick_pressed(id)
				get_viewport().set_input_as_handled()
				return
		return
	get_viewport().set_input_as_handled()


## ESC during an operation pauses it (the patient is frozen).
func on_escape() -> bool:
	if not _ended:
		pause_operation()
	return true


# --- Feedback ----------------------------------------------------------------

## Minor mistakes read amber ("careful"), major ones red ("damage").
static func is_major_mistake(kind: StringName, severity: float) -> bool:
	return GameConfig.MAJOR_MISTAKES.has(kind) or severity >= GameConfig.MAJOR_SEVERITY


func _on_stage_mistake(kind: StringName, severity: float, local_pos: Vector2) -> void:
	SurgeryManager.report_mistake(kind, severity)
	_stage_mistakes += 1
	_explain_mistake(kind)
	var major := is_major_mistake(kind, severity)
	var color := Palette.DANGER if major else Palette.WARN
	var label: String = GameConfig.MISTAKE_LABELS.get(kind, "MISTAKE")
	_fx_text.float_text(field_to_area(local_pos) + Vector2(0, -16), ("!! " if major else "! ") + label, color)
	_fx.ring(local_pos, color, 9.0)
	if BLEEDING_MISTAKES.has(kind):
		_fx.burst(local_pos, Palette.BLOOD, 14 if major else 6, 110.0, 3.0)
	else:
		_fx.burst(local_pos, color, 8 if major else 4, 70.0, 2.0, 60.0)


## The first time a kind of mistake happens in this operation: what it cost
## and what to do differently, in one toast. Later ones only flash.
func _explain_mistake(kind: StringName) -> void:
	if _explained.has(kind) or not MISTAKE_TIPS.has(kind):
		return
	_explained[kind] = true
	var label: String = GameConfig.MISTAKE_LABELS.get(kind, "MISTAKE")
	UIManager.show_toast("%s%s. %s" % [label, mistake_cost(kind), MISTAKE_TIPS[kind]], &"warn")


## "costs bleeding and pain", from the mistake's real effects.
static func mistake_cost(kind: StringName) -> String:
	var fx: Dictionary = GameConfig.MISTAKE_EFFECTS.get(kind, {})
	var parts: Array[String] = []
	if fx.has("bleed_rate") or fx.has("blood"):
		parts.append("bleeding")
	if fx.has("neural"):
		parts.append("neural sync")
	if fx.has("health"):
		parts.append("health")
	if fx.has("pain") or fx.has("pain_baseline"):
		parts.append("pain")
	if parts.is_empty():
		return ""
	var tail := parts.pop_back() as String
	return ": costs %s" % ((", ".join(parts) + " and " + tail) if not parts.is_empty() else tail)


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
	var left := SurgeryManager.get_cooldown_remaining(id)
	if SurgeryManager.is_active and left > 0.0:
		AudioManager.play_sfx(&"denied", 0.0)
		UIManager.show_toast("%s is recharging (%.1fs)" % [String(id).to_upper(), left], &"warn")
		return
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
		var counter: String = str(GameConfig.QUICK_ACTIONS.get(c.counter_action, {}).get("label", ""))
		UIManager.show_toast(("%s: too slow. %s counters it." % [c.title, counter]) if counter != "" else "%s: too slow!" % c.title, &"danger")
		AudioManager.play_sfx(&"mistake")
		UIManager.shake(6.0)
		UIManager.flash(Palette.DANGER, 0.3)
		UIManager.haptic(&"mistake")


func _on_session_finished(result: SurgeryResult) -> void:
	_ended = true
	if current_stage:
		current_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		current_stage.is_finished = true
	_tool_tray.clear_selection()
	_controls_host.visible = false
	_hover.stage = null
	_refresh_steps(SurgeryManager.surgery.stages.size() if result.success else SurgeryManager.stage_index)
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

## Alt-Tab / minimising the window freezes the patient and shows a pause
## card so nothing happens while the player is away.
## Tests disable this so a desktop focus change can't stall the bot.
static var pause_on_suspend: bool = true


func _notification(what: int) -> void:
	if pause_on_suspend and Settings.pause_focus_loss and what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
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


## A surgical dilemma stops the operation until the player decides.
func _on_dilemma_started(_d: Dictionary) -> void:
	if not is_inside_tree():
		return
	AudioManager.play_sfx(&"warning", 0.0)
	UIManager.haptic(&"critical")
	var panel := DilemmaPanel.new()
	panel.name = "DilemmaPanel"
	UIManager.show_modal(panel)
