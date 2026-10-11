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
var _terms_preview: Label
## Emergencies: real seconds before the patient crashes (paused by modals).
var _crash_shown: bool = false
var _crash_bar: ProgressBar
var _crash_label: Label


var _params: Dictionary = {}


func on_enter(params: Dictionary) -> void:
	_params = params
	var cc := GameManager.get_current_customer()
	if cc and cc.is_emergency:
		(func() -> void: Hints.first("emergency")).call_deferred()
	else:
		(func() -> void: Hints.first("neural_load")).call_deferred()
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
	sv.add_child(UIKit.section_head("STATEMENT"))
	_dialogue = UIKit.label(c.dialogue, &"MonoLabel", true)
	sv.add_child(_dialogue)
	statement.gui_input.connect(_on_dialogue_input)
	statement.tooltip_text = "Click to skip the typing"
	mid.add_child(statement)
	if c.is_emergency:
		_triage_section(mid, c)
	if c.dependency > 0 and not c.is_emergency:
		_dependency_section(mid, c)
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
	# Neural load and the at-a-glance card scroll; the decision stays put.
	var rsc := UIKit.scroll()
	UIKit.expand(rsc, true, true)
	right.add_child(rsc)
	var rtop := UIKit.vbox(14)
	UIKit.expand(rtop, true, false)
	rsc.add_child(rtop)
	var load_box := UIKit.section(rtop, "NEURAL LOAD", &"CardPanel", "", "neural_load")
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
	# At a glance: can you do it, what's in the way, one line of advice.
	var glance := UIKit.section(rtop, "AT A GLANCE", &"CardPanel", "", "loop")
	glance.get_parent().name = "AtAGlance"
	JobVerdict.build(glance, c)
	var decide := UIKit.section(right, "DECISION", &"AccentPanel", "", "loop")
	# Recommendation: who should operate, and why (the player decides).
	var rec := Recommend.surgeon(c)
	var rl := UIKit.label("RECOMMENDED: %s · %d%%  (%s)" % [str(rec["name"]).to_upper(), roundi(float(rec["chance"]) * 100.0), rec["reason"]], &"DimLabel", true, Palette.ACCENT, 15)
	rl.name = "Recommendation"
	rl.tooltip_text = "An estimate from the same rules the game uses. You decide."
	rl.mouse_filter = Control.MOUSE_FILTER_PASS
	decide.add_child(rl)
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
	if PeopleManager.has_person(c.id):
		var hist := UIKit.button("REVIEW HISTORY", &"GhostButton", func() -> void:
			UIManager.go_to(UIManager.SCREEN_DOSSIER, {"tab_name": "PATIENTS", "focus": String(c.id)}), "HistoryButton", 40)
		hist.tooltip_text = "Their visits, what they owe, what they remember (journal)."
		decide.add_child(hist)
	if bool(_params.get("assign", false)) and staff_n > 0:
		_toggle_staff.call_deferred()
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
		["TRAITS", ", ".join(c.traits.map(func(t: StringName) -> String: return PeopleManager.trait_label(t))).to_upper() if not c.traits.is_empty() else "—"],
		["MONEY", "%s · %s" % [WEALTH[clampi(c.wealth, 0, 3)], PeopleManager.finance_label(c.finance).to_upper()]],
		["STREET REP", str(c.street_rep)],
	]:
		g.add_child(UIKit.label(pair[0], &"SubHeaderLabel"))
		if pair[1] is Control:
			g.add_child(pair[1])
		else:
			g.add_child(UIKit.expand(UIKit.label(str(pair[1]), &"", true)))
	if c.visits > 0 or c.referred_by != "":
		v.add_child(UIKit.label(("RETURNING · VISIT %d" % (c.visits + 1)) if c.visits > 0 else "REFERRED BY " + c.referred_by.to_upper(), &"SubHeaderLabel", true, Palette.OK))
	_history_block(v, c)
	return card


## Who they are to you: relationship, what changed since last time, what
## they remember about you, what they owe.
func _history_block(v: VBoxContainer, c: CustomerData) -> void:
	var known := PeopleManager.has_person(c.id)
	if known:
		var st := PeopleManager.rel_state(c.id)
		var col: Color = {"loyal": Palette.OK, "grateful": Palette.OK, "friendly": Palette.OK, "wary": Palette.WARN, "hostile": Palette.DANGER}.get(st, Palette.TEXT_DIM)
		var rl := UIKit.label("RELATIONSHIP · %s  (%+d)" % [st.to_upper(), int(PeopleManager.get_person(c.id).get("rel", 0))], &"SubHeaderLabel", true, col)
		rl.name = "RelationshipLabel"
		v.add_child(rl)
	if not c.changes.is_empty():
		v.add_child(UIKit.section_head("SINCE LAST TIME"))
		for ch in c.changes:
			v.add_child(UIKit.label("· " + ch, &"DimLabel", true))
	var mem := MemoryManager.of(c.id)
	if not mem.is_empty():
		v.add_child(UIKit.section_head("THEY REMEMBER"))
		var seen := {}
		for i in range(mem.size() - 1, -1, -1):
			var tag := str(mem[i]["tag"])
			if seen.has(tag) or seen.size() >= 5:
				continue
			seen[tag] = true
			var good := int(MemoryManager.defs.get(tag, {}).get("rel", 0)) >= 0
			v.add_child(UIKit.label("· %s  (day %d)" % [MemoryManager.label(StringName(tag)), int(mem[i]["day"])], &"DimLabel", true, Palette.OK if good else Palette.DANGER))
	if c.dependency > 0:
		v.add_child(UIKit.label("CHROME DEPENDENCY · %s" % PeopleManager.DEPENDENCY_LABELS[clampi(c.dependency, 0, 4)].to_upper(), &"SubHeaderLabel", true, Palette.WARN))


func _grid(parent: Control, rows: Array) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override(&"h_separation", 18)
	g.add_theme_constant_override(&"v_separation", 4)
	parent.add_child(g)
	for pair: Array in rows:
		var k := UIKit.caption(pair[0])
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
		["PROCEDURE", "%s · %d steps · ≈ %s" % [surgery.display_name, surgery.stages.size(), TimeManager.duration_text(TimeManager.procedure_minutes(item.install_difficulty, GameManager.get_current_customer() != null and GameManager.get_current_customer().is_emergency))]],
		["DIFFICULTY", "%s  %d/5" % [UIKit.pips(item.install_difficulty, 5), item.install_difficulty], Palette.WARN if item.install_difficulty >= 3 else null],
		["TOOLS", ", ".join(tools) if not tools.is_empty() else "standard kit", Palette.DANGER if tools.any(func(t: String) -> bool: return t.ends_with("(MISSING)")) else null],
		["IN STOCK", "%d unit(s)" % InventoryManager.get_implant_count(item.id), Palette.DANGER if InventoryManager.get_implant_count(item.id) == 0 else Palette.OK],
	])


func _payment_section(parent: Control, c: CustomerData, item: CyberwareData, _surgery: SurgeryData) -> void:
	var body := UIKit.collapsible(parent, "PAYMENT", true)
	var fee := CustomerGenerator.estimate_fee(c)
	var cast := c.character_id != &"" and CharacterManager.has_character(c.character_id)
	var owed := PeopleManager.owed_by(c.id)
	_grid(body, [
		["EXPECTED FEE", "≈ %s for clean work" % EconomyManager.format_money(fee), Palette.WARN],
		["IMPLANT VALUE", EconomyManager.format_money(item.price)],
		["CAN PAY NOW", "whatever you ask" if cast else EconomyManager.format_money(c.budget), Palette.OK if cast or c.budget >= fee else Palette.WARN],
		["BACKED BY", FactionManager.get_name_of(c.backer) if c.backer != &"" else "nobody"],
		["ALREADY OWES", EconomyManager.format_money(owed) if owed > 0 else "nothing", Palette.DANGER if owed > 0 else null],
		["BONUS", "Clean work, speed and a stable patient raise the final pay."],
	])
	body.add_child(UIKit.section_head("TERMS", "", "terms_payment"))
	var flow := HFlowContainer.new()
	flow.name = "TermsRow"
	flow.add_theme_constant_override(&"h_separation", 8)
	flow.add_theme_constant_override(&"v_separation", 8)
	body.add_child(flow)
	var group := ButtonGroup.new()
	for t in PeopleManager.available_terms(c):
		var d := PeopleManager.terms_def(t)
		var b := UIKit.button(str(d.get("label", t)), &"GhostButton", _set_terms.bind(t), "Terms_%s" % t, 36)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = c.terms == t
		b.tooltip_text = str(d.get("desc", ""))
		flow.add_child(b)
	_terms_preview = UIKit.label("", &"MonoLabel", true)
	_terms_preview.name = "TermsPreview"
	body.add_child(_terms_preview)
	_update_terms_preview()


func _set_terms(t: StringName) -> void:
	var c := GameManager.get_current_customer()
	if c == null:
		return
	c.terms = t
	_update_terms_preview()


## What the chosen terms mean for an average result: paid now / owed.
func _update_terms_preview() -> void:
	var c := GameManager.get_current_customer()
	if c == null or _terms_preview == null:
		return
	var fee := CustomerGenerator.estimate_fee(c)
	var d := PeopleManager.terms_def(c.terms)
	var price := int(round(fee * float(d.get("mult", 1.0))))
	if c.terms == &"full" and c.traits.has(&"greedy"):
		price = int(round(price * 0.85))
	var cast := c.character_id != &"" and CharacterManager.has_character(c.character_id)
	var now := price
	match c.terms:
		&"plan":
			now = int(round(price * float(d.get("upfront", 0.3))))
			if not cast:
				now = mini(now, c.budget)
		&"faction", &"free":
			pass
		_:
			if not cast:
				now = mini(price, c.budget)
	var owe := price - now if c.terms != &"free" else 0
	var txt := "%s  ·  ≈ %s now" % [str(d.get("desc", "")), EconomyManager.format_money(now)]
	if owe > 0:
		txt += ", %s owed" % EconomyManager.format_money(owe)
	if c.terms == &"full" and c.traits.has(&"greedy"):
		txt += "  (they'll haggle)"
	_terms_preview.text = txt
	_terms_preview.add_theme_color_override(&"font_color", Palette.WARN if owe > 0 or c.terms in [&"overcharge", &"free"] else Palette.TEXT)


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
	var l := UIKit.caption(caption)
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
	var ranked := Recommend.staff_ranked(c)
	for i in ranked.size():
		var o: Dictionary = ranked[i]
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
		var best := i == 0 and str(o.get("refusal", "")) == ""
		v.add_child(UIKit.label(str(e["name"]) + ("   ★ RECOMMENDED" if best else ""), &"", true, Palette.ACCENT if best else Palette.TEXT, 15))
		v.add_child(UIKit.label(str(o["reason"]), &"DimLabel", true, null, 13))
		var chance := roundi(float(o["chance"]) * 100.0)
		var lvl: StringName = &"good" if chance >= 70 else (&"warn" if chance >= 45 else &"bad")
		v.add_child(UIKit.label("%s%s · %d%% · stress %d" % [Accessibility.tag(lvl), StaffManager.spec_label(e), chance, roundi(float(e["stress"]))], &"DimLabel", true, Palette.OK if chance >= 70 else (Palette.WARN if chance >= 45 else Palette.DANGER), 13))
		var why := str(o["refusal"])
		if why != "":
			v.add_child(UIKit.label(why, &"DimLabel", true, Palette.WARN, 13))
			if why.begins_with("\""):
				v.add_child(UIKit.button("INSIST (costs loyalty)", &"DangerButton", _on_assign.bind(id, true), "Insist_%s" % id, 36))
		else:
			v.add_child(UIKit.button("ASSIGN", &"AccentButton", _on_assign.bind(id, false), "Assign_%s" % id, 36))
		_staff_box.add_child(row)


func _on_assign(id: StringName, insist: bool) -> void:
	var before := Consequence.snapshot()
	var r := GameManager.assign_customer(id, insist)
	Consequence.show("", before, "JOB HANDED OVER")
	if bool(r.get("refused", true)):
		UIManager.show_toast(str(r.get("text", "")), &"warn")
		return
	var ok := bool(r["success"])
	AudioManager.play_sfx(&"cash" if ok else (&"failure" if bool(r["death"]) else &"denied"), 0.0)
	var title := "JOB DONE" if ok else ("PATIENT LOST" if bool(r["death"]) else "JOB BOTCHED")
	var body := "%s\n\n%s" % [str(r["text"]), ("Paid %s." % EconomyManager.format_money(int(r["pay"]))) if ok else "No pay. People will talk."]
	for l: Variant in r.get("settlement", {}).get("lines", []):
		body += "\n" + str(l)
	var btn: Array[Dictionary] = [{"label": "BACK TO THE CLINIC", "style": &"AccentButton", "name": "AssignResultClose", "callback": GameManager.go_to_clinic}]
	UIManager.show_dialog(title, body, btn)


func _on_defer() -> void:
	var c := GameManager.get_current_customer()
	var name := c.display_name if c else ""
	var back := GameManager.defer_customer()
	UIManager.show_toast("%s will come back tomorrow." % name if back else "%s won't be back." % name, &"info" if back else &"warn")
	GameManager.go_to_clinic()


# --- Emergency triage ----------------------------------------------------------------

func _triage_section(parent: Control, c: CustomerData) -> void:
	var box := UIKit.panel(&"DangerPanel")
	box.name = "TriageSection"
	parent.add_child(box)
	var v := UIKit.vbox(8)
	box.add_child(v)
	v.add_child(UIKit.label("EMERGENCY · TRIAGE%s" % ("  ·  CRASHED ONCE" if c.crashes > 0 else ""), &"SubHeaderLabel", false, Palette.DANGER))
	_crash_label = UIKit.label("", &"MonoLabel", false, Palette.WARN)
	v.add_child(_crash_label)
	_crash_bar = ProgressBar.new()
	_crash_bar.show_percentage = false
	_crash_bar.custom_minimum_size.y = 10
	_crash_bar.max_value = 1.0
	v.add_child(_crash_bar)
	_crash_shown = true
	if not CustomerManager.emergency_crashed.is_connected(_on_crashed):
		CustomerManager.emergency_crashed.connect(_on_crashed)
	if Settings.time_pressure_mult() <= 0.0:
		_crash_label.text = "COUNTDOWN OFF (SETTINGS). They wait for you."
		_crash_bar.value = 1.0
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 8)
	flow.add_theme_constant_override(&"v_separation", 8)
	v.add_child(flow)
	var st := UIKit.button("STABILISE (%d SUPPLIES)" % GameManager.STABILIZE_SUPPLIES, &"AccentButton", _on_stabilize, "TriageStabilize", 40)
	st.disabled = InventoryManager.supplies < GameManager.STABILIZE_SUPPLIES
	st.tooltip_text = "Stop the bleeding and send them on: about a third of the fee now. They come back for the chrome."
	flow.add_child(st)
	var cost := GameManager.specialist_cost(c)
	var sp := UIKit.button("CALL A SPECIALIST (%d CR)" % cost, &"GhostButton", _on_specialist, "TriageSpecialist", 40)
	sp.disabled = not EconomyManager.can_afford(cost)
	sp.tooltip_text = "Someone better takes over: %d%% odds, they take %d cr. The patient pays you the fee if they live." % [roundi(GameManager.SPECIALIST_ODDS * 100.0), cost]
	flow.add_child(sp)
	var rig := UIKit.button("EXPERIMENTAL RIG (%d PARTS)" % GameManager.RIG_PARTS, &"GhostButton", _on_rig, "TriageRig", 40)
	rig.disabled = c.triage.has(&"rig") or InventoryManager.parts < GameManager.RIG_PARTS
	rig.tooltip_text = "Untested frame: 40% less bleeding, fewer surprises on the table, costs some neural stability. Then you operate."
	flow.add_child(rig)
	var prem := GameManager.premium_option(c)
	var pb := UIKit.button(("PREMIUM CHROME: %s" % prem.display_name.to_upper()) if prem else "PREMIUM CHROME", &"GhostButton", _on_premium, "TriagePremium", 40)
	pb.disabled = prem == null or c.triage.has(&"premium")
	pb.tooltip_text = "They're desperate enough to take the expensive unit: harder job, +30% pay." if prem else "Nothing better available at your tier."
	flow.add_child(pb)
	v.add_child(UIKit.label("Or operate now (PERFORM SURGERY) · assign a ripperdoc · refuse. Waiting costs them.", &"DimLabel", true, null, 13))


## The countdown runs in CustomerManager (so it can't be reset by
## reopening this screen or paused by walking away); this only shows it.
func _process(_delta: float) -> void:
	if not _crash_shown or _crash_bar == null or Settings.time_pressure_mult() <= 0.0:
		return
	var c := GameManager.get_current_customer()
	if c == null or not c.is_emergency:
		return
	var left := CustomerManager.emergency_seconds_left()
	_crash_bar.value = clampf(left / CustomerManager.emergency_total(c), 0.0, 1.0)
	_crash_label.text = "%s IN %ds" % ["THEY DIE" if c.crashes > 0 else "THEY CRASH", maxi(0, ceili(left))]


func _exit_tree() -> void:
	if CustomerManager.emergency_crashed.is_connected(_on_crashed):
		CustomerManager.emergency_crashed.disconnect(_on_crashed)


func _on_crashed(who: String, died: bool) -> void:
	if not is_inside_tree():
		return
	if died:
		var ok: Array[Dictionary] = [{"label": "BACK TO THE CLINIC", "style": &"AccentButton", "name": "CrashClose", "callback": GameManager.go_to_clinic}]
		UIManager.show_dialog("PATIENT LOST", "You took too long. %s stopped breathing on your floor." % who, ok)
	else:
		UIManager.go_to(UIManager.SCREEN_CUSTOMER)


func _triage_done(r: Dictionary, title: String) -> void:
	if r.is_empty():
		AudioManager.play_sfx(&"denied", 0.0)
		return
	_crash_shown = false
	AudioManager.play_sfx(&"cash" if int(r.get("pay", 0)) > 0 or bool(r.get("success", true)) else &"failure", 0.0)
	var ok: Array[Dictionary] = [{"label": "BACK TO THE CLINIC", "style": &"AccentButton", "name": "TriageClose", "callback": GameManager.go_to_clinic}]
	UIManager.show_dialog(title, str(r["text"]), ok)


func _on_stabilize() -> void:
	_triage_done(GameManager.triage_stabilize(), "STABILISED")


func _on_specialist() -> void:
	var r := GameManager.triage_specialist()
	_triage_done(r, "SPECIALIST" if r.is_empty() or bool(r.get("success", false)) else "PATIENT LOST")


func _on_rig() -> void:
	if GameManager.triage_experimental():
		UIManager.show_toast("Rig strapped on. Bleeding slows.", &"info")
		UIManager.go_to(UIManager.SCREEN_CUSTOMER)


func _on_premium() -> void:
	if GameManager.triage_premium():
		UIManager.show_toast("They'll take the expensive unit.", &"info")
		UIManager.go_to(UIManager.SCREEN_CUSTOMER)


# --- Dependency ---------------------------------------------------------------------------

func _dependency_section(parent: Control, c: CustomerData) -> void:
	var box := UIKit.panel(&"DangerPanel")
	box.name = "DependencySection"
	parent.add_child(box)
	var v := UIKit.vbox(8)
	box.add_child(v)
	v.add_child(UIKit.label("CHROME DEPENDENCY · %s" % PeopleManager.DEPENDENCY_LABELS[clampi(c.dependency, 0, 4)].to_upper(), &"SubHeaderLabel", false, Palette.WARN))
	v.add_child(UIKit.label("They keep coming back for more and stronger. Every unit you put in feeds it. What do you do?", &"DimLabel", true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 8)
	flow.add_theme_constant_override(&"v_separation", 8)
	v.add_child(flow)
	var feed := UIKit.button("GIVE THEM WHAT THEY WANT", &"GhostButton" if c.care != &"feed" else &"AccentButton", _on_care.bind(&"feed"), "CareFeed", 38)
	feed.tooltip_text = "Install it. Their dependency deepens; at its worst it becomes a crisis."
	flow.add_child(feed)
	var profit := UIKit.button("PROFIT: +40%", &"GhostButton", _on_care.bind(&"profit"), "CareProfit", 38)
	profit.tooltip_text = "They'll pay anything. Overcharge and install. They notice, eventually."
	flow.add_child(profit)
	var safer := GameManager.dependency_safer_option(c)
	var sb := UIKit.button(("SAFER: %s" % safer.display_name.to_upper()) if safer else "SAFER ALTERNATIVE", &"GhostButton" if c.care != &"safer" else &"AccentButton", _on_care.bind(&"safer"), "CareSafer", 38)
	sb.disabled = safer == null
	sb.tooltip_text = "A lower-load unit. It doesn't feed the habit." if safer else "Nothing gentler in that category."
	flow.add_child(sb)
	var st := UIKit.button("STABILISE, NO CHROME", &"GhostButton", _on_dep_stabilize, "CareStabilize", 38)
	st.disabled = InventoryManager.supplies < GameManager.STABILIZE_SUPPLIES
	st.tooltip_text = "Flush the stims, talk them down: a small fee, dependency eases. They won't thank you today."
	flow.add_child(st)


func _on_care(care: StringName) -> void:
	if GameManager.set_care(care):
		UIManager.go_to(UIManager.SCREEN_CUSTOMER)
	else:
		AudioManager.play_sfx(&"denied", 0.0)


func _on_dep_stabilize() -> void:
	_triage_done(GameManager.dependency_stabilize(), "STABILISED")
