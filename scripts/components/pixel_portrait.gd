class_name PixelPortrait
extends Control
## A character portrait at exact game pixel density on a lit monitor
## backdrop. `crop` shows only part of the 64x64 portrait (e.g. the face
## for compact cards) without changing pixel size.

@export var crop: Rect2i = Rect2i(0, 0, 64, 64)
@export var accent: Color = Palette.ACCENT

var appearance: Dictionary = {}
var _texture: Texture2D
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(crop.size) * GameConfig.PIXEL_SCALE + Vector2(4, 4)


func set_appearance(app: Dictionary, p_accent: Color = Palette.ACCENT) -> void:
	appearance = app
	accent = p_accent
	_texture = CharacterArt.portrait(app) if not app.is_empty() else null
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := float(GameConfig.PIXEL_SCALE)
	var area := Vector2(crop.size) * s
	var origin := ((size - area) / 2.0).floor()
	var r := Rect2(origin, area)
	# Monitor backdrop: dark gradient bands + accent glow from the right.
	var bands := 6
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t, r.size.x, r.size.y / bands + 1), Palette.BG_1.lerp(Color(accent, 1).darkened(0.82), t * 0.6))
	draw_rect(Rect2(r.end.x - s * 6, r.position.y, s * 6, r.size.y), Color(accent, 0.07))
	if _texture:
		draw_texture_rect_region(_texture, r, Rect2(crop))
	# Scanlines (every other art pixel row) + sweeping refresh line
	var y := r.position.y
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color(0, 0, 0, 0.12))
		y += s * 2
	var sweep := r.position.y + fmod(_time * 30.0, r.size.y)
	draw_rect(Rect2(r.position.x, floorf(sweep / s) * s, r.size.x, s), Color(accent, 0.06))
	# Frame with corner brackets
	draw_rect(r.grow(2), Palette.LINE, false, 2.0)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_rect(Rect2(corner + Vector2(-2 if sx > 0 else -6, -2 if sy > 0 else 0), Vector2(8, 2)), accent)
		draw_rect(Rect2(corner + Vector2(-2 if sx > 0 else 0, -2 if sy > 0 else -6), Vector2(2, 8)), accent)
