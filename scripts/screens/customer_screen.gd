extends BaseScreen
## Customer intake (PC dossier layout). Left: who they are and what they
## said. Centre: expandable REQUEST / PAYMENT / RISK / MEDICAL HISTORY /
## PREVIOUS OPERATIONS sections. Right: neural load now vs after the job and
## the decision (ACCEPT [ENTER] / DECLINE).

const RISK_LABELS := ["", "LOW", "MEDIUM", "HIGH"]
const RISK_COLORS: Array[Color] = [Palette.TEXT, Palette.OK, Palette.WARN, Palette.DANGER]
const WEALTH := ["BROKE", "GETTING BY", "COMFORTABLE", "LOADED"]

var _dialogue: Label
var _type_tween: Tween
var _panels: Array[Control] = []
var _staff_box: VBoxContainer


func on_enter(_params: Dictionary) -> void:
	var c := GameManager.get_current_customer()
	if c == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	var item := GameManager.get_requested_item()
	var surgery := GameManager.get_current_surgery()
	var col := UIKit.workstation(self, &"clinic")
	col.add_child(UIKit.header("STEP 1 / 4 · INTAKE", "CUSTOMER FILE", GameManager.go_to_clinic))
	var row := UIKit.hbox(18)
	UIKit.expand(row, true, true)
	col.add_child(row)

	# --- Left: identity + statement ---
	var left := UIKit.vbox(14)
	left.custom_minimum_size.x = 440
	row.add_child(left)
	var lsc := UIKit.scroll()
	left.add_child(lsc)
	var profile := _profile_card(c)
	UIKit.expand(profile, true, true)
	lsc.add_child(profile)
	_panels.append(lsc)

	# --- Centre: expandable file sections ---
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	row.add_child(sc)
	var mid := UIKit.vbox(12)
	UIKit.expand(mid)
	sc.add_child(mid)
	var statement := UIKit.panel(&"AccentPanel")
	statement.name = "DialogueCard"
	var sv := UIKit.vbox(8)
	statement.add_child(sv)
	sv.add_child(UIKit.label("STATEMENT", &"SubHeaderLabel", false, Palette.ACCENT))
	_dialogue = UIKit.label(c.dialogue, &"MonoLabel", true)
	sv.add_child(_dialogue)
	statement.gui_input.connect(_on_dialogue_input)
	statement.tooltip_text = "Click to skip the typing"
	mid.add_child(statement)
	if item and surgery:
		_request_section(mid, item, surgery)
		_payment_section(mid, c, item, surgery)
	_risk_section(mid, c)
	_medical_section(mid, c)
	_previous_section(mid, c)
	_panels.append(sc)

	# --- Right: neural load + decision ---
	var right := UIKit.vbox(14)
	right.custom_minimum_size.x = 400
	row.add_child(right)
	var load_box := UIKit.section(right, "NEURAL LOAD")
	var meter := NeuralLoadMeter.new()
	meter.name = "NeuralMeter"
	load_box.add_child(meter)
	var now := NeuralLoad.compute_visible(c)
	var after := now + (item.neural_load if item else 0.0) * maxf(0.2, ModifierManager.mult(&"neural.load"))
	meter.set_load(now, after)
	var band_now: Dictionary = NeuralLoad.band(now)
	var band_after: Dictionary = NeuralLoad.band(after)
	load_box.add_child(UIKit.label("NOW %d%%  %s" % [roundi(now), band_now["name"]], &"MonoLabel", false, band_now["color"]))
	load_box.add_child(UIKit.label("AFTER ≈ %d%%  %s" % [roundi(after), band_after["name"]], &"MonoLabel", false, band_after["color"]))
	load_box.add_child(UIKit.label("Hidden conditions can add more. Scan before you cut.", &"DimLabel", true))
	right.add_child(UIKit.expand(Control.new(), false, true))
	var decide := UIKit.section(right, "DECISION", &"AccentPanel")
	var accept := UIKit.button("PERFORM SURGERY YOURSELF  [ENTER]", &"AccentButton", GameManager.accept_customer, "AcceptButton", 60)
	accept.set_meta(&"default", true)
	decide.add_child(accept)
	var staff_n := StaffManager.at_clinic(ClinicManager.tier).size()
	var assign := UIKit.button("ASSIGN RIPPERDOC  (%d ON SHIFT)" % staff_n, &"GhostButton", _toggle_staff, "AssignButton", 48)
	assign.disabled = staff_n == 0
	assign.tooltip_text = "Hire staff in STAFF to delegate jobs." if staff_n == 0 else "Let one of your ripperdocs take the job."
	decide.add_child(assign)
	_staff_box = UIKit.vbox(6)
	_staff_box.visible = false
	decide.add_child(_staff_box)
	var defer := UIKit.button("DEFER TO TOMORROW", &"GhostButton", _on_defer, "DeferButton", 44)
	defer.tooltip_text = "They may not come back. Emergencies won't wait."
	decide.add_child(defer)
	var decline := UIKit.button("REFUSE  (-%d REP)" % absi(GameConfig.DECLINE_REPUTATION_PENALTY), &"GhostButton", _on_decline, "DeclineButton", 44)
	decide.add_child(decline)
	_panels.append(decide.get_parent())
	accept.grab_focus.call_deferred()

	# Typewriter at the player's text speed (Settings; 0 = instant).
	var cps := Settings.chars_per_second()
	if cps > 0.0:
		_dialogue.visible_ratio = 0.0
		_type_tween = create_tween()
		_type_tween.tween_property(_dialogue, "visible_ratio", 1.0, c.dialogue.length() / cps)


func get_panels() -> Array[Control]:
	return _panels


func _profile_card(c: CustomerData) -> Control:
	var card := UIKit.panel(&"DangerPanel" if c.is_emergency else &"AccentPanel")
	card.name = "ProfileCard"
	var v := UIKit.vbox(10)
	card.add_child(v)
	var row := UIKit.hbox(16)
	v.add_child(row)
	var p := PixelPortrait.new()
	p.name = "Portrait"
	p.framing = PixelPortrait.Framing.BUST
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(p)
	v.move_child(p, 0)
	var look := CharacterPortraitManager.describe(c.id)
	if not look.is_empty():
		p.set_appearance(look["appearance"], look["accent"], look["backdrop"], look["profile"])
	else:
		p.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
	var info := UIKit.vbox(4)
	UIKit.expand(info)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UIKit.label(c.display_name, &"HeaderLabel", true))
	if c.alias != "":
		info.add_child(UIKit.label("\"%s\"" % c.alias, &"MonoLabel", false, Palette.BRAND))
	info.add_child(UIKit.label("%d yrs · %s" % [c.age, c.occupation.capitalize()], &"DimLabel", true))
	if c.is_emergency:
		info.add_child(UIKit.label("EMERGENCY", &"SubHeaderLabel", false, Palette.DANGER))
	if c.age < 18:
		info.add_child(UIKit.label("MINOR · %d YEARS OLD" % c.age, &"SubHeaderLabel", false, Palette.WARN))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override(&"h_separation", 14)
	g.add_theme_constant_override(&"v_separation", 8)
	v.add_child(g)
	var fac_row := UIKit.hbox(6)
	fac_row.add_child(UIKit.icon(str(FactionManager.get_faction(c.faction_id).get("emblem", "")), 16))
	var fl := UIKit.label(FactionManager.get_name_of(c.faction_id).to_upper(), &"SubHeaderLabel", true, FactionManager.get_color(c.faction_id))
	UIKit.expand(fl)
	fac_row.add_child(fl)
	UIKit.expand(fac_row)
	for pair: Array in [
		["FACTION", fac_row],
		["STANDING", FactionManager.get_standing(c.faction_id)],
		["TEMPER", String(c.personality).to_upper()],
		["MONEY", WEALTH[clampi(c.wealth, 0, 3)]],
		["STREET REP", str(c.street_rep)],
	]:
		g.add_child(UIKit.label(pair[0], &"SubHeaderLabel"))
		if pair[1] is Control:
			g.add_child(pair[1])
		else:
			g.add_child(UIKit.expand(UIKit.label(str(pair[1]), &"", true)))
	if c.visits > 0 or c.referred_by != "":
		v.add_child(UIKit.label(("RETURNING · VISIT %d" % (c.visits + 1)) if c.visits > 0 else "REFERRED BY " + c.referred_by.to_upper(), &"SubHeaderLabel", true, Palette.OK))
	return card


func _grid(parent: Control, rows: Array) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override(&"h_separation", 18)
	g.add_theme_constant_override(&"v_separation", 4)
	parent.add_child(g)
	for pair: Array in rows:
		var k := UIKit.label(pair[0], &"SubHeaderLabel")
		k.custom_minimum_size.x = 170
		g.add_child(k)
		var vl := UIKit.label(str(pair[1]), &"", true, pair[2] if pair.size() > 2 else null)
		UIKit.expand(vl)
		g.add_child(vl)


func _request_section(parent: Control, item: CyberwareData, surgery: SurgeryData) -> void:
	var body := UIKit.collapsible(parent, "REQUEST", true, &"CardPanel", "[B] database")
	var row := UIKit.hbox(16)
	body.add_child(row)
	row.add_child(CyberwareIcon.make(item))
	var v := UIKit.vbox(4)
	UIKit.expand(v)
	row.add_child(v)
	v.add_child(UIKit.label(item.display_name, &"HeaderLabel", true, item.get_rarity_color()))
	v.add_child(UIKit.label(item.description, &"DimLabel", true))
	var tools: Array[String] = []
	for req in item.get_tool_requirements():
		var have := InventoryManager.has_tool_category(StringName(str(req["category"])), int(req["tier"]))
		tools.append("%s T%d%s" % [String(req["category"]).to_upper(), int(req["tier"]), "" if have else " (MISSING)"])
	_grid(body, [
		["CLASS", "T%d %s · %s" % [item.tier, item.get_tier_name(), item.rarity.to_upper()], item.get_rarity_color()],
		["MAKER", item.manufacturer if item.manufacturer != "" else "unknown"],
		["PROCEDURE", "%s · %d steps" % [surgery.display_name, surgery.stages.size()]],
		["DIFFICULTY", "%s  %d/5" % [UIKit.pips(item.install_difficulty, 5), item.install_difficulty], Palette.WARN if item.install_difficulty >= 3 else null],
		["TOOLS", ", ".join(tools) if not tools.is_empty() else "standard kit", Palette.DANGER if tools.any(func(t: String) -> bool: return t.ends_with("(MISSING)")) else null],
		["IN STOCK", "%d unit(s)" % InventoryManager.get_implant_count(item.id), Palette.DANGER if InventoryManager.get_implant_count(item.id) == 0 else Palette.OK],
	])


func _payment_section(parent: Control, c: CustomerData, item: CyberwareData, surgery: SurgeryData) -> void:
	var body := UIKit.collapsible(parent, "PAYMENT", true)
	var offer := int(round((surgery.base_pay + item.price * GameConfig.IMPLANT_PRICE_MARKUP) * c.pay_multiplier))
	_grid(body, [
		["OFFER", "%s base" % EconomyManager.format_money(offer), Palette.WARN],
		["IMPLANT VALUE", EconomyManager.format_money(item.price)],
		["PAYS", "x%.2f of list (%s)" % [c.pay_multiplier, WEALTH[clampi(c.wealth, 0, 3)].to_lower()]],
		["BONUS", "Clean work, speed and a stable patient raise the final pay."],
	])


func _risk_section(parent: Control, c: CustomerData) -> void:
	var risk := c.get_risk_level()
	var body := UIKit.collapsible(parent, "RISK", true, &"CardPanel", RISK_LABELS[risk])
	_grid(body, [
		["OVERALL", RISK_LABELS[risk], RISK_COLORS[risk]],
		["NEURAL STABILITY", "%d%%" % roundi(c.neural_stability), Palette.OK if c.neural_stability >= 70.0 else Palette.WARN],
		["KNOWN CONDITIONS", str(c.revealed_conditions.size()) + ("" if c.revealed_conditions.is_empty() else "  (" + ", ".join(c.revealed_conditions.map(func(id: StringName) -> String: return str(CustomerManager.get_condition(id).get("name", id)))) + ")")],
	])
	_stat_row(body, "PATIENCE", c.patience / 100.0, Palette.ACCENT)
	_stat_row(body, "RISK APPETITE", c.risk_tolerance, Palette.BRAND)


func _medical_section(parent: Control, c: CustomerData) -> void:
	var body := UIKit.collapsible(parent, "MEDICAL HISTORY", true, &"CardPanel", "%d implant(s)" % c.existing_cyberware.size())
	if c.existing_cyberware.is_empty():
		body.add_child(UIKit.label("No installed chrome.", &"DimLabel"))
	var chrome := HFlowContainer.new()
	chrome.add_theme_constant_override(&"h_separation", 12)
	chrome.add_theme_constant_override(&"v_separation", 8)
	body.add_child(chrome)
	for id in c.existing_cyberware:
		var e := CyberwareManager.get_cyberware(id)
		if e == null:
			continue
		var chip := UIKit.hbox(8)
		chip.tooltip_text = "%s\n%s\nNeural load %d%%" % [e.display_name, e.description, roundi(e.neural_load)]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var icon := CyberwareIcon.make(e)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		chip.add_child(UIKit.label("%s\nload %d%%" % [e.display_name, roundi(e.neural_load)], &"DimLabel"))
		chrome.add_child(chip)
	for h in c.medical_history:
		body.add_child(UIKit.label("· " + h, &"DimLabel", true))


func _previous_section(parent: Control, c: CustomerData) -> void:
	var ops := CustomerManager.get_previous_operations(c)
	var body := UIKit.collapsible(parent, "PREVIOUS OPERATIONS", not ops.is_empty(), &"CardPanel", "%d on file" % ops.size())
	if ops.is_empty():
		body.add_child(UIKit.label("No operations at this clinic yet.", &"DimLabel"))
		return
	for h in ops.slice(0, 6):
		var ok := str(h.get("outcome", "")) == "success"
		var what := str(h.get("surgery", "Operation"))
		if str(h.get("implant", "")) != "":
			what += " · " + str(h["implant"])
		body.add_child(UIKit.label("JOB #%d  %s  —  %s  %s" % [int(h.get("op", 0)), what, "OK" if ok else str(h.get("outcome", "")).to_upper().replace("_", " "), "grade " + str(h.get("grade", "-"))],
				&"MonoLabel", true, Palette.OK if ok else Palette.DANGER))


func _stat_row(parent: Control, caption: String, ratio: float, color: Color) -> void:
	var row := UIKit.hbox(12)
	var l := UIKit.label(caption, &"SubHeaderLabel")
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var bar := UIKit.meter(ratio, color, 8)
	UIKit.expand(bar)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(UIKit.label("%d%%" % roundi(ratio * 100.0), &"SubHeaderLabel"))
	parent.add_child(row)


func _on_dialogue_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_dialogue.visible_ratio = 1.0


func _on_decline() -> void:
	UIManager.confirm("TURN THEM AWAY?", "Word gets around. Declining costs %d rep." % absi(GameConfig.DECLINE_REPUTATION_PENALTY),
			"DECLINE", GameManager.decline_customer, true)


func _toggle_staff() -> void:
	_staff_box.visible = not _staff_box.visible
	if not _staff_box.visible:
		return
	UIKit.clear(_staff_box)
	var c := GameManager.get_current_customer()
	for o: Dictionary in StaffManager.options_for(c):
		var e: Dictionary = o["employee"]
		var id := StringName(str(e["id"]))
		var row := UIKit.hbox(8)
		var p := PixelPortrait.new()
		p.framing = PixelPortrait.Framing.HEAD
		p.set_appearance(e["appearance"], Palette.ACCENT, &"clinic", StringName(str(e.get("anim", "calm"))))
		row.add_child(p)
		var v := UIKit.vbox(2)
		UIKit.expand(v)
		row.add_child(v)
		v.add_child(UIKit.label(str(e["name"]), &"", true, Palette.TEXT, 15))
		var chance := roundi(float(o["chance"]) * 100.0)
		v.add_child(UIKit.label("%s · %d%% · stress %d" % [StaffManager.spec_label(e), chance, roundi(float(e["stress"]))], &"DimLabel", true, Palette.OK if chance >= 70 else (Palette.WARN if chance >= 45 else Palette.DANGER), 13))
		var why := str(o["refusal"])
		if why != "":
			v.add_child(UIKit.label(why, &"DimLabel", true, Palette.WARN, 13))
			if why.begins_with("\""):
				v.add_child(UIKit.button("INSIST (costs loyalty)", &"DangerButton", _on_assign.bind(id, true), "Insist_%s" % id, 36))
		else:
			v.add_child(UIKit.button("ASSIGN", &"AccentButton", _on_assign.bind(id, false), "Assign_%s" % id, 36))
		_staff_box.add_child(row)


func _on_assign(id: StringName, insist: bool) -> void:
	var r := GameManager.assign_customer(id, insist)
	if bool(r.get("refused", true)):
		UIManager.show_toast(str(r.get("text", "")), &"warn")
		return
	var ok := bool(r["success"])
	AudioManager.play_sfx(&"cash" if ok else (&"failure" if bool(r["death"]) else &"denied"), 0.0)
	var title := "JOB DONE" if ok else ("PATIENT LOST" if bool(r["death"]) else "JOB BOTCHED")
	var body := "%s\n\n%s" % [str(r["text"]), ("Paid %s." % EconomyManager.format_money(int(r["pay"]))) if ok else "No pay. People will talk."]
	var btn: Array[Dictionary] = [{"label": "BACK TO THE CLINIC", "style": &"AccentButton", "name": "AssignResultClose", "callback": GameManager.go_to_clinic}]
	UIManager.show_dialog(title, body, btn)


func _on_defer() -> void:
	var c := GameManager.get_current_customer()
	var name := c.display_name if c else ""
	var back := GameManager.defer_customer()
	UIManager.show_toast("%s will come back tomorrow." % name if back else "%s won't be back." % name, &"info" if back else &"warn")
	GameManager.go_to_clinic()
