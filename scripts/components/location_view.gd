class_name LocationView
extends Control
## The street-level view of a place: the place's HD street scene
## (assets/sprites/streets/<id>_night|day.png, tools/art/streets_hd.py) with
## the moving parts drawn on top in whole art pixels. Without a scene it
## falls back to drawing from the district's palette and the place's kind: a skyline,
## the place's own shapes (stalls, tunnel, stacks, towers, fence...), lit
## windows by hour and activity, people walking past (more when it's busy),
## police lights when the police are there, the season's weather (rain,
## sleet, snow, falling leaves or heat haze; TimeManager.weather, heavier in
## the lower city), and the hour's and the season's tint. Seeded by the place,
## so it's always the same street.

var location_id: StringName = &""
var _time: float = 0.0
var _seed: int = 0
var _pal: Array[Color] = []
var _buildings: Array[Rect2] = []
var _walkers: Array[Vector3] = []  # x, speed, kind
var _drops: Array[Vector2] = []
## Particle kind per drop (index into WEATHER_KINDS), and today's weather.
var _drop_kind: PackedByteArray = PackedByteArray()
var _weather: Dictionary = {}
const WEATHER_KINDS := ["rain", "sleet", "snow", "leaves"]
const WEATHER_MAX_DROPS := 70
## Street-scene ground line (art px from the top of the scene texture).
const SCENE_GROUND := 124


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	material = Settings.room_material()
	setup(location_id)


func setup(id: StringName) -> void:
	location_id = id
	_seed = hash(String(id))
	_pal.clear()
	var hexes: Array = WorldManager.get_district(LocationManager.district_of(id)).get("palette", ["202028", "404050", "604030", "c0a040"])
	for h: Variant in hexes:
		_pal.append(Color(str(h)))
	while _pal.size() < 4:
		_pal.append(Color("808080"))
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_buildings.clear()
	var x := -4.0
	while x < 620.0:
		var w := rng.randf_range(14, 34)
		_buildings.append(Rect2(x, rng.randf_range(10, 52), w, 0))
		x += w + rng.randf_range(-2, 3)
	_walkers.clear()
	var act := int(WorldSimulationManager.state(id)["activity"]) if id != &"" else 1
	for i in act * 4 + 1:
		_walkers.append(Vector3(rng.randf_range(0, 600), rng.randf_range(6, 16) * (1 if rng.randf() < 0.5 else -1), rng.randi() % 3))
	_drops.clear()
	_drop_kind.clear()
	_weather = TimeManager.weather()
	var n := int(round(WEATHER_MAX_DROPS * float(_weather["density"]) * (1.0 if _lower_city() else 0.6)))
	for i in n:
		var kind := str(_weather["kind"])
		if rng.randf() < float(_weather["mix"]):
			kind = str(_weather["next"])
		elif str(_weather["second"]) != "" and rng.randf() < 0.2:
			kind = str(_weather["second"])
		var k := WEATHER_KINDS.find(kind)
		if k < 0:
			continue  # haze has no particles
		if kind == "leaves" and rng.randf() < 0.6:
			continue  # a few leaves, not a blizzard of them
		_drops.append(Vector2(rng.randf_range(0, 620), rng.randf_range(0, 170)))
		_drop_kind.append(k)
	queue_redraw()


## The lower city gets the weather worst: the water runs down to it.
func _lower_city() -> bool:
	return LocationManager.district_of(location_id) in [&"undercity", &"industrial", &"market"]


## Fall speed (art px/s) of a particle kind; snow and leaves drift sideways.
func _drop_velocity(k: int, i: int) -> Vector2:
	match k:
		1:
			return Vector2(-24, 150)
		2:
			return Vector2(sin(_time * 0.9 + i) * 8.0, 22)
		3:
			return Vector2(sin(_time * 1.6 + i) * 14.0 - 6.0, 26)
	return Vector2(-18, 180)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	for i in _walkers.size():
		var w := _walkers[i]
		w.x += w.y * delta
		if w.x > _art().x + 6:
			w.x = -6
		elif w.x < -6:
			w.x = _art().x + 6
		_walkers[i] = w
	var calm := Settings.reduce_motion or not Settings.environment_effects
	for i in _drops.size():
		if calm:
			break
		var d := _drops[i]
		d += _drop_velocity(_drop_kind[i] if i < _drop_kind.size() else 0, i) * delta
		if d.y > _art().y:
			d = Vector2(fmod(d.x + 37.0 * (i + 1), _art().x + 20), -4)
		_drops[i] = d
	queue_redraw()


func _s() -> float:
	return float(GameConfig.ART_SCALE)


func _scene() -> Texture2D:
	var path := "res://assets/sprites/streets/%s_%s.png" % [String(location_id), "night" if TimeManager.is_night() else "day"]
	return PixelArt.tex(path) if ResourceLoader.exists(path) else null


func _art() -> Vector2:
	return (size / _s()).floor()


## Rect in art pixels.
func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	var s := _s()
	draw_rect(Rect2(Vector2(floorf(x), floorf(y)) * s, Vector2(maxf(1, floorf(w)), maxf(1, floorf(h))) * s), c)


func _draw() -> void:
	var a := _art()
	if a.x <= 0 or a.y <= 0:
		return
	var night := TimeManager.is_night()
	var st := WorldSimulationManager.state(location_id)
	var act := int(st["activity"])
	var flags: Array = st["flags"]
	var ground := a.y - 14
	var top := _pal[0].darkened(0.75 if night else 0.45)
	var low := _pal[1].darkened(0.4 if night else 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var scene := _scene()
	if scene:
		# The HD street, bottom-aligned and centred; sky colour above it.
		var ts := PixelArt.scene_size(scene)
		var o := Vector2(floorf((a.x - ts.x) / 2.0), a.y - ts.y)
		draw_rect(Rect2(Vector2.ZERO, size), top)
		draw_texture_rect(scene, Rect2(o * _s(), ts * _s()), false)
		ground = o.y + SCENE_GROUND + 6
	else:
		_draw_procedural(a, ground, night, act, top, low, rng)
	_draw_life(a, ground, night, flags)


func _draw_procedural(a: Vector2, ground: float, night: bool, act: int, top: Color, low: Color, rng: RandomNumberGenerator) -> void:
	# Sky: dark at the top, the district's glow at the horizon.
	for y in int(ground):
		_r(0, y, a.x, 1, top.lerp(low, float(y) / ground))
	for b in _buildings:
		if b.position.x > a.x:
			break
		var h := ground - b.position.y
		_r(b.position.x, b.position.y, b.size.x, h, _pal[0].darkened(0.5).lerp(low, 0.15))
		# Windows, lit by hour and how busy the street is.
		var lit := 0.12 + 0.12 * act + (0.25 if night else 0.0)
		var wy := b.position.y + 3
		while wy < ground - 4:
			var wx := b.position.x + 2
			while wx < b.position.x + b.size.x - 2:
				if rng.randf() < lit:
					_r(wx, wy, 1, 1, _pal[3].lightened(0.2) if rng.randf() < 0.8 else Color("8ad0ff"))
				wx += 3
			wy += 4
	_feature(a, ground, night, act, rng)
	# Street.
	_r(0, ground, a.x, a.y - ground, _pal[0].darkened(0.6))
	_r(0, ground, a.x, 1, _pal[2].darkened(0.2))
	for i in int(a.x / 16):
		_r(i * 16 + 4, ground + 7, 6, 1, _pal[1].darkened(0.3))


## People walking past, police lights, rain, the hour's light, shutters.
func _draw_life(a: Vector2, ground: float, night: bool, flags: Array) -> void:
	# People: silhouettes with a head, shoulders, swinging legs and a coat.
	for w in _walkers:
		var c := Color(0.04, 0.04, 0.06) if not night else Color(0.02, 0.02, 0.03)
		var hgt := 13 if int(w.z) != 1 else 11
		var step := int(_time * 6.0 + w.x) % 2
		var x := floorf(w.x)
		_r(x + 1, ground - hgt, 2, 2, c.lightened(0.12))            # head
		_r(x, ground - hgt + 2, 4, hgt - 6, c)                         # torso / coat
		_r(x - (1 if step == 0 else 0), ground - 4, 2, 4, c)         # legs
		_r(x + 2 + (1 if step == 1 else 0), ground - 4, 2, 4, c)
		_r(x + (4 if w.y > 0 else -1), ground - hgt + 3, 1, 4, c)    # an arm
		if night:
			_r(x + (3 if w.y > 0 else 0), ground - hgt + 2, 1, hgt - 7, Color(0.5, 0.6, 0.9, 0.18))  # rim light
		if int(w.z) == 2:
			_r(x + (3 if w.y > 0 else 0), ground - hgt, 1, 1, Palette.ACCENT)  # a glowing implant
	# Police lights.
	if flags.has(&"police"):
		var on := fmod(_time, 0.5) < 0.25
		_r(a.x - 46, ground - 10, 30, 9, Color(0.08, 0.08, 0.1))
		_r(a.x - 42, ground - 14, 10, 4, Color(0.1, 0.1, 0.13))
		_r(a.x - 41, ground - 15, 4, 1, Color("ff3040") if on else Color("3050ff"))
		_r(a.x - 37, ground - 15, 4, 1, Color("3050ff") if on else Color("ff3040"))
		_r(a.x - 44, ground - 2, 5, 2, Color(0.02, 0.02, 0.02))
		_r(a.x - 24, ground - 2, 5, 2, Color(0.02, 0.02, 0.02))
		var glow := Color("ff3040") if on else Color("3050ff")
		_r(a.x - 70, ground - 34, 70, 34, Color(glow, 0.08))
		_r(a.x - 70, ground, 70, 10, Color(glow, 0.12))  # on the wet street
	_draw_weather(a, ground)
	# The season's light under the hour's.
	var st := TimeManager.season_tint()
	if st.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(st.r, st.g, st.b, st.a))
	var t := TimeManager.tint()
	if t.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(t.r, t.g, t.b, t.a * 0.8))
	# Closed: shutters.
	if flags.has(&"closed") or flags.has(&"after_hours"):
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(Vector2.ZERO, size), Palette.LINE, false, 2.0)


## Today's weather: the particles, plus what it leaves on the street (a wet
## sheen, a line of slush, a heat shimmer).
func _draw_weather(a: Vector2, ground: float) -> void:
	if _weather.is_empty():
		return
	var density := float(_weather["density"])
	var kind := str(_weather["kind"])
	if density > 0.0:
		if kind == "haze" or (str(_weather["next"]) == "haze" and float(_weather["mix"]) > 0.5):
			# Heat: a warm band over the street and a slow shimmer.
			_r(0, ground - 40, a.x, 40, Color(1.0, 0.75, 0.4, 0.06 * density))
			for k in 4:
				var y := ground - 8 - k * 9 + sin(_time * 1.3 + k) * 1.5
				_r(0, y, a.x, 1, Color(1.0, 0.9, 0.7, 0.05 * density))
		elif kind in ["snow", "sleet"] or str(_weather["next"]) == "snow":
			_r(0, ground, a.x, 1, Color(0.85, 0.9, 0.95, 0.35 * density))
		else:
			_r(0, ground + 1, a.x, 3, Color(0.55, 0.65, 0.8, 0.1 * density))
	for i in _drops.size():
		var d := _drops[i]
		match int(_drop_kind[i]) if i < _drop_kind.size() else 0:
			1:
				_r(d.x, d.y, 1, 2, Color(0.75, 0.82, 0.92, 0.4))
			2:
				_r(d.x, d.y, 1, 1, Color(0.92, 0.95, 1.0, 0.75))
			3:
				_r(d.x, d.y, 2, 1, Color(0.7, 0.4, 0.15, 0.8) if i % 2 == 0 else Color(0.55, 0.3, 0.1, 0.8))
			_:
				_r(d.x, d.y, 1, 4, Color(0.6, 0.7, 0.85, 0.3))


func _blink(period: float, phase: float = 0.0) -> bool:
	return fmod(_time + phase, period) < period * 0.55


## The place's own shapes.
func _feature(a: Vector2, ground: float, night: bool, act: int, rng: RandomNumberGenerator) -> void:
	var cx := floorf(a.x * 0.5)
	var accent := _pal[3]
	match LocationManager.type_of(location_id):
		"bar":
			_r(cx - 40, ground - 34, 80, 34, _pal[0].darkened(0.3))
			_r(cx - 8, ground - 16, 16, 16, accent.darkened(0.2) if night or act > 1 else accent.darkened(0.7))
			var neon := Color("ff5a8a") if location_id == &"velvet_lounge" else Color("ff9a3a")
			if _blink(2.3) or act >= 3:
				_r(cx - 30, ground - 30, 60, 8, Color(neon, 0.25))
				_r(cx - 28, ground - 28, 56, 4, neon)
			_r(cx - 40, ground - 35, 80, 1, _pal[2])
		"night_market":
			for i in 6:
				var x := 10 + i * (a.x - 20) / 6.0
				var c := [_pal[2], accent, Color("5ad6a0"), Color("c04ad6")][i % 4] as Color
				_r(x, ground - 14, 30, 3, c)
				_r(x + 2, ground - 11, 26, 11, _pal[0].darkened(0.2))
				_r(x + 4, ground - 8, 6, 2, accent.lightened(0.3))
			for i in int(a.x / 6):
				if (i + int(_time * 3.0)) % 3 != 0 or act >= 3:
					_r(i * 6 + 2, ground - 22 + (i % 2), 1, 1, accent.lightened(0.4))
			# Dead ad screens overhead.
			_r(cx - 50, 14, 40, 18, Color(0.1, 0.12, 0.14))
			_r(cx + 20, 10, 46, 20, Color(0.1, 0.12, 0.14))
			if _blink(4.0):
				_r(cx + 22, 12, 42, 16, Color("3ad0c0", 0.35))
		"black_market":
			_r(0, 0, a.x, ground, Color(0, 0, 0, 0.55))
			for i in 9:
				var x := 6 + i * a.x / 9.0
				_r(x, ground - 46, 2, 46, _pal[0].darkened(0.4))
			_r(cx - 70, ground - 50, 140, 6, _pal[0].darkened(0.2))
			for i in 12:
				_r(cx - 30 + i * 5, ground - 44, 1, 30, Color(0.5, 0.5, 0.55, 0.6))
			for i in 5:
				var x := 20 + i * (a.x - 40) / 4.0
				var on := _blink(1.7 + i * 0.3, i)
				_r(x, ground - 42, 1, 6, Color(0.3, 0.3, 0.3))
				_r(x - 1, ground - 36, 3, 2, accent.lightened(0.3) if on else accent.darkened(0.4))
		"industrial":
			for i in 3:
				var x := 30 + i * 60
				_r(x, ground - 70, 8, 70, _pal[0].darkened(0.2))
				for k in 4:
					var sy := fmod(_time * 6.0 + k * 9.0 + i * 5.0, 36.0)
					_r(x - 2 + sin(_time + k) * 3.0, ground - 74 - sy, 6, 4, Color(0.5, 0.5, 0.5, 0.35 * (1.0 - sy / 36.0)))
			_r(0, ground - 30, a.x, 2, _pal[1])
			for i in int(a.x / 12):
				_r(i * 12, ground - 30, 1, 30, _pal[1].darkened(0.3))
			_r(0, ground - 8, a.x, 8, Color(1.0, 0.45, 0.15, 0.12 + (0.08 if _blink(0.8) else 0.0)))
		"corporate":
			for i in 4:
				var x := cx - 80 + i * 44
				var h := 70 + (i % 2) * 18
				_r(x, ground - h, 26, h, Color(0.85, 0.88, 0.92).darkened(0.55 if night else 0.15))
				_r(x + 2, ground - h + 2, 22, 1, Color("8ac8ff"))
			for i in 3:
				var dx := fmod(_time * (12 + i * 5) + i * 70, a.x + 20) - 10
				_r(dx, 16 + i * 7, 2, 1, Color(0.9, 0.9, 1.0))
				if _blink(0.6, i):
					_r(dx + 1, 17 + i * 7, 1, 1, Color("ff3040"))
			if _blink(1.2):
				_r(cx + 70, ground - 40, 1, 1, Color("ff3040"))
		"residential":
			for i in 5:
				for k in 6:
					var x := 18 + i * 34 + (k % 2) * 3
					var y := ground - 10 - k * 9
					_r(x, y, 26, 8, [_pal[1], _pal[2].darkened(0.3), _pal[0].lightened(0.15)][(i + k) % 3])
					if rng.randf() < (0.5 if night else 0.2):
						_r(x + 4, y + 2, 3, 3, accent.lightened(0.2))
				_r(18 + i * 34, ground - 62, 1, 52, _pal[0])
			for i in 8:
				_r(10 + i * 22, ground - 48 + (i % 3), 10, 1, Color(0.8, 0.8, 0.75, 0.6))
		"transit":
			for i in 40:
				var ang := PI + PI * i / 40.0
				_r(cx + cos(ang) * 90, ground - 10 + sin(ang) * 60, 3, 2, Color(0.6, 0.75, 0.8, 0.7))
			_r(0, ground - 4, a.x, 1, Color(0.7, 0.7, 0.7))
			var tx := fmod(_time * 60.0, a.x * 3.0) - a.x
			if act > 0:
				_r(tx, ground - 12, 120, 8, Color(0.75, 0.78, 0.8))
				for k in 10:
					_r(tx + 4 + k * 12, ground - 10, 6, 3, accent.lightened(0.3))
		"restricted":
			for i in int(a.x / 4):
				_r(i * 4, ground - 24, 1, 24, Color(0.55, 0.55, 0.6))
			_r(0, ground - 24, a.x, 1, Color(0.7, 0.7, 0.75))
			_r(0, ground - 12, a.x, 1, Color(0.7, 0.7, 0.75))
			_r(cx + 50, ground - 64, 10, 64, _pal[0].lightened(0.1))
			var sweep := sin(_time * 0.7) * 60.0
			var lx := cx + 55
			for k in 30:
				var t := k / 30.0
				_r(lx + sweep * t - t * 10, ground - 62 + t * 60, 1 + t * 18, 1, Color(1, 1, 0.85, 0.12))
			_r(cx - 20, ground - 40, 60, 40, Color(0.75, 0.75, 0.8).darkened(0.6))
