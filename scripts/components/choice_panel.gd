class_name ChoicePanel
extends Control
## Modal for something that needs a decision out in the city (a travel
## encounter, a missing patient): kicker, title, text, choices gated by
## their "requires" (EventManager.get_choice_block_reason), then the outcome.
## `resolver` takes the choice index and returns the outcome text.

signal closed()

var kicker: String = "ON THE WAY"
var title: String = ""
var text: String = ""
var choices: Array = []
var resolver: Callable
var _box: VBoxContainer


func _ready() -> void:
	UIKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	add_child(UIKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var p := UIKit.panel(&"AccentPanel")
	p.custom_minimum_size.x = 720
	center.add_child(p)
	_box = UIKit.vbox(12)
	p.add_child(_box)
	_box.add_child(UIKit.label(kicker, &"SubHeaderLabel"))
	if title != "":
		_box.add_child(UIKit.label(title, &"HeaderLabel", true))
	var body := TypewriterLabel.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 680
	_box.add_child(body)
	body.play()
	var first: Button = null
	for i in choices.size():
		var c: Dictionary = choices[i]
		var reason := EventManager.get_choice_block_reason(c)
		var b := UIKit.button(str(c.get("label", "OK")), &"AccentButton" if i == 0 else &"Button", _on_choice.bind(i), "Choice_%d" % i)
		b.disabled = reason != ""
		_box.add_child(b)
		if reason != "":
			_box.add_child(UIKit.label("  " + reason, &"DimLabel", false, Palette.WARN, 13))
		elif first == null:
			first = b
	if choices.is_empty():
		first = UIKit.button("CONTINUE", &"AccentButton", _close, "ChoiceContinue")
		_box.add_child(first)
	if first:
		first.set_meta(&"default", true)
		first.grab_focus.call_deferred()


func _on_choice(i: int) -> void:
	var out := str(resolver.call(i)) if resolver.is_valid() else ""
	AudioManager.play_sfx(&"stage", 0.0)
	UIKit.clear(_box)
	_box.add_child(UIKit.label("OUTCOME", &"SubHeaderLabel"))
	_box.add_child(UIKit.label(out if out != "" else "Done.", &"", true))
	var b := UIKit.button("CONTINUE", &"AccentButton", _close, "ChoiceContinue")
	_box.add_child(b)
	b.grab_focus.call_deferred()


## ESC can't dodge a decision; after the outcome it continues.
func on_escape() -> void:
	if _box.find_child("ChoiceContinue", true, false):
		_close()


func _close() -> void:
	UIManager.close_modal()
	closed.emit()
