class_name Glossary
extends RefCounted
## Plain-language explanations of the game's words and numbers
## (data/glossary.json). short() feeds tooltips; show() opens a small card
## next to the mouse; open_guide() opens the FIELD GUIDE (F1): every topic,
## searchable. Both live in an overlay above everything (even an open
## conversation or dialog, which they never close); ESC or a click outside
## closes them.

const PATH := "res://data/glossary.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = DataLoader.load_json(PATH)
		_data = d if d is Dictionary else {"topics": [], "terms": {}}
	return _data


## Stat captions shown around the game -> the term that explains them.
const CAPTIONS := {
	"TIER": "tier", "PERFORMANCE": "performance", "NEURAL LOAD": "neural_load", "DIFFICULTY": "difficulty",
	"FAILURE RISK": "failure_risk", "CONDITION": "condition", "PRICE": "credits", "RISK": "risk", "OVERALL": "risk",
	"PATIENCE": "patience", "HEAT": "heat", "LOYALTY": "loyalty", "STRESS": "stress", "ETHICS": "ethics",
	"KNOWN CONDITIONS": "conditions", "NEURAL STABILITY": "neural_load", "EXPECTED FEE": "terms_payment",
	"CAN PAY NOW": "terms_payment", "TERMS": "terms_payment", "ALREADY OWES": "debt", "DEBT": "debt",
	"STANDING": "factions", "STREET REP": "rep", "TOOLS": "difficulty", "SUPPLIES": "supplies", "CONSENT": "neural_load",
	"REVEALED": "conditions", "HIDDEN TRAITS": "black_market", "SLOT": "tier", "INFLUENCE": "influence",
	"SKILL": "work_stats", "SPEED": "work_stats", "PRECISION": "work_stats", "RELIABILITY": "work_stats", "SALARY": "salary",
}


static func term_for(caption: String) -> String:
	return str(CAPTIONS.get(caption.strip_edges().to_upper(), ""))


static func has(term: String) -> bool:
	return (data().get("terms", {}) as Dictionary).has(term)


static func entry(term: String) -> Dictionary:
	return data().get("terms", {}).get(term, {})


static func title(term: String) -> String:
	return str(entry(term).get("title", term.capitalize()))


static func short(term: String) -> String:
	return str(entry(term).get("short", ""))


static func text(term: String) -> String:
	return str(entry(term).get("text", short(term)))


## KNOWN vs NOT YET INTRODUCED: an entry tied to a section (its "feature")
## shows once that section has been introduced (Features); everything about
## the basics always shows. Outside a game, everything is known.
static func known(term: String) -> bool:
	var f := str(entry(term).get("feature", ""))
	return f == "" or not GameManager.is_running or Features.is_on(StringName(f))


## Recently discovered: its section was introduced in the last day.
static func is_new(term: String) -> bool:
	var f := str(entry(term).get("feature", ""))
	return f != "" and GameManager.is_running and Features.progressive() and Features.is_new(StringName(f))


static func terms_in(topic: String, only_known: bool = true) -> Array[String]:
	var out: Array[String] = []
	var t: Dictionary = data().get("terms", {})
	for k: String in t:
		if str(t[k].get("topic", "")) == topic and (not only_known or known(k)):
			out.append(k)
	return out


## How many entries in a topic are still to come.
static func hidden_in(topic: String) -> int:
	return terms_in(topic, false).size() - terms_in(topic).size()


static func search(q: String) -> Array[String]:
	var out: Array[String] = []
	var needle := q.strip_edges().to_lower()
	var t: Dictionary = data().get("terms", {})
	for k: String in t:
		var e: Dictionary = t[k]
		if not known(k):
			continue
		if needle == "" or (str(e.get("title", "")) + " " + str(e.get("short", "")) + " " + str(e.get("text", ""))).to_lower().contains(needle):
			out.append(k)
	return out


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## The help layer: above screens and modals, below the screen fade.
static func _host() -> Control:
	var tree := _tree()
	if tree == null:
		return null
	var overlay: Control = UIManager.get_overlay_host()
	var parent: Node = overlay if overlay else tree.root
	var h := parent.get_node_or_null("HelpHost") as Control
	if h == null:
		h = Control.new()
		h.name = "HelpHost"
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(h)
		if not overlay:
			UIKit.full_rect(h)
	parent.move_child(h, parent.get_child_count() - 1)
	return h


static func close() -> void:
	var h := _host()
	if h:
		for c in h.get_children():
			h.remove_child(c)
			c.queue_free()


## Is the guide (or a card) open?
static func is_open() -> bool:
	var tree := _tree()
	if tree == null:
		return false
	var h: Node = tree.root.find_child("HelpHost", true, false)
	return h != null and h.get_child_count() > 0


## A full-rect catcher: a click outside the panel closes it.
static func _catcher(h: Control, dim: float) -> void:
	var c := ColorRect.new()
	c.name = "HelpCatcher"
	c.color = Color(0, 0, 0, dim)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed:
			(func() -> void: close()).call_deferred())


## The small explanation card, next to the mouse.
static func show(term: String) -> void:
	var h := _host()
	if h == null or not has(term):
		return
	close()
	var card := UIKit.panel(&"AccentPanel")
	card.name = "GlossaryCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(card)
	# A click outside closes the card and still reaches what was clicked.
	var closer: Node = preload("res://scripts/ui/click_outside_closer.gd").new()
	closer.name = "GlossaryCloser"
	closer.set("target", card)
	closer.set("on_close", close)
	h.add_child(closer)
	var v := UIKit.vbox(8)
	card.add_child(v)
	v.add_child(UIKit.label(title(term).to_upper(), &"SectionLabel"))
	var body := UIKit.label(text(term), &"", true)
	body.custom_minimum_size.x = 520
	v.add_child(body)
	var row := UIKit.hbox(8)
	v.add_child(row)
	# Deferred: the pressed button is removed by what it does.
	row.add_child(UIKit.button("FIELD GUIDE %s" % Controls.hint("help"), &"GhostButton", func() -> void:
		(func() -> void: open_guide(str(entry(term).get("topic", "basics")), term)).call_deferred(), "GlossaryGuide", 36))
	var ok := UIKit.button("GOT IT", &"AccentButton", func() -> void: (func() -> void: close()).call_deferred(), "GlossaryClose", 36)
	row.add_child(ok)
	card.reset_size()
	var vp := h.get_viewport_rect().size
	var mouse := h.get_global_mouse_position()
	var sz := card.get_combined_minimum_size()
	card.position = (mouse + Vector2(16, 16)).clamp(Vector2(8, 8), vp - sz - Vector2(8, 8))
	UIManager.focus_later(ok)
	AudioManager.play_sfx(&"click", 0.0)


## The FIELD GUIDE: topics on the left, explanations on the right, search.
static func open_guide(topic: String = "basics", focus_term: String = "") -> void:
	var h := _host()
	if h == null:
		return
	close()
	_catcher(h, 0.6)
	var vp := h.get_viewport_rect().size
	var sz := Vector2(minf(1400, vp.x - 120), minf(860, vp.y - 120))
	var pop := UIKit.panel(&"AccentPanel")
	pop.name = "FieldGuide"
	pop.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(pop)
	pop.position = ((vp - sz) / 2.0).floor()
	pop.size = sz
	pop.custom_minimum_size = sz
	var col := UIKit.vbox(12)
	pop.add_child(col)
	var head := UIKit.hbox(12)
	col.add_child(head)
	var t := UIKit.label("FIELD GUIDE", &"HeaderLabel")
	UIKit.expand(t)
	head.add_child(t)
	var find := LineEdit.new()
	find.name = "GuideSearch"
	find.placeholder_text = "search: heat, neural load, travel..."
	find.custom_minimum_size.x = 420
	head.add_child(find)
	head.add_child(UIKit.button("CLOSE %s" % Controls.hint("pause"), &"GhostButton", func() -> void: (func() -> void: close()).call_deferred(), "GuideClose", 40))
	var row := UIKit.hbox(16)
	UIKit.expand(row, true, true)
	col.add_child(row)
	var nav := UIKit.vbox(6)
	nav.custom_minimum_size.x = 300
	row.add_child(nav)
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	row.add_child(sc)
	var body := UIKit.vbox(14)
	UIKit.expand(body, true, false)
	sc.add_child(body)
	# BACK: the guide remembers where you came from inside it.
	var history: Array = []
	var back := UIKit.button("◀ BACK", &"GhostButton", Callable(), "GuideBack", 40)
	back.disabled = true
	head.add_child(back)
	head.move_child(back, 1)
	var state := {"current": []}
	var fill := func(keys: Array[String], heading: String, focus: String, hidden: int, record: bool) -> void:
		if record and not (state["current"] as Array).is_empty():
			history.append(state["current"])
		state["current"] = [keys, heading, focus, hidden]
		back.disabled = history.is_empty()
		UIKit.clear(body)
		body.add_child(UIKit.label(heading, &"SectionLabel"))
		if keys.is_empty():
			body.add_child(UIKit.label("Nothing matches.", &"DimLabel"))
		for k in keys:
			_guide_card(body, k, k == focus or k == focus_term, state)
		if hidden > 0:
			body.add_child(UIKit.label("%d more entr%s open up as your clinic grows." % [hidden, "y" if hidden == 1 else "ies"], &"DimLabel", true, null, 14))
		sc.scroll_vertical = 0
	state["fill"] = fill
	back.pressed.connect(func() -> void:
		if history.is_empty():
			return
		var prev: Array = history.pop_back()
		fill.call(prev[0], prev[1], prev[2], prev[3], false))
	var topics: Array = data().get("topics", [])
	for tp: Dictionary in topics:
		var id := str(tp["id"])
		var fresh := terms_in(id).any(func(k: String) -> bool: return is_new(k))
		nav.add_child(UIKit.button(str(tp["label"]) + ("  · NEW" if fresh else ""), &"TabButton", func() -> void:
			fill.call(terms_in(id), str(tp["label"]), "", hidden_in(id), true), "GuideTopic_%s" % id, 44))
	nav.add_child(UIKit.button("TUTORIALS", &"TabButton", func() -> void:
		history.append(state["current"])
		back.disabled = false
		UIKit.clear(body)
		_tutorials(body), "GuideTopic_tutorials", 44))
	nav.add_child(UIKit.button("CONTROLS", &"TabButton", func() -> void:
		UIKit.clear(body)
		body.add_child(UIKit.label("CONTROLS", &"SectionLabel"))
		body.add_child(UIKit.label(TutorialManager.help_text(), &"", true)), "GuideTopic_controls", 44))
	find.text_changed.connect(func(q: String) -> void: fill.call(search(q), "SEARCH: %s" % q.to_upper(), "", 0, false))
	var label := topic
	for tp: Dictionary in topics:
		if str(tp["id"]) == topic:
			label = str(tp["label"])
	fill.call(terms_in(topic), label, focus_term, hidden_in(topic), true)
	UIManager.focus_later(find)
	AudioManager.play_sfx(&"click", 0.0)


## One handbook entry: what it is (the text), why it matters, where you use
## it, and related entries (SEE ALSO stays inside the guide; BACK returns).
static func _guide_card(body: Control, k: String, focused: bool, state: Dictionary) -> void:
	var e := entry(k)
	var card := UIKit.panel(&"AccentPanel" if focused else &"CardPanel")
	card.name = "Guide_%s" % k
	body.add_child(card)
	var v := UIKit.vbox(4)
	card.add_child(v)
	v.add_child(UIKit.label(title(k).to_upper() + ("   · NEW" if is_new(k) else ""), &"SubHeaderLabel", false, Palette.ACCENT))
	v.add_child(UIKit.label(text(k), &"", true))
	if str(e.get("why", "")) != "":
		v.add_child(UIKit.label("WHY IT MATTERS  " + str(e["why"]), &"", true, Palette.TEXT, 15))
	if str(e.get("where", "")) != "":
		v.add_child(UIKit.label("WHERE  " + str(e["where"]), &"DimLabel", true, null, 15))
	var see: Array = (e.get("see", []) as Array).filter(func(x: Variant) -> bool: return has(str(x)) and known(str(x)))
	if not see.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override(&"h_separation", 6)
		v.add_child(row)
		row.add_child(UIKit.label("SEE ALSO", &"SubHeaderLabel", false, Palette.TEXT_DIM, 13))
		for s: Variant in see:
			var key := str(s)
			row.add_child(UIKit.button(title(key).to_upper(), &"GhostButton", func() -> void:
				var keys: Array[String] = [key]
				(state["fill"] as Callable).call(keys, title(key).to_upper(), key, 0, true), "SeeAlso_%s_%s" % [k, key], 32))


## TUTORIALS: everything the game has taught you, to read or see again.
static func _tutorials(body: Control) -> void:
	body.add_child(UIKit.label("TUTORIALS", &"SectionLabel"))
	body.add_child(UIKit.label("Everything the game has introduced so far. SHOW AGAIN brings the card back; the first operation's steps are under CONTROLS.", &"DimLabel", true))
	var any := false
	for id: StringName in Features.LIST:
		if not Features.is_on(id) or not GameManager.is_running:
			continue
		any = true
		var f: Dictionary = Features.LIST[id]
		var row := UIKit.hbox(8)
		row.name = "Tutorial_%s" % id
		body.add_child(row)
		var l := UIKit.label("%s: %s" % [str(f["title"]), str(f["what"])], &"", true, Palette.TEXT, 15)
		UIKit.expand(l)
		row.add_child(l)
		row.add_child(UIKit.button("SHOW AGAIN", &"GhostButton", func() -> void:
			close()
			Features.show_intro(id), "TutorialAgain_%s" % id, 34))
	for h: String in Hints.HINTS:
		if not Hints.seen(h):
			continue
		any = true
		var data_h: Array = Hints.HINTS[h]
		var row := UIKit.hbox(8)
		row.name = "Hint_%s" % h
		body.add_child(row)
		var l := UIKit.label(str(data_h[0]), &"", true, Palette.TEXT, 15)
		UIKit.expand(l)
		row.add_child(l)
		row.add_child(UIKit.button("SHOW AGAIN", &"GhostButton", func() -> void:
			close()
			Hints.show_again(h), "HintAgain_%s" % h, 34))
	if not any:
		body.add_child(UIKit.label("Nothing yet: cards appear as you play.", &"DimLabel"))


## The shared help layer for other overlays (recent changes, hints): they
## close with ESC and count as the GUIDE input context like the guide.
static func host() -> Control:
	return _host()


static func catcher(h: Control, dim: float) -> void:
	_catcher(h, dim)
