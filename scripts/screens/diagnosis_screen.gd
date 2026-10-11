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
var _region_buttons: Dictionary = {}
var _ready_note: Label
var _preview: VBoxContainer
var _hand_off: Button
var _region_text: Dictionary = {}


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
	frame.custom_minimum_size = Vector2(620, 560)
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
	_findings = UIKit.vbox(8)
	UIKit.expand(_findings)
	sc.add_child(_findings)
	_findings.add_child(UIKit.section_head("FINDINGS", "", "diagnosis"))
	_findings.add_child(UIKit.label("Scan at least %d regions: click them on the body or press SCAN. Start with the surgical site (%s, pink)." % [
		MIN_SCANS_TO_DIAGNOSE, ScanView.REGION_LABELS.get(surgery.scan_region, "?")], &"DimLabel", true))
	# One row per region: status, what the scan found, a SCAN button.
	for region: StringName in ScanView.REGIONS:
		var card := UIKit.panel(&"CardPanel")
		card.name = "Region_%s" % region
		_findings.add_child(card)
		var rv := UIKit.vbox(4)
		card.add_child(rv)
		var head := UIKit.hbox(10)
		rv.add_child(head)
		var site := region == surgery.scan_region
		var t := UIKit.label(str(ScanView.REGION_LABELS[region]) + ("  · SURGICAL SITE" if site else ""), &"SubHeaderLabel", false, Palette.BRAND if site else Palette.TEXT)
		UIKit.expand(t)
		head.add_child(t)
		var b := UIKit.button("SCAN", &"GhostButton", _scan_region.bind(region), "Scan_%s" % region, 36)
		b.custom_minimum_size.x = 110
		head.add_child(b)
		_region_buttons[region] = b
		# Empty until scanned (one instruction above covers how to scan).
		var body := UIKit.label("", &"DimLabel", true)
		body.name = "Finding_%s" % region
		body.visible = false
		rv.add_child(body)
		_region_text[region] = body
	var side := UIKit.panel(&"CardPanel")
	side.custom_minimum_size.x = 460
	_diagnose.add_child(side)
	_panels.append(side)
	var sv := UIKit.vbox(10)
	side.add_child(sv)
	sv.add_child(UIKit.section_head("DIAGNOSIS", "", "diagnosis"))
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
		var desc := str(option.get("description", option.get("hint", "")))
		if desc != "":
			_options.add_child(UIKit.label(desc, &"DimLabel", true, null, 15))
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
	buttons.add_child(UIKit.section_head("SURGERY PREVIEW", "", "odds"))
	# The preview scrolls if it runs long, so the buttons below always fit.
	var psc := UIKit.scroll()
	psc.name = "PreviewScroll"
	buttons.add_child(psc)
	var pv := UIKit.vbox(8)
	UIKit.expand(pv)
	psc.add_child(pv)
	_preview = UIKit.vbox(4)
	_preview.name = "SurgeryPreview"
	pv.add_child(_preview)
	_ready_note = UIKit.label("", &"", true)
	_ready_note.name = "ReadyNote"
	buttons.add_child(_ready_note)
	_begin = UIKit.button("BEGIN OPERATION   [ENTER]", &"BrandButton", GameManager.begin_surgery, "BeginButton", 72)
	_begin.set_meta(&"default", true)
	buttons.add_child(_begin)
	_hand_off = UIKit.button("", &"GhostButton", func() -> void:
		UIManager.go_to(UIManager.SCREEN_CUSTOMER, {"assign": true}), "ChangeSurgeon", 44)
	_hand_off.tooltip_text = "Hand the job to one of your ripperdocs instead (their odds, their stress)."
	buttons.add_child(_hand_off)
	var row := UIKit.hbox(8)
	buttons.add_child(row)
	var back := UIKit.button("RE-DIAGNOSE", &"GhostButton", _show_diagnose, "PlanBackButton", 44)
	UIKit.expand(back)
	row.add_child(back)
	var cancel := UIKit.button("CANCEL", &"GhostButton", func() -> void: UIManager.go_to(UIManager.SCREEN_CUSTOMER), "PlanCancel", 44)
	cancel.tooltip_text = "Back to the patient's file (nothing is spent)."
	UIKit.expand(cancel)
	row.add_child(cancel)


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


func _scan_region(region: StringName) -> void:
	if _scan.scan(region):
		var b: Button = _region_buttons.get(region)
		if b:
			b.disabled = true
			b.text = "SCANNING"


func _on_region_scanned(region: StringName) -> void:
	var customer := GameManager.get_current_customer()
	var text := str(customer.scan_findings.get(String(region), "No anomalies."))
	var found := false
	var body: Label = _region_text.get(region)
	if body:
		body.text = text
		body.visible = true
		body.add_theme_color_override(&"font_color", Palette.TEXT)
	for cid in CustomerManager.try_reveal_conditions(customer, region):
		var cond := CustomerManager.get_condition(cid)
		found = true
		var warn := UIKit.label("! %s: %s" % [str(cond.get("name", cid)).to_upper(), str(cond.get("hint", ""))], &"", true, Palette.DANGER, 16)
		warn.name = "Condition_%s" % cid
		if body:
			body.get_parent().add_child(warn)
		AudioManager.play_sfx(&"warning", 0.0)
	var b: Button = _region_buttons.get(region)
	if b:
		b.disabled = true
		b.text = "FOUND" if found else "SCANNED"
	AudioManager.play_sfx(&"stage", 0.0)
	_update_hint()


func _update_hint() -> void:
	var count := _scan.get_scanned_count()
	var unlocked := count >= MIN_SCANS_TO_DIAGNOSE
	for b: Button in _option_buttons.values():
		b.disabled = not unlocked
	if not unlocked:
		_hint.text = "Scan at least %d regions first (%d done). Start with the surgical site (pink)." % [MIN_SCANS_TO_DIAGNOSE, count]
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
	hv.add_child(UIKit.label("Diagnosis: %s" % surgery.get_diagnosis_name(_selected), &"DimLabel", true, null, 14))
	# Neural load only when it matters (what the doctor can see).
	var vis_after := float(r["neural_after"]) - (NeuralLoad.compute(customer) - NeuralLoad.compute_visible(customer))
	var band := NeuralLoad.band(vis_after)
	if NeuralLoad.band_index(vis_after) >= 2:
		hv.add_child(UIKit.label("! Neural load ≈ %d%% after: %s. Complications are likelier." % [roundi(vis_after), str(band["name"]).to_lower()], &"DimLabel", true, Palette.DANGER if NeuralLoad.band_index(vis_after) >= 3 else Palette.WARN, 14))
	_plan_info.add_child(head)
	# Implant choice
	_plan_list.add_child(UIKit.section_head("IMPLANT UNIT", "click to choose which unit goes in"))
	var opts := GameManager.get_implant_options()
	var selected := GameManager.get_selected_implant()
	if opts.is_empty():
		var src := str(r["implant_source"])
		var msg := "None in stock. Buy on start: %s" % EconomyManager.format_money(InventoryManager.implant_price(item)) if src == "buy" else "None in stock and can't buy: customer brings a salvaged unit (-20% performance)."
		_plan_list.add_child(UIKit.label(msg, &"DimLabel", true, Palette.WARN if src != "buy" else Palette.TEXT))
	for i in opts.size():
		_plan_list.add_child(_implant_option(i, opts[i], opts[i] == selected, item))
	# Checks
	_plan_info.add_child(UIKit.section_head("CHECKS"))
	var missing: Array = r["missing_tools"]
	_check("TOOLS", "READY" if missing.is_empty() else "MISSING " + ", ".join(missing), missing.is_empty())
	_check("SUPPLIES", "%d / need %d" % [InventoryManager.supplies, surgery.supplies], bool(r["supplies_ok"]))
	var refusal := "REFUSES: LOAD TOO HIGH" if GameManager.consent_risk_needed(float(r["neural_after"])) > 0.0 else "REFUSES THIS UNIT"
	_check("CONSENT", "AGREES" if bool(r["accepts"]) else refusal, bool(r["accepts"]))
	if not customer.revealed_conditions.is_empty():
		_check("FOUND", "%d condition(s): see the patient's risks" % customer.revealed_conditions.size(), false)
	_begin.disabled = not bool(r["ok"])
	_fill_preview(customer, item, surgery, r)
	# Say why BEGIN is blocked (or that you're good to go).
	var adv := JobVerdict.advice(customer)
	_ready_note.text = adv["text"] if _begin.disabled or adv["level"] != &"good" else Controls.fill("Everything's ready. Keep COAG [{quick_coag}], SEDATE [{quick_sedate}] and STABIL [{quick_stabilize}] in reach.")
	_ready_note.add_theme_color_override(&"font_color", JobVerdict.color(adv["level"]) if _begin.disabled or adv["level"] != &"good" else Palette.OK)


## SURGERY PREVIEW: the decision on one card before you commit.
func _fill_preview(c: CustomerData, item: CyberwareData, surgery: SurgeryData, r: Dictionary) -> void:
	UIKit.clear(_preview)
	var me := Recommend.self_estimate(c)
	var d := int(item.install_difficulty) if item else 2
	# Essentials first (your odds, what you keep); the rest under DETAILS.
	var target := {"box": _preview}
	var row := func(cap: String, val: String, col: Variant = null, _term: String = "") -> void:
		var h := UIKit.hbox(6)
		var k := UIKit.caption(cap)
		k.custom_minimum_size.x = 130
		h.add_child(k)
		var v := UIKit.label(val, &"", true, col, 15)
		UIKit.expand(v)
		h.add_child(v)
		(target["box"] as Control).add_child(h)
	var est := JobEstimate.for_customer(c, r)
	var chance := roundi(float(me["chance"]) * 100.0)
	row.call("YOUR ODDS", "≈ %d%%  (estimate)" % chance, Palette.OK if chance >= 75 else (Palette.WARN if chance >= 50 else Palette.DANGER))
	var keep := int(est["net"])
	row.call("YOU KEEP", "≈ %s before rent and wages" % ("%+d cr" % keep), Palette.OK if keep > 0 else Palette.DANGER)
	target["box"] = UIKit.collapsible(_preview, "DETAILS", false, &"CardPanel")
	row.call("DIFFICULTY", "%s  %d / 5" % [UIKit.pips(d, 5), d])
	var risk := c.get_risk_level()
	row.call("PATIENT RISK", ["", "✓ Low", "! Medium", "✕ High"][clampi(risk, 1, 3)], [Palette.OK, Palette.OK, Palette.WARN, Palette.DANGER][clampi(risk, 1, 3)])
	row.call("TIME", "≈ %s of the night" % TimeManager.duration_text(TimeManager.procedure_minutes(d, c.is_emergency)))
	var cost := surgery.supplies
	var buy := str(r.get("implant_source", "")) == "buy"
	row.call("COST", "%d suppl%s%s" % [cost, "y" if cost == 1 else "ies", (" + implant %s" % EconomyManager.format_money(InventoryManager.implant_price(item))) if buy and item else ""])
	var pay_txt := "≈ %s" % EconomyManager.format_money(int(est["fee"]))
	if int(est["owed"]) > 0:
		pay_txt += " · can pay %s now, owes the rest" % EconomyManager.format_money(int(est["can_pay"]))
	row.call("PAYMENT", pay_txt, Palette.WARN)
	var src := str(est["implant_source"])
	row.call("USES UP", "implant %s (%s) + supplies %s" % [EconomyManager.format_money(int(est["implant_cost"])),
		{"buy": "bought now", "salvaged": "salvaged", "stock": "from stock"}.get(src, "from stock"), EconomyManager.format_money(int(est["supplies_cost"]))])
	var extra := float(me["extra"])
	var comp_text := "%d expected" % int(me["guaranteed"]) if int(me["guaranteed"]) > 0 else "none expected"
	if extra > 0.0:
		comp_text += " · %d%% chance of another" % roundi(extra * 100.0)
	row.call("COMPLICATIONS", comp_text, Palette.WARN if extra >= 0.4 else null)
	var names := Recommend.possible_complications(c)
	if not names.is_empty():
		row.call("COULD BE", ", ".join(names))
	row.call("ODDS BASED ON", "%s%s" % [me["record"], (", " + ", ".join(me["factors"])) if not (me["factors"] as Array).is_empty() else ""])
	var rec := Recommend.surgeon(c)
	var best := Recommend.best_staff(c)
	row.call("RECOMMENDED", "%s · %d%%  (%s)" % [rec["name"], roundi(float(rec["chance"]) * 100.0), rec["reason"]], Palette.ACCENT)
	_hand_off.visible = not best.is_empty()
	if not best.is_empty():
		var e: Dictionary = best["employee"]
		_hand_off.text = "CHANGE SURGEON · %s %d%%" % [str(e["name"]).get_slice(" ", 0).to_upper(), roundi(float(best["chance"]) * 100.0)]
	(target["box"] as Control).add_child(UIKit.label("Estimates from the same rules the operation uses (assuming your diagnosis is right).", &"DimLabel", true, null, 13))


func _implant_option(i: int, inst: ImplantInstance, selected: bool, requested: CyberwareData) -> Control:
	var data := inst.get_data()
	var b := Button.new()
	b.name = "Implant_%d" % i
	b.theme_type_variation = &"ToolButton"
	b.toggle_mode = true
	b.button_pressed = selected
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 96
	b.tooltip_text = "%s\n%s" % [data.display_name, data.description] if inst.identified else "Unidentified device: model, condition and properties unknown."
	b.pressed.connect(func() -> void:
		GameManager.select_implant(inst.uid)
		_build_plan_contents())
	var row := UIKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(UIKit.full_rect(UIKit.margin(6, 4, 6, 4)))
	(b.get_child(0) as MarginContainer).add_child(row)
	if inst.identified:
		row.add_child(CyberwareIcon.make(data))
	else:
		row.add_child(UIKit.icon("res://assets/sprites/ui/icons/warning.png", 16))
	var v := UIKit.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.expand(v)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	var tag := "REQUESTED" if data.id == requested.id else ("UPGRADE" if data.tier > requested.tier else "SUBSTITUTE")
	if not inst.identified:
		v.add_child(UIKit.label(inst.display_name(), &"", true, Palette.BRAND, 15))
		v.add_child(UIKit.label("UNKNOWN · COND ?? · LOAD ??  · install it blind", &"SubHeaderLabel", true, Palette.WARN))
		return b
	v.add_child(UIKit.label(data.display_name, &"", true, null, 15))
	var unknown := "  ?? TRAITS" if inst.has_unknown_traits() else ""
	v.add_child(UIKit.label("%s · COND %d%% · LOAD +%d%%%s" % [tag, roundi(inst.condition), roundi(inst.get_neural_load()), unknown], &"SubHeaderLabel", true,
			Palette.OK if tag == "REQUESTED" else Palette.WARN))
	return b


func _check(caption: String, value: String, good: bool) -> void:
	var row := UIKit.hbox(8)
	var c := UIKit.caption(caption)
	c.custom_minimum_size.x = 150
	row.add_child(c)
	# Symbol + colour: "+" ready, "x" blocked (readable without colour).
	var v := UIKit.label(("+ " if good else "x ") + value, &"MonoLabel", true, Palette.OK if good else Palette.WARN, 19)
	UIKit.expand(v)
	row.add_child(v)
	_plan_info.add_child(row)
