extends BaseScreen
## Diagnose (scan regions, discover hidden conditions, pick a diagnosis),
## then plan: pick the implant unit, check tools / supplies / neural load
## and the customer's consent, then begin.

const MIN_SCANS_TO_DIAGNOSE := 2

var _title: Label
var _step: Label
var _diagnose: VBoxContainer
var _plan: VBoxContainer
var _scan: ScanView
var _findings: VBoxContainer
var _hint: Label
var _options: VBoxContainer
var _confirm: Button
var _plan_list: VBoxContainer
var _begin: Button
var _selected: StringName = &""
var _option_buttons: Dictionary = {}


func on_enter(_params: Dictionary) -> void:
	var customer := GameManager.get_current_customer()
	var surgery := GameManager.get_current_surgery()
	if customer == null or surgery == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	var m := UIKit.full_rect(UIKit.margin(12, 8, 12, 12))
	add_child(m)
	var col := UIKit.vbox(8)
	m.add_child(col)
	var header := UIKit.header("STEP 2 / 4 · DIAGNOSIS", "BODY SCAN", _on_back)
	col.add_child(header)
	_title = header.find_child("Title", true, false)
	_step = (header.get_child(1) as VBoxContainer).get_child(0)
	_build_diagnose(col, customer, surgery)
	_build_plan(col)
	_show_diagnose()
	_update_hint()


func _build_diagnose(col: VBoxContainer, customer: CustomerData, surgery: SurgeryData) -> void:
	_diagnose = UIKit.vbox(8)
	UIKit.expand(_diagnose, true, true)
	col.add_child(_diagnose)
	var row := UIKit.hbox(8)
	UIKit.expand(row, true, true)
	_diagnose.add_child(row)
	var frame := UIKit.panel(&"AccentPanel")
	frame.custom_minimum_size = Vector2(150, 200)
	row.add_child(frame)
	_scan = ScanView.new()
	_scan.name = "ScanView"
	_scan.highlight_region = surgery.scan_region
	frame.add_child(_scan)
	_scan.region_scanned.connect(_on_region_scanned)
	var fc := UIKit.panel(&"CardPanel")
	UIKit.expand(fc)
	row.add_child(fc)
	var sc := UIKit.scroll()
	fc.add_child(sc)
	_findings = UIKit.vbox(6)
	UIKit.expand(_findings)
	sc.add_child(_findings)
	_findings.add_child(UIKit.label("FINDINGS", &"SubHeaderLabel"))
	var item := GameManager.get_requested_item()
	_findings.add_child(UIKit.label("Site: %s (%s)" % [ScanView.REGION_LABELS.get(surgery.scan_region, "?"), item.category.to_upper() if item else "?"], &"DimLabel", true, Palette.BRAND, 13))
	_hint = UIKit.label("", &"DimLabel")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diagnose.add_child(_hint)
	_options = UIKit.vbox(6)
	_diagnose.add_child(_options)
	var group := ButtonGroup.new()
	for option in surgery.diagnosis_options:
		var id := StringName(str(option.get("id", "")))
		var b := UIKit.button(str(option.get("name", id)).to_upper(), &"", _on_option_pressed.bind(id), "Option_%s" % id)
		b.toggle_mode = true
		b.button_group = group
		b.disabled = true
		_options.add_child(b)
		_option_buttons[id] = b
	_confirm = UIKit.button("CONFIRM DIAGNOSIS", &"AccentButton", _on_confirm, "ConfirmButton", 54)
	_confirm.disabled = true
	_diagnose.add_child(_confirm)


func _build_plan(col: VBoxContainer) -> void:
	_plan = UIKit.vbox(8)
	UIKit.expand(_plan, true, true)
	col.add_child(_plan)
	var sc := UIKit.scroll()
	_plan.add_child(sc)
	_plan_list = UIKit.vbox(8)
	UIKit.expand(_plan_list)
	sc.add_child(_plan_list)
	var buttons := UIKit.hbox(10)
	_plan.add_child(buttons)
	var back := UIKit.button("RE-DIAGNOSE", &"GhostButton", _show_diagnose, "PlanBackButton", 56)
	UIKit.expand(back)
	buttons.add_child(back)
	_begin = UIKit.button("BEGIN OPERATION", &"BrandButton", GameManager.begin_surgery, "BeginButton", 56)
	UIKit.expand(_begin)
	_begin.size_flags_stretch_ratio = 1.6
	buttons.add_child(_begin)


func _on_back() -> void:
	if _plan.visible:
		_show_diagnose()
	else:
		GameManager.go_to_clinic()


func _show_diagnose() -> void:
	_diagnose.visible = true
	_plan.visible = false
	_step.text = "STEP 2 / 4 · DIAGNOSIS"
	_title.text = "BODY SCAN"


func _on_region_scanned(region: StringName) -> void:
	var customer := GameManager.get_current_customer()
	var text := str(customer.scan_findings.get(String(region), "No anomalies."))
	_add_finding("> %s: %s" % [ScanView.REGION_LABELS.get(region, region), text], Palette.TEXT)
	for cid in CustomerManager.try_reveal_conditions(customer, region):
		var cond := CustomerManager.get_condition(cid)
		_add_finding("! %s: %s" % [str(cond.get("name", cid)).to_upper(), str(cond.get("hint", ""))], Palette.DANGER)
		AudioManager.play_sfx(&"warning", 0.0)
	AudioManager.play_sfx(&"stage", 0.0)
	_update_hint()


func _add_finding(text: String, color: Color) -> void:
	var label := UIKit.label(text, &"MonoLabel", true, color, 18)
	_findings.add_child(label)
	label.modulate.a = 0.0
	create_tween().tween_property(label, "modulate:a", 1.0, 0.2)


func _update_hint() -> void:
	var count := _scan.get_scanned_count()
	var unlocked := count >= MIN_SCANS_TO_DIAGNOSE
	for b: Button in _option_buttons.values():
		b.disabled = not unlocked
	if not unlocked:
		_hint.text = "Tap regions to scan (%d/%d) · site in pink" % [count, MIN_SCANS_TO_DIAGNOSE]
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
	_diagnose.visible = false
	_plan.visible = true
	_step.text = "STEP 3 / 4 · PLAN"
	_title.text = "OPERATION PLAN"
	_build_plan_contents()
	TutorialManager.notify("plan")


func _build_plan_contents() -> void:
	UIKit.clear(_plan_list)
	var surgery := GameManager.get_current_surgery()
	var customer := GameManager.get_current_customer()
	var item := GameManager.get_requested_item()
	var r := GameManager.get_surgery_readiness()
	var head := UIKit.panel(&"AccentPanel")
	var hv := UIKit.vbox(4)
	head.add_child(hv)
	hv.add_child(UIKit.label(surgery.display_name.to_upper(), &"MonoLabel", true, Palette.ACCENT))
	hv.add_child(UIKit.label("Dx: %s · %d stages · target %d:%02d" % [surgery.get_diagnosis_name(_selected), surgery.stages.size(), int(surgery.target_time_sec) / 60, int(surgery.target_time_sec) % 60], &"DimLabel", true, null, 14))
	var meter := NeuralLoadMeter.new()
	meter.name = "PlanNeuralMeter"
	hv.add_child(meter)
	meter.set_load(NeuralLoad.compute_visible(customer), r["neural_after"] - (NeuralLoad.compute(customer) - NeuralLoad.compute_visible(customer)))
	var band := NeuralLoad.band(float(r["neural_after"]))
	if NeuralLoad.band_index(float(r["neural_after"])) >= 3:
		hv.add_child(UIKit.label("WARNING: %s load after install. Risk of neural break." % str(band["name"]), &"DimLabel", true, Palette.DANGER, 14))
	_plan_list.add_child(head)
	# Implant choice
	_plan_list.add_child(UIKit.label("IMPLANT UNIT", &"SubHeaderLabel"))
	var opts := GameManager.get_implant_options()
	var selected := GameManager.get_selected_implant()
	if opts.is_empty():
		var src := str(r["implant_source"])
		var msg := "None in stock. Buy on start: %s" % EconomyManager.format_money(InventoryManager.implant_price(item)) if src == "buy" else "None in stock and can't buy: customer brings a salvaged unit (-20% performance)."
		_plan_list.add_child(UIKit.label(msg, &"DimLabel", true, Palette.WARN if src != "buy" else Palette.TEXT))
	for i in opts.size():
		_plan_list.add_child(_implant_option(i, opts[i], opts[i] == selected, item))
	# Checks
	_plan_list.add_child(UIKit.label("CHECKS", &"SubHeaderLabel"))
	var missing: Array = r["missing_tools"]
	_check("TOOLS", "READY" if missing.is_empty() else "MISSING " + ", ".join(missing), missing.is_empty())
	_check("SUPPLIES", "%d / need %d" % [InventoryManager.supplies, surgery.supplies], bool(r["supplies_ok"]))
	var refusal := "REFUSES: LOAD TOO HIGH" if GameManager.consent_risk_needed(float(r["neural_after"])) > 0.0 else "REFUSES THIS UNIT"
	_check("CONSENT", "AGREES" if bool(r["accepts"]) else refusal, bool(r["accepts"]))
	_check("REVEALED", "%d condition(s)" % customer.revealed_conditions.size(), customer.revealed_conditions.is_empty())
	var stages: Array[String] = []
	for k in surgery.stages.size():
		stages.append("%d %s" % [k + 1, surgery.stages[k].title])
	_plan_list.add_child(UIKit.label(" · ".join(stages), &"DimLabel", true, null, 13))
	_begin.disabled = not bool(r["ok"])


func _implant_option(i: int, inst: ImplantInstance, selected: bool, requested: CyberwareData) -> Control:
	var data := inst.get_data()
	var b := Button.new()
	b.name = "Implant_%d" % i
	b.theme_type_variation = &"ToolButton"
	b.toggle_mode = true
	b.button_pressed = selected
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 76
	b.pressed.connect(func() -> void:
		GameManager.select_implant(inst.uid)
		_build_plan_contents())
	var row := UIKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(UIKit.full_rect(UIKit.margin(6, 4, 6, 4)))
	(b.get_child(0) as MarginContainer).add_child(row)
	row.add_child(CyberwareIcon.make(data))
	var v := UIKit.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.expand(v)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	var tag := "REQUESTED" if data.id == requested.id else ("UPGRADE" if data.tier > requested.tier else "SUBSTITUTE")
	v.add_child(UIKit.label(data.display_name, &"", true, null, 15))
	var unknown := "  ?? TRAITS" if inst.has_unknown_traits() else ""
	v.add_child(UIKit.label("%s · COND %d%% · LOAD +%d%%%s" % [tag, roundi(inst.condition), roundi(inst.get_neural_load()), unknown], &"SubHeaderLabel", true,
			Palette.OK if tag == "REQUESTED" else Palette.WARN))
	return b


func _check(caption: String, value: String, good: bool) -> void:
	var row := UIKit.hbox(8)
	var c := UIKit.label(caption, &"SubHeaderLabel")
	c.custom_minimum_size.x = 92
	row.add_child(c)
	# Symbol + colour: "+" ready, "x" blocked (readable without colour).
	var v := UIKit.label(("+ " if good else "x ") + value, &"MonoLabel", true, Palette.OK if good else Palette.WARN, 19)
	UIKit.expand(v)
	row.add_child(v)
	_plan_list.add_child(row)
