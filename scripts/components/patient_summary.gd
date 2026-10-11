class_name PatientSummary
extends Control
## PATIENT SUMMARY: the first thing you see when you click a patient. On the
## left, their PATIENT INTAKE FORM (IntakeForm: who they are, the request,
## history and disclosures, complications and risk factors, each line tagged
## REPORTED / ON FILE / CONFIRMED / SUSPECTED / UNKNOWN). On the right, the
## operation (difficulty, your odds), the money and the decision: ACCEPT
## JOB, DECLINE (with its real cost) or MORE DETAILS (the full dossier:
## payment terms, staff, deferring). Numbers: PatientBrief (the game's own).
##
## Opened with GameManager.show_patient_summary(). A modal: ESC or CLOSE goes
## back to the clinic with the patient still waiting.

var _accept: Button


func _ready() -> void:
	name = "PatientSummary"
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	add_child(UIKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var c := GameManager.get_current_customer()
	if c == null:
		_close.call_deferred()
		return
	var b := PatientBrief.build(c)
	var p := UIKit.panel(&"AccentPanel")
	p.name = "SummaryPanel"
	p.custom_minimum_size = Vector2(1640, 0)
	center.add_child(p)
	var col := UIKit.vbox(12)
	p.add_child(col)
	_head(col, c, b)
	var row := UIKit.hbox(14)
	row.name = "SummaryRow"
	col.add_child(row)
	# Left: the intake form (scrolls inside itself if a record is long).
	var form := IntakeForm.new().setup(c)
	form.custom_minimum_size = Vector2(960, 720)
	UIKit.expand(form, true, true)
	row.add_child(form)
	# Right: the decision column.
	var grid := VBoxContainer.new()
	grid.name = "SummaryGrid"
	grid.add_theme_constant_override(&"separation", 12)
	grid.custom_minimum_size.x = 640
	row.add_child(grid)
	_operation(grid, b)
	_finances(grid, b)
	_decision(grid, c, b)
	TutorialManager.notify("summary")
	AudioManager.play_sfx(&"click", 0.0)


# --- Blocks -------------------------------------------------------------------------

func _head(col: VBoxContainer, c: CustomerData, b: Dictionary) -> void:
	var head := UIKit.hbox(14)
	col.add_child(head)
	var portrait := PixelPortrait.new()
	portrait.framing = PixelPortrait.Framing.FACE
	portrait.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
	head.add_child(portrait)
	var who := UIKit.vbox(2)
	UIKit.expand(who)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(who)
	who.add_child(UIKit.label("PATIENT SUMMARY" + ("  ·  EMERGENCY" if bool(b["emergency"]) else ""), &"SubHeaderLabel", false, Palette.DANGER if bool(b["emergency"]) else Palette.ACCENT))
	var nm := str(b["name"]) + ((" \"%s\"" % str(b["alias"])) if str(b["alias"]) != "" else "")
	who.add_child(UIKit.label(nm, &"HeaderLabel"))
	# Who they are, their words and their history are on the intake form below.
	who.add_child(UIKit.label("Read their intake form, then decide on the right.", &"DimLabel", true, null, 14))
	var close := UIKit.button("CLOSE  %s" % Controls.hint("pause"), &"GhostButton", _close, "SummaryClose", 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(close)


func _operation(grid: Container, b: Dictionary) -> void:
	var o: Dictionary = b["operation"]
	var box := _block(grid, "OPERATION", "SummaryOperation")
	var d := int(o["difficulty"])
	_row(box, "DIFFICULTY", "%s (%d / 5) · about %s" % [o["difficulty_word"], d, TimeManager.duration_text(int(o["minutes"]))],
		Palette.OK if d <= 2 else (Palette.WARN if d <= 3 else Palette.DANGER), "difficulty")
	var chance := roundi(float(o["success"]) * 100.0)
	var lvl: StringName = &"good" if chance >= 75 else (&"warn" if chance >= 55 else &"bad")
	var srow := _row(box, "YOUR ODDS", "%s≈ %d%%  (estimate)" % [Accessibility.tag(lvl), chance], JobVerdict.color(lvl), "success_estimate")
	srow.name = "SummarySuccess"
	box.add_child(UIKit.label("Based on: " + "; ".join(o["factors"]) + ".", &"DimLabel", true, null, 13))
	var risks: Array = o["risks"]
	if not risks.is_empty():
		_row(box, "WHAT CAN GO WRONG", ", ".join(risks), Palette.WARN, "risk")
	var missing: Array = b["missing"]
	for m: Dictionary in missing:
		var line := UIKit.hbox(8)
		line.name = "Missing_%s" % m["key"]
		box.add_child(line)
		var t := UIKit.label("✕ " + str(m["text"]), &"", true, Palette.DANGER, 15)
		UIKit.expand(t)
		line.add_child(t)
		if str(m["fix"]) != "":
			var link: Dictionary = m["link"]
			line.add_child(UIKit.button(str(m["fix"]), &"GhostButton", func() -> void:
				_close()
				Nav.open(link), "Fix_%s" % m["key"], 34))


func _finances(grid: Container, b: Dictionary) -> void:
	var f: Dictionary = b["finance"]
	var box := _block(grid, "FINANCES", "SummaryFinances")
	var pay := "≈ %s" % EconomyManager.format_money(int(f["fee"]))
	if int(f["owed"]) > 0:
		pay += "  ·  %s now, %s in instalments" % [EconomyManager.format_money(int(f["pays_now"])), EconomyManager.format_money(int(f["owed"]))]
	_row(box, "PATIENT PAYS", pay, Palette.TEXT, "terms_payment")
	var src := str(f["implant_source"])
	var src_text: String = {"stock": "from stock, replacement value", "buy": "bought when you begin", "substitute": "a substitute from stock", "salvaged": "salvaged parts"}.get(src, src)
	_row(box, "IMPLANT", "−%s  (%s)" % [EconomyManager.format_money(int(f["implant_cost"])), src_text], Palette.TEXT_DIM, "credits")
	_row(box, "SUPPLIES", "−%s  (%d used)" % [EconomyManager.format_money(int(f["supplies_cost"])), int(f["supplies"])], Palette.TEXT_DIM, "supplies")
	var margin := int(f["margin"])
	var mrow := _row(box, "DIRECT MARGIN", "%s≈ %s" % [Accessibility.tag(&"good" if margin > 0 else &"bad"), "%+d cr" % margin], Palette.OK if margin > 0 else Palette.DANGER, "direct_margin")
	mrow.name = "SummaryMargin"
	# A unit from stock is already paid for: say what the job brings in today.
	if src in ["stock", "substitute"]:
		var cash := int(f["cash_today"])
		var crow := _row(box, "CASH IN HAND", "%+d cr today (the implant is already yours)" % cash, Palette.OK if cash > 0 else Palette.DANGER, "the_money")
		crow.name = "SummaryCash"
	box.add_child(UIKit.label("Estimate before rent and wages. The real fee depends on how the operation goes.", &"DimLabel", true, null, 13))


func _decision(grid: Container, c: CustomerData, b: Dictionary) -> void:
	var box := _block(grid, "DECISION", "SummaryDecision")
	var rec: Dictionary = b["recommendation"]
	var rl := UIKit.label(str(rec["text"]), &"", true, JobVerdict.color(rec["level"]))
	rl.name = "SummaryAdvice"
	box.add_child(rl)
	var blocked := not (b["missing"] as Array).is_empty()
	if c.is_emergency:
		# Triage lives in the dossier (stabilise, specialist, rig, premium).
		_accept = UIKit.button("OPEN TRIAGE  [ENTER]", &"AccentButton", _details, "AcceptButton", 52)
	else:
		_accept = UIKit.button("ACCEPT JOB  [ENTER]", &"AccentButton", _on_accept, "AcceptButton", 52)
		_accept.disabled = blocked
		_accept.tooltip_text = "Fix what's missing first (or hand the job to staff in MORE DETAILS)." if blocked else "Scan them, then plan the operation. Nothing is spent until you begin."
	box.add_child(_accept)
	var row := UIKit.hbox(8)
	box.add_child(row)
	var dec: Dictionary = b["decline"]
	var decline := UIKit.button("DECLINE", &"GhostButton", _on_decline, "SummaryDecline", 44)
	decline.tooltip_text = "They leave. Costs %d street rep and %d standing with %s." % [absi(int(dec["rep"])), absi(int(dec["faction_delta"])), dec["faction"]]
	UIKit.expand(decline)
	row.add_child(decline)
	var more := UIKit.button("MORE DETAILS", &"GhostButton", _details, "SummaryDetails", 44)
	more.tooltip_text = "The full file: statement, history, payment terms, staff, deferring."
	UIKit.expand(more)
	row.add_child(more)
	box.add_child(UIKit.label("Declining: %d street rep, %d %s." % [int(dec["rep"]), int(dec["faction_delta"]), dec["faction"]], &"DimLabel", true, null, 13))
	if not _accept.disabled:
		_accept.grab_focus.call_deferred()


# --- Actions ------------------------------------------------------------------------

func _on_accept() -> void:
	_close()
	GameManager.accept_customer()


func _details() -> void:
	_close()
	GameManager.open_customer()


func _on_decline() -> void:
	var b := PatientBrief.build(GameManager.get_current_customer())
	var dec: Dictionary = b.get("decline", {})
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

func _block(grid: Container, title: String, node_name: String) -> VBoxContainer:
	var panel := UIKit.panel(&"CardPanel")
	panel.name = node_name
	UIKit.expand(panel, true, false)
	grid.add_child(panel)
	var v := UIKit.vbox(6)
	panel.add_child(v)
	v.add_child(UIKit.label(title, &"SectionLabel"))
	return v


func _row(parent: Control, caption: String, value: String, color: Color, term: String = "") -> HBoxContainer:
	var row := UIKit.hbox(8)
	parent.add_child(row)
	var cap := UIKit.caption(caption)
	cap.custom_minimum_size.x = 190
	row.add_child(cap)
	var v := UIKit.label(value, &"", true, color, 16)
	UIKit.expand(v)
	row.add_child(v)
	if term != "" and Glossary.has(term):
		row.add_child(UIKit.info(term))
	return row


static func _first_sentence(s: String) -> String:
	var t := s.strip_edges()
	if t == "":
		return ""
	for sep in [". ", "! ", "? "]:
		var i := t.find(sep)
		if i > 0 and i < 140:
			return t.substr(0, i + 1)
	return t if t.length() <= 140 else t.substr(0, 137) + "..."
