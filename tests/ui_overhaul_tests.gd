extends RefCounted
## UI overhaul tests (3.3): the glossary and field guide, stat captions,
## the job verdict (at a glance), the brightness setting, the art changes.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	_glossary()
	_captions()
	_verdict()
	_brightness()
	_art()


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _glossary() -> void:
	var d := Glossary.data()
	var topics := {}
	for tp: Dictionary in d.get("topics", []):
		topics[str(tp["id"])] = true
	check(topics.size() >= 6, "the field guide has topics (%d)" % topics.size())
	var bad: Array[String] = []
	var terms: Dictionary = d.get("terms", {})
	for k: String in terms:
		var e: Dictionary = terms[k]
		if str(e.get("title", "")) == "" or str(e.get("short", "")) == "" or str(e.get("text", "")) == "":
			bad.append("%s incomplete" % k)
		if not topics.has(str(e.get("topic", ""))):
			bad.append("%s topic" % k)
		if str(e.get("short", "")).length() > 110:
			bad.append("%s short too long" % k)
	check(bad.is_empty(), "every glossary term has a title, a short line, a full text and a real topic %s" % str(bad))
	check(terms.size() >= 40, "the glossary covers the game's words (%d terms)" % terms.size())
	for topic: String in topics:
		check(not Glossary.terms_in(topic).is_empty(), "topic %s has entries" % topic)
	check(Glossary.search("heat").has("heat") and Glossary.search("neural").has("neural_load"), "the guide search finds terms")
	check(Glossary.search("zzzz-nothing").is_empty(), "and nothing for nonsense")
	check(Glossary.text("heat").contains("Clean"), "the heat entry matches the game (cools with clean work)")
	check(Glossary.text("rep").contains("25"), "the reputation entry names the real black-market threshold")
	# Every term the UI points at exists.
	var used := ["loop", "time", "factions", "neural_load", "diagnosis", "odds", "vitals", "condition", "terms_payment", "credits",
		"level", "rep", "heat", "supplies", "parts", "tokens", "jobs", "risk", "difficulty", "performance", "work_stats", "salary"]
	var missing: Array[String] = []
	for u in used:
		if not Glossary.has(u):
			missing.append(u)
	for k: String in Glossary.CAPTIONS:
		if not Glossary.has(str(Glossary.CAPTIONS[k])):
			missing.append("caption %s" % k)
	check(missing.is_empty(), "every term the UI links to exists %s" % str(missing))
	check(Controls.ACTIONS.has("help") and Controls.get_slots("help")[0] == KEY_F1, "F1 opens the field guide (rebindable)")
	check(SideNav.TIPS.size() == SideNav.ITEMS.size(), "every sidebar section explains itself on hover")


func _captions() -> void:
	var l := UIKit.caption("NEURAL LOAD")
	check(l.mouse_filter == Control.MOUSE_FILTER_STOP and l.tooltip_text.contains(Glossary.short("neural_load")), "a stat caption explains itself on hover")
	check(l.mouse_default_cursor_shape == Control.CURSOR_HELP, "with a help cursor")
	var plain := UIKit.caption("MAKER")
	check(plain.mouse_filter == Control.MOUSE_FILTER_IGNORE and plain.tooltip_text == "", "captions without an entry stay plain")
	var info := UIKit.info("heat")
	check(info.text == "?" and info.tooltip_text == Glossary.short("heat"), "the ? chip carries the short explanation")
	var head := UIKit.section_head("FINDINGS", "hint", "diagnosis")
	check(head.find_child("Info_diagnosis", true, false) != null, "section heads can carry a ? chip")
	for n in [l, plain, info, head]:
		n.free()


func _verdict() -> void:
	SaveManager.reset_all()
	EventManager.operations = 10
	var c := CustomerManager.generator.generate({"archetype": "civilian"})
	CustomerManager.debug_set_customer(c)
	InventoryManager.add_implant(c.requested_cyberware_id)
	InventoryManager.supplies = 10
	var cs := JobVerdict.checks(c)
	var keys := cs.map(func(x: Dictionary) -> String: return str(x["key"]))
	for k in ["implant", "tools", "supplies", "difficulty", "neural", "risk", "pay"]:
		check(keys.has(k), "at a glance shows %s" % k)
	check(cs.filter(func(x: Dictionary) -> bool: return x["key"] == "implant")[0]["level"] == &"good", "an implant in stock is good")
	# Missing supplies: the advice says so.
	InventoryManager.supplies = 0
	var adv := JobVerdict.advice(c)
	check(adv["level"] == &"bad" and str(adv["text"]).contains("supplies"), "no supplies: the advice says restock (%s)" % adv["text"])
	InventoryManager.supplies = 10
	# Missing tools: the advice names SUPPLY.
	var owned := InventoryManager.owned_tools.duplicate()
	InventoryManager.owned_tools.clear()
	adv = JobVerdict.advice(c)
	var r := GameManager.get_surgery_readiness()
	if not (r["missing_tools"] as Array).is_empty():
		check(adv["level"] == &"bad" and str(adv["text"]).contains("SUPPLY"), "missing tools: the advice says buy them (%s)" % adv["text"])
	InventoryManager.owned_tools = owned
	# The verdict agrees with the operation plan.
	r = GameManager.get_surgery_readiness()
	var tools: Dictionary = cs.filter(func(x: Dictionary) -> bool: return x["key"] == "tools")[0]
	check((tools["level"] == &"good") == (r["missing_tools"] as Array).is_empty(), "the tools line agrees with the operation plan")
	# Builds into a container (full and compact).
	var box := VBoxContainer.new()
	JobVerdict.build(box, c)
	check(box.find_child("VerdictAdvice", true, false) != null and box.find_child("Verdict_pay", true, false) != null, "the card has advice and rows")
	var compact := VBoxContainer.new()
	JobVerdict.build(compact, c, true)
	check(compact.get_child_count() < box.get_child_count(), "the door card version is shorter")
	check(compact.find_child("Verdict_pay", true, false) != null, "and always shows the pay")
	box.free()
	compact.free()
	# The clinic card and the customer file use the same fee.
	check(CustomerGenerator.estimate_fee(c) > 0, "one fee estimate everywhere")
	CustomerManager.dismiss_current()


func _brightness() -> void:
	var old := Settings.brightness
	var m := Settings.room_material()
	check(m != null and m.shader != null, "a room-light material exists")
	Settings.brightness = 1.5
	Settings.changed.emit()
	check(is_equal_approx(float(m.get_shader_parameter(&"lift")), 1.5), "changing ROOM BRIGHTNESS updates the room")
	Settings.brightness = old
	Settings.changed.emit()
	check(Settings.DEFAULTS.has("brightness") and float(Settings.DEFAULTS["brightness"]) > 1.0, "the room is a little brighter by default")


func _art() -> void:
	# The body sprite shows what the portrait wears on the face.
	var app := CharacterAppearanceManager.normalize(CharacterManager.appearance(&"rook_varga"))
	var parts := CharacterArt.parts_for(&"body", app)
	var acc: Array = parts.get("acc", [])
	var portrait_acc: Array = app.get("accessories", [])
	if portrait_acc.has("bandana") or portrait_acc.has("scarf") or portrait_acc.has("surgical_mask"):
		check(acc.any(func(a: Variant) -> bool: return str(a).begins_with("mask_")), "a masked face is masked on the body too")
	var man := CharacterArt.manifest()
	var body_acc: Dictionary = man.get("parts", {}).get("body", {}).get("acc", {})
	var ok := true
	for kind in ["mask", "eyewear"]:
		var found := false
		for k: Variant in body_acc:
			if str(k).begins_with(kind + "_"):
				found = true
				break
		ok = ok and found
	check(ok, "the body atlas has mask and eyewear parts")
	var tex := CharacterArt.portrait(app)
	check(tex != null and tex.get_width() == 144 and tex.get_height() == 168, "portraits build at the HD 144x168")
