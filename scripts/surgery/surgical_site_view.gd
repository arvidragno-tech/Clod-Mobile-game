class_name SurgicalSiteView
extends Control
## Renders the operating field: a 64x64 "art pixel" close-up of the back of
## the patient's neck, plus everything the surgery has done to it so far
## (incision, opening, clamps, burnt tissue, implant, wires, stitches).
## Stages mutate the public state; this node only draws it.
##
## Coordinates: stages work in normalised field space (0..1). Use
## to_local_pos() / to_norm() to convert to/from this control's local space,
## and art_px() for sizes given in art pixels.

const ART_SIZE := 64
const IMPLANT_TEXTURE := preload("res://assets/sprites/surgery/implant_nx1.png")
## Max half-width of the opened wound, in art pixels.
const OPENING_HALF_WIDTH := 13.0
const SOCKET_RADIUS := 7.0
const HAIR_COLOR := Color("17141c")

enum ImplantState { NONE, IN_TRAY, HELD, PLACED, SEATED }

# --- Public state (driven by stages) ----------------------------------------
var skin_color: Color = Color("b07a5a")
var incision_path: Array[Vector2] = []
var cut_progress: float = 0.0
var cut_points: Array[Vector2] = []
var opening: float = 0.0
var clamps: Array[Vector2] = []
## Each: {"pos": Vector2 (norm), "radius": float (art px), "burn": float 0..1}
var damaged_nodes: Array[Dictionary] = []
var nerves: Array[PackedVector2Array] = []
var show_socket: bool = false
var socket_pos: Vector2 = Vector2(0.5, 0.5)
var implant_state: ImplantState = ImplantState.NONE
var implant_pos: Vector2 = Vector2(0.5, 0.9)
var implant_angle: float = 0.0
var implant_aligned: bool = false
## Each: {"from": Vector2, "to": Vector2, "color": Color} (norm)
var connections: Array[Dictionary] = []
var stitches: Array[Vector2] = []
var closed: bool = false
var bleed_intensity: float = 0.0
var blood_level: float = 0.0

var _field_origin: Vector2 = Vector2.ZERO
var _px: float = 4.0
var _skin_texture: ImageTexture
var _splats: Array[Vector3] = []  # x, y (norm), size (art px)
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout)
	_layout()


func configure(customer: CustomerData) -> void:
	skin_color = customer.skin_color if customer else skin_color
	_skin_texture = ImageTexture.create_from_image(_build_skin_image(skin_color))
	# Nerve bundles hug the wound edges and end at the splice terminals.
	nerves = [
		PackedVector2Array([Vector2(0.41, 0.3), Vector2(0.38, 0.45), Vector2(0.4, 0.64)]),
		PackedVector2Array([Vector2(0.59, 0.3), Vector2(0.62, 0.45), Vector2(0.6, 0.64)]),
	]
	queue_redraw()


# --- Coordinate helpers ------------------------------------------------------

func art_px() -> float:
	return _px


func get_field_rect() -> Rect2:
	return Rect2(_field_origin, Vector2.ONE * _px * ART_SIZE)


func to_local_pos(norm: Vector2) -> Vector2:
	return _field_origin + norm * _px * ART_SIZE


func to_norm(local: Vector2) -> Vector2:
	return (local - _field_origin) / (_px * ART_SIZE)


func norm_to_art(norm: Vector2) -> Vector2:
	return norm * ART_SIZE


## Half width (norm) of the wound opening at a given normalised y, or 0.
func opening_half_width_at(norm_y: float, open_amount: float = -1.0) -> float:
	if incision_path.size() < 2:
		return 0.0
	var amount := opening if open_amount < 0.0 else open_amount
	var y0 := incision_path[0].y
	var y1 := incision_path[incision_path.size() - 1].y
	var t := (norm_y - y0) / (y1 - y0)
	if t <= 0.0 or t >= 1.0:
		return 0.0
	return amount * sqrt(sin(PI * t)) * OPENING_HALF_WIDTH / ART_SIZE


func incision_x_at(norm_y: float) -> float:
	for i in range(incision_path.size() - 1):
		var a := incision_path[i]
		var b := incision_path[i + 1]
		if norm_y >= a.y and norm_y <= b.y:
			return lerpf(a.x, b.x, (norm_y - a.y) / maxf(b.y - a.y, 0.0001))
	return incision_path[0].x if not incision_path.is_empty() else 0.5


func is_inside_opening(norm: Vector2, margin_norm: float = 0.0, open_amount: float = -1.0) -> bool:
	var hw := opening_half_width_at(norm.y, open_amount) - margin_norm
	return hw > 0.0 and absf(norm.x - incision_x_at(norm.y)) <= hw


## Distance in art px from a normalised point to the nearest nerve.
func distance_to_nerves(norm: Vector2) -> float:
	var p := norm_to_art(norm)
	var best := INF
	for nerve in nerves:
		for i in range(nerve.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(p, norm_to_art(nerve[i]), norm_to_art(nerve[i + 1]))
			best = minf(best, p.distance_to(closest))
	return best


func add_blood_splat(norm: Vector2, amount: int = 4) -> void:
	for i in amount:
		var offset := Vector2(randf_range(-3, 3), randf_range(-3, 3)) / ART_SIZE
		_splats.append(Vector3(norm.x + offset.x, norm.y + offset.y, randf_range(1.0, 2.0)))
	if _splats.size() > 80:
		_splats = _splats.slice(_splats.size() - 80)


# --- Layout / drawing --------------------------------------------------------

func _layout() -> void:
	var side := minf(size.x, size.y)
	_px = maxf(side / ART_SIZE, 1.0)
	_field_origin = ((size - Vector2.ONE * _px * ART_SIZE) / 2.0).round()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _art_rect(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(_field_origin + Vector2(floorf(x), floorf(y)) * _px, Vector2(w, h) * _px), color)


func _art_line(a: Vector2, b: Vector2, color: Color, thickness: int = 1) -> void:
	# Bresenham on the art-pixel grid for a crisp pixel line.
	var x0 := int(floorf(a.x))
	var y0 := int(floorf(a.y))
	var x1 := int(floorf(b.x))
	var y1 := int(floorf(b.y))
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_art_rect(x0, y0, thickness, thickness, color)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


func _art_disc(center: Vector2, radius: float, color: Color) -> void:
	for y in range(int(floorf(center.y - radius)), int(ceilf(center.y + radius)) + 1):
		for x in range(int(floorf(center.x - radius)), int(ceilf(center.x + radius)) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				_art_rect(x, y, 1, 1, color)


func _draw() -> void:
	var field := get_field_rect()
	draw_rect(field.grow(_px), Palette.BG_0)
	if _skin_texture:
		draw_texture_rect(_skin_texture, field, false)
	_draw_wound()
	_draw_splats()
	_draw_clamps()
	_draw_implant()
	_draw_connections()
	_draw_stitches()
	_draw_blood_pool()
	# Field frame (surgical drape edge)
	draw_rect(field, Palette.ACCENT_DIM, false, 2.0)


func _draw_wound() -> void:
	if incision_path.size() < 2:
		return
	var y_start := incision_path[0].y * ART_SIZE
	var y_end := incision_path[incision_path.size() - 1].y * ART_SIZE
	if opening > 0.01:
		var cavity_color := Palette.TISSUE.lerp(skin_color, 0.15)
		for row in range(int(y_start), int(y_end) + 1):
			var ny := (row + 0.5) / ART_SIZE
			var hw := opening_half_width_at(ny) * ART_SIZE
			if hw <= 0.3:
				continue
			var cx := incision_x_at(ny) * ART_SIZE
			var left := roundf(cx - hw)
			var width := maxf(roundf(hw * 2.0), 1.0)
			_art_rect(left - 1, row, width + 2, 1, Palette.TISSUE_DARK)
			_art_rect(left, row, width, 1, cavity_color)
			# Deeper cavity towards the centre.
			if hw > 3.0:
				_art_rect(left + 2, row, width - 4, 1, Palette.TISSUE)
			if hw > 6.0:
				_art_rect(left + 4, row, width - 8, 1, Palette.TISSUE_DARK.lerp(Palette.TISSUE, 0.5))
			# Wet highlight speckle
			if (row * 7) % 5 == 0:
				_art_rect(left + 1, row, 1, 1, Palette.TISSUE.lightened(0.25))
		if opening > 0.4:
			_draw_nerves()
		if show_socket:
			_draw_socket()
		_draw_damaged_nodes()
	# The cut itself (follows the player's actual stroke).
	if cut_points.size() >= 2 and not closed:
		for i in range(cut_points.size() - 1):
			_art_line(norm_to_art(cut_points[i]), norm_to_art(cut_points[i + 1]), Palette.BLOOD_DARK if opening > 0.2 else Palette.BLOOD)
	if closed:
		for i in range(incision_path.size() - 1):
			_art_line(norm_to_art(incision_path[i]), norm_to_art(incision_path[i + 1]), skin_color.darkened(0.35))


func _draw_nerves() -> void:
	var alpha := clampf((opening - 0.4) / 0.4, 0.0, 1.0)
	var c := Color(Palette.NERVE, alpha)
	for nerve in nerves:
		for i in range(nerve.size() - 1):
			_art_line(norm_to_art(nerve[i]), norm_to_art(nerve[i + 1]), c)
			_art_line(norm_to_art(nerve[i]) + Vector2(1, 0), norm_to_art(nerve[i + 1]) + Vector2(1, 0), Color(Palette.NERVE.darkened(0.4), alpha))


func _draw_socket() -> void:
	var center := norm_to_art(socket_pos)
	_art_disc(center, SOCKET_RADIUS + 1.0, Palette.METAL_DARK.darkened(0.3))
	_art_disc(center, SOCKET_RADIUS, Palette.METAL_DARK)
	_art_disc(center, SOCKET_RADIUS - 2.0, Color("0c0f14"))
	# Key slot at the top: the implant's notch must line up with it.
	var slot_color := Palette.OK if implant_aligned else Palette.WARN
	_art_rect(center.x - 1, center.y - SOCKET_RADIUS - 1, 2, 3, slot_color)


func _draw_damaged_nodes() -> void:
	for node in damaged_nodes:
		var center := norm_to_art(node["pos"])
		var r: float = node["radius"] * (1.0 - float(node["burn"]) * 0.6)
		var pulse := 0.1 * sin(_time * 6.0 + center.x)
		_art_disc(center, r + 1.0, Color("6b3a78"))
		_art_disc(center, r, Palette.NECROTIC.lightened(pulse))
		_art_rect(center.x - 1, center.y - 1, 1, 1, Color("8a4f99"))
		if float(node["burn"]) > 0.0:
			_art_disc(center, r * float(node["burn"]), Color(Palette.WARN, 0.8))


func _draw_splats() -> void:
	for s in _splats:
		_art_rect(s.x * ART_SIZE, s.y * ART_SIZE, s.z, s.z, Palette.BLOOD)


func _draw_clamps() -> void:
	for c in clamps:
		var p := norm_to_art(c)
		var toward := signf(incision_x_at(c.y) - c.x)
		_art_rect(p.x - 2, p.y - 1, 4, 3, Palette.METAL_DARK)
		_art_rect(p.x - 2, p.y - 1, 4, 1, Palette.METAL)
		_art_rect(p.x + (2 if toward > 0 else -4), p.y, 2, 1, Palette.METAL)


func _draw_implant() -> void:
	if implant_state == ImplantState.NONE:
		return
	var tex_size := Vector2(IMPLANT_TEXTURE.get_size())
	var center := to_local_pos(implant_pos)
	var scale := _px * (1.15 if implant_state == ImplantState.HELD else 1.0)
	if implant_state == ImplantState.IN_TRAY:
		var tray := Rect2(center - tex_size * _px * 0.5 - Vector2(2, 2) * _px, (tex_size + Vector2(4, 4)) * _px)
		draw_rect(tray, Color(Palette.BG_1, 0.85))
		draw_rect(tray, Palette.LINE_HI, false, 2.0)
	if implant_state == ImplantState.HELD:
		draw_rect(Rect2(center - tex_size * scale * 0.5 + Vector2(3, 4) * _px, tex_size * scale), Color(0, 0, 0, 0.35))
	draw_set_transform(center, implant_angle, Vector2(scale, scale))
	draw_texture_rect(IMPLANT_TEXTURE, Rect2(-tex_size / 2.0, tex_size), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if implant_state == ImplantState.PLACED:
		var ring_color := Palette.OK if implant_aligned else Color(Palette.WARN, 0.6 + 0.4 * sin(_time * 8.0))
		draw_arc(center, (tex_size.x * 0.5 + 3.0) * _px, 0, TAU, 32, ring_color, 2.0)


func _draw_connections() -> void:
	for c in connections:
		var a := norm_to_art(c["from"])
		var b := norm_to_art(c["to"])
		var mid := (a + b) / 2.0 + Vector2(0, 3)
		_art_line(a, mid, c["color"])
		_art_line(mid, b, c["color"])


func _draw_stitches() -> void:
	for s in stitches:
		var p := norm_to_art(s)
		_art_rect(p.x - 2, p.y, 5, 1, Palette.METAL)
		_art_rect(p.x, p.y - 1, 1, 3, Palette.METAL.darkened(0.3))


func _draw_blood_pool() -> void:
	if incision_path.size() < 2 or closed:
		return
	if bleed_intensity > 0.0 and cut_progress > 0.0:
		var bottom := norm_to_art(incision_path[incision_path.size() - 1])
		var drips := clampi(int(bleed_intensity * 3.0), 1, 6)
		for i in drips:
			var phase := fmod(_time * (0.6 + i * 0.13) + i * 0.37, 1.0)
			var x := bottom.x - 3.0 + float(i * 5 % 7)
			_art_rect(x, bottom.y + phase * 8.0, 1, 2, Palette.BLOOD)
	if blood_level > 5.0:
		var w := clampf(blood_level / 4.0, 2.0, 30.0)
		var bottom2 := norm_to_art(incision_path[incision_path.size() - 1])
		_art_rect(bottom2.x - w / 2.0, bottom2.y + 6.0, w, 2, Palette.BLOOD_DARK)


func _build_skin_image(base: Color) -> Image:
	var img := Image.create(ART_SIZE, ART_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for y in ART_SIZE:
		for x in ART_SIZE:
			var c := base
			# Spine ridge shading + side falloff for some volume.
			var from_center := absf(x - ART_SIZE * 0.5) / (ART_SIZE * 0.5)
			c = c.darkened(0.18 * from_center * from_center)
			if absi(x - ART_SIZE / 2) <= 1 and y > 10:
				c = c.darkened(0.06)
			var n := rng.randf()
			if n < 0.08:
				c = c.darkened(0.07)
			elif n > 0.95:
				c = c.lightened(0.05)
			# Hairline at the top with ragged edge.
			var hairline := 7 + int(2.0 * sin(x * 0.7)) + (1 if rng.randf() < 0.3 else 0)
			if y < hairline:
				c = HAIR_COLOR if rng.randf() > 0.15 else HAIR_COLOR.lightened(0.15)
			img.set_pixel(x, y, c)
	# Old port scar.
	for i in 9:
		img.set_pixel(22 + i, 46 + i / 3, base.darkened(0.25))
	# Barcode tattoo, because of course.
	for i in 6:
		if i % 2 == 0 or i == 3:
			for y in range(54, 59):
				img.set_pixel(44 + i, y, base.darkened(0.45))
	return img
