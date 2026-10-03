class_name ScanView
extends Control
## Holographic body scan. Tap a region to analyse it; emits region_scanned
## when the sweep finishes. Hit areas are enlarged to comfortable touch size
## and resolved to the nearest region centre.

signal region_scanned(region_id: StringName)

const BODY := preload("res://assets/sprites/surgery/scan_body.png")
## Region rects in scan_body.png pixels.
const REGIONS := {
	&"head": Rect2(16, 1, 16, 19),
	&"neck": Rect2(18, 18, 12, 8),
	&"spine": Rect2(18, 27, 12, 28),
}
const REGION_LABELS := {&"head": "HEAD", &"neck": "PORT", &"spine": "SPINE"}
const SCAN_TIME := 0.7
const PADDING := 8.0

var _scanned: Dictionary = {}
var _scanning: StringName = &""
var _scan_t: float = 0.0
var _time: float = 0.0
var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	_scale = maxf(floorf(minf(avail.x / img.x, avail.y / img.y) * 2.0) / 2.0, 0.5)
	_origin = ((size - img * _scale) / 2.0).round()
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
	var max_dist := maxf(GameConfig.MIN_TOUCH, 40.0 * _scale / 2.0)
	if best != &"" and best_dist <= max_dist and not _scanned.has(best):
		_scanning = best
		_scan_t = 0.0
		AudioManager.play_sfx(&"tool")
		accept_event()


func _draw() -> void:
	# Grid backdrop
	var grid_color := Color(Palette.ACCENT_DIM, 0.12)
	var step := 4.0 * _scale
	var x := fmod(_origin.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
		x += step
	var y := fmod(_origin.y, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)
		y += step
	# Body
	var flicker := 0.85 + 0.15 * sin(_time * 9.0)
	draw_texture_rect(BODY, Rect2(_origin, Vector2(BODY.get_size()) * _scale), false, Color(1, 1, 1, flicker))
	# Idle sweep line
	var sweep_y := _origin.y + fmod(_time * 40.0, BODY.get_size().y) * _scale
	draw_rect(Rect2(_origin.x, sweep_y, BODY.get_size().x * _scale, _scale), Color(Palette.ACCENT, 0.25))
	# Regions
	var font := get_theme_font(&"font", &"SubHeaderLabel")
	for region: StringName in REGIONS:
		var r: Rect2 = REGIONS[region]
		var rect := Rect2(_origin + r.position * _scale, r.size * _scale).grow(2.0)
		var color := Palette.ACCENT if _scanned.has(region) else Palette.WARN
		if not _scanned.has(region) and _scanning != region:
			color.a = 0.55 + 0.45 * sin(_time * 5.0)
		if _scanned.has(region):
			draw_rect(rect, Color(Palette.ACCENT, 0.18))
		if _scanning == region:
			var sy := rect.position.y + rect.size.y * _scan_t
			draw_rect(Rect2(rect.position.x, sy - 1.0, rect.size.x, 3.0), Palette.ACCENT)
		_draw_brackets(rect, color)
		var label_pos := Vector2(rect.end.x + 6.0, rect.get_center().y + 4.0)
		draw_string(font, label_pos, REGION_LABELS[region], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_brackets(rect: Rect2, color: Color) -> void:
	var l := minf(8.0, rect.size.x / 3.0)
	var w := 2.0
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var sx := 1.0 if corner.x == rect.position.x else -1.0
		var sy := 1.0 if corner.y == rect.position.y else -1.0
		draw_rect(Rect2(corner.x - (w if sx < 0 else 0.0), corner.y - (w if sy < 0 else 0.0), l * sx, w).abs(), color)
		draw_rect(Rect2(corner.x - (w if sx < 0 else 0.0), corner.y - (w if sy < 0 else 0.0), w, l * sy).abs(), color)
