class_name CityMapView
extends Control
## The Caldera map (320x180 art at the global pixel density) with district
## markers: labels, lock state, your clinics, the active practice and the
## selected district. Hover highlights; click selects.

signal district_clicked(id: StringName)

const ART := Vector2(320, 180)

var selected: StringName = &""
var _tex: Texture2D
var _hover: StringName = &""
var _time: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tex = PixelArt.tex("res://assets/sprites/ui/city_map.png")
	custom_minimum_size = ART * GameConfig.PIXEL_SCALE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _s() -> float:
	return float(GameConfig.PIXEL_SCALE)


func _pos(id: StringName) -> Vector2:
	var m: Array = WorldManager.get_district(id).get("map", [0.5, 0.5])
	return (Vector2(float(m[0]), float(m[1])) * ART).floor()


func district_at(local: Vector2) -> StringName:
	var art := local / _s()
	var best: StringName = &""
	var bd := 26.0
	for id: StringName in WorldManager.order:
		var d := art.distance_to(_pos(id))
		if d < bd:
			bd = d
			best = id
	return best


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var h := district_at(mm.position)
		if h != _hover:
			_hover = h
			tooltip_text = WorldManager.district_name(h) if h != &"" else ""
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != &"" else Control.CURSOR_ARROW
			if h != &"":
				AudioManager.play_sfx(&"hover", 0.03)
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var id := district_at(mb.position)
		if id != &"":
			AudioManager.play_sfx(&"click", 0.05)
			district_clicked.emit(id)
			accept_event()


func _draw() -> void:
	var s := _s()
	if _tex:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, ART * s), false)
	var font := get_theme_font(&"font", &"PixelLabel")
	var current := WorldManager.current_district_id()
	for id: StringName in WorldManager.order:
		var p := _pos(id) * s
		var d := WorldManager.get_district(id)
		var unlocked := WorldManager.is_district_unlocked(id)
		var col := Palette.ACCENT if id == current else (Palette.TEXT if unlocked else Palette.TEXT_DIM)
		# Marker: a pixel diamond; pulsing ring on the active practice.
		var r := 3.0 * s
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(0.02, 0.02, 0.03, 0.9))
		draw_polyline(pts + PackedVector2Array([pts[0]]), col, s * 0.67)
		if id == current:
			var k := fmod(_time, 1.6) / 1.6
			draw_arc(p, (4.0 + k * 6.0) * s, 0, TAU, 20, Color(Palette.ACCENT, 0.6 * (1.0 - k)), s * 0.67)
		if id == selected or id == _hover:
			draw_arc(p, 7.0 * s, 0, TAU, 24, Color(Palette.WARN if id == selected else Palette.TEXT, 0.9), s * 0.67)
		# Owned clinics in this district: small squares under the marker.
		var n := 0
		for i in ClinicManager.owned:
			if StringName(str(ClinicManager.get_tier_data(i).get("district", ""))) == id:
				draw_rect(Rect2(p + Vector2((-2 + n * 3) * s, 5 * s), Vector2(2, 2) * s), Palette.OK)
				n += 1
		var label := str(d.get("name", id)).to_upper()
		if not unlocked:
			label += "  [LOCKED]"
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var lp := p + Vector2(-w / 2.0, -6 * s)
		lp.x = clampf(lp.x, 8.0, ART.x * s - w - 8.0)
		draw_rect(Rect2(lp + Vector2(-4, -15), Vector2(w + 8, 20)), Color(0.02, 0.02, 0.04, 0.78))
		draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	draw_rect(Rect2(Vector2.ZERO, ART * s), Palette.LINE, false, 2.0)
