class_name ScanView
extends Control
## Holographic body scan at game pixel density. Tap a region to analyse it;
## emits region_scanned when the sweep finishes. Hit areas are enlarged to
## comfortable touch size and resolved to the nearest region centre.

signal region_scanned(region_id: StringName)

const BODY := preload("res://assets/sprites/surgery/scan_hologram.png")
## Region rects in scan_hologram.png pixels.
const REGIONS := {
	&"head": Rect2(22, 1, 16, 19),
	&"neck": Rect2(25, 19, 10, 7),
	&"chest": Rect2(18, 27, 24, 24),
	&"arms": Rect2(4, 30, 10, 36),
	&"legs": Rect2(19, 70, 22, 46),
}
const REGION_LABELS := {&"head": "HEAD", &"neck": "SPINE", &"chest": "TORSO", &"arms": "ARMS", &"legs": "LEGS"}
const SCAN_TIME := 0.7
const PADDING := 6.0

var highlight_region: StringName = &""
var _scanned: Dictionary = {}
var _scanning: StringName = &""
var _scan_t: float = 0.0
var _time: float = 0.0
var _scale: float = 2.0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	_layout()


func is_scanned(region: StringName) -> bool:
	return _scanned.has(region)


func get_scanned_count() -> int:
	return _scanned.size()


func is_busy() -> bool:
	return _scanning != &""


## Region centre in local coordinates (used by tests / tutorial hints).
func get_region_center(region: StringName) -> Vector2:
	var r: Rect2 = REGIONS[region]
	return _origin + r.get_center() * _scale


func _layout() -> void:
	var img := Vector2(BODY.get_size())
	var avail := size - Vector2(PADDING, PADDING) * 2.0
	# Prefer the game's pixel density; drop to 1x only on very small screens.
	_scale = float(GameConfig.PIXEL_SCALE) if avail.y >= img.y * GameConfig.PIXEL_SCALE else 1.0
	_origin = ((size - img * _scale) / 2.0).floor()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _scanning != &"":
		_scan_t += delta / SCAN_TIME
		if _scan_t >= 1.0:
			var done := _scanning
			_scanning = &""
			_scanned[done] = true
			region_scanned.emit(done)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or is_busy():
		return
	var best: StringName = &""
	var best_dist := INF
	for region: StringName in REGIONS:
		var d := mb.position.distance_to(get_region_center(region))
		if d < best_dist:
			best_dist = d
			best = region
	if best != &"" and best_dist <= GameConfig.MIN_CONTROL and not _scanned.has(best):
		_scanning = best
		_scan_t = 0.0
		AudioManager.play_sfx(&"tool")
		accept_event()


func _draw() -> void:
	var s := _scale
	var grid_color := Color(Palette.ACCENT_DIM, 0.12)
	var step := 4.0 * s
	var x := fmod(_origin.x, step)
	while x < size.x:
		draw_rect(Rect2(x, 0, 1, size.y), grid_color)
		x += step
	var y := fmod(_origin.y, step)
	while y < size.y:
		draw_rect(Rect2(0, y, size.x, 1), grid_color)
		y += step
	var flicker := 0.85 + 0.15 * sin(_time * 9.0)
	draw_texture_rect(BODY, Rect2(_origin, Vector2(BODY.get_size()) * s), false, Color(1, 1, 1, flicker))
	var sweep_y := _origin.y + floorf(fmod(_time * 30.0, BODY.get_size().y)) * s
	draw_rect(Rect2(_origin.x, sweep_y, BODY.get_size().x * s, s), Color(Palette.ACCENT, 0.25))
	var font := get_theme_font(&"font", &"PixelLabel")
	for region: StringName in REGIONS:
		var r: Rect2 = REGIONS[region]
		var rect := Rect2(_origin + r.position * s, r.size * s).grow(s)
		var color := Palette.ACCENT if _scanned.has(region) else Palette.WARN
		if region == highlight_region:
			color = Palette.BRAND
		if not _scanned.has(region) and _scanning != region:
			color.a = 0.55 + 0.45 * sin(_time * 5.0)
		if _scanned.has(region):
			draw_rect(rect, Color(Palette.ACCENT, 0.15))
		if _scanning == region:
			var sy := rect.position.y + floorf(rect.size.y * _scan_t / s) * s
			draw_rect(Rect2(rect.position.x, sy, rect.size.x, s), Palette.ACCENT)
		_draw_brackets(rect, color, s)
		var label_pos := Vector2(rect.end.x + 2 * s, rect.get_center().y + 4)
		if region == &"arms":
			label_pos = Vector2(rect.position.x, rect.end.y + 10)
		draw_string(font, label_pos.floor(), REGION_LABELS[region], HORIZONTAL_ALIGNMENT_LEFT, -1, 8 * int(s), color)


func _draw_brackets(rect: Rect2, color: Color, s: float) -> void:
	var l := minf(4.0 * s, rect.size.x / 3.0)
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var sx := 1.0 if corner.x == rect.position.x else -1.0
		var sy := 1.0 if corner.y == rect.position.y else -1.0
		draw_rect(Rect2(corner.x - (s if sx < 0 else 0.0), corner.y - (s if sy < 0 else 0.0), l * sx, s).abs(), color)
		draw_rect(Rect2(corner.x - (s if sx < 0 else 0.0), corner.y - (s if sy < 0 else 0.0), s, l * sy).abs(), color)
