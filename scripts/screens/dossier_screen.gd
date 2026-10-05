extends BaseScreen
## The journal: quests, the comms inbox, the people in your story (with
## relationship status and what you know of them), factions, rumours, the
## operation record and the story so far (acts and endgame paths).

const TABS := ["QUESTS", "COMMS", "PEOPLE", "FACTIONS", "RUMORS", "RECORDS", "STORY"]
enum Tab { QUESTS, COMMS, PEOPLE, FACTIONS, RUMORS, RECORDS, STORY }

var _list: GridContainer
var _tab: int = 0


var _selected_msg: int = -1


func on_enter(params: Dictionary) -> void:
	_tab = int(params.get("tab", Tab.QUESTS))
	var col := UIKit.workstation(self, &"dossier")
	col.add_child(UIKit.header("CLINIC · INTEL", "JOURNAL", GameManager.go_to_clinic))
	var tabs := UIKit.tabs(TABS, _on_tab, "DossierTab")
	tabs.custom_minimum_size.x = 1300
	if _tab > 0 and _tab < tabs.get_child_count():
		(tabs.get_child(_tab) as Button).button_pressed = true
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tabs)
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = GridContainer.new()
	_list.add_theme_constant_override(&"h_separation", 14)
	_list.add_theme_constant_override(&"v_separation", 12)
	UIKit.expand(_list)
	sc.add_child(_list)
	_rebuild()


func _on_tab(i: int) -> void:
	_tab = i
	_rebuild()


func _rebuild() -> void:
	UIKit.clear(_list)
	_list.columns = 1 if _tab == Tab.RECORDS else 2
	match _tab:
		Tab.QUESTS:
			_quests()
		Tab.COMMS:
			_comms()
		Tab.PEOPLE:
			_people()
		Tab.STORY:
			_story()
		Tab.FACTIONS:
			_list.columns = 3
			var heat := UIKit.panel(&"DangerPanel" if FactionManager.heat >= 35 else &"HudPanel")
			UIKit.expand(heat)
			heat.add_child(UIKit.label("HEAT %d / 100\nInspections start around 35. Black-market work and failed jobs raise it." % roundi(FactionManager.heat), &"MonoLabel", true, Palette.DANGER if FactionManager.heat >= 35 else Palette.TEXT_DIM))
			_list.add_child(heat)
			for id in FactionManager.order:
				_list.add_child(_faction_card(id))
		-1:
			var any := false
			for id in StoryManager.met_characters:
				var c := CustomerManager.get_customer(id)
				if c:
					_list.add_child(_contact_card(c, str(CustomerManager.characters[id].get("role", "")).to_upper()))
					any = true
			if not any:
				_list.add_child(UIKit.label("No contacts yet. Keep the clinic open and people will find you.", &"DimLabel", true))
		Tab.RUMORS:
			if StoryManager.unlocked_rumors.is_empty():
				_list.add_child(UIKit.label("Nothing on the street yet.", &"DimLabel"))
			for id in StoryManager.unlocked_rumors:
				var card := UIKit.panel(&"CardPanel")
				UIKit.expand(card)
				card.add_child(UIKit.label(StoryManager.get_rumor_text(id), &"MonoLabel", true, Palette.ACCENT, 18))
				_list.add_child(card)
		Tab.RECORDS:
			_records()


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
	return card


func _records() -> void:
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
	_list.columns = 2
	var any := false
	for state: String in ["active", "completed", "failed"]:
		for id in QuestManager.by_state(state):
			_list.add_child(_quest_card(id, state))
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
					CommsManager.act(uid, i)
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
		_list.add_child(UIKit.label("Nobody important knows your name yet.", &"DimLabel", true))


func _person_card(id: StringName) -> Control:
	var c := CharacterManager.get_character(id)
	var card := UIKit.panel(&"CardPanel")
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
	return card


# --- Story ---------------------------------------------------------------------------

func _story() -> void:
	_list.columns = 2
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
	pv.add_child(UIKit.label("WHO YOU ARE BECOMING", &"SubHeaderLabel", false, Palette.ACCENT))
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
	rv.add_child(UIKit.label("CHOICES THAT WILL MATTER", &"SubHeaderLabel", false, Palette.ACCENT))
	var ch := DialogueManager.choices.duplicate()
	ch.reverse()
	for c: Dictionary in ch.slice(0, 10):
		var d := DialogueManager.get_dialogue(StringName(str(c["dialogue"])))
		rv.add_child(UIKit.label("D%d · %s: \"%s\"%s" % [int(c["day"]), str(d.get("title", "")), str(c["option"]), "" if bool(c["success"]) else " (failed)"], &"DimLabel", true, null, 13))
