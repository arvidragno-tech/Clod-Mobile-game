extends BaseScreen
## Customer intake: who they are (faction, personality, money, history,
## existing chrome, neural load) and what they want.

const RISK_LABELS := ["", "LOW", "MEDIUM", "HIGH"]
const RISK_COLORS: Array[Color] = [Palette.TEXT, Palette.OK, Palette.WARN, Palette.DANGER]
const WEALTH := ["BROKE", "GETTING BY", "COMFORTABLE", "LOADED"]

var _dialogue: Label
var _type_tween: Tween


func on_enter(_params: Dictionary) -> void:
	var c := GameManager.get_current_customer()
	if c == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	var item := GameManager.get_requested_item()
	var surgery := GameManager.get_current_surgery()
	var m := UIKit.full_rect(UIKit.margin(12, 8, 12, 12))
	add_child(m)
	var col := UIKit.vbox(10)
	m.add_child(col)
	col.add_child(UIKit.header("STEP 1 / 4 · INTAKE", "CUSTOMER FILE", GameManager.go_to_clinic))
	var sc := UIKit.scroll()
	col.add_child(sc)
	var cards := UIKit.vbox(10)
	UIKit.expand(cards)
	sc.add_child(cards)
	cards.add_child(_profile_card(c))
	var statement := UIKit.panel(&"CardPanel")
	statement.name = "DialogueCard"
	var sv := UIKit.vbox(4)
	statement.add_child(sv)
	sv.add_child(UIKit.label("STATEMENT", &"SubHeaderLabel"))
	_dialogue = UIKit.label(c.dialogue, &"MonoLabel", true, null, 20)
	sv.add_child(_dialogue)
	statement.gui_input.connect(_on_dialogue_input)
	cards.add_child(statement)
	cards.add_child(_medical_card(c))
	if item and surgery:
		cards.add_child(_job_card(c, item, surgery))
	var buttons := UIKit.hbox(10)
	col.add_child(buttons)
	var decline := UIKit.button("DECLINE", &"GhostButton", _on_decline, "DeclineButton", 56)
	UIKit.expand(decline)
	buttons.add_child(decline)
	var accept := UIKit.button("ACCEPT JOB", &"AccentButton", GameManager.accept_customer, "AcceptButton", 56)
	UIKit.expand(accept)
	accept.size_flags_stretch_ratio = 1.8
	buttons.add_child(accept)
	# Typewriter at the player's text speed (Settings; 0 = instant).
	var cps := Settings.chars_per_second()
	if cps > 0.0:
		_dialogue.visible_ratio = 0.0
		_type_tween = create_tween()
		_type_tween.tween_property(_dialogue, "visible_ratio", 1.0, c.dialogue.length() / cps)


func _profile_card(c: CustomerData) -> Control:
	var card := UIKit.panel(&"DangerPanel" if c.is_emergency else &"AccentPanel")
	var row := UIKit.hbox(12)
	card.add_child(row)
	var p := PixelPortrait.new()
	p.name = "Portrait"
	row.add_child(p)
	p.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
	var info := UIKit.vbox(3)
	UIKit.expand(info)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UIKit.label(c.display_name, &"HeaderLabel", true))
	if c.alias != "":
		info.add_child(UIKit.label("\"%s\"" % c.alias, &"MonoLabel", false, Palette.BRAND))
	info.add_child(UIKit.label("%d yrs · %s" % [c.age, c.occupation], &"DimLabel", true, null, 14))
	var fac := UIKit.hbox(4)
	fac.add_child(UIKit.icon(str(FactionManager.get_faction(c.faction_id).get("emblem", "")), 16))
	var fl := UIKit.label("%s\n%s" % [FactionManager.get_name_of(c.faction_id).to_upper(), FactionManager.get_standing(c.faction_id)], &"SubHeaderLabel", true, FactionManager.get_color(c.faction_id))
	UIKit.expand(fl)
	fac.add_child(fl)
	info.add_child(fac)
	info.add_child(UIKit.label("%s · %s" % [String(c.personality).to_upper(), WEALTH[clampi(c.wealth, 0, 3)]], &"SubHeaderLabel", true))
	if c.visits > 0 or c.referred_by != "":
		info.add_child(UIKit.label(("RETURNING · VISIT %d" % (c.visits + 1)) if c.visits > 0 else "REFERRED BY " + c.referred_by.to_upper(), &"SubHeaderLabel", true, Palette.OK))
	return card


func _medical_card(c: CustomerData) -> Control:
	var card := UIKit.panel(&"CardPanel")
	var v := UIKit.vbox(5)
	card.add_child(v)
	v.add_child(UIKit.label("MEDICAL", &"SubHeaderLabel"))
	var meter := NeuralLoadMeter.new()
	meter.name = "NeuralMeter"
	v.add_child(meter)
	meter.set_load(NeuralLoad.compute_visible(c))
	_stat_row(v, "PATIENCE", c.patience / 100.0, Palette.ACCENT)
	_stat_row(v, "RISK APPETITE", c.risk_tolerance, Palette.BRAND)
	var chrome: Array[String] = []
	for id in c.existing_cyberware:
		var e := CyberwareManager.get_cyberware(id)
		if e:
			chrome.append(e.display_name)
	v.add_child(UIKit.label("Chrome: " + (", ".join(chrome) if not chrome.is_empty() else "none"), &"DimLabel", true, null, 14))
	for h in c.medical_history:
		v.add_child(UIKit.label("· " + h, &"DimLabel", true, null, 13))
	return card


func _stat_row(parent: Control, caption: String, ratio: float, color: Color) -> void:
	var row := UIKit.hbox(8)
	var l := UIKit.label(caption, &"SubHeaderLabel")
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var bar := UIKit.meter(ratio, color, 6)
	UIKit.expand(bar)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	parent.add_child(row)


func _job_card(c: CustomerData, item: CyberwareData, surgery: SurgeryData) -> Control:
	var card := UIKit.panel(&"CardPanel")
	var row := UIKit.hbox(10)
	card.add_child(row)
	row.add_child(CyberwareIcon.make(item))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override(&"h_separation", 10)
	g.add_theme_constant_override(&"v_separation", 3)
	UIKit.expand(g)
	row.add_child(g)
	var offer := int(round((surgery.base_pay + item.price * GameConfig.IMPLANT_PRICE_MARKUP) * c.pay_multiplier))
	var risk := c.get_risk_level()
	for pair: Array in [
		["WANTS", item.display_name, Palette.TEXT],
		["CLASS", "T%d %s · DIFF %d/5" % [item.tier, item.get_tier_name(), item.install_difficulty], item.get_rarity_color()],
		["PROCEDURE", surgery.display_name, Palette.TEXT],
		["OFFER", "%s base" % EconomyManager.format_money(offer), Palette.WARN],
		["RISK", RISK_LABELS[risk], RISK_COLORS[risk]],
	]:
		g.add_child(UIKit.label(pair[0], &"SubHeaderLabel"))
		var vl := UIKit.label(pair[1], &"", true, pair[2], 15)
		UIKit.expand(vl)
		g.add_child(vl)
	return card


func _on_dialogue_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_dialogue.visible_ratio = 1.0


func _on_decline() -> void:
	UIManager.confirm("TURN THEM AWAY?", "Word gets around. Declining costs %d rep." % absi(GameConfig.DECLINE_REPUTATION_PENALTY),
			"DECLINE", GameManager.decline_customer, true)
