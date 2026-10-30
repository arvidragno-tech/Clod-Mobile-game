class_name CyberwareIcon
extends Control
## A cyberware sprite at game pixel density that feels powered on:
## emissive pixels pulse, a scan glint sweeps across the metal, and each
## category has its own tell: optics refocus (aperture closes briefly),
## neural / spine chips flicker with data, limbs flash a servo glint.
## The overlay is computed once from the sprite (no per-frame allocations).

var category: StringName = &""
var _tex: Texture2D
var _glow: PackedVector2Array = PackedVector2Array()
var _glow_col: PackedColorArray = PackedColorArray()
var _solid: PackedVector2Array = PackedVector2Array()
var _center := Vector2(24, 24)
var _time: float = 0.0
var _art: int = 32
var _scale: float = GameConfig.PIXEL_SCALE


static func make(item: CyberwareData) -> CyberwareIcon:
	var c := CyberwareIcon.new()
	c.setup(item.icon_path, item.category)
	return c


func setup(path: String, p_category: StringName) -> void:
	category = p_category
	_tex = PixelArt.tex(path)
	_scale = float(PixelArt.density(path))
	_time = randf() * 10.0
	if _tex == null:
		return
	var img := _tex.get_image()
	_art = img.get_width()
	custom_minimum_size = Vector2(img.get_size()) * PixelArt.density(path)
	var sum := Vector2.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			_solid.append(Vector2(x, y))
			sum += Vector2(x, y)
			n += 1
			# Emissive = bright and saturated (LEDs, lenses, cores).
			if c.v > 0.75 and c.s > 0.45:
				_glow.append(Vector2(x, y))
				_glow_col.append(c)
	if n > 0:
		_center = (sum / n).round()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_time += delta
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var s := _scale
	var origin := ((size - Vector2(_art, _art) * s) / 2.0).floor()
	draw_texture_rect(_tex, Rect2(origin, Vector2(_art, _art) * s), false)
	if Settings.reduce_motion:
		return
	# Emissive pulse.
	var pulse := 0.5 + 0.5 * sin(_time * (5.0 if category in [&"neural", &"spine"] else 2.4))
	for i in _glow.size():
		var c := _glow_col[i]
		if category in [&"neural", &"spine"] and (int(_time * 12.0) + i) % 7 == 0:
			continue  # data flicker: a pixel drops out
		draw_rect(Rect2(origin + _glow[i] * s, Vector2(s, s)), Color(c.lightened(0.4), 0.35 * pulse))
	# Scan glint: a diagonal band sweeping every few seconds.
	var period := 3.2 if category != &"arms" else 2.2
	var g := fmod(_time, period) / period * (_art * 2.5) - _art * 0.5
	for p in _solid:
		var d := absf((p.x + p.y) - g)
		if d < 1.0:
			draw_rect(Rect2(origin + p * s, Vector2(s, s)), Color(1, 1, 1, 0.28))
	# Optics refocus: the aperture closes for a moment.
	if category == &"eyes" and fmod(_time, 4.0) < 0.18:
		draw_rect(Rect2(origin + (_center - Vector2(1, 1)) * s, Vector2(3, 3) * s), Color(0.02, 0.03, 0.05, 0.85))
