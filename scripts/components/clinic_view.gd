class_name ClinicView
extends Control
## Draws the clinic backdrop for the current facility tier at exactly
## GameConfig.ART_SCALE (HD art, cropping to fit), places the waiting customer's
## composited body sprite in front of the door, and brings the room to life
## from the generator's animation anchors (data/clinic_fx.json): blinking
## status LEDs, monitor refresh lines and ECG traces, holo shimmer, spinning
## vent fans, steam from leaking pipes, sparking wires, drips, plus dust in
## the lamp light, a flickering bulb and the customer breathing.
## Everything is drawn in whole art pixels; Reduce Motion keeps it calm.

signal customer_tapped()
## A room prop was clicked (PC: the clinic is an interactive room).
signal hotspot_clicked(id: StringName)

## Clickable props (art px in the 600x336 HD room) -> workstation section.
const HOTSPOTS := [
	{"id": &"database", "rect": Rect2(117, 129, 54, 51), "label": "DIAGNOSTICS TERMINAL · cyberware database", "min_tier": 0},
	{"id": &"upgrades", "rect": Rect2(240, 156, 120, 87), "label": "OPERATING TABLE · facility upgrades", "min_tier": 0},
	{"id": &"inventory", "rect": Rect2(372, 150, 114, 93), "label": "STORAGE BENCH · inventory", "min_tier": 0},
	{"id": &"supply", "rect": Rect2(498, 78, 54, 165), "label": "SUPPLY CABINET · buy tools and implants", "min_tier": 0},
	{"id": &"dossier", "rect": Rect2(555, 111, 42, 132), "label": "RECORDS SERVER · journal", "min_tier": 2},
	{"id": &"wall", "rect": Rect2(348, 63, 114, 51), "label": "THE WALL · the clinic's memory", "min_tier": 0},
]

## Point (in background pixels) where the customer's feet stand.
const CUSTOMER_FOOT := Vector2(42, 248)
## 0 = keep top edge, 1 = keep bottom edge when cropping vertically.
const VERTICAL_FOCUS := 0.35
const DUST_COUNT := 26
const BUBBLE_BOB_PX := 2.0

var _background: Texture2D
var _scale: float = 2.0
var _offset: Vector2 = Vector2.ZERO
var _customer_tex: Texture2D
var _has_customer: bool = false
var _customer_alpha: float = 1.0
var _bubble: Label
var _time: float = 0.0
var _flicker: float = 0.0
var _next_flicker: float = 2.0
var _dust: Array[Vector3] = []
## Detail zoom: double-click or wheel doubles the (integer) pixel scale around the
## clicked point; drag pans while zoomed; double-click, wheel down or right-click resets.
var zoomed: bool = false
var _zoom_focus := Vector2(135, 180)  # art px kept centred when zoomed
var _last_tap_ms: int = -1000
var _last_tap_pos := Vector2.ZERO
var _panning: bool = false
var _hot: int = -1
const DOUBLE_TAP_MS := 350
var _fx: Array = []
var _puffs: Array[Vector4] = []  # x, y, age, life (steam)
var _sparks: Array[Vector4] = []  # x, y, vy, life
var _spark_timer: float = 3.0
var _drip_t: float = 0.0
## The season in the room (TimeManager calendar): drip period, steam and
## dust multipliers, refreshed each morning.
var _room_season := {"drip": 1.0, "steam": 1.0, "dust": 1.0}

const FX_COLORS := {
	"cyan": Color("2ee6c8"), "green": Color("6dff8a"), "amber": Color("ffb43d"), "red": Color("ff4d4d"),
	"magenta": Color("ff3d81"), "blue": Color("3a8cff"), "white": Color("e8fff8"), "dark": Color("4c5868"),
}
static var _fx_data: Dictionary = {}
var _overlays: Array = []  # [Texture2D, Vector2 art px]
## Waiting room: where the people on the bench stand (art px, feet).
const WAIT_FEET := [Vector2(201, 250), Vector2(228, 255), Vector2(177, 256), Vector2(252, 258)]
## The Clinic Wall: pinned notes, photos and notices on the back wall (art px).
const WALL_ORIGIN := Vector2(354, 69)
const WALL_COLS := 8
## One pin's cell on the wall texture (art px): 8 x 3 pins fill the 114x51 board.
const WALL_CELL := Vector2i(13, 16)
var _waiting_tex: Dictionary = {}  # customer id -> Texture2D
var _caption: Label
var _caption_t: float = 0.0
## The wire: a news ticker along the bottom of the room (the old CRT by the door).
var _ticker_box: Control
var _ticker: Label
const TICKER_H := 26.0
const TICKER_SPEED := 46.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bubble = UIKit.label("!", &"BigMonoLabel", false, Palette.WARN)
	_bubble.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_bubble.add_theme_constant_override(&"outline_size", 6)
	_bubble.visible = false
	add_child(_bubble)
	for i in DUST_COUNT:
		_dust.append(Vector3(randf_range(225, 375), randf_range(75, 240), randf_range(0.0, TAU)))
	_caption = UIKit.label("", &"DimLabel", true, Palette.TEXT, 15)
	_caption.name = "LifeCaption"
	_caption.add_theme_color_override(&"font_outline_color", Palette.BG_0)
	_caption.add_theme_constant_override(&"outline_size", 5)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	add_child(_caption)
	ClinicLifeManager.caption_posted.connect(show_caption)
	# The hour colours the room (cold morning, amber evening, blue night) as a
	# colour multiply on the room's own draw: no extra full-screen pass.
	EventBus.period_changed.connect(func(_p: StringName) -> void: _apply_tint())
	EventBus.time_changed.connect(func(_m: int, _p: StringName) -> void: _apply_tint())
	EventBus.day_started.connect(func(_d: int) -> void: _apply_season())
	_apply_season()
	ClinicLifeManager.wall_changed.connect(func() -> void: _wall_tex = null)
	_ticker_box = Control.new()
	_ticker_box.name = "NewsTicker"
	_ticker_box.clip_contents = true
	_ticker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ticker_box)
	_ticker = UIKit.label("", &"MonoLabel", false, Palette.WARN, 15)
	_ticker.name = "TickerText"
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker_box.add_child(_ticker)
	EventBus.news_posted.connect(func(_n: Dictionary) -> void: refresh_ticker())
	refresh_ticker()
	ClinicLifeManager.waiting_changed.connect(_refresh_waiting)
	_refresh_waiting()
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: refresh_background())
	EventBus.clinic_upgrade_installed.connect(func(_c: StringName, _l: int) -> void: refresh_background())
	resized.connect(_layout)
	material = Settings.room_material()
	refresh_background()


var _tint_applied := Color(-1, -1, -1)
var _wall_tex: ImageTexture = null
var _wall_tex_clinic: String = ""


func _apply_tint() -> void:
	var t := TimeManager.tint()
	var m := Color.WHITE.lerp(Color(t.r, t.g, t.b), clampf(t.a * 1.6, 0.0, 0.6)).darkened(t.a * 0.5)
	# The season sits under the hour, faintly: a basement only feels it.
	var st := TimeManager.season_tint()
	m *= Color.WHITE.lerp(Color(st.r, st.g, st.b), clampf(st.a * 1.2, 0.0, 0.2))
	m.a = 1.0
	if m != _tint_applied:
		_tint_applied = m
		self_modulate = m


func _apply_season() -> void:
	for k: String in _room_season:
		_room_season[k] = TimeManager.season_value("room", k, 1.0)
	_apply_tint()


## A line of clinic life at the bottom of the room, fading after a while.
func show_caption(text: String) -> void:
	if _caption == null:
		return
	_caption.text = text
	_caption_t = 7.0
	_caption.modulate.a = 1.0


func refresh_ticker() -> void:
	if _ticker == null:
		return
	var heads: Array[String] = []
	for n in WorldEventManager.latest_news(4):
		heads.append(("▲ " if bool(n.get("about_you", false)) else "") + str(n["headline"]).to_upper())
	_ticker.text = ("WIRE ▸ " + "   ///   ".join(heads)) if not heads.is_empty() else ""
	_ticker.reset_size()
	_ticker.position.x = _ticker_box.size.x


func _refresh_waiting() -> void:
	var keep := {}
	for c in ClinicLifeManager.waiting_customers():
		keep[c.id] = true
		if not _waiting_tex.has(c.id):
			var app := CharacterAppearanceManager.normalize(c.appearance)
			_waiting_tex[c.id] = CharacterArt.body_layers(app)[0] if not app.is_empty() else null
	for k: Variant in _waiting_tex.keys():
		if not keep.has(k):
			_waiting_tex.erase(k)
	queue_redraw()


func refresh_background() -> void:
	_background = PixelArt.tex(ClinicManager.get_background_path())
	if _fx_data.is_empty():
		var d: Variant = DataLoader.load_json(GameConfig.DATA_CLINIC_FX)
		_fx_data = d.get("clinics", {}) if d is Dictionary else {}
	_fx = (_fx_data.get(ClinicManager.clinic_id(), []) as Array).duplicate()
	# Installed upgrades are drawn as pre-lit overlay sprites with their own
	# animation anchors (tools/art/clinics.py).
	_overlays.clear()
	for o: Dictionary in ClinicManager.get_overlays():
		var tex := PixelArt.tex(str(o["path"]))
		if tex:
			_overlays.append([tex, Vector2(float(o["x"]), float(o["y"]))])
		_fx.append_array(o.get("fx", []))
	_puffs.clear()
	_sparks.clear()
	_layout()


## Feet sit this many body-texture pixels above the bottom of the sprite
## (3 on the 40x80 bodies; scaled with the body width).
const BODY_FOOT_PAD := 3.0
var _customer_glow: Texture2D
var _customer_app: Dictionary = {}
var _anim: Dictionary = {}


func show_customer(customer: CustomerData, animate: bool) -> void:
	_customer_app = CharacterAppearanceManager.normalize(customer.appearance)
	var layers := CharacterArt.body_layers(_customer_app) if not _customer_app.is_empty() else [null, null]
	_customer_tex = layers[0]
	_customer_glow = layers[1]
	CharacterAnimationManager.unregister(self)
	var prof: StringName = CharacterPortraitManager.PROFILE_BY_PERSONALITY.get(customer.personality, &"calm")
	if (_customer_app.get("body_acc", []) as Array).has("cigarette"):
		prof = &"smoker"
	_anim = CharacterAnimationManager.register(self, prof, not (_customer_app.get("body_cyber", []) as Array).is_empty())
	_has_customer = true
	_bubble.visible = true
	if animate:
		_customer_alpha = 0.0
		create_tween().tween_property(self, "_customer_alpha", 1.0, 0.4)
	_layout()


func hide_customer() -> void:
	CharacterAnimationManager.unregister(self)
	_has_customer = false
	_bubble.visible = false
	queue_redraw()


func get_customer_rect() -> Rect2:
	if _customer_tex == null:
		return Rect2(_offset + CUSTOMER_FOOT * _scale - Vector2(24, 96) * _scale, Vector2(48, 96) * _scale)
	var bs := body_scale(_customer_tex)
	var s := Vector2(_customer_tex.get_size()) * bs
	return Rect2(_offset + CUSTOMER_FOOT * _scale - Vector2(s.x / 2.0, s.y - _foot_pad(_customer_tex) * bs), s)


## Screen units per body-texture pixel: bodies fill BODY_ART_W art px at the
## room's scale, whatever resolution they were drawn at.
func body_scale(tex: Texture2D) -> float:
	return _scale * GameConfig.BODY_ART_W / maxf(1.0, float(tex.get_width()))


func _foot_pad(tex: Texture2D) -> float:
	return roundf(BODY_FOOT_PAD * float(tex.get_width()) / 40.0)


func _layout() -> void:
	if _background == null or size.x <= 0.0:
		return
	var img := PixelArt.scene_size(_background)
	# Always the HD world density (2 units per art px on the 1920x1080 canvas);
	# the panel frame absorbs any leftover space.
	_scale = float(GameConfig.ART_SCALE)
	if zoomed:
		_scale *= 2.0
	var drawn := img * _scale
	if zoomed:
		_offset = (size / 2.0 - _zoom_focus * _scale).round()
		_offset.x = clampf(_offset.x, size.x - drawn.x, 0.0)
		_offset.y = clampf(_offset.y, size.y - drawn.y, 0.0)
	else:
		_offset = Vector2((size.x - drawn.x) / 2.0, (size.y - drawn.y) * VERTICAL_FOCUS).round()
	queue_redraw()


func set_zoom(on: bool, at_local: Vector2 = Vector2.INF) -> void:
	if at_local != Vector2.INF:
		_zoom_focus = (at_local - _offset) / _scale
	zoomed = on
	_layout()


func _process(delta: float) -> void:
	_time += delta
	_next_flicker -= delta
	if _next_flicker <= 0.0 and Settings.lighting_quality > 0 and Settings.flashing_allowed():
		_next_flicker = randf_range(1.5, 7.0) if ClinicManager.tier <= 1 else randf_range(6.0, 14.0)
		_flicker = 0.22
	_flicker = maxf(0.0, _flicker - delta)
	if _ticker and _ticker.text != "":
		_ticker_box.position = Vector2(0, size.y - TICKER_H)
		_ticker_box.size = Vector2(size.x, TICKER_H)
		_ticker.position.y = (TICKER_H - _ticker.size.y) / 2.0
		_ticker.position.x -= delta * (TICKER_SPEED if not Settings.reduce_motion else 0.0)
		if _ticker.position.x < -_ticker.size.x:
			_ticker.position.x = size.x
		if Settings.reduce_motion:
			_ticker.position.x = 8.0
	if _caption_t > 0.0:
		_caption_t -= delta
		_caption.modulate.a = clampf(_caption_t / 1.5, 0.0, 1.0)
		_caption.custom_minimum_size.x = maxf(100.0, size.x - 40.0)
		_caption.size = Vector2(_caption.custom_minimum_size.x, _caption.get_minimum_size().y)
		_caption.position = Vector2(20, size.y - _caption.size.y - 12 - (TICKER_H if _ticker.text != "" else 0.0))
	_update_fx(delta)
	for i in _dust.size():
		var d := _dust[i]
		d.y -= delta * 4.5
		d.x += sin(_time * 0.7 + d.z) * delta * 3.0
		if d.y < 75.0:
			d.y = 240.0
		_dust[i] = d
	if _bubble.visible:
		_bubble.reset_size()
		var r := get_customer_rect()
		var bob := roundf(sin(_time * 4.0) * BUBBLE_BOB_PX) * _scale / 2.0
		_bubble.position = Vector2(r.get_center().x - _bubble.size.x / 2.0, r.position.y - _bubble.size.y + bob)
	queue_redraw()


func _draw() -> void:
	if _background == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04))
	draw_texture_rect(_background, Rect2(_offset, PixelArt.scene_size(_background) * _scale), false)
	for o: Array in _overlays:
		var t: Texture2D = o[0]
		draw_texture_rect(t, Rect2(_offset + (o[1] as Vector2) * _scale, PixelArt.scene_size(t) * _scale), false)
	_draw_fx()
	_draw_wall()
	_draw_hotspot()
	# Dust motes catching the lamp light (one art pixel each).
	var motes: int = 0 if not Settings.environment_effects else [6, 14, DUST_COUNT][Settings.effects_level()]
	for di in mini(motes, _dust.size()):
		var d := _dust[di]
		var a := (0.25 + 0.2 * sin(_time * 2.0 + d.z)) * clampf(float(_room_season["dust"]), 0.5, 1.6)
		draw_rect(Rect2((_offset + Vector2(floorf(d.x), floorf(d.y)) * _scale), Vector2.ONE * _scale), Color(1, 0.95, 0.85, a))
	_draw_waiting()
	if _has_customer and _customer_tex:
		var r := get_customer_rect()
		# Contact shadow (pixel-snapped ellipse)
		var foot := _offset + CUSTOMER_FOOT * _scale
		for k in 3:
			var w := (21 - k * 6) * _scale
			draw_rect(Rect2(foot.x - w / 2.0, foot.y - _scale + k * 0.0, w, _scale), Color(0, 0, 0, 0.25 + k * 0.15))
		_draw_customer(r)
	if zoomed:
		# Zoom badge (top-right), drawn in whole pixels.
		var badge := Rect2(size.x - 34, 6, 28, 14)
		draw_rect(badge, Color(0.02, 0.03, 0.05, 0.8))
		draw_string(get_theme_font(&"font", &"PixelLabel"), badge.position + Vector2(4, 11), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.ACCENT)
	if _ticker and _ticker.text != "":
		draw_rect(Rect2(0, size.y - TICKER_H, size.x, TICKER_H), Color(0.02, 0.02, 0.03, 0.82))
		draw_rect(Rect2(0, size.y - TICKER_H, size.x, 1), Color(1, 0.7, 0.25, 0.35))
	if _flicker > 0.0 and fmod(_flicker * 40.0, 2.0) < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))


## The people on the bench: further back, a little darker, breathing.
func _draw_waiting() -> void:
	var list := ClinicLifeManager.waiting_customers()
	var feet: Array = ClinicManager.get_tier_data().get("waiting_feet", WAIT_FEET)
	for i in mini(list.size(), feet.size()):
		var tex: Texture2D = _waiting_tex.get(list[i].id, null)
		if tex == null:
			continue
		var bs := body_scale(tex)
		var s := Vector2(tex.get_size()) * bs
		var fp: Variant = feet[i]
		var foot: Vector2 = _offset + (Vector2(float(fp[0]), float(fp[1])) if fp is Array else fp as Vector2) * _scale
		var bob := (floorf(sin(_time * 1.6 + i * 1.3) + 1.0) * 0.5) * bs if Settings.environment_effects else 0.0
		var r := Rect2(foot - Vector2(s.x / 2.0, s.y - _foot_pad(tex) * bs) + Vector2(0, -bob), s)
		draw_rect(Rect2(foot.x - 8 * _scale, foot.y - _scale, 16 * _scale, _scale), Color(0, 0, 0, 0.35))
		draw_texture_rect(tex, r, false, Color(0.62, 0.62, 0.7, 1.0))


## The Clinic Wall: pins rendered once into a small art-pixel texture
## (rebuilt when the wall or the clinic changes) and drawn with the room.
func _draw_wall() -> void:
	if ClinicLifeManager.wall.is_empty():
		return
	var wd: Dictionary = ClinicManager.get_tier_data().get("wall", {})
	var origin := Vector2(float(wd.get("x", WALL_ORIGIN.x)), float(wd.get("y", WALL_ORIGIN.y)))
	if _wall_tex == null or _wall_tex_clinic != ClinicManager.clinic_id():
		_wall_tex = _build_wall_texture(int(wd.get("cols", WALL_COLS)))
		_wall_tex_clinic = ClinicManager.clinic_id()
	var at := _offset + (origin - Vector2(1, 2)) * _scale
	draw_texture_rect(_wall_tex, Rect2(at, Vector2(_wall_tex.get_size()) * _scale), false)


func _build_wall_texture(cols: int) -> ImageTexture:
	var img := Image.create(cols * WALL_CELL.x + 4, WALL_CELL.y * 3 + 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pins := ClinicLifeManager.wall
	for i in mini(pins.size(), cols * 3):
		var p: Dictionary = pins[i]
		var cell := Vector2i((i % cols) * WALL_CELL.x, (i / cols) * WALL_CELL.y) + Vector2i((i * 7) % 3, (i * 5) % 2) + Vector2i(1, 2)
		var col := ClinicLifeManager.pin_color(str(p["kind"])).darkened(0.25)
		var card := Vector2i(10, 12)
		img.fill_rect(Rect2i(cell + Vector2i(1, 1), card), Color(0, 0, 0, 0.45))
		img.fill_rect(Rect2i(cell, card), col)
		img.fill_rect(Rect2i(cell, Vector2i(card.x, 1)), col.lightened(0.25))
		if str(p["kind"]) == "patient":
			# A tiny photo: dark frame, a face, shoulders.
			img.fill_rect(Rect2i(cell + Vector2i(1, 1), Vector2i(8, 7)), Color(0.2, 0.18, 0.22))
			img.fill_rect(Rect2i(cell + Vector2i(3, 2), Vector2i(4, 4)), Color(0.75, 0.58, 0.48))
			img.fill_rect(Rect2i(cell + Vector2i(2, 6), Vector2i(6, 2)), Color(0.32, 0.36, 0.44))
			img.fill_rect(Rect2i(cell + Vector2i(1, 9), Vector2i(7, 1)), col.darkened(0.5))
		else:
			for ln in 4:
				img.fill_rect(Rect2i(cell + Vector2i(1, 2 + ln * 2), Vector2i(8 - (ln % 2) * 3, 1)), col.darkened(0.5))
		img.fill_rect(Rect2i(cell + Vector2i(4, -1), Vector2i(2, 2)), Color(0.9, 0.2, 0.25))
	return ImageTexture.create_from_image(img)


## Body in three bands so it can breathe and look around without
## redrawing art: legs planted, torso rises 1 px on the inhale, head shifts
## 1 px with the gaze and jitters with tremor. Emissive chrome flickers.
func _draw_customer(r: Rect2) -> void:
	var tex_size := Vector2(_customer_tex.get_size())
	var inhale := float(_anim.get("breath", 0))
	var gaze := str(_anim.get("gaze", "center"))
	var head_dx := (-1.0 if gaze == "left" else (1.0 if gaze == "right" else 0.0))
	var j: Vector2i = _anim.get("jitter", Vector2i.ZERO)
	var lean := float(_anim.get("lean", 0))
	var k := tex_size.x / 40.0  # bands were laid out on the 40x80 body
	var head_h := roundf(19.0 * k)
	var leg_y := roundf(44.0 * k)
	var bs := body_scale(_customer_tex)
	var bands := [
		[Rect2(0, leg_y, tex_size.x, tex_size.y - leg_y), Vector2.ZERO],
		[Rect2(0, head_h, tex_size.x, leg_y - head_h), Vector2(j.x * 0.0 + lean, -inhale)],
		[Rect2(0, 0, tex_size.x, head_h), Vector2(head_dx + j.x + lean, -inhale)],
	]
	var tint := Color(1, 1, 1, _customer_alpha)
	var glow_tint := Color(1, 1, 1, _customer_alpha * 0.5 * float(_anim.get("glow", 1.0)) * (1.0 if Settings.glow else 0.0))
	for band: Array in bands:
		var src: Rect2 = band[0]
		var off: Vector2 = band[1]
		var dst := Rect2(r.position + (src.position + off * k) * bs, src.size * bs)
		draw_texture_rect_region(_customer_tex, dst, src, tint)
		if _customer_glow:
			draw_texture_rect_region(_customer_glow, dst, src, glow_tint)
	# Smoke curling up from a cigarette in the left hand.
	if _anim.get("action", &"") == &"smoke" and (_customer_app.get("body_acc", []) as Array).has("cigarette"):
		var t := float(_anim.get("action_t", 0.0))
		var hand := r.position + Vector2(13, 43) * k * bs
		for n in 4:
			var p := hand + Vector2(sin(t * 5.0 + n) * 1.8 + n * 0.6, -t * 21.0 - n * 4.5) * _scale
			draw_rect(Rect2(p.floor(), Vector2(_scale, _scale)), Color(0.7, 0.72, 0.78, clampf(0.4 - t * 0.3 - n * 0.06, 0.0, 1.0)))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if not mb.pressed:
			_panning = false
			return
		if _has_customer and get_customer_rect().grow(GameConfig.CLICK_SLOP).has_point(mb.position):
			customer_tapped.emit()
			accept_event()
			return
		var hot := _hotspot_at(mb.position)
		if hot >= 0 and not zoomed and not mb.double_click:
			AudioManager.play_sfx(&"click", 0.05)
			hotspot_clicked.emit(HOTSPOTS[hot]["id"])
			accept_event()
			return
		var now := Time.get_ticks_msec()
		if now - _last_tap_ms < DOUBLE_TAP_MS and mb.position.distance_to(_last_tap_pos) < 40.0:
			set_zoom(not zoomed, mb.position)
			AudioManager.play_sfx(&"servo", 0.0)
			_last_tap_ms = -1000
		else:
			_last_tap_ms = now
			_last_tap_pos = mb.position
		_panning = zoomed
		accept_event()
		return
	# Wheel zooms around the cursor, right-click resets.
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_RIGHT]:
		var want := mb.button_index == MOUSE_BUTTON_WHEEL_UP
		if want != zoomed:
			set_zoom(want, mb.position)
			AudioManager.play_sfx(&"servo", 0.0)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _panning and zoomed:
		_zoom_focus -= mm.relative / _scale
		_layout()
		accept_event()
	elif mm:
		var hot := -1 if zoomed else _hotspot_at(mm.position)
		if hot != _hot:
			_hot = hot
			tooltip_text = str(HOTSPOTS[hot]["label"]) if hot >= 0 else _base_tooltip
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hot >= 0 or (_has_customer and get_customer_rect().has_point(mm.position)) else Control.CURSOR_ARROW
			if hot >= 0:
				AudioManager.play_sfx(&"hover", 0.03)
			queue_redraw()


var _base_tooltip: String = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hot >= 0:
		_hot = -1
		tooltip_text = _base_tooltip
		queue_redraw()


## The Wall's hotspot follows where this clinic's wall space is.
func _hotspot_rect(h: Dictionary) -> Rect2:
	if h["id"] == &"wall":
		var wd: Dictionary = ClinicManager.get_tier_data().get("wall", {})
		return Rect2(float(wd.get("x", WALL_ORIGIN.x)) - 6, float(wd.get("y", WALL_ORIGIN.y)) - 6, int(wd.get("cols", WALL_COLS)) * WALL_CELL.x + 8, 51)
	return h["rect"]


func _hotspot_at(local: Vector2) -> int:
	var art := (local - _offset) / _scale
	for i in HOTSPOTS.size():
		var h: Dictionary = HOTSPOTS[i]
		if ClinicManager.tier >= int(h["min_tier"]) and _hotspot_rect(h).has_point(art):
			return i
	return -1


## Pulsing pixel brackets around the hovered prop.
func _draw_hotspot() -> void:
	if _hot < 0:
		return
	var r: Rect2 = _hotspot_rect(HOTSPOTS[_hot])
	var a := 0.6 + 0.3 * sin(_time * 6.0)
	var c := Color(Palette.ACCENT, a)
	var tl := _px(r.position)
	var br := _px(r.end)
	var l := 4.0 * _scale
	var w := _scale
	for corner: Vector2 in [tl, Vector2(br.x - w, tl.y), Vector2(tl.x, br.y - w), br - Vector2(w, w)]:
		var sx := 1.0 if corner.x <= tl.x else -1.0
		var sy := 1.0 if corner.y <= tl.y else -1.0
		draw_rect(Rect2(corner + Vector2(minf(0.0, sx * l) + (w if sx < 0 else 0.0), 0), Vector2(l, w)), c)
		draw_rect(Rect2(corner + Vector2(0, minf(0.0, sy * l) + (w if sy < 0 else 0.0)), Vector2(w, l)), c)


# --- Ambient animation ----------------------------------------------------------

func _px(p: Vector2) -> Vector2:
	return _offset + p.floor() * _scale


func _dot(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(_px(p), Vector2.ONE * _scale), c)


func _update_fx(delta: float) -> void:
	var calm := Settings.reduce_motion or not Settings.environment_effects or Settings.effects_level() == 0
	_drip_t += delta
	# Steam puffs drift up and fade.
	for e: Dictionary in _fx:
		if e["type"] == "steam" and not calm and randf() < delta * 2.5 * float(_room_season["steam"]):
			_puffs.append(Vector4(float(e["x"]) + randf_range(-1, 1), float(e["y"]), 0.0, randf_range(1.2, 2.2)))
	for i in range(_puffs.size() - 1, -1, -1):
		var p := _puffs[i]
		p.z += delta
		p.y += delta * 6.0
		p.x += sin(_time * 1.3 + i) * delta * 3.0
		if p.z >= p.w:
			_puffs.remove_at(i)
		else:
			_puffs[i] = p
	# Sparks from exposed wiring every few seconds.
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = randf_range(2.5, 7.0)
		for e: Dictionary in _fx:
			if e["type"] == "spark" and not calm:
				for k in 5:
					_sparks.append(Vector4(float(e["x"]) + randf_range(-1, 1), float(e["y"]), randf_range(-12, -4), randf_range(0.25, 0.5)))
	for i in range(_sparks.size() - 1, -1, -1):
		var s := _sparks[i]
		s.y += s.z * delta
		s.z += 90.0 * delta
		s.w -= delta
		if s.w <= 0.0:
			_sparks.remove_at(i)
		else:
			_sparks[i] = s


func _draw_fx() -> void:
	var calm := Settings.reduce_motion or not Settings.environment_effects
	for e: Dictionary in _fx:
		var pos := Vector2(float(e["x"]), float(e["y"]))
		var c: Color = FX_COLORS.get(str(e.get("color", "cyan")), Palette.ACCENT)
		match str(e["type"]):
			"led":
				var rate := float(e.get("rate", 0.5))
				var on := fmod(_time * rate + pos.x * 0.13, 1.0) < 0.7
				var w := maxi(1, int(e.get("w", 1)))
				for k in w:
					_dot(pos + Vector2(k, 0), Color(c, 0.9) if on else Color(0.03, 0.03, 0.05, 0.75))
			"laser":
				if fmod(_time * 1.7, 1.0) < 0.5:
					_dot(pos, Color(c, 0.9))
			"monitor":
				var r := Rect2(pos, Vector2(float(e["w"]), float(e["h"])))
				if not calm:
					var line := floorf(fmod(_time * 6.0, r.size.y))
					draw_rect(Rect2(_px(r.position + Vector2(0, line)), Vector2(r.size.x, 1) * _scale), Color(c, 0.18))
					if fmod(_time + pos.x, 9.0) < 0.08:
						draw_rect(Rect2(_px(r.position), r.size * _scale), Color(0, 0, 0, 0.45))
			"ecg":
				var r2 := Rect2(pos, Vector2(float(e["w"]), float(e["h"])))
				var head := fmod(_time * 8.0, r2.size.x)
				for k in 4:
					var x := fmod(head - k + r2.size.x, r2.size.x)
					var beat := int(fmod(_time * 8.0 - k, r2.size.x * 2.0)) % int(r2.size.x)
					var dy := -3.0 if beat == 5 else (2.0 if beat == 6 else 0.0)
					_dot(r2.position + Vector2(x, r2.size.y / 2.0 + dy), Color(c, 1.0 - k * 0.22))
			"holo":
				if not calm:
					var hr := Rect2(pos, Vector2(float(e["w"]), float(e["h"])))
					var y := floorf(fmod(_time * 10.0, hr.size.y))
					draw_rect(Rect2(_px(hr.position + Vector2(0, y)), Vector2(hr.size.x, 1) * _scale), Color(c, 0.22))
			"fan":
				var fr := Rect2(pos, Vector2(float(e["w"]), float(e["h"])))
				var ctr := fr.get_center()
				var ang := 0.0 if calm else _time * 7.0
				var rad := minf(fr.size.x, fr.size.y) / 2.0 - 0.5
				for blade in 3:
					var a := ang + blade * TAU / 3.0
					for t in range(1, int(rad) + 1):
						_dot(ctr + Vector2(cos(a), sin(a)) * t, Color(0.32, 0.36, 0.42, 0.9))
			"drip":
				var period := 4.5 * float(_room_season["drip"])
				var t2 := fmod(_drip_t + pos.x * 0.1, period)
				if t2 < 0.9 and not calm:
					var fall := pos.y + float(e["h"]) * pow(t2 / 0.9, 2.0)
					_dot(Vector2(pos.x, fall), Color(0.55, 0.85, 0.95, 0.7))
	for p in _puffs:
		var a2 := 0.22 * (1.0 - p.z / p.w)
		_dot(Vector2(p.x, p.y), Color(0.8, 0.85, 0.9, a2))
		_dot(Vector2(p.x + 1, p.y), Color(0.8, 0.85, 0.9, a2 * 0.6))
	for s in _sparks:
		_dot(Vector2(s.x, s.y), Color(1.0, 0.85, 0.4, clampf(s.w * 3.0, 0.0, 1.0)))
