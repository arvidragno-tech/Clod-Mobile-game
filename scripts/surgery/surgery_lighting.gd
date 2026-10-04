class_name SurgeryLighting
extends Control
## Additive pixel lighting over the operating field (inside the pixel
## SubViewport): the surgical lamp pool, cyan monitor spill, and a rotating
## red emergency beacon during complications. Light falloff is banded and
## Bayer-dithered so it reads as pixel art, not a smooth blur.

const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
const BANDS := 5

var emergency: bool = false
var _pool: ImageTexture
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_pool = _make_pool(64)


static func _make_pool(r: int) -> ImageTexture:
	var size := r * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() / r
			if d >= 1.0:
				continue
			var i := pow(1.0 - d, 1.6)
			var th: float = (BAYER[y & 3][x & 3] + 0.5) / 16.0
			var q := floorf(i * BANDS + th) / BANDS
			if q > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, q))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var c := (size / 2.0).floor()
	# Surgical lamp: warm-white pool on the field, slow subtle breathing.
	var lamp := 0.10 + 0.01 * sin(_time * 0.8)
	_light(c + Vector2(0, -6), 96.0, Color(0.9, 1.0, 0.97, lamp))
	# Monitor spill from the right edge.
	_light(Vector2(size.x + 8, size.y * 0.3), 70.0, Color(0.18, 0.9, 0.78, 0.07))
	if emergency:
		# Rotating beacon: a red pool sweeping around the room edge.
		var a := _time * 4.0
		var p := c + Vector2(cos(a), sin(a)) * Vector2(size.x * 0.55, size.y * 0.5)
		var pulse := 0.16 + 0.08 * sin(_time * 12.0)
		_light(p, 90.0, Color(1.0, 0.15, 0.2, pulse))
		_light(c, 140.0, Color(1.0, 0.1, 0.15, 0.04))


func _light(center: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(_pool, Rect2((center - Vector2.ONE * radius).floor(), Vector2.ONE * radius * 2.0), false, color)
