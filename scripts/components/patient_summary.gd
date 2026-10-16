class_name PatientSummary
extends Control
## THE PATIENT: what you see when you click a patient. The default view
## answers four questions and nothing else:
##   what do they want · the one thing to know before operating ·
##   is it worth it · what to do next (ACCEPT JOB)
## DETAILS (one click) adds your odds, the money line by line and every
## risk factor; from there, their INTAKE FORM (the in-world document) and
## their FILE (payment terms, staff, deferring). Numbers: PatientBrief and
## IntakeRecord (the game's own rules, what the doctor can see).
##
## Opened with GameManager.show_patient_summary(). ESC or CLOSE goes back to
## the clinic with the patient still waiting.

var _accept: Button
var _details_box: VBoxContainer
var _form_box: VBoxContainer
var _details_button: Button
var _customer: CustomerData
var _brief: Dictionary = {}


func _ready() -> void:
	name = "PatientSummary"
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	add_child(UIKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UIKit.full_rect(center))
	_customer = GameManager.get_current_customer()
	if _customer == null:
		_close.call_deferred()
		return
	_brief = PatientBrief.build(_customer)
	var p := UIKit.panel(&"AccentPanel")
	p.name = "SummaryPanel"
	p.custom_minimum_size = Vector2(980, 0)
	center.add_child(p)
	var col := UIKit.vbox(14)
	p.add_child(col)
	_head(col)
	_essentials(col)
	_actions(col)
	# Level 2 and 3 live in the same window, folded away.
	_details_box = UIKit.vbox(10)
	_details_box.name = "SummaryDetailsBox"
	_details_box.visible = false
	col.add_child(_details_box)
	_form_box = UIKit.vbox(8)
	_form_box.name = "SummaryFormBox"
	_form_box.visible = false
	col.add_child(_form_box)
	TutorialManager.notify("summary")
	AudioManager.play_sfx(&"click", 0.0)


# --- Level 1: the essentials -------------------------------------------------------

func _head(col: VBoxContainer) -> void:
	var head := UIKit.hbox(14)
	col.add_child(head)
	var portrait := PixelPortrait.new()
	portrait.framing = PixelPortrait.Framing.FACE
	portrait.set_appearance(_customer.appearance, FactionManager.get_color(_customer.faction_id))
	head.add_child(portrait)
	var who := UIKit.vbox(2)
	UIKit.expand(who)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(who)
	if bool(_brief["emergency"]):
		who.add_child(UIKit.label("EMERGENCY", &"SubHeaderLabel", false, Palette.DANGER))
	var nm := str(_brief["name"]) + ((" \"%s\"" % str(_brief["alias"])) if str(_brief["alias"]) != "" else "")
	who.add_child(UIKit.label(nm, &"HeaderLabel"))
	if _customer.referred_by != "":
		who.add_child(UIKit.label("Sent by %s" % _customer.referred_by, &"DimLabel", true, Palette.TEXT_DIM, 15))
	# Someone with a story speaks for themselves here: the case is told
	# through what they say, so it can't be skipped by never opening the file.
	if _customer.case_id != &"" and _customer.dialogue != "":
		var said := UIKit.flavor(_customer.dialogue, 15)
		said.name = "SummarySaid"
		said.custom_minimum_size.x = 520
		who.add_child(said)
	var close := UIKit.button("CLOSE  %s" % Controls.hint("pause"), &"GhostButton", _close, "SummaryClose", 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(close)


func _essentials(col: VBoxContainer) -> void:
	var r: Dictionary = _brief["request"]
	var f: Dictionary = _brief["finance"]
	_line(col, "SummaryWants", "WANTS", "%s · %s" % [r["implant"], r["procedure"]], Palette.TEXT)
	# One sentence: what stops you, else the most serious risk you can see.
	var missing: Array = _brief["missing"]
	if not missing.is_empty():
		var m: Dictionary = missing[0]
		var row := _line(col, "SummaryKeyRisk", "MISSING", "✕ " + str(m["text"]), Palette.DANGER)
		if str(m["fix"]) != "":
			var link: Dictionary = m["link"]
			row.add_child(UIKit.button(str(m["fix"]), &"GhostButton", func() -> void:
				_close()
				Nav.open(link), "Fix_%s" % m["key"], 36))
	else:
		var k := IntakeRecord.key_risk(_customer)
		if not k.is_empty():
			_line(col, "SummaryKeyRisk", "RISK", "%s %s" % [IntakeRecord.mark(k["level"]), k["text"]], IntakeRecord.color(k["level"]))
	# The money in one line (revenue is not profit).
	var margin := int(f["margin"])
	var pays := "≈ %s" % EconomyManager.format_money(int(f["fee"]))
	if int(f["owed"]) > 0:
		pays += " (%s now)" % EconomyManager.format_money(int(f["pays_now"]))
	var money := _line(col, "SummaryMargin", "MONEY", "pays %s · you keep ≈ %+d cr before rent" % [pays, margin], Palette.OK if margin > 0 else Palette.DANGER)
	money.tooltip_text = "Estimated direct margin: the whole fee (what they pay now plus any instalments) minus the implant and supplies. Rent and wages come out at closing. DETAILS has the breakdown."


func _actions(col: VBoxContainer) -> void:
	var row := UIKit.hbox(10)
	row.name = "SummaryActions"
	col.add_child(row)
	var blocked := not (_brief["missing"] as Array).is_empty()
	if _customer.is_emergency:
		# Triage lives in the file (stabilise, specialist, rig, premium).
		_accept = UIKit.button("OPEN TRIAGE  [ENTER]", &"AccentButton", _open_file, "AcceptButton", 56)
	else:
		_accept = UIKit.button("ACCEPT JOB  [ENTER]", &"AccentButton", _on_accept, "AcceptButton", 56)
		_accept.disabled = blocked
		_accept.tooltip_text = "Fix what's missing first." if blocked else "Scan them, then plan the operation. Nothing is spent until you begin."
	UIKit.expand(_accept)
	_accept.size_flags_stretch_ratio = 2.0
	row.add_child(_accept)
	_details_button = UIKit.button("DETAILS", &"GhostButton", _toggle_details, "SummaryDetails", 56)
	_details_button.tooltip_text = "Your odds, the money line by line, every risk factor."
	UIKit.expand(_details_button)
	row.add_child(_details_button)
	var dec: Dictionary = _brief["decline"]
	var decline := UIKit.button("DECLINE", &"GhostButton", _on_decline, "SummaryDecline", 56)
	decline.tooltip_text = "They leave. %d street rep, %d standing with %s." % [int(dec["rep"]), int(dec["faction_delta"]), dec["faction"]]
	UIKit.expand(decline)
	row.add_child(decline)
	if not _accept.disabled:
		_accept.grab_focus.call_deferred()


# --- Level 2: details ----------------------------------------------------------------

func _toggle_details() -> void:
	if _details_box.get_child_count() == 0:
		_build_details()
	_form_box.visible = false
	_details_box.visible = not _details_box.visible
	_details_button.text = "HIDE DETAILS" if _details_box.visible else "DETAILS"


func _build_details() -> void:
	var o: Dictionary = _brief["operation"]
	var f: Dictionary = _brief["finance"]
	var box := _details_box
	box.add_child(_rule())
	var chance := roundi(float(o["success"]) * 100.0)
	var lvl: StringName = &"good" if chance >= 75 else (&"warn" if chance >= 55 else &"bad")
	_line(box, "SummaryDifficulty", "DIFFICULTY", "%s (%d / 5) · about %s" % [o["difficulty_word"], int(o["difficulty"]), TimeManager.duration_text(int(o["minutes"]))], Palette.TEXT)
	var s := _line(box, "SummarySuccess", "YOUR ODDS", "%s≈ %d%% (estimate: %s)" % [Accessibility.tag(lvl), chance, "; ".join(o["factors"])], JobVerdict.color(lvl))
	s.tooltip_text = Glossary.short("success_estimate")
	var risks: Array = o["risks"]
	if not risks.is_empty():
		_line(box, "SummaryCanGoWrong", "CAN GO WRONG", ", ".join(risks), Palette.TEXT_DIM)
	var src := str(f["implant_source"])
	var src_text: String = {"stock": "from stock", "buy": "bought when you begin", "substitute": "substitute from stock", "salvaged": "salvaged"}.get(src, src)
	_line(box, "SummaryCosts", "COSTS", "implant %s (%s) + supplies %s" % [EconomyManager.format_money(int(f["implant_cost"])), src_text, EconomyManager.format_money(int(f["supplies_cost"]))], Palette.TEXT_DIM)
	if int(f["owed"]) > 0:
		_line(box, "SummaryOwed", "LATER", "%s in instalments" % EconomyManager.format_money(int(f["owed"])), Palette.TEXT_DIM)
	if src in ["stock", "substitute"] or int(f["owed"]) > 0:
		var why := "the implant is already yours" if src in ["stock", "substitute"] else "the rest comes in instalments"
		_line(box, "SummaryCash", "CASH TODAY", "%+d cr (%s)" % [int(f["cash_today"]), why], Palette.TEXT_DIM)
	# (The one-line advice is on the door card behind this window.)
	var rf := IntakeRecord.risks(_customer)
	if rf.size() > 1:
		for e: Dictionary in rf:
			box.add_child(UIKit.label("%s %s: %s" % [IntakeRecord.mark(e["level"]), str(e["label"]).capitalize(), e["value"]], &"", true, IntakeRecord.color(e["level"]), 14))
	# Level 3: the document and the full file.
	var more := UIKit.hbox(10)
	box.add_child(more)
	more.add_child(UIKit.button("INTAKE FORM", &"GhostButton", _show_form, "SummaryForm", 40))
	more.add_child(UIKit.button("FULL FILE", &"GhostButton", _open_file, "SummaryFile", 40))


# --- Level 3: the intake form ------------------------------------------------------

func _show_form() -> void:
	if _form_box.get_child_count() == 0:
		var form := IntakeForm.new().setup(_customer)
		form.custom_minimum_size = Vector2(940, 560)
		_form_box.add_child(form)
	_details_box.visible = false
	_details_button.text = "DETAILS"
	_form_box.visible = true


# --- Actions ------------------------------------------------------------------------

func _on_accept() -> void:
	_close()
	GameManager.accept_customer()


func _open_file() -> void:
	_close()
	GameManager.open_customer()


func _on_decline() -> void:
	var dec: Dictionary = _brief.get("decline", {})
	_close()
	UIManager.guard("TURN THEM AWAY?", "They leave. Word gets around: %d street rep and %d standing with %s." % [int(dec.get("rep", 0)), int(dec.get("faction_delta", 0)), str(dec.get("faction", ""))],
		"DECLINE", GameManager.decline_customer)


func on_escape() -> void:
	_close()


func _close() -> void:
	if UIManager.top_modal() == self:
		UIManager.close_modal()
	elif is_inside_tree():
		queue_free()


# --- Helpers ------------------------------------------------------------------------

func _line(parent: Control, node_name: String, caption: String, value: String, color: Color) -> HBoxContainer:
	var row := UIKit.hbox(10)
	row.name = node_name
	parent.add_child(row)
	var cap := UIKit.caption(caption)
	cap.custom_minimum_size.x = 150
	row.add_child(cap)
	var v := UIKit.label(value, &"", true, color, 17)
	UIKit.expand(v)
	row.add_child(v)
	return row


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(Palette.TEXT_DIM, 0.3)
	r.custom_minimum_size.y = 1
	return r


static func _first_sentence(s: String) -> String:
	var t := s.strip_edges()
	if t == "":
		return ""
	for sep in [". ", "! ", "? "]:
		var i := t.find(sep)
		if i > 0 and i < 140:
			return t.substr(0, i + 1)
	return t if t.length() <= 140 else t.substr(0, 137) + "..."
