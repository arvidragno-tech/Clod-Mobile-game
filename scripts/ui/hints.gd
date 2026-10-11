class_name Hints
extends RefCounted
## LEARN AS YOU GO: the first time a system shows up, a small card
## explains it in two sentences (with MORE for the full field-guide entry).
## After that the game relies on the shorter tooltips and the "?" chips.
##
## Hints never block: the card sits bottom-right, doesn't capture the
## keyboard, and goes away with GOT IT or after a while. Which hints were
## seen is player knowledge, so it lives in the settings (shared by every
## save); TUTORIAL HINTS off turns them all off.

const SHOW_SECONDS := 14.0
## Test harnesses switch hints off so cards never sit over what they click.
static var enabled: bool = true

## id -> [title, text, glossary term]
const HINTS := {
	"neural_load": ["NEURAL LOAD", "Every implant adds neural load. High load raises the risk of neurological complications during surgery and of a breakdown after.", "neural_load"],
	"preview": ["SURGERY PREVIEW", "Before you cut, the preview shows the risk, time, cost, pay, likely complications, your odds and who should operate. The call is yours.", "preview"],
	"priorities": ["WHAT MATTERS NOW", "This list is what needs you, most urgent first (■ critical, ▲ important). Click a line to go straight there.", "priorities"],
	"heat": ["AUTHORITY HEAT", "Black-market work and messy jobs draw attention. Clean work cools it; high heat brings inspections and raids.", "heat"],
	"map": ["THE CITY", "Each place has people, services and its own hours. Travelling takes time and sometimes money; the panel shows both before you go.", "travel"],
	"follow": ["FOLLOW", "☆ FOLLOW keeps a quest, person or place on your journal's MAIN page with where and when, so you never have to remember it.", "follow"],
	"black_market": ["THE BLACK MARKET", "Chrome with no paperwork: cheap, strong, sometimes cursed. Unknown traits show as ??. Buying here raises heat.", "black_market"],
	"staff": ["STAFF", "Ripperdocs can take jobs for you. Their odds come from skill, specialty and stress; the recommended one is marked ★.", "stress"],
	"emergency": ["EMERGENCY", "A bleeding patient won't wait: decide before the countdown runs out. Reading screens and the field guide stop the clock.", "emergency"],
	"changes": ["RECENT CHANGES", "Things changed while you were busy. Open CHANGES (or press {changes}) for what moved and by how much.", "changes"],
	"journal": ["THE JOURNAL", "MAIN has what you follow, messages waiting for an answer and your objectives. Everything else is one tab away.", "follow"],
	"consequence": ["CONSEQUENCES", "Big decisions show what they changed right away. Some also set things in motion you'll only see later.", "factions"],
}


## Shows hint `id` once (if hints are on). Returns true when it showed.
static func first(id: String) -> bool:
	if not enabled or not HINTS.has(id) or not Settings.tutorial_hints or seen(id) or not GameManager.is_running:
		return false
	if TutorialManager.is_active():
		return false  # the first operation has its own coach marks
	if Settings.is_minimal():
		return false
	if SurgeryManager.is_active or DialogueManager.is_active():
		return false  # never over an operation or a conversation; it shows next time
	_mark(id)
	_show(id)
	return true


static func seen(id: String) -> bool:
	return Settings.seen_hints.has(id)


static func _mark(id: String) -> void:
	var a: Array = Settings.seen_hints.duplicate()
	a.append(id)
	Settings.set_value("seen_hints", a)


static func reset_all() -> void:
	Settings.set_value("seen_hints", [])


static func is_showing() -> bool:
	var h := _host()
	return h != null and h.get_child_count() > 0


static func dismiss() -> void:
	var h := _host()
	if h:
		for c in h.get_children():
			c.queue_free()


static func _show(id: String) -> void:
	var h := _host()
	if h == null:
		return
	dismiss()
	var data: Array = HINTS[id]
	var card := UIKit.panel(&"AccentPanel")
	card.name = "HintCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only its two buttons take clicks
	h.add_child(card)
	var v := UIKit.vbox(6)
	card.add_child(v)
	v.add_child(UIKit.label("NEW · " + str(data[0]), &"SubHeaderLabel", false, Palette.ACCENT))
	var body := UIKit.label(Controls.fill(str(data[1])), &"", true, Palette.TEXT, 16)
	body.custom_minimum_size.x = 440
	v.add_child(body)
	var row := UIKit.hbox(8)
	v.add_child(row)
	var term := str(data[2])
	var more := UIKit.button("MORE", &"GhostButton", func() -> void:
		dismiss()
		Glossary.show(term), "HintMore", 34)
	more.focus_mode = Control.FOCUS_NONE
	more.set_meta(&"no_focus", true)
	row.add_child(more)
	var ok := UIKit.button("GOT IT", &"AccentButton", dismiss, "HintClose", 34)
	ok.focus_mode = Control.FOCUS_NONE
	ok.set_meta(&"no_focus", true)
	row.add_child(ok)
	card.reset_size()
	var vp := h.get_viewport_rect().size
	var sz := card.get_combined_minimum_size()
	card.position = Vector2(vp.x - sz.x - 32, vp.y - sz.y - 40).floor()
	var tw := card.create_tween()
	tw.tween_interval(SHOW_SECONDS)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)


static func _host() -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var overlay: Control = UIManager.get_overlay_host()
	var parent: Node = overlay if overlay else tree.root
	var h := parent.get_node_or_null("HintHost") as Control
	if h == null:
		h = Control.new()
		h.name = "HintHost"
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(h)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return h
