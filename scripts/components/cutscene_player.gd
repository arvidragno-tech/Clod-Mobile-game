class_name CutscenePlayer
extends Control
## A short in-engine scene (data/cutscenes.json), played as a modal in the
## clinic. Letterbox bars, a backdrop made from art the game already has
## (the title key art, the clinic room, a street scene with today's weather
## and light), an optional cast portrait or chapter card, and one line of
## text per shot, typed at the player's text speed. Shots fade into each
## other with a slow drift (none with Reduce Motion).
##
## Click / SPACE / ENTER: finish the line, then the next shot. ESC or SKIP:
## end the scene. Lines move on by themselves after a moment, so a scene
## never waits on the player; left alone, every scene runs at least
## MIN_SCENE_SEC at any text speed (estimate_seconds). Nobody walks in
## while it plays.

signal closed()

## Test harnesses switch cutscenes off (bots test the systems, not scenes).
static var enabled: bool = true

const BAR_H := 120.0
const FADE_SEC := 0.4
const DRIFT := 1.05
const TEXT_W := 1400.0
const MIN_SCENE_SEC := 30.0

var cutscene_id: StringName
var _shots: Array = []
var _index: int = -1
var _stage: Control
var _backdrop: Control
var _portrait: PixelPortrait
var _who: Label
var _card: Label
var _text: TypewriterLabel
var _fade: ColorRect
var _hold: float = 0.0
var _busy: bool = false
var _done: bool = false
var _laid_out := Vector2.ZERO


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(bg))
	_stage = Control.new()
	_stage.name = "CutsceneStage"
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(_stage))
	_stage.offset_top = BAR_H
	_stage.offset_bottom = -BAR_H
	_portrait = PixelPortrait.new()
	_portrait.name = "CutscenePortrait"
	_portrait.pixel_scale = 3
	_portrait.framing = PixelPortrait.Framing.BUST
	_portrait.visible = false
	add_child(_portrait)
	_who = UIKit.label("", &"SubHeaderLabel", false, Palette.ACCENT)
	_who.visible = false
	add_child(_who)
	_card = UIKit.label("", &"TitleLabel")
	_card.name = "CutsceneCard"
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(_card))
	_card.offset_top = BAR_H
	_card.offset_bottom = -BAR_H
	_text = TypewriterLabel.new()
	_text.name = "CutsceneLine"
	_text.theme_type_variation = &"MonoLabel"
	_text.add_theme_font_size_override(&"font_size", 26)
	_text.add_theme_color_override(&"font_color", Palette.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(_fade))
	# Above the fade so it's always there to press.
	var skip := UIKit.button("SKIP  [ESC]", &"GhostButton", skip_scene, "CutsceneSkip", 40)
	skip.focus_mode = Control.FOCUS_NONE
	add_child(skip)
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -skip.get_combined_minimum_size().x - 32.0
	skip.offset_right = -32.0
	skip.offset_top = (BAR_H - 40.0) / 2.0
	skip.offset_bottom = skip.offset_top + 40.0
	var hint := UIKit.label("CLICK or SPACE: next", &"DimLabel", false, null, 15)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	hint.position = Vector2(32, (BAR_H - 20.0) / 2.0)
	resized.connect(_layout)
	_shots = StoryManager.get_cutscene(cutscene_id).get("shots", [])
	AudioManager.enter_dialogue()
	CustomerManager.set_arrivals_paused(true)
	UIManager.set_feedback_hidden(true)
	_layout()
	if _shots.is_empty():
		_close.call_deferred()
		return
	_show(0)


func _exit_tree() -> void:
	AudioManager.exit_dialogue()
	CustomerManager.set_arrivals_paused(false)
	UIManager.set_feedback_hidden(false)
	closed.emit()


func _layout() -> void:
	_laid_out = size
	_text.size = Vector2(minf(TEXT_W, size.x - 80.0), BAR_H - 16.0)
	_text.position = Vector2((size.x - _text.size.x) / 2.0, size.y - BAR_H + 8.0)
	var ps := _portrait.get_combined_minimum_size()
	_portrait.size = ps
	_portrait.position = Vector2(size.x * 0.08, size.y - BAR_H - ps.y - 12.0)
	_who.position = Vector2(_portrait.position.x, _portrait.position.y + ps.y - _who.get_combined_minimum_size().y - 4.0)


func _process(delta: float) -> void:
	# The modal host may size the player after its first shot was laid out.
	if size != _laid_out:
		_layout()
	if _busy or _done or _index < 0:
		return
	if _text.is_revealing():
		return
	_hold -= delta
	if _hold <= 0.0:
		next()


## Click, SPACE or ENTER: finish the line, or go on.
func advance() -> void:
	if _busy or _done:
		return
	if _text.is_revealing():
		_text.finish()
		_hold = maxf(_hold, 1.0)
	else:
		next()


func next() -> void:
	if _busy or _done:
		return
	if _index + 1 >= _shots.size():
		_close()
		return
	_busy = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, FADE_SEC * 0.6)
	t.tween_callback(_show.bind(_index + 1))


## ESC / SKIP: the scene ends now.
func skip_scene() -> void:
	_close()


## UIManager routes ESC to the top modal.
func on_escape() -> void:
	skip_scene()


func _show(i: int) -> void:
	_index = i
	var shot: Dictionary = _shots[i]
	if _backdrop:
		_backdrop.queue_free()
		_backdrop = null
	_backdrop = _make_backdrop(str(shot.get("backdrop", "black")))
	if _backdrop:
		_stage.add_child(UIKit.full_rect(_backdrop))
		_backdrop.resized.connect(func() -> void: _backdrop.pivot_offset = _backdrop.size / 2.0)
		_backdrop.pivot_offset = _backdrop.size / 2.0
		if not Settings.reduce_motion:
			_backdrop.scale = Vector2.ONE * DRIFT
			create_tween().tween_property(_backdrop, "scale", Vector2.ONE, 9.0).set_trans(Tween.TRANS_SINE)
	var who := StringName(str(shot.get("portrait", "")))
	_portrait.visible = who != &"" and CharacterManager.has_character(who)
	_who.visible = _portrait.visible
	if _portrait.visible:
		_portrait.set_character(who, str(shot.get("expr", "neutral")))
		_who.text = CharacterManager.get_character(who).display_name.to_upper()
	_card.text = str(shot.get("card", ""))
	_card.visible = _card.text != ""
	_text.text = str(shot.get("text", ""))
	_text.play()
	_hold = hold_for(shot)
	_layout()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, FADE_SEC)
	t.tween_callback(func() -> void: _busy = false)


## Seconds a shot stays up after its line is typed: time to read it and
## look at the picture.
static func hold_for(shot: Dictionary) -> float:
	return float(shot.get("hold", clampf(2.2 + str(shot.get("text", "")).length() * 0.035, 3.5, 7.0)))


## How long a scene runs when nobody touches it, at `cps` characters a
## second (0: lines appear at once): each shot fades in while its line
## types, holds, and fades out.
static func estimate_seconds(shots: Array, cps: float) -> float:
	var total := 0.0
	for shot: Dictionary in shots:
		var typing := str(shot.get("text", "")).length() / cps if cps > 0.0 else 0.0
		total += maxf(FADE_SEC, typing) + hold_for(shot) + FADE_SEC * 0.6
	return total


func _make_backdrop(spec: String) -> Control:
	if spec.begins_with("street:"):
		# The street at the game's pixel size, doubled: it fills the frame
		# the way it fills the street screen, instead of a small scene in a
		# big sky.
		var holder := Control.new()
		holder.name = "CutsceneStreetHolder"
		holder.clip_contents = true
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := LocationView.new()
		v.location_id = StringName(spec.trim_prefix("street:"))
		v.name = "CutsceneStreet"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.scale = Vector2(2, 2)
		holder.add_child(v)
		holder.resized.connect(func() -> void: v.size = (holder.size / 2.0).ceil())
		return holder
	var path := ""
	match spec:
		"keyart":
			path = "res://assets/sprites/ui/title_keyart.png"
		"clinic":
			path = ClinicManager.get_background_path()
	if path == "" or not ResourceLoader.exists(path):
		return null
	var r := TextureRect.new()
	r.name = "CutsceneBackdrop"
	r.texture = PixelArt.tex(path)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if spec == "clinic":
		r.material = Settings.room_material()
		# The room at this hour and season, as in the clinic.
		var h := TimeManager.tint()
		var st := TimeManager.season_tint()
		var m := Color.WHITE.lerp(Color(h.r, h.g, h.b), clampf(h.a * 1.6, 0.0, 0.6)).darkened(h.a * 0.5)
		m *= Color.WHITE.lerp(Color(st.r, st.g, st.b), clampf(st.a * 1.2, 0.0, 0.2))
		m.a = 1.0
		r.self_modulate = m
	return r


func _close() -> void:
	if _done:
		return
	_done = true
	_busy = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, FADE_SEC * 0.5)
	t.tween_callback(UIManager.close_modal)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		advance()
		get_viewport().set_input_as_handled()
