class_name ClinicView
extends Control
## Draws the clinic backdrop for the current facility tier at exactly
## GameConfig.PIXEL_SCALE (cropping to fit), places the waiting customer's
## composited body sprite in front of the door, and brings the room to life
## from the generator's animation anchors (data/clinic_fx.json): blinking
## status LEDs, monitor refresh lines and ECG traces, holo shimmer, spinning
## vent fans, steam from leaking pipes, sparking wires, drips, plus dust in
## the lamp light, a flickering bulb and the customer breathing.
## Everything is drawn in whole art pixels; Reduce Motion keeps it calm.

signal customer_tapped()
## A room prop was clicked (PC: the clinic is an interactive room).
signal hotspot_clicked(id: StringName)

## Clickable props (art px in the 400x224 room) -> workstation section.
const HOTSPOTS := [
	{"id": &"database", "rect": Rect2(78, 86, 36, 34), "label": "DIAGNOSTICS TERMINAL · cyberware database", "min_tier": 0},
	{"id": &"upgrades", "rect": Rect2(160, 104, 80, 58), "label": "OPERATING TABLE · facility upgrades", "min_tier": 0},
	{"id": &"inventory", "rect": Rect2(248, 100, 76, 62), "label": "STORAGE BENCH · inventory", "min_tier": 0},
	{"id": &"supply", "rect": Rect2(332, 52, 36, 110), "label": "SUPPLY CABINET · buy tools and implants", "min_tier": 0},
	{"id": &"dossier", "rect": Rect2(370, 74, 28, 88), "label": "RECORDS SERVER · journal", "min_tier": 2},
]

## Point (in background pixels) where the customer's feet stand.
const CUSTOMER_FOOT := Vector2(27, 165)
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
var _zoom_focus := Vector2(90, 120)  # art px kept centred when zoomed
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

const FX_COLORS := {
	"cyan": Color("2ee6c8"), "green": Color("6dff8a"), "amber": Color("ffb43d"), "red": Color("ff4d4d"),
	"magenta": Color("ff3d81"), "blue": Color("3a8cff"), "white": Color("e8fff8"), "dark": Color("4c5868"),
}
static var _fx_data: Dictionary = {}


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
		_dust.append(Vector3(randf_range(150, 250), randf_range(50, 160), randf_range(0.0, TAU)))
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: refresh_background())
	resized.connect(_layout)
	refresh_background()


func refresh_background() -> void:
	_background = PixelArt.tex(ClinicManager.get_background_path())
	if _fx_data.is_empty():
		var d: Variant = DataLoader.load_json(GameConfig.DATA_CLINIC_FX)
		_fx_data = d.get("tiers", {}) if d is Dictionary else {}
	_fx = _fx_data.get(str(ClinicManager.tier), [])
	_puffs.clear()
	_sparks.clear()
	_layout()


func show_customer(customer: CustomerData, animate: bool) -> void:
	_customer_tex = CharacterArt.body(customer.appearance) if not customer.appearance.is_empty() else null
	_has_customer = true
	_bubble.visible = true
	if animate:
		_customer_alpha = 0.0
		create_tween().tween_property(self, "_customer_alpha", 1.0, 0.4)
	_layout()


func hide_customer() -> void:
	_has_customer = false
	_bubble.visible = false
	queue_redraw()


func get_customer_rect() -> Rect2:
	if _customer_tex == null:
		return Rect2(_offset + CUSTOMER_FOOT * _scale - Vector2(16, 64) * _scale, Vector2(32, 64) * _scale)
	var s := Vector2(_customer_tex.get_size()) * _scale
	return Rect2(_offset + CUSTOMER_FOOT * _scale - Vector2(s.x / 2.0, s.y), s)


func _layout() -> void:
	if _background == null or size.x <= 0.0:
		return
	var img := Vector2(_background.get_size())
	# Always the global pixel density (3x on the 1920x1080 canvas) so the room
	# matches every other sprite; the panel frame absorbs any leftover space.
	_scale = float(GameConfig.PIXEL_SCALE)
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
	if _next_flicker <= 0.0:
		_next_flicker = randf_range(1.5, 7.0) if ClinicManager.tier <= 1 else randf_range(6.0, 14.0)
		_flicker = 0.22
	_flicker = maxf(0.0, _flicker - delta)
	_update_fx(delta)
	for i in _dust.size():
		var d := _dust[i]
		d.y -= delta * 3.0
		d.x += sin(_time * 0.7 + d.z) * delta * 2.0
		if d.y < 50.0:
			d.y = 160.0
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
	draw_texture_rect(_background, Rect2(_offset, Vector2(_background.get_size()) * _scale), false)
	_draw_fx()
	_draw_hotspot()
	# Dust motes catching the lamp light (one art pixel each).
	for d in _dust:
		var a := 0.25 + 0.2 * sin(_time * 2.0 + d.z)
		draw_rect(Rect2((_offset + Vector2(floorf(d.x), floorf(d.y)) * _scale), Vector2.ONE * _scale), Color(1, 0.95, 0.85, a))
	if _has_customer and _customer_tex:
		var r := get_customer_rect()
		# Contact shadow (pixel-snapped ellipse)
		var foot := _offset + CUSTOMER_FOOT * _scale
		for k in 3:
			var w := (14 - k * 4) * _scale
			draw_rect(Rect2(foot.x - w / 2.0, foot.y - _scale + k * 0.0, w, _scale), Color(0, 0, 0, 0.25 + k * 0.15))
		# Breathing: the upper body rises one art pixel on each inhale.
		var inhale := 0.0 if Settings.reduce_motion else (1.0 if fmod(_time, 3.2) < 1.4 else 0.0)
		var split := 0.62  # legs stay planted below this fraction
		var tex_size := Vector2(_customer_tex.get_size())
		var top_src := Rect2(0, 0, tex_size.x, floorf(tex_size.y * split))
		var bot_src := Rect2(0, top_src.size.y, tex_size.x, tex_size.y - top_src.size.y)
		var tint := Color(1, 1, 1, _customer_alpha)
		draw_texture_rect_region(_customer_tex, Rect2(r.position + Vector2(0, bot_src.position.y * _scale), bot_src.size * _scale), bot_src, tint)
		draw_texture_rect_region(_customer_tex, Rect2(r.position - Vector2(0, inhale * _scale), top_src.size * _scale), top_src, tint)
	if zoomed:
		# Zoom badge (top-right), drawn in whole pixels.
		var badge := Rect2(size.x - 34, 6, 28, 14)
		draw_rect(badge, Color(0.02, 0.03, 0.05, 0.8))
		draw_string(get_theme_font(&"font", &"PixelLabel"), badge.position + Vector2(4, 11), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.ACCENT)
	if _flicker > 0.0 and fmod(_flicker * 40.0, 2.0) < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))


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


func _hotspot_at(local: Vector2) -> int:
	var art := (local - _offset) / _scale
	for i in HOTSPOTS.size():
		var h: Dictionary = HOTSPOTS[i]
		if ClinicManager.tier >= int(h["min_tier"]) and (h["rect"] as Rect2).has_point(art):
			return i
	return -1


## Pulsing pixel brackets around the hovered prop.
func _draw_hotspot() -> void:
	if _hot < 0:
		return
	var r: Rect2 = HOTSPOTS[_hot]["rect"]
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
	var calm := Settings.reduce_motion
	_drip_t += delta
	# Steam puffs drift up and fade.
	for e: Dictionary in _fx:
		if e["type"] == "steam" and not calm and randf() < delta * 2.5:
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
	var calm := Settings.reduce_motion
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
				var period := 4.5
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
