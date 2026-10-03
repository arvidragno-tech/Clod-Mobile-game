extends BaseScreen
## Diagnose (scan + pick a diagnosis), then review the operation plan.

const MIN_SCANS_TO_DIAGNOSE := 2
const TOOL_ICONS := {
	&"scalpel": "res://assets/sprites/tools/scalpel.png",
	&"retractor": "res://assets/sprites/tools/retractor.png",
	&"cautery": "res://assets/sprites/tools/cautery.png",
	&"forceps": "res://assets/sprites/tools/forceps.png",
	&"splicer": "res://assets/sprites/tools/splicer.png",
	&"suture": "res://assets/sprites/tools/suture.png",
}

@onready var _back: Button = %BackButton
@onready var _step: Label = %Step
@onready var _title: Label = %Title
@onready var _diagnose_phase: Control = %DiagnosePhase
@onready var _plan_phase: Control = %PlanPhase
@onready var _scan_view: ScanView = %ScanView
@onready var _findings: VBoxContainer = %Findings
@onready var _hint: Label = %Hint
@onready var _options: VBoxContainer = %Options
@onready var _confirm: Button = %ConfirmButton
@onready var _plan_code: Label = %PlanCode
@onready var _plan_stages: VBoxContainer = %PlanStages
@onready var _plan_checks: VBoxContainer = %PlanChecks
@onready var _plan_back: Button = %PlanBackButton
@onready var _begin: Button = %BeginButton

var _selected: StringName = &""
var _option_buttons: Dictionary = {}  # StringName -> Button


func on_enter(_params: Dictionary) -> void:
	var customer := GameManager.get_current_customer()
	var surgery := GameManager.get_current_surgery()
	if customer == null or surgery == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	_back.pressed.connect(_on_back)
	_scan_view.region_scanned.connect(_on_region_scanned)
	_confirm.pressed.connect(_on_confirm)
	_plan_back.pressed.connect(_show_diagnose_phase)
	_begin.pressed.connect(GameManager.begin_surgery)
	var group := ButtonGroup.new()
	for option in surgery.diagnosis_options:
		var id := StringName(str(option.get("id", "")))
		var b := Button.new()
		b.name = "Option_%s" % id
		b.text = str(option.get("name", id)).to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.y = GameConfig.MIN_TOUCH
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = true
		b.pressed.connect(_on_option_pressed.bind(id))
		_options.add_child(b)
		_option_buttons[id] = b
	_show_diagnose_phase()
	_update_hint()


func _on_back() -> void:
	if _plan_phase.visible:
		_show_diagnose_phase()
	else:
		GameManager.go_to_clinic()


func _show_diagnose_phase() -> void:
	_diagnose_phase.visible = true
	_plan_phase.visible = false
	_step.text = "STEP 2 / 4 · DIAGNOSIS"
	_title.text = "BODY SCAN"


func _on_region_scanned(region: StringName) -> void:
	var customer := GameManager.get_current_customer()
	var text := str(customer.scan_findings.get(String(region), "No anomalies."))
	var label := Label.new()
	label.text = "> %s: %s" % [ScanView.REGION_LABELS.get(region, region), text]
	label.theme_type_variation = &"MonoLabel"
	label.add_theme_font_size_override(&"font_size", 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_findings.add_child(label)
	label.modulate.a = 0.0
	create_tween().tween_property(label, "modulate:a", 1.0, 0.2)
	AudioManager.play_sfx(&"stage", 0.0)
	_update_hint()


func _update_hint() -> void:
	var count := _scan_view.get_scanned_count()
	var unlocked := count >= MIN_SCANS_TO_DIAGNOSE
	for b: Button in _option_buttons.values():
		b.disabled = not unlocked
	if not unlocked:
		_hint.text = "Tap highlighted regions to scan (%d/%d)" % [count, MIN_SCANS_TO_DIAGNOSE]
	elif _selected == &"":
		_hint.text = "Choose a diagnosis"
	else:
		_hint.text = "Diagnosis selected"
	_confirm.disabled = _selected == &""


func _on_option_pressed(id: StringName) -> void:
	_selected = id
	_update_hint()


func _on_confirm() -> void:
	if _selected == &"":
		return
	GameManager.submit_diagnosis(_selected)
	_build_plan()
	_diagnose_phase.visible = false
	_plan_phase.visible = true
	_step.text = "STEP 3 / 4 · PLAN"
	_title.text = "OPERATION PLAN"


func _build_plan() -> void:
	var surgery := GameManager.get_current_surgery()
	_plan_code.text = "%s\nDx: %s" % [surgery.code, surgery.get_diagnosis_name(_selected)]
	for child in _plan_stages.get_children():
		child.queue_free()
	for child in _plan_checks.get_children():
		child.queue_free()
	for i in surgery.stages.size():
		var stage := surgery.stages[i]
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path: String = TOOL_ICONS.get(stage.tool_category, "")
		icon.texture = load(icon_path) as Texture2D if icon_path != "" else null
		row.add_child(icon)
		var label := Label.new()
		label.text = "%d  %s" % [i + 1, stage.title]
		label.theme_type_variation = &"MonoLabel"
		label.add_theme_font_size_override(&"font_size", 20)
		row.add_child(label)
		_plan_stages.add_child(row)
	var readiness := GameManager.get_surgery_readiness()
	var missing: Array = readiness["missing_tools"]
	_add_check("Tools", "ALL READY" if missing.is_empty() else "MISSING: %s" % ", ".join(missing), missing.is_empty())
	var item := CyberwareManager.get_cyberware(surgery.cyberware_id)
	match readiness["implant_source"]:
		&"stock":
			_add_check("Implant", "IN STOCK (%d)" % InventoryManager.get_implant_count(surgery.cyberware_id), true)
		&"buy":
			_add_check("Implant", "BUY ON START (-%s)" % EconomyManager.format_money(item.price), true)
		&"salvaged":
			_add_check("Implant", "SALVAGED UNIT (-20% PERF)", false)
	_begin.disabled = not readiness["ok"]


func _add_check(caption: String, value: String, good: bool) -> void:
	var row := HBoxContainer.new()
	var c := Label.new()
	c.text = caption.to_upper()
	c.theme_type_variation = &"SubHeaderLabel"
	c.custom_minimum_size.x = 80
	row.add_child(c)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = &"MonoLabel"
	v.add_theme_font_size_override(&"font_size", 20)
	v.add_theme_color_override(&"font_color", Palette.OK if good else Palette.WARN)
	row.add_child(v)
	_plan_checks.add_child(row)
