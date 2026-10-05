class_name CityMapView
extends Control
## The Caldera map (320x180 art at the global pixel density) with district
## markers: labels, lock state, your clinics, the active practice and the
## selected district; and the places you know (LocationManager) with their
## state colour and where you are. Hover highlights; click selects.

signal district_clicked(id: StringName)
signal location_clicked(id: StringName)

const TYPE_COLORS := {
	"clinic": Color("5ad6a0"), "night_market": Color("e0b040"), "black_market": Color("c04ad6"), "bar": Color("e07a3a"),
	"industrial": Color("d0603a"), "corporate": Color("8ac8ff"), "residential": Color("b8b0a0"), "transit": Color("6ad0d0"),
	"restricted": Color("ff4a5a"),
}

const ART := Vector2(320, 180)

var selected: StringName = &""
var selected_location: StringName = &""
var _tex: Texture2D
var _hover: StringName = &""
var _hover_loc: StringName = &""
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


## Marker of a known place (art px).
func loc_pos(id: StringName) -> Vector2:
	var p := (LocationManager.map_pos(id) * ART).floor()
	if id == LocationManager.CLINIC:
		p += Vector2(0, 9)
	return p


func location_at(local: Vector2) -> StringName:
	var art := local / _s()
	var best: StringName = &""
	var bd := 6.0
	for id in LocationManager.known_locations():
		var d := art.distance_to(loc_pos(id))
		if d < bd:
			bd = d
			best = id
	return best


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var hl := location_at(mm.position)
		var h := district_at(mm.position) if hl == &"" else &""
		if h != _hover or hl != _hover_loc:
			_hover = h
			_hover_loc = hl
			if hl != &"":
				tooltip_text = "%s · %s · %s" % [LocationManager.location_name(hl), LocationManager.type_label(hl), WorldSimulationManager.state_label(hl)]
			else:
				tooltip_text = WorldManager.district_name(h) if h != &"" else ""
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != &"" or hl != &"" else Control.CURSOR_ARROW
			if h != &"" or hl != &"":
				AudioManager.play_sfx(&"hover", 0.03)
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var l := location_at(mb.position)
		if l != &"":
			AudioManager.play_sfx(&"click", 0.05)
			location_clicked.emit(l)
			accept_event()
			return
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
	_draw_locations(font)
	draw_rect(Rect2(Vector2.ZERO, ART * s), Palette.LINE, false, 2.0)


## Known places: a small square in the type's colour, a ring in the state's
## colour, a dashed line to where you are, and YOU pulsing on your spot.
func _draw_locations(font: Font) -> void:
	var s := _s()
	var here := LocationManager.player_location
	var hp := loc_pos(here) * s
	for id in LocationManager.known_locations():
		var p := loc_pos(id) * s
		var col: Color = TYPE_COLORS.get(LocationManager.type_of(id), Palette.TEXT)
		var open := LocationManager.access_block(id) == ""
		if not open:
			col = Color(col, 0.45)
		if id == selected_location and id != here:
			_dashed(hp, p, Palette.WARN)
		var r := Rect2(p - Vector2(2, 2) * s, Vector2(4, 4) * s)
		draw_rect(r.grow(s * 0.67), Color(0.02, 0.02, 0.03, 0.9))
		draw_rect(r, col)
		if (WorldSimulationManager.has_flag(id, &"event") or WorldSimulationManager.has_flag(id, &"lead")) and fmod(_time, 1.0) < 0.6:
			draw_rect(r.grow(s * 1.5), Palette.WARN, false, s * 0.67)
		if id == selected_location or id == _hover_loc:
			draw_rect(r.grow(s * 2.5), Palette.TEXT if id == _hover_loc else Palette.WARN, false, s * 0.67)
			var label := LocationManager.location_name(id).to_upper()
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var lp := p + Vector2(-w / 2.0, 6 * s + 12)
			lp.x = clampf(lp.x, 8.0, ART.x * s - w - 8.0)
			draw_rect(Rect2(lp + Vector2(-4, -14), Vector2(w + 8, 19)), Color(0.02, 0.02, 0.04, 0.85))
			draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	# You.
	var k := fmod(_time, 1.2) / 1.2
	draw_arc(hp, (3.0 + k * 5.0) * s, 0, TAU, 20, Color(Palette.OK, 0.8 * (1.0 - k)), s * 0.67)
	draw_string(font, hp + Vector2(4 * s, -3 * s), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.OK)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var n := maxi(1, int(a.distance_to(b) / (_s() * 4.0)))
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), Color(col, 0.8), _s() * 0.67)
