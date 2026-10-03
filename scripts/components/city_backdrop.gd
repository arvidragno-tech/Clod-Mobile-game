class_name CityBackdrop
extends Control
## Procedural pixel skyline with falling rain for the main menu.

const PIXEL := 3.0
const DROP_COUNT := 70
const DROP_SPEED := Vector2(-40.0, 520.0)
const SKYLINE_SEED := 1337
const WINDOW_COLORS: Array[Color] = [Palette.ACCENT_DIM, Palette.BRAND_DIM, Color("4a3a1a")]

var _drops: Array[Vector3] = []  # x, y, length
var _rng := RandomNumberGenerator.new()
var _buildings: Array[Rect2] = []
var _windows: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_build)
	_build()


func _build() -> void:
	_rng.seed = SKYLINE_SEED
	_buildings.clear()
	_windows.clear()
	var x := -PIXEL * 2
	while x < size.x:
		var w := _rng.randi_range(8, 18) * PIXEL
		var h := _rng.randi_range(20, 70) * PIXEL
		var rect := Rect2(x, size.y - h, w, h)
		_buildings.append(rect)
		var wy := rect.position.y + PIXEL * 3
		while wy < size.y - PIXEL * 3:
			var wx := rect.position.x + PIXEL * 2
			while wx < rect.end.x - PIXEL * 2:
				if _rng.randf() < 0.18:
					_windows.append({
						"rect": Rect2(wx, wy, PIXEL, PIXEL),
						"color": WINDOW_COLORS[_rng.randi_range(0, WINDOW_COLORS.size() - 1)],
						"phase": _rng.randf() * TAU,
					})
				wx += PIXEL * 2
			wy += PIXEL * 3
		x += w + _rng.randi_range(0, 2) * PIXEL
	_drops.clear()
	for i in DROP_COUNT:
		_drops.append(Vector3(_rng.randf() * size.x, _rng.randf() * size.y, _rng.randi_range(3, 7) * PIXEL))


func _process(delta: float) -> void:
	_time += delta
	for i in _drops.size():
		var d := _drops[i]
		d.x += DROP_SPEED.x * delta
		d.y += DROP_SPEED.y * delta
		if d.y > size.y:
			d.y = -d.z
			d.x = _rng.randf() * (size.x + 60.0)
		_drops[i] = d
	queue_redraw()


func _draw() -> void:
	# Sky gradient bands
	var bands := 6
	for i in bands:
		var t := float(i) / bands
		var c := Palette.BG_0.lerp(Color("140d1c"), t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / bands + 1), c)
	for b in _buildings:
		draw_rect(b, Color("0a0c12"))
		draw_rect(Rect2(b.position, Vector2(b.size.x, PIXEL)), Color("161b25"))
	for w in _windows:
		var flicker := 0.6 + 0.4 * sin(_time * 1.3 + float(w["phase"]))
		draw_rect(w["rect"], Color(w["color"], flicker))
	var rain := Color(Palette.ACCENT, 0.22)
	for d in _drops:
		draw_rect(Rect2(roundf(d.x / PIXEL) * PIXEL, roundf(d.y / PIXEL) * PIXEL, 1.0 * PIXEL / 2.0, d.z), rain)
