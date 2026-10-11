class_name EventPanel
extends Control
## Modal for random / story events: who's involved, what's happening, and
## the choices (gated by requirements). After choosing, shows the outcome.

signal closed()

var event_id: StringName
var _box: VBoxContainer


func _ready() -> void:
	UIKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	add_child(UIKit.full_rect(dim))
	var m := UIKit.margin(12, 30, 12, 30)
	add_child(UIKit.full_rect(m))
	var center := CenterContainer.new()
	m.add_child(center)
	var p := UIKit.panel(&"AccentPanel")
	p.custom_minimum_size.x = 320
	center.add_child(p)
	_box = UIKit.vbox(10)
	p.add_child(_box)
	_build()


func _build() -> void:
	var e := EventManager.get_event(event_id)
	var head := UIKit.hbox(10)
	_box.add_child(head)
	var char_id := StringName(str(e.get("character", "")))
	var who := CustomerManager.get_customer(char_id) if char_id != &"" else null
	if who:
		var portrait := PixelPortrait.new()
		portrait.framing = PixelPortrait.Framing.HEAD
		head.add_child(portrait)
		portrait.set_appearance(who.appearance, FactionManager.get_color(who.faction_id))
	else:
		head.add_child(UIKit.icon("res://assets/sprites/ui/icons/warning.png", 12))
	var titles := UIKit.vbox(2)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.expand(titles)
	titles.add_child(UIKit.label("INCIDENT", &"SubHeaderLabel"))
	titles.add_child(UIKit.label(str(e.get("title", "EVENT")), &"HeaderLabel", true))
	if who:
		titles.add_child(UIKit.label(who.get_display_title(), &"DimLabel", true))
	head.add_child(titles)
	var body := TypewriterLabel.new()
	body.text = str(e.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(body)
	body.play()
	var choices: Array = e.get("choices", [])
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var reason := EventManager.get_choice_block_reason(choice)
		var b := UIKit.button(str(choice.get("label", "OK")), &"Button" if i > 0 else &"AccentButton", _on_choice.bind(i), "Choice_%d" % i)
		b.disabled = reason != ""
		_box.add_child(b)
		if reason != "":
			_box.add_child(UIKit.label("  " + reason, &"DimLabel", false, Palette.WARN, 13))


func _on_choice(i: int) -> void:
	var before := Consequence.snapshot()
	var text := EventManager.resolve(i)
	Consequence.show("", before)
	AudioManager.play_sfx(&"stage", 0.0)
	UIKit.clear(_box)
	_box.add_child(UIKit.label("OUTCOME", &"SubHeaderLabel"))
	_box.add_child(UIKit.label(text if text != "" else "Done.", &"", true))
	_box.add_child(UIKit.button("CONTINUE", &"AccentButton", _close, "EventContinue"))


func _close() -> void:
	UIManager.close_modal()
	closed.emit()
