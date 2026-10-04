class_name TypewriterLabel
extends Label
## Label that reveals its text at the player's chosen text speed
## (Settings.text_speed). Tapping it, or calling finish(), shows everything.

signal revealed

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func play() -> void:
	if _tween:
		_tween.kill()
	var cps := Settings.chars_per_second()
	var count := text.length()
	if cps <= 0.0 or count == 0:
		finish()
		return
	visible_characters = 0
	_tween = create_tween()
	_tween.tween_property(self, "visible_characters", count, count / cps)
	_tween.tween_callback(revealed.emit)


func is_revealing() -> bool:
	return _tween != null and _tween.is_running()


func finish() -> void:
	if _tween:
		_tween.kill()
	visible_characters = -1
	revealed.emit()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and is_revealing():
		finish()
		accept_event()
