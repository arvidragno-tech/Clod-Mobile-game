class_name Consequence
extends RefCounted
## CONSEQUENCE feedback: take a snapshot before a meaningful decision, show
## what actually changed right after it. The numbers are the real deltas
## of the game state (money, reputation, every faction, authority heat,
## supplies, parts, tokens), never a guess, and future effects stay hidden:
## the card only adds "This may affect future events." when a decision
## also set something in motion.
##
##   var before := Consequence.snapshot()
##   ...apply the choice...
##   Consequence.show("You sold restricted military chrome to a gang.", before)
##
## The card sits at the top of the screen, doesn't block input, and fades
## after a few seconds (click to dismiss). Symbols ▲ ▼ carry the direction,
## so it never relies on colour alone.

const SHOW_SECONDS := 6.0


static func snapshot() -> Dictionary:
	var f := {}
	for id: StringName in FactionManager.order:
		f[id] = FactionManager.get_rep(id)
	return {"money": EconomyManager.money, "rep": ReputationManager.reputation, "heat": FactionManager.heat,
		"factions": f, "supplies": InventoryManager.supplies, "parts": InventoryManager.parts, "tokens": InventoryManager.tokens,
		"talk": StoryManager.talk_queue.size(), "quests": QuestManager.by_state("active").size()}


## [{label, delta, good}] for everything that moved since `before`.
static func diff(before: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if before.is_empty():
		return out
	var now := snapshot()
	var add := func(label: String, d: float, good_when_up: bool = true) -> void:
		if absf(d) >= 1.0:
			out.append({"label": label, "delta": d, "good": (d > 0.0) == good_when_up})
	add.call("Credits", float(int(now["money"]) - int(before["money"])))
	add.call("Reputation", float(int(now["rep"]) - int(before["rep"])))
	for id: StringName in FactionManager.order:
		add.call(FactionManager.get_name_of(id), float(int(now["factions"].get(id, 0)) - int(before["factions"].get(id, 0))))
	add.call("Authority heat", float(now["heat"]) - float(before["heat"]), false)
	add.call("Medical supplies", float(int(now["supplies"]) - int(before["supplies"])))
	add.call("Parts", float(int(now["parts"]) - int(before["parts"])))
	add.call("Tokens", float(int(now["tokens"]) - int(before["tokens"])))
	return out


## Shows the card when anything changed. Returns the deltas shown.
static func show(headline: String, before: Dictionary, title: String = "CONSEQUENCE") -> Array[Dictionary]:
	var d := diff(before)
	var now := snapshot()
	var future := int(now["talk"]) > int(before.get("talk", 0)) or int(now["quests"]) != int(before.get("quests", 0))
	if d.is_empty() and not future:
		return d
	var host := _host()
	if host == null:
		return d
	for c in host.get_children():
		c.queue_free()
	var card := UIKit.panel(&"AccentPanel")
	card.name = "ConsequenceCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(card)
	var v := UIKit.vbox(4)
	card.add_child(v)
	v.add_child(UIKit.label(title, &"SubHeaderLabel", false, Palette.ACCENT))
	if headline != "":
		var h := UIKit.label(headline, &"", true, Palette.TEXT, 16)
		h.custom_minimum_size.x = 520
		v.add_child(h)
	for x in d:
		var up := float(x["delta"]) > 0.0
		var col := Palette.OK if bool(x["good"]) else Palette.DANGER
		v.add_child(UIKit.label("%s %s  %+d" % ["▲" if up else "▼", str(x["label"]), roundi(float(x["delta"]))], &"MonoLabel", false, col, 17))
	if future:
		v.add_child(UIKit.label("This may affect future events.", &"DimLabel", true, Palette.TEXT_DIM, 14))
	card.reset_size()
	(func() -> void: Hints.first("consequence")).call_deferred()
	var vp := host.get_viewport_rect().size
	card.position = Vector2(((vp.x - card.get_combined_minimum_size().x) / 2.0), 96).floor()
	card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed:
			card.queue_free())
	var tw := card.create_tween()
	tw.tween_interval(SHOW_SECONDS)
	tw.tween_property(card, "modulate:a", 0.0, 0.6)
	tw.tween_callback(card.queue_free)
	return d


static func is_showing() -> bool:
	var h := _host()
	return h != null and h.get_child_count() > 0


static func _host() -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var overlay: Control = UIManager.get_overlay_host()
	var parent: Node = overlay if overlay else tree.root
	var h := parent.get_node_or_null("ConsequenceHost") as Control
	if h == null:
		h = Control.new()
		h.name = "ConsequenceHost"
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(h)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.move_child(h, parent.get_child_count() - 1)
	return h
