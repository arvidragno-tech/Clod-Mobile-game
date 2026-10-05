class_name PixelPortrait
extends Control
## A character portrait (96x112 art, v2) at the global pixel density on a
## lit, place-specific backdrop (clinic tiles, wet street, corporate glass,
## market haze...). Animated through CharacterAnimationManager: blinks,
## gaze shifts, a 1-pixel breath, tremor and cyberware flicker. Expression
## can change at any time (dialogue). `framing` picks how much of the bust
## to show without ever changing pixel size.

enum Framing { FULL, BUST, FACE, HEAD }
const FRAMES := {
	Framing.FULL: Rect2i(0, 0, 96, 112),
	Framing.BUST: Rect2i(6, 2, 84, 100),
	Framing.FACE: Rect2i(18, 6, 60, 68),
	Framing.HEAD: Rect2i(26, 12, 44, 48),
}
const BACKDROPS := ["clinic", "street", "market", "corporate", "medical", "industrial", "lab", "bar"]

@export var framing: Framing = Framing.FACE
@export var accent: Color = Palette.ACCENT
## Custom crop (art px) overriding `framing` when it has an area.
var crop: Rect2i = Rect2i()
## Integer pixel density override for large dialogue portraits (0 = global).
var pixel_scale: int = 0
var appearance: Dictionary = {}
var expression: String = ""
var backdrop: StringName = &"street"
var profile: StringName = &"calm"
var _anim: Dictionary = {}
var _layers: Dictionary = {}  # "expr|gaze" -> [tex, glow]
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_rect().size) * _ps() + Vector2(6, 6)


func _exit_tree() -> void:
	CharacterAnimationManager.unregister(self)


func _ps() -> float:
	return float(pixel_scale if pixel_scale > 0 else GameConfig.PIXEL_SCALE)


func _rect() -> Rect2i:
	return crop if crop.has_area() else FRAMES[framing]


func set_framing(f: Framing) -> void:
	framing = f
	custom_minimum_size = Vector2(_rect().size) * _ps() + Vector2(6, 6)
	queue_redraw()


## app may be v1 or v2; bg: backdrop style; prof: animation profile.
func set_appearance(app: Dictionary, p_accent: Color = Palette.ACCENT, bg: StringName = &"", prof: StringName = &"") -> void:
	appearance = CharacterAppearanceManager.normalize(app) if not app.is_empty() else {}
	accent = p_accent
	if bg != &"":
		backdrop = bg
	if prof != &"":
		profile = prof
	_layers.clear()
	var cy: Array = appearance.get("cyber", [])
	CharacterAnimationManager.unregister(self)
	if is_inside_tree() or true:
		_anim = CharacterAnimationManager.register(self, profile, not cy.is_empty())
	queue_redraw()


## Shows a named story character (CharacterManager) with their backdrop
## and animation profile.
func set_character(id: StringName, expr: String = "") -> void:
	var c := CharacterManager.get_character(id)
	if c == null:
		return
	expression = expr
	set_appearance(CharacterManager.appearance(id), FactionManager.get_color(c.faction_id) if FactionManager.factions.has(c.faction_id) else Palette.ACCENT,
		c.portrait_bg, c.anim_profile)


func set_expression(e: String) -> void:
	if e != expression:
		expression = e
		queue_redraw()


func _textures() -> Array:
	var gaze := "closed" if bool(_anim.get("blink", false)) else str(_anim.get("gaze", "center"))
	var key := "%s|%s" % [expression, gaze]
	if not _layers.has(key):
		_layers[key] = CharacterArt.portrait_layers(appearance, expression, gaze)
	return _layers[key]


func _draw() -> void:
	var s := _ps()
	var cr := _rect()
	var area := Vector2(cr.size) * s
	var origin := ((size - area) / 2.0).floor()
	var r := Rect2(origin, area)
	draw_rect(r, Palette.BG_0)
	_draw_backdrop(r, s)
	if not appearance.is_empty():
		var tex: Array = _textures()
		var breath := int(_anim.get("breath", 0))
		var j: Vector2i = _anim.get("jitter", Vector2i.ZERO)
		var off := Vector2(j.x, -breath) * s
		var src := Rect2(cr)
		# Clip the shifted portrait to the frame.
		var dst := Rect2(r.position + off, r.size)
		var clip := dst.intersection(r)
		if clip.has_area():
			var src_clip := Rect2(src.position + (clip.position - dst.position) / s, clip.size / s)
			draw_texture_rect_region(tex[0], clip, src_clip)
			var glow := float(_anim.get("glow", 1.0))
			draw_texture_rect_region(tex[1], clip, src_clip, Color(1, 1, 1, 0.35 * glow))
		_draw_action(r, s, cr)
	# Grime vignette + scanlines + refresh sweep.
	for i in 4:
		draw_rect(Rect2(r.position.x, r.position.y + i * s, r.size.x, s), Color(0, 0, 0, 0.18 - i * 0.04))
		draw_rect(Rect2(r.position.x, r.end.y - (i + 1) * s, r.size.x, s), Color(0, 0, 0, 0.22 - i * 0.05))
	var y := r.position.y
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color(0, 0, 0, 0.1))
		y += s * 2
	# Frame + corner brackets
	draw_rect(r.grow(2), Palette.LINE, false, 2.0)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_rect(Rect2(corner + Vector2(-2 if sx > 0 else -8, -2 if sy > 0 else 0), Vector2(10, 2)), accent)
		draw_rect(Rect2(corner + Vector2(-2 if sx > 0 else 0, -2 if sy > 0 else -8), Vector2(2, 10)), accent)


## Idle action overlays (smoke from a cigarette, a glint when checking chrome).
func _draw_action(r: Rect2, s: float, cr: Rect2i) -> void:
	var act: StringName = _anim.get("action", &"")
	var t := float(_anim.get("action_t", 0.0))
	if act == &"smoke" and (appearance.get("accessories", []) as Array).has("cigarette"):
		var base := Vector2(63, 60) - Vector2(cr.position)
		for k in 4:
			var p := base + Vector2(sin(t * 6.0 + k) * 1.5 + k * 0.6, -t * 18.0 - k * 4.0)
			var a := clampf(0.45 - t * 0.35 - k * 0.07, 0.0, 1.0)
			if p.x >= 0 and p.y >= 0 and p.x < cr.size.x and p.y < cr.size.y:
				draw_rect(Rect2(r.position + p.floor() * s, Vector2(2, 1) * s), Color(0.75, 0.78, 0.82, a))
	elif act == &"check" and not (appearance.get("cyber", []) as Array).is_empty():
		var p := Vector2(55, 42) - Vector2(cr.position)
		if p.x >= 0 and p.y >= 0:
			draw_rect(Rect2(r.position + p * s, Vector2(s, s)), Color(accent, 0.7 * (1.0 - t)))


## Restrained, place-specific backdrops drawn in art pixels.
func _draw_backdrop(r: Rect2, s: float) -> void:
	var cols := int(r.size.x / s)
	var rows := int(r.size.y / s)
	var px := func(x: int, yy: int, w: int, h: int, c: Color) -> void:
		draw_rect(Rect2(r.position + Vector2(x, yy) * s, Vector2(w, h) * s), c)
	match backdrop:
		&"clinic":
			draw_rect(r, Color("10151a"))
			for yy in range(0, rows, 8):
				px.call(0, yy, cols, 1, Color("0b0f12"))
			for x in range(0, cols, 8):
				px.call(x, 0, 1, rows, Color("0b0f12"))
			px.call(4, 26, 9, 5, Color(Palette.BLOOD_DARK, 0.5))
			px.call(cols - 14, 60, 6, 9, Color("1d1a12"))
			draw_rect(Rect2(r.position, Vector2(r.size.x * 0.45, r.size.y * 0.35)), Color(0.85, 0.82, 0.6, 0.05))
		&"street":
			draw_rect(r, Color("0c0d14"))
			for yy in range(2, rows, 6):
				for x in range((yy / 6 % 2) * 6, cols, 12):
					px.call(x, yy, 11, 5, Color("11131c"))
			px.call(cols - 16, 10, 10, 3, Color(Palette.BRAND, 0.22))
			px.call(cols - 15, 14, 6, 1, Color(Palette.ACCENT, 0.18))
			for k in 10:
				var x := (k * 37 + int(_time)) % cols
				px.call(x, (k * 23) % rows, 1, 4, Color(0.6, 0.7, 0.9, 0.08))
		&"market":
			draw_rect(r, Color("120a16"))
			for k in 6:
				px.call(6 + k * 15, 8 + (k % 2) * 4, 2, 2, Color(Palette.BRAND, 0.35))
			for x in cols:
				px.call(x, 4 + int(sin(x * 0.18) * 2.0), 1, 1, Color("2a1a30"))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.6), Vector2(r.size.x, r.size.y * 0.4)), Color(0.4, 0.05, 0.3, 0.12))
		&"corporate":
			draw_rect(r, Color("161b24"))
			for x in range(0, cols, 4):
				px.call(x, 0, 1, rows, Color("1c2330"))
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Color(0.5, 0.65, 0.9, 0.06))
		&"medical":
			draw_rect(r, Color("121a18"))
			for yy in range(0, rows, 6):
				px.call(0, yy, cols, 1, Color("0e1513"))
			px.call(cols - 12, 8, 2, 6, Color(Palette.OK, 0.12))
			px.call(cols - 14, 10, 6, 2, Color(Palette.OK, 0.12))
		&"industrial":
			draw_rect(r, Color("15110e"))
			for k in 3:
				px.call(0, 14 + k * 22, cols, 3, Color("2a1c14"))
				px.call(0, 15 + k * 22, cols, 1, Color("3a2618"))
			px.call(10, 0, 2, rows, Color("1f1712"))
		&"lab":
			draw_rect(r, Color("0b1020"))
			for yy in range(0, rows, 5):
				px.call(0, yy, cols, 1, Color(0.2, 0.35, 0.8, 0.07))
			for k in 3:
				draw_arc(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.42), (14 + k * 10) * s, 3.4, 6.0, 24, Color(0.3, 0.5, 1.0, 0.07), s)
		&"bar":
			draw_rect(r, Color("161009"))
			for k in 12:
				px.call(4 + k * 8, 10 + (k % 3), 2, 5, Color(0.9, 0.6, 0.2, 0.15))
		_:
			draw_rect(r, Palette.BG_1)
