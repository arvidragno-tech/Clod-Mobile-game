extends BaseScreen
## The unified journal. MAIN: what you follow, open objectives and the
## latest messages (one place for "what am I doing?"). MESSAGES: the comms
## inbox. PEOPLE: the cast and contacts. PATIENTS: everyone you treated
## (where they are now, what they owe, what they remember). FACTIONS.
## BUSINESS: your record and the books. DISCOVERIES: the story so far, the
## news and rumours, the places you know, the clinic wall.
## FOLLOW (on quests, people, patients and places) puts a thing on MAIN and
## the clinic's priorities, so the player never has to remember it.

const TABS := ["MAIN", "MESSAGES", "PEOPLE", "PATIENTS", "STANDING", "BUSINESS", "DISCOVERIES"]
enum Tab { MAIN, MESSAGES, PEOPLE, PATIENTS, FACTIONS, BUSINESS, DISCOVERIES }
const DISCOVERY_VIEWS := ["STORY", "NEWS", "PLACES", "WALL"]
## Old tab numbers (saves, links, tests) -> [tab, discoveries view].
const LEGACY := {0: [Tab.MAIN, ""], 1: [Tab.MESSAGES, ""], 2: [Tab.PATIENTS, ""], 3: [Tab.FACTIONS, ""],
	4: [Tab.DISCOVERIES, "NEWS"], 5: [Tab.BUSINESS, ""], 6: [Tab.DISCOVERIES, "STORY"], 7: [Tab.DISCOVERIES, "WALL"]}

var _list: GridContainer
var _tab: int = 0
var _view: String = "STORY"
var _focus: String = ""
var _scroll: ScrollContainer


var _selected_msg: int = -1


func on_enter(params: Dictionary) -> void:
	(func() -> void: Hints.first("journal")).call_deferred()
	_tab = Tab.MAIN
	if params.has("tab_name"):
		var n := str(params["tab_name"]).to_upper()
		if n == "COMMS":
			n = "MESSAGES"
		if n == "FACTIONS":
			n = "STANDING"
		if TABS.has(n):
			_tab = TABS.find(n)
	elif params.has("tab"):
		var l: Array = LEGACY.get(int(params["tab"]), [Tab.MAIN, ""])
		_tab = int(l[0])
		if str(l[1]) != "":
			_view = str(l[1])
	if params.has("view"):
		_view = str(params["view"]).to_upper()
	_focus = str(params.get("focus", ""))
	var col := UIKit.workstation(self, &"dossier")
	col.add_child(UIKit.header("CLINIC · INTEL", "JOURNAL", GameManager.go_to_clinic))
	var tabs := UIKit.tabs(TABS, _on_tab, "DossierTab")
	tabs.custom_minimum_size.x = 1480
	(tabs.get_child(_tab) as Button).button_pressed = true
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tabs)
	var sc := UIKit.scroll()
	_scroll = sc
	col.add_child(sc)
	_list = GridContainer.new()
	_list.add_theme_constant_override(&"h_separation", 14)
	_list.add_theme_constant_override(&"v_separation", 12)
	UIKit.expand(_list)
	sc.add_child(_list)
	_rebuild()


func _on_tab(i: int) -> void:
	_tab = i
	_focus = ""
	_rebuild()


func _rebuild() -> void:
	UIKit.clear(_list)
	_list.columns = 2
	match _tab:
		Tab.MAIN:
			_main()
		Tab.MESSAGES:
			_comms()
		Tab.PEOPLE:
			_people()
		Tab.PATIENTS:
			_patients()
		Tab.FACTIONS:
			_standing()
		Tab.BUSINESS:
			_records()
			_list.add_child(UIKit.button("OPEN THE LEDGER  [%s]" % Controls.key_name("business"), &"AccentButton", func() -> void: UIManager.go_to(UIManager.SCREEN_BUSINESS), "OpenLedger", 48))
		Tab.DISCOVERIES:
			_discoveries()
	if _focus != "":
		_focus_card.call_deferred()


## Scrolls to (and lights up) the card the caller asked for.
func _focus_card() -> void:
	var n := _list.find_child("Patient_%s" % _focus, true, false) as Control
	if n == null:
		n = _list.find_child("Person_%s" % _focus, true, false) as Control
	if n and _scroll:
		_scroll.ensure_control_visible(n)
		if n is PanelContainer:
			(n as PanelContainer).theme_type_variation = &"AccentPanel"


## A FOLLOW / FOLLOWING toggle for anything with a when or a where.
func _follow_button(kind: String, ref: String, title: String) -> Button:
	var on := Follows.is_following(Follows.key(kind, ref))
	var b := UIKit.button("★ FOLLOWING" if on else "☆ FOLLOW", &"AccentButton" if on else &"GhostButton", Callable(), "Follow_%s_%s" % [kind, ref], 34)
	b.tooltip_text = "Keep this on your MAIN page and the clinic's priorities (where, when, what's left)."
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void:
		var now := Follows.toggle(kind, ref, title)
		UIManager.show_toast(("★ Following %s" if now else "Stopped following %s") % title, &"success" if now else &"info")
		_rebuild.call_deferred())
	return b


# --- MAIN ----------------------------------------------------------------------------

func _main() -> void:
	_list.columns = 2
	# Following: live where/when for everything you asked the game to remember.
	var fol := UIKit.panel(&"AccentPanel")
	fol.name = "Following"
	UIKit.expand(fol)
	_list.add_child(fol)
	var fv := UIKit.vbox(6)
	fol.add_child(fv)
	fv.add_child(UIKit.section_head("FOLLOWING", "where and when, kept up to date"))
	var live := Follows.live()
	if live.is_empty():
		fv.add_child(UIKit.label("Nothing followed. Use ☆ FOLLOW on a quest, a person, a patient or a place, and it shows up here with where to find it.", &"DimLabel", true))
	for f: Dictionary in live:
		var row := UIKit.hbox(8)
		fv.add_child(row)
		var link: Dictionary = f["link"]
		var txt := "%s %s  ·  %s%s" % ["◆" if bool(f["soon"]) else "◇", str(f["title"]), str(f["detail"]) if str(f["detail"]) != "" else "", (" · " + str(f["when"])) if str(f["when"]) != "" else ""]
		var b := UIKit.button(txt, &"GhostButton", func() -> void: Nav.open(link), "Followed_%s" % str(f["id"]).replace(":", "_"), 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = txt + ("\nClick to go there." if Nav.can_open(link) else "")
		b.disabled = not Nav.can_open(link)
		UIKit.expand(b)
		row.add_child(b)
		var fid := str(f["id"])
		row.add_child(UIKit.button("✕", &"GhostButton", func() -> void:
			Follows.unfollow(fid)
			_rebuild.call_deferred(), "Unfollow_%s" % fid.replace(":", "_"), 36))
	# Messages that still need an answer.
	var msg := UIKit.panel(&"CardPanel")
	UIKit.expand(msg)
	_list.add_child(msg)
	var mv := UIKit.vbox(6)
	msg.add_child(mv)
	mv.add_child(UIKit.section_head("MESSAGES", "%d unread" % CommsManager.unread_count()))
	var shown := 0
	var inbox := CommsManager.inbox.duplicate()
	inbox.reverse()
	for m: Dictionary in inbox:
		var needs := not bool(m["read"]) or ((m.get("actions", []) as Array).size() > 0 and int(m["resolved"]) < 0)
		if not needs:
			continue
		var uid := int(m["uid"])
		var b := UIKit.button("%s %s · %s" % ["●" if not bool(m["read"]) else "○", CommsManager.sender_name(m), str(m["subject"])], &"GhostButton", func() -> void:
			_selected_msg = uid
			_tab = Tab.MESSAGES
			_rebuild(), "MainMsg_%d" % uid, 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mv.add_child(b)
		shown += 1
		if shown >= 6:
			break
	if shown == 0:
		mv.add_child(UIKit.label("Nothing waiting for an answer.", &"DimLabel"))
	# Objectives: active quests first, the rest after.
	_quests()


# --- STANDING (3.6) ----------------------------------------------------------------------

var _standing_all: bool = false
var _standing_open: String = ""


## YOUR STANDING: reputation (groups), attention (heat), relationships
## (people) and trust (suppliers), each with what it means now, which way
## it's going, what it affects, the next threshold and why it changed.
func _standing() -> void:
	_list.columns = 2
	# Left: the groups.
	var left := UIKit.vbox(10)
	UIKit.expand(left, true, false)
	_list.add_child(left)
	var head := UIKit.hbox(10)
	left.add_child(head)
	var t := UIKit.label("YOUR STANDING", &"SectionLabel")
	UIKit.expand(t)
	head.add_child(t)
	head.add_child(UIKit.button("SHOW FEWER" if _standing_all else "ALL FACTIONS", &"GhostButton", func() -> void:
		_standing_all = not _standing_all
		_rebuild(), "StandingAll", 36))
	left.add_child(UIKit.label("Reputation is how a group sees you; heat is how closely the authorities watch. Click a row for its history.", &"DimLabel", true, null, 14))
	for row: Dictionary in Standing.overview(_standing_all):
		left.add_child(_standing_card(row))
	# Identity: who the street thinks you are.
	var id_card := UIKit.panel(&"CardPanel")
	left.add_child(id_card)
	var iv := UIKit.vbox(4)
	id_card.add_child(iv)
	var ident := ReputationManager.identity()
	iv.add_child(UIKit.section_head("WHO THE STREET THINKS YOU ARE", "", "identity"))
	iv.add_child(UIKit.label("%s · %s" % [str(ident.get("title", "")), str(ident.get("text", ""))], &"", true, Palette.ACCENT, 15))
	for d: Dictionary in Standing.identity_rows():
		iv.add_child(UIKit.label("%s %s  %+d  %s" % [Standing.mark(d["level"]), str(d["name"]), int(d["value"]), str(d["trend_text"])], &"MonoLabel", true, Standing.color(d["level"]), 15))
	# Right: people and suppliers, then the history.
	var right := UIKit.vbox(10)
	UIKit.expand(right, true, false)
	_list.add_child(right)
	var pc := UIKit.panel(&"CardPanel")
	right.add_child(pc)
	var pv := UIKit.vbox(4)
	pc.add_child(pv)
	pv.add_child(UIKit.section_head("PEOPLE YOU DEAL WITH", "personal relationships, separate from their group", "loyalty"))
	var ppl := Standing.people()
	if ppl.is_empty():
		pv.add_child(UIKit.label("Nobody yet.", &"DimLabel"))
	for p: Dictionary in ppl:
		var line := "%s · %s %+d" % [str(p["name"]), str(p["personal"]).capitalize(), int(p["rel"])]
		if str(p["faction"]) != "":
			line += "   (their group, %s: %s)" % [str(p["faction"]), str(p["faction_standing"])]
		var l := UIKit.label(line, &"", true, Palette.TEXT, 15)
		l.name = "Person_%s" % p["id"]
		pv.add_child(l)
	var sups := Standing.suppliers()
	if not sups.is_empty():
		pv.add_child(UIKit.label("SUPPLIERS (trust)", &"SubHeaderLabel"))
		for s: Dictionary in sups:
			var txt := "%s · %s (trust %d)" % [str(s["name"]), str(s["standing"]), int(s["trust"])]
			if int(s["debt"]) > 0:
				txt += " · you owe %s" % EconomyManager.format_money(int(s["debt"]))
			if str(s["next"]) != "":
				txt += " · next: %s" % str(s["next"])
			pv.add_child(UIKit.label(txt, &"DimLabel", true, null, 14))
	var hc := UIKit.panel(&"CardPanel")
	hc.name = "StandingHistory"
	right.add_child(hc)
	var hv := UIKit.vbox(2)
	hc.add_child(hv)
	hv.add_child(UIKit.section_head("HISTORY", "every change and what caused it", "changes"))
	var hist := ChangeLog.standing_history("", 30)
	if hist.is_empty():
		hv.add_child(UIKit.label("No changes recorded yet.", &"DimLabel"))
	for e: Dictionary in hist:
		var d := float(e["delta"])
		var group := str(e["group"])
		var good := (d > 0.0) != (group == "heat")
		hv.add_child(UIKit.label(Standing.history_line(e), &"DimLabel", true, Palette.OK if good else Palette.WARN, 14))


func _standing_card(row: Dictionary) -> Control:
	var card := UIKit.panel(&"DangerPanel" if row["level"] == Standing.BAD else &"CardPanel")
	card.name = "Standing_%s" % str(row["group"]).replace(":", "_")
	var v := UIKit.vbox(3)
	card.add_child(v)
	var top := UIKit.hbox(10)
	v.add_child(top)
	var name_l := UIKit.label("%s %s" % [Standing.mark(row["level"]), str(row["name"]).to_upper()], &"SubHeaderLabel", true, Standing.color(row["level"]))
	UIKit.expand(name_l)
	top.add_child(name_l)
	top.add_child(UIKit.label("%s  %d" % [str(row["category"]), int(row["value"])], &"MonoLabel", false, Standing.color(row["level"]), 18))
	v.add_child(UIKit.label(str(row["trend_text"]) + ("   · attention, not reputation: lower is better" if str(row["kind"]) == "attention" else ""), &"DimLabel", true, null, 14))
	v.add_child(UIKit.label("Affects: " + "; ".join(row["affects"]), &"", true, Palette.TEXT, 14))
	v.add_child(UIKit.label("Next: " + str(row["next"]), &"DimLabel", true, Palette.ACCENT, 14))
	var group := str(row["group"])
	var open := _standing_open == group
	var b := UIKit.button(("HIDE HISTORY" if open else "HISTORY"), &"GhostButton", func() -> void:
		_standing_open = "" if _standing_open == group else group
		_rebuild(), "StandingHist_%s" % group.replace(":", "_"), 32)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	if open:
		var hist := ChangeLog.standing_history(group, 10)
		if hist.is_empty():
			v.add_child(UIKit.label("No changes recorded yet.", &"DimLabel"))
		for e: Dictionary in hist:
			v.add_child(UIKit.label(Standing.history_line(e), &"DimLabel", true, null, 14))
	return card


func _faction_card(id: StringName) -> Control:
	var f := FactionManager.get_faction(id)
	var color := FactionManager.get_color(id)
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card)
	var v := UIKit.vbox(4)
	card.add_child(v)
	var top := UIKit.hbox(8)
	v.add_child(top)
	top.add_child(UIKit.icon(str(f.get("emblem", "")), 16))
	var names := UIKit.vbox(0)
	UIKit.expand(names)
	names.add_child(UIKit.label(str(f.get("name", id)).to_upper(), &"HeaderLabel", true, color))
	names.add_child(UIKit.label("%s · %+d" % [FactionManager.get_standing(id), FactionManager.get_rep(id)], &"SubHeaderLabel"))
	top.add_child(names)
	var bar := UIKit.meter((FactionManager.get_rep(id) + 100) / 200.0, color, 6)
	v.add_child(bar)
	v.add_child(UIKit.label(str(f.get("description", "")), &"DimLabel", true, null, 13))
	return card


func _contact_card(c: CustomerData, role: String) -> Control:
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card)
	var row := UIKit.hbox(10)
	card.add_child(row)
	var p := PixelPortrait.new()
	p.framing = PixelPortrait.Framing.HEAD
	row.add_child(p)
	if CharacterManager.has_character(c.id):
		p.set_character(c.id)
	else:
		p.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
	var v := UIKit.vbox(2)
	UIKit.expand(v)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	v.add_child(UIKit.label(c.get_display_title(), &"HeaderLabel", true))
	v.add_child(UIKit.label("%s · %s" % [role, FactionManager.get_name_of(c.faction_id)], &"SubHeaderLabel", true, FactionManager.get_color(c.faction_id)))
	v.add_child(UIKit.label(c.occupation, &"DimLabel", true, null, 13))
	if CharacterManager.has_met(c.id):
		var w := WorldSimulationManager.where_is_cast(c.id)
		if w != &"" and LocationManager.is_known(w):
			v.add_child(UIKit.label("Right now: %s" % LocationManager.location_name(w), &"DimLabel", true, Palette.OK, 13))
	return card


func _records() -> void:
	_list.columns = 1
	var top := UIKit.hbox(12)
	_list.add_child(top)
	var cards := [
		["SURGEON", "LV %d" % ProgressionManager.level, "%d / %d XP to next" % [ProgressionManager.get_xp_into_level(), ProgressionManager.get_xp_for_next_level()]],
		["REPUTATION", "%d" % ReputationManager.reputation, ReputationManager.get_tier_name()],
		["STORY", "ACT %d" % StoryManager.act, StoryManager.act_title().get_slice("·", 1).strip_edges()],
		["BUSINESS", "DAY %d" % BusinessManager.day, "%s cash · debt %d" % [EconomyManager.format_money(EconomyManager.money), BusinessManager.debt]],
		["PROPERTY", "%d / %d" % [ClinicManager.owned.size(), ClinicManager.tiers.size()], "clinics · %d upgrades" % QuestManager._value({"type": "upgrades"})],
		["TEAM", "%d" % StaffManager.count(), "ripperdocs · %d/day payroll" % StaffManager.daily_salaries()],
		["CITY", "%d / %d" % [WorldManager.visited.size(), WorldManager.order.size()], "districts · stronghold %s" % WorldManager.district_name(WorldManager.stronghold())],
	]
	for c: Array in cards:
		var p := UIKit.panel(&"CardPanel")
		UIKit.expand(p)
		var v := UIKit.vbox(2)
		p.add_child(v)
		v.add_child(UIKit.label(str(c[0]), &"SubHeaderLabel"))
		v.add_child(UIKit.label(str(c[1]), &"BigMonoLabel", false, Palette.ACCENT))
		v.add_child(UIKit.label(str(c[2]), &"DimLabel", true, null, 13))
		top.add_child(p)
	_list.add_child(UIKit.meter(ProgressionManager.get_level_progress(), Palette.ACCENT, 6))
	var ends := StoryManager.ranked_endings()
	_list.add_child(UIKit.label("Endings within reach: %s" % (", ".join(ends.map(func(e: StringName) -> String: return str(StoryManager.ending_text(e).get("title", e)))) if not ends.is_empty() else "none yet"), &"MonoLabel", true, Palette.BRAND, 17))
	var lines := [
		"Level %d · %d XP" % [ProgressionManager.level, ProgressionManager.total_xp],
		"Reputation %d · %s" % [ReputationManager.reputation, ReputationManager.get_tier_name()],
		"Operations: %d · customers served %d" % [EventManager.operations, ProgressionManager.customers_served],
		"Clinic: %s" % ClinicManager.get_tier_name(),
	]
	for l: String in lines:
		_list.add_child(UIKit.label(l, &"MonoLabel", true, null, 18))
	for sid: String in ProgressionManager.surgery_records:
		var rec: Dictionary = ProgressionManager.surgery_records[sid]
		var s := SurgeryManager.get_surgery(StringName(sid))
		_list.add_child(UIKit.label("%s: %d done, %d failed, best %s" % [s.display_name if s else sid, rec.get("completed", 0), rec.get("failed", 0), str(rec.get("best_grade", "-"))], &"DimLabel", true))
	_list.add_child(UIKit.label("RECENT PATIENTS", &"SubHeaderLabel"))
	var hist := CustomerManager.history.duplicate()
	hist.reverse()
	for h: Dictionary in hist.slice(0, 12):
		var ok := str(h.get("outcome", "")) == "success"
		var tag := " · REGULAR" if bool(h.get("regular", false)) else ""
		_list.add_child(UIKit.label("%s  %s  %s%s" % [str(h.get("grade", "?")), str(h.get("name", "?")), "OK" if ok else str(h.get("outcome", "")).to_upper(), tag], &"MonoLabel", true, Palette.TEXT if ok else Palette.DANGER, 17))


# --- Quests ------------------------------------------------------------------------

func _quests() -> void:
	var any := false
	for id in QuestManager.by_state("active"):
		_list.add_child(_quest_card(id, "active"))
		any = true
	var done: Array[String] = []
	for state: String in ["completed", "failed"]:
		for id in QuestManager.by_state(state):
			done.append("%s %s" % ["✓" if state == "completed" else "✕", str(QuestManager.get_quest(id)["title"])])
	if not done.is_empty():
		var card := UIKit.panel(&"CardPanel")
		UIKit.expand(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		v.add_child(UIKit.section_head("FINISHED", "%d" % done.size()))
		for d in done:
			v.add_child(UIKit.label(d, &"DimLabel", true, null, 14))
		_list.add_child(card)
		any = true
	if not any:
		_list.add_child(UIKit.label("No work on the board yet.", &"DimLabel"))


func _quest_card(id: StringName, state: String) -> Control:
	var q := QuestManager.get_quest(id)
	var card := UIKit.panel(&"AccentPanel" if state == "active" else &"CardPanel")
	UIKit.expand(card)
	card.modulate.a = 1.0 if state == "active" else 0.7
	var v := UIKit.vbox(4)
	card.add_child(v)
	var head := UIKit.hbox(8)
	v.add_child(head)
	var t := UIKit.label(str(q["title"]).to_upper(), &"SubHeaderLabel", true, Palette.ACCENT if state == "active" else Palette.TEXT)
	UIKit.expand(t)
	head.add_child(t)
	var col: Color = {"active": Palette.WARN, "completed": Palette.OK, "failed": Palette.DANGER}[state]
	head.add_child(UIKit.label("%s · %s" % [str(QuestManager.TYPE_LABELS.get(str(q["type"]), "")), state.to_upper()], &"SubHeaderLabel", false, col))
	v.add_child(UIKit.label(str(q["description"]), &"DimLabel", true, null, 14))
	var prog := QuestManager.progress_text(id)
	v.add_child(UIKit.label("OBJECTIVE  %s%s" % [str(q["objective"].get("text", "")), ("  (%s)" % prog) if prog != "" else ""], &"MonoLabel", true, Palette.TEXT, 16))
	if q.has("deadline_days") and state == "active":
		var left := int(q["deadline_days"]) - (BusinessManager.day - int(QuestManager.states[id]["started_day"]))
		v.add_child(UIKit.label("%d day(s) left" % maxi(0, left), &"MonoLabel", false, Palette.WARN, 15))
	v.add_child(UIKit.label("REWARD  %s" % QuestManager.reward_text(id), &"DimLabel", true, Palette.OK, 13))
	v.add_child(UIKit.label("IF IT HAPPENS  %s" % str(q.get("consequence", "")), &"DimLabel", true, Palette.TEXT_DIM, 13))
	var giver := StringName(str(q.get("giver", "")))
	if CharacterManager.has_character(giver):
		v.add_child(UIKit.label("From %s" % CharacterManager.get_character(giver).display_name, &"DimLabel", false, null, 13))
	if state == "active":
		v.add_child(_follow_button("quest", String(id), str(q["title"])))
	return card


# --- Comms ---------------------------------------------------------------------------

func _comms() -> void:
	_list.columns = 2
	var left := UIKit.vbox(6)
	left.custom_minimum_size.x = 620
	_list.add_child(left)
	var right := UIKit.panel(&"AccentPanel")
	UIKit.expand(right, true, true)
	_list.add_child(right)
	if CommsManager.inbox.is_empty():
		left.add_child(UIKit.label("The terminal is quiet.", &"DimLabel"))
		return
	var msgs := CommsManager.inbox.duplicate()
	msgs.reverse()
	if _selected_msg < 0:
		_selected_msg = int(msgs[0]["uid"])
	for m: Dictionary in msgs:
		var uid := int(m["uid"])
		var label := "%s%-10s D%-3d %s · %s" % ["● " if not bool(m["read"]) else "  ", str(CommsManager.KIND_LABELS.get(str(m["kind"]), "")), int(m["day"]), CommsManager.sender_name(m), str(m["subject"])]
		var b := UIKit.button(label, &"AccentButton" if uid == _selected_msg else &"GhostButton", func() -> void:
			_selected_msg = uid
			_rebuild(), "Msg_%d" % uid, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left.add_child(b)
	var m := CommsManager.get_message(_selected_msg)
	if m.is_empty():
		return
	CommsManager.mark_read(_selected_msg)
	var v := UIKit.vbox(8)
	right.add_child(v)
	var kind := str(m["kind"])
	var head := UIKit.hbox(12)
	v.add_child(head)
	var from := StringName(str(m["from"]))
	if CharacterManager.has_character(from):
		var p := PixelPortrait.new()
		p.framing = PixelPortrait.Framing.HEAD
		p.set_character(from)
		head.add_child(p)
	var hv := UIKit.vbox(2)
	head.add_child(hv)
	hv.add_child(UIKit.label(str(CommsManager.KIND_LABELS.get(kind, "")), &"SubHeaderLabel", false, Palette.BRAND if kind == "encrypted" else Palette.ACCENT))
	hv.add_child(UIKit.label(str(m["subject"]), &"HeaderLabel", true))
	hv.add_child(UIKit.label("From %s · day %d" % [CommsManager.sender_name(m), int(m["day"])], &"DimLabel"))
	var body := UIKit.label(str(m["body"]), &"MonoLabel", true)
	if kind == "encrypted":
		body.add_theme_color_override(&"font_color", Palette.ACCENT)
	v.add_child(body)
	var acts: Array = m.get("actions", [])
	if not acts.is_empty():
		if int(m["resolved"]) >= 0:
			v.add_child(UIKit.label("Answered: %s" % str(acts[int(m["resolved"])]["label"]), &"SubHeaderLabel", false, Palette.OK))
		else:
			var row := UIKit.hbox(8)
			v.add_child(row)
			for i in acts.size():
				var uid := int(m["uid"])
				row.add_child(UIKit.button(str(acts[i]["label"]), &"AccentButton" if i == 0 else &"GhostButton", func() -> void:
					var before := Consequence.snapshot()
					CommsManager.act(uid, i)
					Consequence.show("You answered: %s" % str(acts[i]["label"]), before)
					_rebuild(), "MsgAction_%d" % i, 44))


# --- People ---------------------------------------------------------------------------

func _people() -> void:
	_list.columns = 2
	var any := false
	for id: StringName in CharacterManager.cast:
		if not CharacterManager.has_met(id) and not StoryManager.met_characters.has(id):
			continue
		_list.add_child(_person_card(id))
		any = true
	for id in StoryManager.met_characters:
		if CharacterManager.has_character(id):
			continue
		var c := CustomerManager.get_customer(id)
		if c:
			_list.add_child(_contact_card(c, str(CustomerManager.characters[id].get("role", "")).to_upper()))
			any = true
	if not any:
		_list.add_child(UIKit.label("Nobody important knows your name yet. Your patients are under PATIENTS.", &"DimLabel", true))


const PATIENT_FILTERS := ["ALL", "OWES YOU", "DUE BACK", "LOYAL", "HOSTILE", "FOLLOWED"]
var _pfilter: int = 0


## Everyone you treated, with quick filters (smart filters for patients).
func _patients() -> void:
	_list.columns = 2
	var chips := UIKit.hbox(6)
	chips.name = "PatientFilters"
	_list.add_child(chips)
	_list.add_child(Control.new())
	for i in PATIENT_FILTERS.size():
		var b := UIKit.button(PATIENT_FILTERS[i], &"TabButton", func() -> void:
			_pfilter = i
			_rebuild(), "PFilter_%d" % i, 36)
		b.toggle_mode = true
		b.button_pressed = i == _pfilter
		chips.add_child(b)
	var pats: Array = PeopleManager.people.values().filter(func(p: Dictionary) -> bool:
		var id := StringName(str(p["id"]))
		var base := int(p.get("visits", 0)) >= 1 or absi(int(p.get("rel", 0))) >= 15 or PeopleManager.owed_by(id) > 0
		if not base:
			return false
		match _pfilter:
			1:
				return PeopleManager.owed_by(id) > 0
			2:
				return int(p.get("next_day", -1)) >= 0 and int(p["next_day"]) <= BusinessManager.day + 1
			3:
				return PeopleManager.rel_state(id) in ["loyal", "grateful", "friendly"]
			4:
				return PeopleManager.rel_state(id) in ["hostile", "wary"]
			5:
				return Follows.is_following(Follows.key("person", String(id)))
		return true)
	pats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absi(int(a["rel"])) + int(a["visits"]) * 8 > absi(int(b["rel"])) + int(b["visits"]) * 8)
	for p: Dictionary in pats.slice(0, 30):
		_list.add_child(_patient_card(p))
	if pats.is_empty():
		_list.add_child(UIKit.label("Nobody here yet." if _pfilter == 0 else "Nobody matches %s." % PATIENT_FILTERS[_pfilter], &"DimLabel", true))


func _patient_card(p: Dictionary) -> Control:
	var id := StringName(str(p["id"]))
	var card := UIKit.panel(&"CardPanel")
	card.name = "Patient_%s" % str(p["id"])
	UIKit.expand(card)
	var row := UIKit.hbox(12)
	card.add_child(row)
	var por := PixelPortrait.new()
	por.framing = PixelPortrait.Framing.FACE
	por.set_appearance(p.get("appearance", {}), FactionManager.get_color(StringName(str(p.get("faction", "")))))
	row.add_child(por)
	var v := UIKit.vbox(3)
	UIKit.expand(v)
	row.add_child(v)
	var status := str(p.get("status", "alive"))
	var dead := status == "dead"
	v.add_child(UIKit.label(("%s%s" % [str(p["name"]), "  †" if dead else ("  [MISSING]" if status == "missing" else "")]).to_upper(), &"SubHeaderLabel", true,
		Palette.TEXT_DIM if dead else (Palette.WARN if status == "missing" else Palette.ACCENT)))
	v.add_child(UIKit.label("PATIENT · %s · %s · %d visit(s)" % [str(p.get("occupation", "")), FactionManager.get_name_of(StringName(str(p.get("faction", "")))), int(p.get("visits", 0))], &"DimLabel", true, null, 13))
	var st := PeopleManager.rel_state(id)
	v.add_child(UIKit.label("%s  %+d · paid you %d cr in all" % [st.to_upper(), int(p.get("rel", 0)), int(p.get("paid_total", 0))], &"SubHeaderLabel", false,
		{"loyal": Palette.OK, "grateful": Palette.OK, "friendly": Palette.OK, "wary": Palette.WARN, "hostile": Palette.DANGER}.get(st, Palette.TEXT)))
	var traits: Array = (p.get("traits", []) as Array).map(func(t: Variant) -> String: return PeopleManager.trait_label(StringName(str(t))))
	if not traits.is_empty():
		v.add_child(UIKit.label(", ".join(traits) + " · " + PeopleManager.finance_label(StringName(str(p.get("finance", "")))), &"DimLabel", true, null, 13))
	var mem := MemoryManager.of(id)
	if not mem.is_empty():
		v.add_child(UIKit.label("Remembers: " + MemoryManager.label(StringName(str(mem[mem.size() - 1]["tag"]))), &"DimLabel", true, Palette.TEXT, 13))
	var hist: Array = p.get("history", [])
	for h in hist.slice(maxi(0, hist.size() - 2)):
		v.add_child(UIKit.label(str(h), &"DimLabel", true, null, 12))
	if PeopleManager.owed_by(id) > 0:
		v.add_child(UIKit.label("Owes you %d cr" % PeopleManager.owed_by(id), &"DimLabel", true, Palette.WARN, 13))
	if status == "alive":
		v.add_child(UIKit.label(_whereabouts(p), &"DimLabel", true, Palette.TEXT_DIM, 12))
		v.add_child(_follow_button("person", str(p["id"]), str(p["name"])))
	elif status == "missing":
		v.add_child(UIKit.label("Missing. Their family asked you for help: start at their home.", &"DimLabel", true, Palette.WARN, 12))
	return card


## Home / work / now, for the places you know.
func _whereabouts(p: Dictionary) -> String:
	WorldSimulationManager.ensure_routine(p)
	var name_of := func(key: String) -> String:
		var l := StringName(str(p.get(key, "")))
		return LocationManager.location_name(l) if LocationManager.is_known(l) else "somewhere you don't know"
	var now := WorldSimulationManager.person_place(p)
	return "Lives: %s · Works: %s · Now: %s" % [name_of.call("home"), name_of.call("work"),
		(LocationManager.location_name(now) if LocationManager.is_known(now) else "?") + " (%s)" % WorldSimulationManager.activity_of(p)]


func _person_card(id: StringName) -> Control:
	var c := CharacterManager.get_character(id)
	var card := UIKit.panel(&"CardPanel")
	card.name = "Person_%s" % String(id)
	UIKit.expand(card)
	var row := UIKit.hbox(12)
	card.add_child(row)
	var p := PixelPortrait.new()
	p.framing = PixelPortrait.Framing.FACE
	p.set_character(id)
	row.add_child(p)
	var v := UIKit.vbox(3)
	UIKit.expand(v)
	row.add_child(v)
	v.add_child(UIKit.label(c.title().to_upper(), &"SubHeaderLabel", true, Palette.ACCENT))
	v.add_child(UIKit.label("%s · %s" % [c.occupation, c.faction_name()], &"DimLabel", true, null, 13))
	var st := CharacterManager.relationship_state(id)
	v.add_child(UIKit.label("%s  %+d" % [st.to_upper(), CharacterManager.relationship(id)], &"SubHeaderLabel", false, CharacterManager.state_color(st)))
	v.add_child(UIKit.label(c.background, &"DimLabel", true, null, 13))
	if CharacterManager.relationship(id) >= 20:
		v.add_child(UIKit.label("Wants: %s" % c.motivation, &"DimLabel", true, Palette.TEXT, 13))
	var ev := CharacterManager.appearance_events(id)
	if not ev.is_empty():
		v.add_child(UIKit.label("Changed: %s" % ", ".join(ev.map(func(x: Variant) -> String: return str(x).replace("_", " "))), &"DimLabel", true, Palette.WARN, 12))
	var at := WorldSimulationManager.where_is_cast(id)
	v.add_child(UIKit.label("Now: %s" % (LocationManager.location_name(at) if at != &"" else "not out right now (people keep hours)"), &"DimLabel", true, Palette.TEXT_DIM, 12))
	v.add_child(_follow_button("cast", String(id), c.display_name))
	return card


# --- Discoveries ---------------------------------------------------------------------

func _discoveries() -> void:
	var chips := UIKit.hbox(6)
	chips.name = "DiscoveryViews"
	_list.add_child(chips)
	_list.add_child(Control.new())
	for v in DISCOVERY_VIEWS:
		var b := UIKit.button(v, &"TabButton", func() -> void:
			_view = v
			_rebuild(), "View_%s" % v, 36)
		b.toggle_mode = true
		b.button_pressed = v == _view
		chips.add_child(b)
	match _view:
		"NEWS":
			_news()
			if StoryManager.unlocked_rumors.is_empty():
				_list.add_child(UIKit.label("Nothing on the street yet.", &"DimLabel"))
			for id in StoryManager.unlocked_rumors:
				var card := UIKit.panel(&"CardPanel")
				UIKit.expand(card)
				card.add_child(UIKit.label(StoryManager.get_rumor_text(id), &"MonoLabel", true, Palette.ACCENT, 18))
				_list.add_child(card)
		"PLACES":
			_places()
		"WALL":
			var holder := _list
			_wall()
			holder.columns = maxi(2, holder.columns)
		_:
			_story()


## The places you know: what they are, what's going on, FOLLOW.
func _places() -> void:
	for id in LocationManager.known_locations():
		var card := UIKit.panel(&"CardPanel")
		card.name = "Place_%s" % String(id)
		UIKit.expand(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		v.add_child(UIKit.label(LocationManager.location_name(id).to_upper(), &"SubHeaderLabel", true, Palette.ACCENT))
		v.add_child(UIKit.label("%s · %s · %s" % [LocationManager.type_label(id), LocationManager.hours_text(id), WorldSimulationManager.state_label(id)], &"DimLabel", true, null, 13))
		var ev := WorldSimulationManager.event_at(id)
		if not ev.is_empty():
			v.add_child(UIKit.label("HAPPENING NOW: %s" % str(ev.get("title", "")), &"DimLabel", true, Palette.WARN, 13))
		var row := UIKit.hbox(8)
		v.add_child(row)
		var loc := id
		row.add_child(UIKit.button("SHOW ON MAP", &"GhostButton", func() -> void: Nav.open({"location": loc}), "PlaceMap_%s" % String(id), 34))
		if String(id) != "clinic":
			row.add_child(_follow_button("place", String(id), LocationManager.location_name(id)))
		_list.add_child(card)


# --- Story ---------------------------------------------------------------------------

func _story() -> void:
	_list.columns = 2
	# What the street calls you, from what you've actually done.
	var idn := ReputationManager.identity()
	var ic := UIKit.panel(&"DangerPanel")
	ic.name = "IdentityCard"
	UIKit.expand(ic)
	_list.add_child(ic)
	var iv := UIKit.vbox(4)
	ic.add_child(iv)
	iv.add_child(UIKit.label("THE STREET CALLS YOU", &"SubHeaderLabel"))
	iv.add_child(UIKit.label(str(idn["title"]), &"HeaderLabel", true, Palette.WARN))
	iv.add_child(UIKit.label(str(idn["text"]), &"DimLabel", true))
	var dl: Array[String] = []
	for d in ReputationManager.DIMENSIONS:
		dl.append("%s %+d" % [str(ReputationManager.DIMENSION_LABELS[d]), ReputationManager.dim(d)])
	iv.add_child(UIKit.label("  ·  ".join(dl), &"MonoLabel", true, Palette.TEXT_DIM, 14))
	var spacer := Control.new()
	_list.add_child(spacer)
	var acts := UIKit.panel(&"AccentPanel")
	UIKit.expand(acts)
	_list.add_child(acts)
	var av := UIKit.vbox(6)
	acts.add_child(av)
	for n in range(1, 6):
		var d := StoryManager.act_data(n)
		var cur := n == StoryManager.act
		var col: Color = Palette.ACCENT if cur else (Palette.OK if n < StoryManager.act else Palette.TEXT_DIM)
		av.add_child(UIKit.label(("▶ " if cur else ("✓ " if n < StoryManager.act else "· ")) + str(d.get("title", "")), &"SubHeaderLabel", false, col))
		if n <= StoryManager.act:
			av.add_child(UIKit.label(str(d.get("theme", "")), &"DimLabel", true, null, 13))
	var paths := UIKit.panel(&"CardPanel")
	UIKit.expand(paths)
	_list.add_child(paths)
	var pv := UIKit.vbox(6)
	paths.add_child(pv)
	pv.add_child(UIKit.section_head("WHO YOU ARE BECOMING"))
	var best := 1
	for p in StoryManager.PATHS:
		best = maxi(best, StoryManager.path_score(p))
	for p in StoryManager.PATHS:
		var e := StoryManager.ending_text(p)
		pv.add_child(UIKit.label("%s  %d" % [str(e.get("title", p)), StoryManager.path_score(p)], &"MonoLabel", false, Palette.TEXT, 15))
		pv.add_child(UIKit.meter(float(StoryManager.path_score(p)) / float(best), Palette.ACCENT, 4))
	if StoryManager.ending != &"":
		var e := StoryManager.ending_text()
		pv.add_child(UIKit.label(str(e.get("title", "")), &"HeaderLabel", true, Palette.BRAND))
		pv.add_child(UIKit.label(str(e.get("text", "")), &"DimLabel", true))
	var recent := UIKit.panel(&"CardPanel")
	UIKit.expand(recent)
	_list.add_child(recent)
	var rv := UIKit.vbox(4)
	recent.add_child(rv)
	rv.add_child(UIKit.section_head("CHOICES THAT WILL MATTER"))
	var ch := DialogueManager.choices.duplicate()
	ch.reverse()
	for c: Dictionary in ch.slice(0, 10):
		var d := DialogueManager.get_dialogue(StringName(str(c["dialogue"])))
		rv.add_child(UIKit.label("D%d · %s: \"%s\"%s" % [int(c["day"]), str(d.get("title", "")), str(c["option"]), "" if bool(c["success"]) else " (failed)"], &"DimLabel", true, null, 13))


# --- The Clinic Wall ---------------------------------------------------------------------

func _wall() -> void:
	_list.columns = 4
	var pins := ClinicLifeManager.wall
	if pins.is_empty():
		_list.columns = 1
		_list.add_child(UIKit.label("The wall over the sink is bare. It fills up with the clinic's history: first jobs, regulars, the ones you lost, notices, clippings.", &"DimLabel", true))
	for i in range(pins.size() - 1, -1, -1):
		var p: Dictionary = pins[i]
		var card := UIKit.panel(&"CardPanel")
		card.name = "Pin_%d" % i
		UIKit.expand(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var kind := str(p["kind"])
		v.add_child(UIKit.label("%s · DAY %d" % [ClinicLifeManager.kind_label(kind).to_upper(), int(p["day"])], &"SubHeaderLabel", false, ClinicLifeManager.pin_color(kind)))
		v.add_child(UIKit.label(str(p["title"]), &"", true, Palette.TEXT, 15))
		v.add_child(UIKit.label(str(p.get("text", "")), &"DimLabel", true, null, 13))
		_list.add_child(card)
	if not ClinicLifeManager.captions.is_empty():
		var log_card := UIKit.panel(&"HudPanel")
		UIKit.expand(log_card)
		var lv := UIKit.vbox(2)
		log_card.add_child(lv)
		lv.add_child(UIKit.label("AROUND THE CLINIC TODAY", &"SubHeaderLabel"))
		for c in ClinicLifeManager.captions.slice(maxi(0, ClinicLifeManager.captions.size() - 8)):
			lv.add_child(UIKit.label(c, &"DimLabel", true, null, 13))
		_list.add_child(log_card)


# --- News ---------------------------------------------------------------------------------

## The wire: what's going on in the city (and what it says about you),
## above the street rumours.
func _news() -> void:
	for a in WorldEventManager.active:
		var s := WorldEventManager.situation(StringName(str(a["id"])))
		var card := UIKit.panel(&"DangerPanel")
		card.name = "Situation_%s" % str(a["id"])
		UIKit.expand(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		v.add_child(UIKit.label("HAPPENING NOW · %d DAY%s LEFT" % [int(a["days_left"]), "" if int(a["days_left"]) == 1 else "S"], &"SubHeaderLabel", false, Palette.DANGER))
		v.add_child(UIKit.label(WorldEventManager._fill(str(s.get("headline", "")), a["vars"]), &"", true, Palette.TEXT, 16))
		v.add_child(UIKit.label(WorldEventManager._fill(str(s.get("body", "")), a["vars"]), &"DimLabel", true, null, 13))
		_list.add_child(card)
	for n in WorldEventManager.latest_news(10):
		var card := UIKit.panel(&"AccentPanel" if bool(n.get("about_you", false)) else &"CardPanel")
		UIKit.expand(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		v.add_child(UIKit.label("DAY %d · %s%s" % [int(n["day"]), TimeManager.clock_text(int(n.get("minute", 540))), "  · ABOUT YOU" if bool(n.get("about_you", false)) else ""], &"SubHeaderLabel", false, Palette.ACCENT if bool(n.get("about_you", false)) else null))
		v.add_child(UIKit.label(str(n["headline"]), &"", true, Palette.TEXT, 16))
		if str(n.get("body", "")) != "":
			v.add_child(UIKit.label(str(n["body"]), &"DimLabel", true, null, 13))
		_list.add_child(card)
