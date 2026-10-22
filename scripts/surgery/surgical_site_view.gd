class_name SurgicalSiteView
extends Control
## Renders the operating field at native art resolution (it lives inside a
## SubViewport scaled by GameConfig.PIXEL_SCALE, so every pixel here is one
## art pixel): the operating-room backdrop, the patient's anatomy close-up
## (recoloured for their skin/hair), and everything the surgery has done so
## far — incision, opening, clamps, anchors, burns, implant, wires, stitches.
## Stages mutate the public state; this node only draws it.
##
## Coordinates: stages work in normalised field space (0..1) over the
## FIELD_SIZE anatomy texture. Use to_local_pos() / to_norm() to convert, and
## art_px() for sizes given in design units (1/64 of the field, as in data).
##
## Implant geometry has one source of truth here, in field pixels: the socket
## and the implant are anchored on whole pixels (socket_center() /
## implant_center()), the implant art turns about its own centre on that
## pixel (implant_pivot()), and the socket's key slot and the implant's notch
## both sit on key_radius() from the anchor. Stages draw
## their alignment marks and hit-test with these, never with their own sizes.
##
## A seated implant is drawn into the body, not over it: only the part inside
## the open wound shows (the skin covers the rest, as a raised outline), and
## once the skin is closed only its exposed part (site.implant.exposed_radius:
## a jack, a lens) stays visible.

const FIELD_SIZE := 160
const DESIGN_GRID := 64.0
## Max half-width of the opened wound, in design units (overridable per surgery).
const OPENING_HALF_WIDTH := 13.0
const SOCKET_RADIUS := 7.0
## _open_depth value for a pixel covered by intact (or closed) skin.
const OUTSIDE_WOUND := 2.0
## Implant art size when no texture is set (the cyberware icons are 32 px).
const DEFAULT_IMPLANT_SIZE := Vector2(32, 32)
const DEFAULT_IMPLANT_ICON := "res://assets/sprites/cyberware/neural_t1.png"
const REGION_TEXTURES := {
	&"neck": "res://assets/sprites/surgery/regions/neck.png",
	&"forearm": "res://assets/sprites/surgery/regions/forearm.png",
	&"chest": "res://assets/sprites/surgery/regions/chest.png",
	&"thigh": "res://assets/sprites/surgery/regions/thigh.png",
	&"orbital": "res://assets/sprites/surgery/regions/orbital.png",
}
const BACKDROPS := ["res://assets/sprites/surgery/backdrop_0.png", "res://assets/sprites/surgery/backdrop_1.png",
	"res://assets/sprites/surgery/backdrop_2.png"]

# Hue-shifted material ramps (dark -> light).
const TISSUE := [Color("2a0a14"), Color("4d1424"), Color("6e1f30"), Color("8a3040"), Color("a8485a"), Color("c46a78"), Color("de9aa4"), Color("f0c8cc")]
const NECROTIC := [Color("120a16"), Color("1e1024"), Color("2b1630"), Color("3e2048"), Color("552c5e"), Color("6b3a78"), Color("8a4f99"), Color("a87ab8")]
const NERVE := [Color("4a3c14"), Color("7a6424"), Color("a88c34"), Color("d0b24a"), Color("f2d16b"), Color("fae49a"), Color("fff2c8"), Color("ffffff")]
const STEEL := [Color("14181e"), Color("232a34"), Color("343e4c"), Color("4c5868"), Color("6c7a8c"), Color("929fb0"), Color("bcc6d2"), Color("e4eaf0")]
const BLOOD := [Color("3a0610"), Color("5c0a18"), Color("80101f"), Color("a8162a"), Color("c42a3a")]
const WIRE_COLORS: Array[Color] = [Color("2ee6c8"), Color("ffb43d"), Color("ff3d81")]

enum ImplantState { NONE, IN_TRAY, HELD, PLACED, SEATED }

# --- Public state (driven by stages) ----------------------------------------
var skin_color: Color = Color("b07a5a")
var incision_path: Array[Vector2] = []
var cut_progress: float = 0.0
var cut_points: Array[Vector2] = []
var opening: float = 0.0:
	set(v):
		if not is_equal_approx(v, opening):
			opening = v
			_wound_dirty = true
var opening_half_width: float = OPENING_HALF_WIDTH
var clamps: Array[Vector2] = []
## Each: {"pos": Vector2 (norm), "depth": float 0..1, "ok": bool}
var anchors: Array[Dictionary] = []
## Each: {"pos": Vector2 (norm), "radius": float (design units), "burn": float 0..1}
var damaged_nodes: Array[Dictionary] = []
var nerves: Array[PackedVector2Array] = []
var show_socket: bool = false
var socket_pos: Vector2 = Vector2(0.5, 0.5)
var implant_state: ImplantState = ImplantState.NONE:
	set(v):
		implant_state = v
		_implant_dirty = true
var implant_pos: Vector2 = Vector2(0.5, 0.86):
	set(v):
		implant_pos = v
		_implant_dirty = true
var implant_angle: float = 0.0:
	set(v):
		implant_angle = v
		_implant_dirty = true
var implant_aligned: bool = false
var implant_texture: Texture2D:
	set(v):
		implant_texture = v
		_implant_image = v.get_image() if v else null
		if _implant_image and _implant_image.is_compressed():
			_implant_image.decompress()
		_implant_dirty = true
## Field px around the implant centre that stay visible through closed skin
## (from the surgery's site.implant.exposed_radius; 0 = fully subdermal).
var implant_exposed_radius: float = 0.0
## Each: {"from": Vector2, "to": Vector2, "color": Color} (norm)
var connections: Array[Dictionary] = []
var stitches: Array[Vector2] = []
var closed: bool = false:
	set(v):
		closed = v
		_wound_dirty = true
		_implant_dirty = true
var bleed_intensity: float = 0.0
var blood_level: float = 0.0
var emergency: bool = false
## Beats per minute for the wound flush (set from vitals by the screen).
var heart_rate: float = 72.0

var _field_origin: Vector2 = Vector2.ZERO
var _region_texture: Texture2D
var _backdrop: Texture2D
var _wound_image: Image
var _wound_texture: ImageTexture
var _wound_dirty: bool = true
# Precomputed tube around the incision: per candidate pixel.
var _tube_xy: PackedInt32Array = PackedInt32Array()
var _tube_d: PackedFloat32Array = PackedFloat32Array()
var _tube_hw: PackedFloat32Array = PackedFloat32Array()
var _splats: Array[Vector3] = []
## Per field pixel: depth into the open wound (distance / half width, <= 1
## inside the cavity), or OUTSIDE_WOUND where intact skin covers it.
var _open_depth: PackedFloat32Array = PackedFloat32Array()
var _implant_image: Image
var _implant_layer: Image
var _implant_layer_texture: ImageTexture
var _implant_dirty: bool = true
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	_wound_image = Image.create(FIELD_SIZE, FIELD_SIZE, false, Image.FORMAT_RGBA8)
	_wound_texture = ImageTexture.create_from_image(_wound_image)
	_implant_layer = Image.create(FIELD_SIZE, FIELD_SIZE, false, Image.FORMAT_RGBA8)
	_implant_layer_texture = ImageTexture.create_from_image(_implant_layer)
	_open_depth.resize(FIELD_SIZE * FIELD_SIZE)
	_open_depth.fill(OUTSIDE_WOUND)
	_layout()


## Sets up anatomy, nerves and backdrop for a surgery + customer.
func configure(customer: CustomerData, surgery: SurgeryData = null, backdrop_level: int = 1) -> void:
	var app := customer.appearance.duplicate() if customer and not customer.appearance.is_empty() else {"skin": 2, "hair_color": "black"}
	app["cloth_a"] = "drape"
	app["metal"] = "chrome"
	skin_color = PixelArt.ramp("skin", app.get("skin", 2))[3]
	var region := surgery.get_region() if surgery else &"neck"
	_region_texture = PixelArt.recolor(REGION_TEXTURES.get(region, REGION_TEXTURES[&"neck"]), app)
	_backdrop = PixelArt.tex(BACKDROPS[clampi(backdrop_level, 0, BACKDROPS.size() - 1)])
	nerves.clear()
	var site: Dictionary = surgery.site if surgery else {}
	var nerve_data: Array = site.get("nerves", [[[0.41, 0.3], [0.38, 0.45], [0.4, 0.64]], [[0.59, 0.3], [0.62, 0.45], [0.6, 0.64]]])
	for n: Variant in nerve_data:
		var pts := PackedVector2Array()
		for p: Variant in n:
			pts.append(Vector2(float(p[0]), float(p[1])))
		nerves.append(pts)
	opening_half_width = float(site.get("opening_half_width", OPENING_HALF_WIDTH))
	var implant_site: Dictionary = site.get("implant", {})
	implant_exposed_radius = float(implant_site.get("exposed_radius", 0.0))
	_implant_dirty = true
	queue_redraw()


func set_implant_icon(path: String) -> void:
	implant_texture = PixelArt.tex(path if path != "" else DEFAULT_IMPLANT_ICON)


func set_incision_path(path: Array[Vector2]) -> void:
	incision_path = path
	_build_tube()
	_wound_dirty = true


# --- Coordinate helpers ------------------------------------------------------

## Local units per design unit (data tolerances are in 1/64 of the field).
func art_px() -> float:
	return FIELD_SIZE / DESIGN_GRID


func get_field_rect() -> Rect2:
	return Rect2(_field_origin, Vector2.ONE * FIELD_SIZE)


## The part of the field actually visible (the control may be smaller).
func get_visible_field_rect() -> Rect2:
	return get_field_rect().intersection(Rect2(Vector2.ZERO, size))


func to_local_pos(norm: Vector2) -> Vector2:
	return _field_origin + norm * FIELD_SIZE


func to_norm(local: Vector2) -> Vector2:
	return (local - _field_origin) / FIELD_SIZE


# --- Implant geometry (field px; see the class notes) --------------------------

## The socket's anchor pixel (local units): its rings and key slot centre here.
func socket_center() -> Vector2:
	return to_local_pos(socket_pos).floor()


## The implant's anchor pixel and rotation pivot (local units).
func implant_center() -> Vector2:
	return to_local_pos(implant_pos).floor()


func socket_radius() -> float:
	return SOCKET_RADIUS * art_px()


## Distance from the anchor to the socket's key slot and the implant's notch:
## the slot is cut into the socket rim, so the two meet there when aligned.
func key_radius() -> float:
	return roundf(socket_radius())


## Where the notch must go: the socket's key slot (an anchor pixel).
func socket_key_pos() -> Vector2:
	return socket_center() + Vector2.UP * key_radius()


## Where the implant's notch is at its current angle (an anchor pixel).
func implant_notch_pos() -> Vector2:
	return (implant_center() + Vector2.UP.rotated(implant_angle) * key_radius()).round()


## The point the art turns about: its true centre, placed so the art's
## corner lands on a whole pixel (the anchor pixel's corner for even sizes,
## its centre for odd ones).
func implant_pivot() -> Vector2:
	return implant_center() + _pivot_offset(implant_size())


static func _pivot_offset(art: Vector2) -> Vector2:
	return art / 2.0 - (art / 2.0).floor()


func implant_size() -> Vector2:
	return Vector2(implant_texture.get_size()) if implant_texture else DEFAULT_IMPLANT_SIZE


## Radius of the circle that encloses the implant art at any angle.
func implant_reach() -> float:
	return implant_size().length() / 2.0


func is_inside_opening(norm: Vector2, margin_norm: float = 0.0, open_amount: float = -1.0) -> bool:
	var amount := opening if open_amount < 0.0 else open_amount
	var info := _closest_on_path(norm * FIELD_SIZE)
	var hw := _half_width_at(info.y) * amount - margin_norm * FIELD_SIZE
	return hw > 0.0 and info.x <= hw


## Distance in design units from a normalised point to the nearest nerve.
func distance_to_nerves(norm: Vector2) -> float:
	var p := norm * DESIGN_GRID
	var best := INF
	for nerve in nerves:
		for i in range(nerve.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(p, nerve[i] * DESIGN_GRID, nerve[i + 1] * DESIGN_GRID)
			best = minf(best, p.distance_to(closest))
	return best


func add_blood_splat(norm: Vector2, amount: int = 4) -> void:
	for i in amount:
		var o := Vector2(randf_range(-6, 6), randf_range(-6, 6)) / FIELD_SIZE
		_splats.append(Vector3(norm.x + o.x, norm.y + o.y, randf_range(1.0, 2.0)))
	if _splats.size() > 90:
		_splats = _splats.slice(_splats.size() - 90)


# --- Wound geometry ----------------------------------------------------------

## Returns (distance, t) from a field-pixel point to the incision polyline.
func _closest_on_path(p: Vector2) -> Vector2:
	if incision_path.size() < 2:
		return Vector2(INF, 0.0)
	var total := 0.0
	var lengths: Array[float] = []
	for i in range(incision_path.size() - 1):
		var l := (incision_path[i] * FIELD_SIZE).distance_to(incision_path[i + 1] * FIELD_SIZE)
		lengths.append(l)
		total += l
	var best_d := INF
	var best_t := 0.0
	var acc := 0.0
	for i in range(incision_path.size() - 1):
		var a := incision_path[i] * FIELD_SIZE
		var b := incision_path[i + 1] * FIELD_SIZE
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < best_d:
			best_d = d
			best_t = (acc + a.distance_to(q)) / maxf(total, 0.001)
		acc += lengths[i]
	return Vector2(best_d, best_t)


## Full-open half width (field px) at a fraction along the incision.
func _half_width_at(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	return sqrt(sin(PI * t)) * opening_half_width * art_px()


func _build_tube() -> void:
	_tube_xy.clear()
	_tube_d.clear()
	_tube_hw.clear()
	if incision_path.size() < 2:
		return
	# Segment table in field pixels (computed once, not per pixel).
	var seg_a := PackedVector2Array()
	var seg_b := PackedVector2Array()
	var seg_acc := PackedFloat32Array()
	var total := 0.0
	for i in range(incision_path.size() - 1):
		var a := incision_path[i] * FIELD_SIZE
		var b := incision_path[i + 1] * FIELD_SIZE
		seg_a.append(a)
		seg_b.append(b)
		seg_acc.append(total)
		total += a.distance_to(b)
	total = maxf(total, 0.001)
	var margin := opening_half_width * art_px() + 2.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in incision_path:
		lo = lo.min(p * FIELD_SIZE)
		hi = hi.max(p * FIELD_SIZE)
	var seg_count := seg_a.size()
	for y in range(maxi(0, int(lo.y - margin)), mini(FIELD_SIZE, int(hi.y + margin) + 1)):
		for x in range(maxi(0, int(lo.x - margin)), mini(FIELD_SIZE, int(hi.x + margin) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var best_d := INF
			var best_t := 0.0
			for i in seg_count:
				var q := Geometry2D.get_closest_point_to_segment(p, seg_a[i], seg_b[i])
				var d := p.distance_to(q)
				if d < best_d:
					best_d = d
					best_t = (seg_acc[i] + seg_a[i].distance_to(q)) / total
			if best_d > margin:
				continue
			var hw := _half_width_at(best_t)
			if hw > 0.5 and best_d <= hw + 1.5:
				_tube_xy.append(y * FIELD_SIZE + x)
				_tube_d.append(best_d)
				_tube_hw.append(hw)


func _rebuild_wound() -> void:
	_wound_dirty = false
	_implant_dirty = true
	_open_depth.fill(OUTSIDE_WOUND)
	var data := PackedByteArray()
	data.resize(FIELD_SIZE * FIELD_SIZE * 4)
	if not closed and opening > 0.01:
		var skin_dark := skin_color.darkened(0.45)
		for i in _tube_xy.size():
			var hw := _tube_hw[i] * opening
			var d := _tube_d[i]
			var idx := _tube_xy[i]
			var c: Color
			if d <= hw:
				var r := d / maxf(hw, 0.001)
				_open_depth[idx] = r
				var x := idx % FIELD_SIZE
				var y := idx / FIELD_SIZE
				var shade := 1.6 + r * 3.6 + (0.6 if (x * 7 + y * 13) % 29 == 0 else 0.0)
				if hw > 6.0 and r < 0.35:
					shade -= 1.2  # deep cavity
				if (x * 5 + y * 3) % 23 == 0 and r > 0.3:
					shade = 6.5  # wet highlight
				c = TISSUE[clampi(int(shade), 0, 7)]
				if r > 0.86:
					c = TISSUE[1]
			elif d <= hw + 1.2:
				c = skin_dark  # wound lip shadow
			else:
				continue
			var o := idx * 4
			data[o] = c.r8
			data[o + 1] = c.g8
			data[o + 2] = c.b8
			data[o + 3] = 255
	_wound_image.set_data(FIELD_SIZE, FIELD_SIZE, false, Image.FORMAT_RGBA8, data)
	_wound_texture.update(_wound_image)


# --- Layout / drawing --------------------------------------------------------

## Region of interest (normalised). When the visible window is smaller than
## the field (short phones), the field is framed around it instead of the
## centre. Stages set it once at their start, never mid-gesture.
var focus: Vector2 = Vector2(0.5, 0.5)


func set_focus(norm: Vector2) -> void:
	focus = norm.clamp(Vector2.ZERO, Vector2.ONE)
	_layout()


func _layout() -> void:
	var o := ((size - Vector2.ONE * FIELD_SIZE) / 2.0).floor()
	for axis in 2:
		if size[axis] < FIELD_SIZE:
			o[axis] = floorf(clampf(size[axis] / 2.0 - focus[axis] * FIELD_SIZE, size[axis] - FIELD_SIZE, 0.0))
	_field_origin = o
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _backdrop:
		var bs := Vector2(_backdrop.get_size())
		draw_texture(_backdrop, ((size - bs) / 2.0).floor())
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.BG_0)
	var field := get_field_rect()
	# Drape opening: soft shadow ring around the exposed skin.
	draw_rect(field.grow(2), Color(0, 0, 0, 0.55))
	draw_rect(field.grow(1), Color(0.05, 0.12, 0.13, 1.0))
	if _region_texture:
		draw_texture(_region_texture, _field_origin)
	if _wound_dirty:
		_rebuild_wound()
	draw_texture(_wound_texture, _field_origin)
	# Heartbeat: the open wound flushes faintly on each beat.
	if not closed and opening > 0.2 and not Settings.reduce_motion:
		var beat := fmod(_time * heart_rate / 60.0, 1.0)
		if beat < 0.12:
			draw_texture(_wound_texture, _field_origin, Color(1.4, 0.7, 0.7, 0.18 * (1.0 - beat / 0.12)))
	if not closed and opening > 0.4:
		_draw_nerves()
	if show_socket:
		_draw_socket()
	_draw_damaged_nodes()
	_draw_cut()
	_draw_splats()
	# Anchors and wiring are inside the body: closed skin covers them.
	if not closed:
		_draw_anchors()
	_draw_clamps()
	_draw_implant()
	if not closed:
		_draw_connections()
	_draw_stitches()
	_draw_blood()


func _px(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), c)


func _line(a: Vector2, b: Vector2, c: Color, wound_only: bool = false) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for k in steps + 1:
		var p := a.lerp(b, float(k) / maxf(steps, 1))
		if not wound_only or is_in_wound(p):
			_px(p, c)


## True when a local point lies inside the open wound as last drawn (the
## per-pixel mask behind the implant compositing).
func is_in_wound(local: Vector2) -> bool:
	var f := (local - _field_origin).floor()
	if f.x < 0 or f.y < 0 or f.x >= FIELD_SIZE or f.y >= FIELD_SIZE:
		return false
	return _open_depth[int(f.y) * FIELD_SIZE + int(f.x)] <= 1.0


func _disc(center: Vector2, r: float, c: Color) -> void:
	var ri := int(ceilf(r))
	for y in range(-ri, ri + 1):
		var w := floorf(sqrt(maxf(0.0, r * r - y * y)))
		draw_rect(Rect2(floorf(center.x - w), floorf(center.y + y), w * 2.0 + 1.0, 1.0), c)


func _draw_cut() -> void:
	if closed or cut_points.size() < 2:
		if closed:
			for i in range(incision_path.size() - 1):
				_line(to_local_pos(incision_path[i]), to_local_pos(incision_path[i + 1]), skin_color.darkened(0.4))
		return
	var col := BLOOD[1] if opening > 0.2 else BLOOD[3]
	for i in range(cut_points.size() - 1):
		_line(to_local_pos(cut_points[i]), to_local_pos(cut_points[i + 1]), col)


func _draw_nerves() -> void:
	var a := clampf((opening - 0.4) / 0.4, 0.0, 1.0)
	for nerve in nerves:
		for i in range(nerve.size() - 1):
			var p0 := to_local_pos(nerve[i])
			var p1 := to_local_pos(nerve[i + 1])
			_line(p0 + Vector2(1, 1), p1 + Vector2(1, 1), Color(NERVE[1], a))
			_line(p0 + Vector2(1, 0), p1 + Vector2(1, 0), Color(NERVE[3], a))
			_line(p0, p1, Color(NERVE[5], a))
	# Neural signals: bright pulses travelling along each exposed nerve.
	if Settings.reduce_motion:
		return
	for n in nerves.size():
		var nerve := nerves[n]
		var total := 0.0
		for i in range(nerve.size() - 1):
			total += to_local_pos(nerve[i]).distance_to(to_local_pos(nerve[i + 1]))
		if total <= 0.0:
			continue
		for k in 2:
			var d := fmod(_time * 22.0 + n * 17.0 + k * total * 0.5, total)
			for i in range(nerve.size() - 1):
				var p0 := to_local_pos(nerve[i])
				var p1 := to_local_pos(nerve[i + 1])
				var seg := p0.distance_to(p1)
				if d <= seg:
					var p := p0.lerp(p1, d / maxf(seg, 0.001)).floor()
					_px(p, Color(NERVE[7], a))
					_px(p - (p1 - p0).normalized().round(), Color(NERVE[6], a * 0.6))
					break
				d -= seg


func _draw_socket() -> void:
	var c := socket_center()
	var r := socket_radius()
	_disc(c + Vector2(1, 2), r + 2, Color(0, 0, 0, 0.5))
	_disc(c, r + 1, STEEL[1])
	_disc(c, r, STEEL[4])
	_disc(c - Vector2(1, 1), r - 2, STEEL[5])
	_disc(c, r - 3, STEEL[2])
	_disc(c, r - 5, Color("0a0d12"))
	for k in 8:  # mounting screws
		var a := TAU * k / 8.0
		_px(c + Vector2(cos(a), sin(a)) * (r - 1.5), STEEL[7] if k < 3 else STEEL[3])
	# Key slot, centred on the same pixel the stage's target mark uses.
	var k := socket_key_pos()
	var key := Palette.OK if implant_aligned else Palette.WARN
	draw_rect(Rect2(k - Vector2(2, 2), Vector2(5, 5)), STEEL[0])
	draw_rect(Rect2(k - Vector2(1, 1), Vector2(3, 3)), key)


func _draw_damaged_nodes() -> void:
	for node in damaged_nodes:
		var c := to_local_pos(node["pos"])
		var r: float = float(node["radius"]) * art_px() * (1.0 - float(node["burn"]) * 0.6)
		var pulse := int(sin(_time * 6.0 + c.x) > 0.6)
		_disc(c, r + 1.5, NECROTIC[5])
		_disc(c, r, NECROTIC[2 + pulse])
		_disc(c - Vector2(1, 1), r * 0.45, NECROTIC[4])
		_px(c + Vector2(r * 0.3, -r * 0.3), NECROTIC[7])
		if float(node["burn"]) > 0.0:
			_disc(c, r * float(node["burn"]), Color(Palette.WARN, 0.85))
			_px(c, Color("fff2c8"))


func _draw_splats() -> void:
	for s in _splats:
		draw_rect(Rect2(to_local_pos(Vector2(s.x, s.y)).floor(), Vector2(s.z, s.z)), BLOOD[2])


func _draw_clamps() -> void:
	for cl in clamps:
		var p := to_local_pos(cl)
		var toward := signf(0.5 - cl.x) if absf(cl.x - 0.5) > 0.02 else signf(0.5 - cl.y)
		draw_rect(Rect2(p + Vector2(-4, -3), Vector2(8, 6)), STEEL[2])
		draw_rect(Rect2(p + Vector2(-4, -3), Vector2(8, 1)), STEEL[6])
		draw_rect(Rect2(p + Vector2(-3, -1), Vector2(6, 2)), STEEL[4])
		draw_rect(Rect2(p + Vector2(4 if toward > 0 else -7, -1), Vector2(3, 2)), STEEL[5])
		_px(p + Vector2(2, -2), Palette.ACCENT)


func _draw_anchors() -> void:
	for a in anchors:
		var p := to_local_pos(a["pos"])
		var d := float(a.get("depth", 0.0))
		_disc(p, 3.5, STEEL[1])
		_disc(p, 2.5, STEEL[5] if bool(a.get("ok", true)) else Palette.WARN)
		_px(p, STEEL[0])
		if d > 0.0:
			draw_arc(p, 5.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(d, 0.0, 1.0), 16, Palette.ACCENT, 1.0)


func _draw_implant() -> void:
	if implant_state == ImplantState.NONE or implant_texture == null:
		return
	if implant_state == ImplantState.SEATED:
		if _implant_dirty:
			_rebuild_implant_layer()
		draw_texture(_implant_layer_texture, _field_origin)
		return
	var ts := Vector2(implant_texture.get_size())
	var center := implant_center()
	var pivot := implant_pivot()
	if implant_state == ImplantState.IN_TRAY:
		var tray := Rect2(center - ts / 2.0 - Vector2(3, 3), ts + Vector2(6, 6))
		draw_rect(tray, Color(STEEL[1], 0.92))
		draw_rect(tray, STEEL[4], false, 1.0)
	if implant_state == ImplantState.HELD:
		draw_texture_rect(implant_texture, Rect2(center - ts / 2.0 + Vector2(3, 4), ts), false, Color(0, 0, 0, 0.4))
	draw_set_transform(pivot, implant_angle, Vector2.ONE)
	draw_texture(implant_texture, -ts / 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if implant_state == ImplantState.PLACED:
		var ring := Palette.OK if implant_aligned else Color(Palette.WARN, 0.55 + 0.45 * sin(_time * 8.0))
		draw_arc(center, ts.x * 0.5 + 4.0, 0, TAU, 32, ring, 1.0)


## Composites the seated implant into the body (field-sized layer, rebuilt
## only when the implant, the wound or the closure changes): art inside the
## open wound shows, shaded where the tissue edge overlaps it, with a contact
## shadow on the tissue; art under intact skin shows only as a raised outline
## in the skin; art within implant_exposed_radius always shows, ringed by skin.
func _rebuild_implant_layer() -> void:
	_implant_dirty = false
	if _wound_dirty:
		_rebuild_wound()
		_implant_dirty = false
	var data := PackedByteArray()
	data.resize(FIELD_SIZE * FIELD_SIZE * 4)
	if _implant_image == null:
		_implant_layer.set_data(FIELD_SIZE, FIELD_SIZE, false, Image.FORMAT_RGBA8, data)
		_implant_layer_texture.update(_implant_layer)
		return
	var anchor := implant_center() - _field_origin
	var cover := implant_coverage(anchor, implant_angle)
	var shadow := Color(0, 0, 0, 0.45)
	var exposed_rim := skin_color.darkened(0.5)
	var raised := skin_color.lightened(0.18)
	var sunk := skin_color.darkened(0.28)
	var under := {}  # field index -> true: art hidden under skin
	# The socket stays as the implant's mount, as far as the wound shows it.
	if not closed:
		var mount_r := socket_radius() + 1.0
		for y in range(maxi(0, int(anchor.y - mount_r)), mini(FIELD_SIZE, int(anchor.y + mount_r) + 1)):
			for x in range(maxi(0, int(anchor.x - mount_r)), mini(FIELD_SIZE, int(anchor.x + mount_r) + 1)):
				var idx := y * FIELD_SIZE + x
				var d := Vector2(x, y).distance_to(anchor)
				if d <= mount_r and _open_depth[idx] <= 1.0:
					_put(data, idx, STEEL[1] if d > mount_r - 1.0 else (STEEL[4] if d > mount_r - 3.0 else STEEL[2]))
	for idx: int in cover:
		var src: Vector2i = cover[idx]
		var c := _implant_image.get_pixelv(src)
		var x := idx % FIELD_SIZE
		var y := idx / FIELD_SIZE
		var depth := _open_depth[idx] if not closed else OUTSIDE_WOUND
		var from_center := Vector2(x + 0.5, y + 0.5) - (anchor + _pivot_offset(implant_size()))
		if depth <= 1.0:
			if depth > 0.86:
				c = c.darkened(0.45)  # the wound's edge laps over it
			_put(data, idx, c)
		elif implant_exposed_radius > 0.0 and from_center.length() <= implant_exposed_radius:
			_put(data, idx, c)
		else:
			under[idx] = true
	for idx: int in cover:
		var x := idx % FIELD_SIZE
		var y := idx / FIELD_SIZE
		if under.has(idx):
			# Raised outline: lit along the top-left edge, shaded bottom-right.
			if not cover.has(idx - FIELD_SIZE) or not cover.has(idx - 1):
				_put(data, idx, raised)
			elif not cover.has(idx + FIELD_SIZE) or not cover.has(idx + 1):
				_put(data, idx, sunk)
		else:
			# Visible art: skin rim where it leaves the skin, contact shadow
			# where it rests on tissue.
			for n: int in [idx - FIELD_SIZE, idx - 1, idx + 1, idx + FIELD_SIZE]:
				if under.has(n) and _open_depth[n] > 1.0:
					_put(data, n, exposed_rim)
			var below := idx + FIELD_SIZE + 1
			if x + 1 < FIELD_SIZE and y + 1 < FIELD_SIZE and not cover.has(below) and _open_depth[below] <= 1.0 and not closed \
					and data[below * 4 + 3] == 0:
				_put(data, below, shadow)
	_implant_layer.set_data(FIELD_SIZE, FIELD_SIZE, false, Image.FORMAT_RGBA8, data)
	_implant_layer_texture.update(_implant_layer)


## Field pixels covered by the implant art anchored at field pixel `anchor`
## and turned by `angle` about its pivot: {field index: source texel}. The
## same mapping draw_set_transform() applies to the held / placed sprite.
## (A tiny bias settles texel-edge ties the same way every time, so a
## quarter turn of mixed odd / even art neither drops nor doubles pixels.)
func implant_coverage(anchor: Vector2, angle: float) -> Dictionary:
	var out := {}
	if _implant_image == null:
		return out
	var ts := Vector2(_implant_image.get_size())
	var pivot := anchor + _pivot_offset(ts)
	var reach := ceili(ts.length() / 2.0) + 1
	for y in range(maxi(0, int(anchor.y) - reach), mini(FIELD_SIZE, int(anchor.y) + reach + 1)):
		for x in range(maxi(0, int(anchor.x) - reach), mini(FIELD_SIZE, int(anchor.x) + reach + 1)):
			var q := (Vector2(x + 0.5, y + 0.5) - pivot).rotated(-angle) + ts / 2.0 + Vector2(0.0001, 0.0001)
			if q.x < 0.0 or q.y < 0.0 or q.x >= ts.x or q.y >= ts.y:
				continue
			var src := Vector2i(int(q.x), int(q.y))
			if _implant_image.get_pixelv(src).a < 0.5:
				continue
			out[y * FIELD_SIZE + x] = src
	return out


static func _put(data: PackedByteArray, idx: int, c: Color) -> void:
	var o := idx * 4
	data[o] = c.r8
	data[o + 1] = c.g8
	data[o + 2] = c.b8
	data[o + 3] = c.a8


func _draw_connections() -> void:
	for c in connections:
		var a := to_local_pos(c["from"])
		var b := to_local_pos(c["to"])
		var mid := (a + b) / 2.0 + Vector2(0, 6)
		var col: Color = c["color"]
		# Wiring runs inside the body: only the stretch in the open wound shows.
		for seg: Array in [[a, mid], [mid, b]]:
			_line(seg[0] + Vector2(0, 1), seg[1] + Vector2(0, 1), col.darkened(0.5), true)
			_line(seg[0], seg[1], col, true)
		if is_in_wound(b):
			_disc(b, 2.0, col.darkened(0.3))
			_px(b - Vector2(1, 1), col.lightened(0.5))


func _draw_stitches() -> void:
	for s in stitches:
		var p := to_local_pos(s).floor()
		draw_rect(Rect2(p + Vector2(-4, 0), Vector2(9, 1)), STEEL[6])
		draw_rect(Rect2(p + Vector2(-4, 1), Vector2(9, 1)), STEEL[3])
		draw_rect(Rect2(p + Vector2(-4, -1), Vector2(1, 3)), STEEL[4])
		draw_rect(Rect2(p + Vector2(4, -1), Vector2(1, 3)), STEEL[4])


func _draw_blood() -> void:
	if incision_path.size() < 2 or closed or cut_progress <= 0.0:
		return
	var bottom := to_local_pos(incision_path[incision_path.size() - 1])
	if bleed_intensity > 0.0:
		var drips := clampi(int(bleed_intensity * 4.0), 1, 8)
		for i in drips:
			var phase := fmod(_time * (0.6 + i * 0.13) + i * 0.37, 1.0)
			var x := bottom.x - 6.0 + float(i * 7 % 13)
			draw_rect(Rect2(Vector2(x, bottom.y + phase * 18.0).floor(), Vector2(1, 3)), BLOOD[3])
	if blood_level > 5.0:
		var w := clampf(blood_level / 2.0, 3.0, 60.0)
		draw_rect(Rect2(Vector2(bottom.x - w / 2.0, bottom.y + 12.0).floor(), Vector2(w, 3)), BLOOD[1])
		draw_rect(Rect2(Vector2(bottom.x - w / 2.0 + 2, bottom.y + 12.0).floor(), Vector2(w - 4, 1)), BLOOD[3])
