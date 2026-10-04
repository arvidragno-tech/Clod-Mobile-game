extends BaseScreen
## Diagnose (scan regions, discover hidden conditions, pick a diagnosis),
## then plan: pick the implant unit, check tools / supplies / neural load
## and the customer's consent, then begin. PC layout: scanner | findings |
## diagnosis, then plan summary + checks | implant units | begin.

const MIN_SCANS_TO_DIAGNOSE := 2

var _title: Label
var _step: Label
var _diagnose: HBoxContainer
var _plan: HBoxContainer
var _scan: ScanView
var _findings: VBoxContainer
var _hint: Label
var _options: VBoxContainer
var _confirm: Button
var _plan_list: VBoxContainer
var _plan_info: VBoxContainer
var _panels: Array[Control] = []
var _begin: Button
var _selected: StringName = &""
var _option_buttons: Dictionary = {}


func on_enter(_params: Dictionary) -> void:
	var customer := GameManager.get_current_customer()
	var surgery := GameManager.get_current_surgery()
	if customer == null or surgery == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	var col := UIKit.workstation(self, &"clinic")
	var header := UIKit.header("STEP 2 / 4 · DIAGNOSIS", "BODY SCAN", _on_back)
	col.add_child(header)
	_title = header.find_child("Title", true, false)
	_step = (header.get_child(1) as VBoxContainer).get_child(0)
	_build_diagnose(col, customer, surgery)
	_build_plan(col)
	_show_diagnose()
	_update_hint()


func get_panels() -> Array[Control]:
	var out: Array[Control] = []
	for c in _panels:
		if c.is_visible_in_tree():
			out.append(c)
	return out


func _build_diagnose(col: VBoxContainer, customer: CustomerData, surgery: SurgeryData) -> void:
	_diagnose = UIKit.hbox(18)
	UIKit.expand(_diagnose, true, true)
	col.add_child(_diagnose)
	var row := UIKit.hbox(18)
	UIKit.expand(row, true, true)
	_diagnose.add_child(row)
	var frame := UIKit.panel(&"AccentPanel")
	frame.custom_minimum_size = Vector2(400, 560)
	frame.tooltip_text = "Click a body region to scan it"
	row.add_child(frame)
	_panels.append(frame)
	_scan = ScanView.new()
	_scan.name = "ScanView"
	_scan.highlight_region = surgery.scan_region
	frame.add_child(_scan)
	_scan.region_scanned.connect(_on_region_scanned)
	var fc := UIKit.panel(&"CardPanel")
	UIKit.expand(fc)
	row.add_child(fc)
	_panels.append(fc)
	var sc := UIKit.scroll()
	fc.add_child(sc)
	_findings = UIKit.vbox(6)
	UIKit.expand(_findings)
	sc.add_child(_findings)
	_findings.add_child(UIKit.label("FINDINGS", &"SubHeaderLabel"))
	var item := GameManager.get_requested_item()
	_findings.add_child(UIKit.label("Site: %s (%s)" % [ScanView.REGION_LABELS.get(surgery.scan_region, "?"), item.category.to_upper() if item else "?"], &"DimLabel", true, Palette.BRAND, 13))
	var side := UIKit.panel(&"CardPanel")
	side.custom_minimum_size.x = 460
	_diagnose.add_child(side)
	_panels.append(side)
	var sv := UIKit.vbox(10)
	side.add_child(sv)
	sv.add_child(UIKit.label("DIAGNOSIS", &"SubHeaderLabel", false, Palette.ACCENT))
	_hint = UIKit.label("", &"DimLabel", true)
	sv.add_child(_hint)
	_options = UIKit.vbox(8)
	sv.add_child(_options)
	sv.add_child(UIKit.expand(Control.new(), false, true))
	var group := ButtonGroup.new()
	for option in surgery.diagnosis_options:
		var id := StringName(str(option.get("id", "")))
		var b := UIKit.button(str(option.get("name", id)).to_upper(), &"", _on_option_pressed.bind(id), "Option_%s" % id, 56)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = str(option.get("description", option.get("hint", "")))
		b.button_group = group
		b.disabled = true
		_options.add_child(b)
		_option_buttons[id] = b
	_confirm = UIKit.button("CONFIRM DIAGNOSIS   [ENTER]", &"AccentButton", _on_confirm, "ConfirmButton", 64)
	_confirm.disabled = true
	sv.add_child(_confirm)


func _build_plan(col: VBoxContainer) -> void:
	_plan = UIKit.hbox(18)
	UIKit.expand(_plan, true, true)
	col.add_child(_plan)
	var info_panel := UIKit.panel(&"CardPanel")
	info_panel.custom_minimum_size.x = 560
	_plan.add_child(info_panel)
	_panels.append(info_panel)
	var isc := UIKit.scroll()
	info_panel.add_child(isc)
	_plan_info = UIKit.vbox(10)
	UIKit.expand(_plan_info)
	isc.add_child(_plan_info)
	var list_panel := UIKit.panel(&"CardPanel")
	UIKit.expand(list_panel, true, true)
	_plan.add_child(list_panel)
	_panels.append(list_panel)
	var sc := UIKit.scroll()
	list_panel.add_child(sc)
	_plan_list = UIKit.vbox(10)
	UIKit.expand(_plan_list)
	sc.add_child(_plan_list)
	var side := UIKit.panel(&"AccentPanel")
	side.custom_minimum_size.x = 400
	_plan.add_child(side)
	_panels.append(side)
	var buttons := UIKit.vbox(12)
	side.add_child(buttons)
	buttons.add_child(UIKit.label("READY?", &"SubHeaderLabel", false, Palette.ACCENT))
	buttons.add_child(UIKit.label("Operating starts the clock. Vitals drift while you work: keep COAG, SEDATE and STABIL in reach.", &"DimLabel", true))
	buttons.add_child(UIKit.expand(Control.new(), false, true))
	_begin = UIKit.button("BEGIN OPERATION   [ENTER]", &"BrandButton", GameManager.begin_surgery, "BeginButton", 72)
	_begin.set_meta(&"default", true)
	buttons.add_child(_begin)
	var back := UIKit.button("RE-DIAGNOSE", &"GhostButton", _show_diagnose, "PlanBackButton", 52)
	buttons.add_child(back)


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
		_hint.text = "Click body regions to scan (%d/%d). The surgical site glows pink." % [count, MIN_SCANS_TO_DIAGNOSE]
	elif _selected == &"":
		_hint.text = "Pick the diagnosis the findings point to."
	else:
		_hint.text = "Diagnosis selected. Confirm to plan the operation."
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
	if not _begin.disabled:
		_begin.grab_focus.call_deferred()


func _build_plan_contents() -> void:
	UIKit.clear(_plan_list)
	UIKit.clear(_plan_info)
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
	_plan_info.add_child(head)
	# Implant choice
	_plan_list.add_child(UIKit.label("IMPLANT UNIT · click to choose which unit goes in", &"SubHeaderLabel", false, Palette.ACCENT))
	var opts := GameManager.get_implant_options()
	var selected := GameManager.get_selected_implant()
	if opts.is_empty():
		var src := str(r["implant_source"])
		var msg := "None in stock. Buy on start: %s" % EconomyManager.format_money(InventoryManager.implant_price(item)) if src == "buy" else "None in stock and can't buy: customer brings a salvaged unit (-20% performance)."
		_plan_list.add_child(UIKit.label(msg, &"DimLabel", true, Palette.WARN if src != "buy" else Palette.TEXT))
	for i in opts.size():
		_plan_list.add_child(_implant_option(i, opts[i], opts[i] == selected, item))
	# Checks
	_plan_info.add_child(UIKit.label("CHECKS", &"SubHeaderLabel", false, Palette.ACCENT))
	var missing: Array = r["missing_tools"]
	_check("TOOLS", "READY" if missing.is_empty() else "MISSING " + ", ".join(missing), missing.is_empty())
	_check("SUPPLIES", "%d / need %d" % [InventoryManager.supplies, surgery.supplies], bool(r["supplies_ok"]))
	var refusal := "REFUSES: LOAD TOO HIGH" if GameManager.consent_risk_needed(float(r["neural_after"])) > 0.0 else "REFUSES THIS UNIT"
	_check("CONSENT", "AGREES" if bool(r["accepts"]) else refusal, bool(r["accepts"]))
	_check("REVEALED", "%d condition(s)" % customer.revealed_conditions.size(), customer.revealed_conditions.is_empty())
	_plan_info.add_child(UIKit.label("PROCEDURE", &"SubHeaderLabel", false, Palette.ACCENT))
	for k in surgery.stages.size():
		var st := surgery.stages[k]
		var tool := "  [%s]" % String(st.tool_category).to_upper() if st.tool_category != &"" else ""
		_plan_info.add_child(UIKit.label("%02d  %s%s" % [k + 1, st.title, tool], &"DimLabel"))
	_begin.disabled = not bool(r["ok"])


func _implant_option(i: int, inst: ImplantInstance, selected: bool, requested: CyberwareData) -> Control:
	var data := inst.get_data()
	var b := Button.new()
	b.name = "Implant_%d" % i
	b.theme_type_variation = &"ToolButton"
	b.toggle_mode = true
	b.button_pressed = selected
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 96
	b.tooltip_text = "%s\n%s" % [data.display_name, data.description]
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
	c.custom_minimum_size.x = 150
	row.add_child(c)
	# Symbol + colour: "+" ready, "x" blocked (readable without colour).
	var v := UIKit.label(("+ " if good else "x ") + value, &"MonoLabel", true, Palette.OK if good else Palette.WARN, 19)
	UIKit.expand(v)
	row.add_child(v)
	_plan_info.add_child(row)
