class_name IntakeForm
extends PanelContainer
## PATIENT INTAKE FORM: the patient's record as an in-world document, a
## completed questionnaire the clinic's terminal has stamped and annotated.
## Four sections (1 patient, 2 requested procedure, 3 complications and risk
## factors, 4 history and disclosures), every line tagged with
## where it comes from (REPORTED / ON FILE / CONFIRMED / SUSPECTED /
## UNKNOWN). Content: IntakeRecord (existing data only). Presentation only.

var _record: Dictionary = {}


func setup(c: CustomerData) -> IntakeForm:
	name = "IntakeForm"
	_record = IntakeRecord.build(c)
	# A worn sheet: dark, slightly green-tinted paper, a hard edge, no glow.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.095, 0.092)
	sb.border_color = Color(0.32, 0.42, 0.40, 0.9)
	sb.set_border_width_all(2)
	sb.border_width_left = 6
	sb.set_content_margin_all(18)
	sb.content_margin_left = 24
	add_theme_stylebox_override(&"panel", sb)
	clip_contents = true
	var sc := ScrollContainer.new()
	sc.name = "IntakeScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var v := UIKit.vbox(10)
	UIKit.expand(v, true, false)
	sc.add_child(v)
	_header(v, c)
	# The order a doctor reads it: who, what they want, what could go wrong,
	# then the supporting history (the risks never sit below the fold).
	_section(v, "1", "PATIENT", _record["patient"], "IntakePatient")
	_section(v, "2", "REQUESTED PROCEDURE", _record["request"], "SummaryRequest")
	_risks(v)
	_history(v, c)
	_legend(v)
	return self


func _draw() -> void:
	# Scan artifacts: faint scanlines and two worn bands across the sheet.
	var r := Rect2(Vector2.ZERO, size)
	var y := 0.0
	while y < r.size.y:
		draw_line(Vector2(6, y), Vector2(r.size.x, y), Color(1, 1, 1, 0.018), 1.0)
		y += 4.0
	for band_y in [0.31, 0.74]:
		draw_rect(Rect2(6, r.size.y * band_y, r.size.x - 6, 3), Color(0.6, 0.9, 0.85, 0.035))


func _header(v: VBoxContainer, c: CustomerData) -> void:
	var top := UIKit.hbox(12)
	v.add_child(top)
	var t := UIKit.vbox(0)
	UIKit.expand(t)
	top.add_child(t)
	t.add_child(UIKit.label("SUMP CLINIC // PATIENT INTAKE", &"SectionLabel", false, Color(0.62, 0.82, 0.78)))
	t.add_child(UIKit.label("Completed by the patient · annotated by the clinic terminal", &"DimLabel", false, null, 13))
	var ref := UIKit.vbox(0)
	top.add_child(ref)
	var id := UIKit.label(str(_record["doc_id"]), &"MonoLabel", false, Palette.TEXT_DIM, 14)
	id.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ref.add_child(id)
	var st := UIKit.label(str(_record["stamp"]).to_upper(), &"MonoLabel", false, Palette.TEXT_DIM, 13)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ref.add_child(st)
	var stamp := _chip("RECEIVED", Color(0.62, 0.82, 0.78))
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stamp)
	v.add_child(_rule())
	if c.is_emergency:
		var e := UIKit.label("✕✕ EMERGENCY INTAKE · FORM INCOMPLETE · PATIENT BLEEDING", &"SubHeaderLabel", true, Palette.DANGER)
		v.add_child(e)


func _section(v: VBoxContainer, letter: String, title: String, entries: Array, node_name: String) -> VBoxContainer:
	var box := UIKit.vbox(4)
	box.name = node_name
	v.add_child(box)
	box.add_child(UIKit.label("%s · %s" % [letter, title], &"SubHeaderLabel", false, Color(0.62, 0.82, 0.78)))
	for e: Dictionary in entries:
		box.add_child(_field(e))
	return box


func _history(v: VBoxContainer, c: CustomerData) -> void:
	var box := UIKit.vbox(4)
	box.name = "IntakeHistory"
	v.add_child(box)
	box.add_child(UIKit.label("4 · HISTORY & DISCLOSURES", &"SubHeaderLabel", false, Color(0.62, 0.82, 0.78)))
	# Their own words, styled as what they are: a statement, not a finding.
	if c.dialogue.strip_edges() != "":
		var row := UIKit.hbox(8)
		row.name = "IntakeStatement"
		box.add_child(row)
		var cap := UIKit.caption("STATEMENT")
		cap.custom_minimum_size.x = 190
		row.add_child(cap)
		var f := UIKit.flavor(PatientSummary._first_sentence(c.dialogue), 15)
		UIKit.expand(f)
		row.add_child(f)
		row.add_child(_chip(IntakeRecord.REPORTED, _status_color(IntakeRecord.REPORTED)))
	for e: Dictionary in _record["history"]:
		box.add_child(_field(e))


func _risks(v: VBoxContainer) -> void:
	var box := UIKit.vbox(6)
	box.name = "IntakeRisks"
	v.add_child(box)
	box.add_child(UIKit.label("3 · COMPLICATIONS & RISK FACTORS", &"SubHeaderLabel", false, Palette.WARN))
	var risks: Array = _record["risks"]
	if risks.is_empty():
		box.add_child(UIKit.label("· Nothing that worsens this procedure in what the clinic can see. Hidden conditions stay unknown until a scan.", &"DimLabel", true, null, 15))
	for e: Dictionary in risks:
		var lvl: StringName = e["level"]
		var card := PanelContainer.new()
		card.name = "Risk_%s" % e["key"]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.22)
		sb.border_color = IntakeRecord.color(lvl)
		sb.border_width_left = 4
		sb.set_content_margin_all(8)
		sb.content_margin_left = 12
		card.add_theme_stylebox_override(&"panel", sb)
		box.add_child(card)
		var cv := UIKit.vbox(2)
		card.add_child(cv)
		var head := UIKit.hbox(8)
		cv.add_child(head)
		var mk := UIKit.label("%s %s" % [IntakeRecord.mark(lvl), IntakeRecord.level_word(lvl)], &"MonoLabel", false, IntakeRecord.color(lvl), 14)
		mk.custom_minimum_size.x = 140
		head.add_child(mk)
		var t := UIKit.label("%s: %s" % [e["label"], e["value"]], &"", true, Palette.TEXT, 16)
		UIKit.expand(t)
		head.add_child(t)
		head.add_child(_chip(str(e["status"]), _status_color(str(e["status"]))))
		if str(e["why"]) != "":
			cv.add_child(UIKit.label(str(e["why"]), &"DimLabel", true, null, 14))
		if str(e["affects"]) != "":
			cv.add_child(UIKit.label("AFFECTS  " + str(e["affects"]), &"MonoLabel", true, Palette.TEXT_DIM, 13))


func _legend(v: VBoxContainer) -> void:
	v.add_child(_rule())
	var l := UIKit.label("REPORTED the patient says so · ON FILE clinic records · CONFIRMED examined · SUSPECTED indicated, cause not identified · UNKNOWN not known yet", &"DimLabel", true, Palette.TEXT_DIM, 12)
	l.name = "IntakeLegend"
	v.add_child(l)


# --- Pieces -------------------------------------------------------------------------

func _field(e: Dictionary) -> Control:
	var row := UIKit.hbox(8)
	row.name = "Field_%s" % e["key"]
	var cap := UIKit.caption(str(e["label"]))
	cap.custom_minimum_size.x = 190
	row.add_child(cap)
	var lvl: StringName = e["level"]
	var txt := str(e["value"])
	if lvl != IntakeRecord.NONE:
		txt = "%s %s" % [IntakeRecord.mark(lvl), txt]
	var val := UIKit.label(txt, &"", true, IntakeRecord.color(lvl) if lvl != IntakeRecord.NONE else (Palette.TEXT_DIM if str(e["status"]) == IntakeRecord.UNKNOWN else Palette.TEXT), 15)
	UIKit.expand(val)
	if str(e["why"]) != "":
		val.tooltip_text = str(e["why"]) + (("\nAffects: " + str(e["affects"])) if str(e["affects"]) != "" else "")
		val.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(val)
	row.add_child(_chip(str(e["status"]), _status_color(str(e["status"]))))
	return row


func _chip(text: String, color: Color) -> Label:
	var l := UIKit.label(text, &"MonoLabel", false, color, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(color, 0.7)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override(&"normal", sb)
	l.custom_minimum_size.x = 96
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return l


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(0.32, 0.42, 0.40, 0.6)
	r.custom_minimum_size.y = 1
	return r


static func _status_color(status: String) -> Color:
	match status:
		IntakeRecord.CONFIRMED:
			return Palette.ACCENT
		IntakeRecord.SUSPECTED:
			return Palette.WARN
		IntakeRecord.ON_FILE:
			return Color(0.62, 0.82, 0.78)
		IntakeRecord.UNKNOWN:
			return Palette.TEXT_DIM
	return Palette.TEXT_DIM
