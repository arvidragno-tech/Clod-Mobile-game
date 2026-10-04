class_name PixelArt
extends RefCounted
## Runtime helpers that keep every sprite at the game's single pixel density
## (GameConfig.PIXEL_SCALE UI units per art pixel): cached loads, nearest
## upscaling for Button icons / TextureRects, and palette recolouring of
## indexed art (R = ramp*32, G = shade*32).

static var _textures: Dictionary = {}
static var _scaled: Dictionary = {}
static var _palettes: Dictionary = {}


## Drops cached textures (called on exit so GPU textures are released
## before the rendering server shuts down).
static func clear_cache() -> void:
	_textures.clear()
	_scaled.clear()


static func tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]


## Texture upscaled with nearest filtering so it displays at the game's
## pixel density when used at native size (Button icons, TextureRects).
static func scaled(path: String, factor: int = GameConfig.PIXEL_SCALE) -> Texture2D:
	var key := "%s@%d" % [path, factor]
	if _scaled.has(key):
		return _scaled[key]
	var t := tex(path)
	if t == null:
		return null
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(img.get_width() * factor, img.get_height() * factor, Image.INTERPOLATE_NEAREST)
	var out := ImageTexture.create_from_image(img)
	_scaled[key] = out
	return out


static func image(path: String) -> Image:
	var t := tex(path)
	if t == null:
		return null
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func palettes() -> Dictionary:
	if _palettes.is_empty():
		var parsed: Variant = DataLoader.load_json(GameConfig.DATA_PALETTES)
		if typeof(parsed) == TYPE_DICTIONARY:
			_palettes = parsed
	return _palettes


static func ramp(group: String, key: Variant) -> PackedColorArray:
	var p := palettes()
	var src: Variant = null
	if group == "skin":
		var skins: Array = p.get("skin", [])
		src = skins[clampi(int(key), 0, skins.size() - 1)] if not skins.is_empty() else null
	elif group == "fixed":
		src = p.get("fixed", [])
	else:
		var g: Dictionary = p.get(group, {})
		src = g.get(str(key), g.values()[0] if not g.is_empty() else null)
	var out := PackedColorArray()
	if src == null:
		for i in 8:
			out.append(Color(i / 7.0, i / 7.0, i / 7.0))
		return out
	for h: Variant in src:
		out.append(Color(str(h)))
	return out


const RAMP_COUNT := 16


## 16 ramps x 8 shades flattened as RGBA bytes for fast recolouring.
## 0 skin, 1 hair, 2 cloth A, 3 cloth B, 4 metal, 5 glow, 6 iris, 7 fixed,
## 8 cloth C, 9 leather, 10 grime, 11 blood (12-15 unused).
static func build_palette(app: Dictionary) -> PackedByteArray:
	var fixed := ramp("fixed", 0)
	if app.has("rim"):
		fixed = fixed.duplicate()
		fixed[7] = Color(str(app["rim"]))
	var ramps: Array[PackedColorArray] = [
		ramp("skin", app.get("skin", 2)),
		ramp("hair", app.get("hair_color", "black")),
		ramp("cloth", app.get("cloth_a", "charcoal")),
		ramp("cloth", app.get("cloth_b", "black")),
		ramp("metal", app.get("metal", "chrome")),
		ramp("glow", app.get("glow", "cyan")),
		ramp("iris", app.get("iris", "brown")),
		fixed,
		ramp("cloth", app.get("cloth_c", app.get("cloth_b", "black"))),
		ramp("material", "leather"),
		ramp("material", "grime"),
		ramp("material", "blood"),
	]
	while ramps.size() < RAMP_COUNT:
		ramps.append(fixed)
	var bytes := PackedByteArray()
	bytes.resize(RAMP_COUNT * 8 * 4)
	for r in RAMP_COUNT:
		for s in 8:
			var c: Color = ramps[r][s] if s < ramps[r].size() else Color.MAGENTA
			var i := (r * 8 + s) * 4
			bytes[i] = c.r8
			bytes[i + 1] = c.g8
			bytes[i + 2] = c.b8
			bytes[i + 3] = 255
	return bytes


## Composites indexed layers onto `out` (RGBA8 bytes, same size) using a
## palette from build_palette(). Later layers overwrite earlier ones.
static func blit_indexed(out: PackedByteArray, layer: Image, pal: PackedByteArray) -> void:
	var src := layer.get_data()
	var n := mini(src.size(), out.size())
	var i := 0
	while i < n:
		if src[i + 3] > 0:
			var ramp_i := clampi((src[i] + 8) >> 4, 0, RAMP_COUNT - 1)
			var shade := clampi((src[i + 1] + 16) >> 5, 0, 7)
			var p := (ramp_i * 8 + shade) * 4
			out[i] = pal[p]
			out[i + 1] = pal[p + 1]
			out[i + 2] = pal[p + 2]
			out[i + 3] = 255
		i += 4


## Recolours a single indexed image (e.g. a surgical-field anatomy texture).
static func recolor(path: String, app: Dictionary) -> ImageTexture:
	var img := image(path)
	if img == null:
		return null
	var out := PackedByteArray()
	out.resize(img.get_width() * img.get_height() * 4)
	blit_indexed(out, img, build_palette(app))
	return ImageTexture.create_from_image(Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, out))
