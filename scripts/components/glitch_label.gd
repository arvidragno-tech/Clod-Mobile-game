class_name GlitchLabel
extends Label
## Label that occasionally corrupts a few characters and jitters
## horizontally: the black market's "bad signal" identity.

const GLYPHS := "#%&@$!?/\\|<>=+*01"

@export var glitch_rate: float = 0.08
var base_text: String = ""
var _timer: float = 0.0


func _ready() -> void:
	if base_text == "":
		base_text = text


func set_base_text(t: String) -> void:
	base_text = t
	text = t


func _process(delta: float) -> void:
	if Settings.reduce_motion or not Settings.flashing_allowed():
		if text != base_text:
			text = base_text
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(0.06, 0.4)
	if randf() < glitch_rate * 4.0 and base_text.length() > 2:
		var chars := base_text.split("")
		for i in randi_range(1, 3):
			var k := randi_range(0, chars.size() - 1)
			if chars[k] != " ":
				chars[k] = GLYPHS[randi_range(0, GLYPHS.length() - 1)]
		text = "".join(chars)
		position.x = randf_range(-2.0, 2.0)
	else:
		text = base_text
		position.x = 0.0
