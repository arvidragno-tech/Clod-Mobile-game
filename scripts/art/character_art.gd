class_name CharacterArt
extends RefCounted
## Builds unique character sprites from palette-indexed part layers
## (tools/art/characters.py → data/character_parts.json). One portrait
## (64x64) and one full body (32x64) per appearance, cached.

const PORTRAIT_SIZE := Vector2i(64, 64)
const BODY_SIZE := Vector2i(32, 64)
const CACHE_LIMIT := 48
## Portrait-cyberware that has a matching body overlay.
const BODY_CYBER_FROM_PORTRAIT := {"eye": "eye", "visor": "visor"}

static var _manifest: Dictionary = {}
static var _layers: Dictionary = {}
static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = DataLoader.load_json(GameConfig.DATA_CHARACTER_PARTS)
		if typeof(parsed) == TYPE_DICTIONARY:
			_manifest = parsed
	return _manifest


static func portrait(app: Dictionary) -> Texture2D:
	return _fetch(&"portrait", app)


static func body(app: Dictionary) -> Texture2D:
	return _fetch(&"body", app)


## Ids per slot that a given appearance uses in a view.
static func parts_for(view: StringName, app: Dictionary) -> Dictionary:
	var build := str(app.get("build", "average"))
	var face := str(app.get("face", "round"))
	var out := {}
	if view == &"portrait":
		out["hair_back"] = [app.get("hair_back", "")]
		out["body"] = [build]
		out["outfit"] = ["%s_%s" % [app.get("outfit", "civilian"), build]]
		out["head"] = ["%s_%s" % [face, app.get("expr", "neutral")]]
		var fh := str(app.get("facial_hair", ""))
		out["facial_hair"] = ["%s_%s" % [fh, face]] if fh != "" else []
		out["scar"] = [app.get("scar", "")]
		out["tattoo"] = app.get("tattoos", [])
		out["hair"] = [app.get("hair", "short")]
		out["cyber"] = app.get("cyber", [])
		out["accessory"] = app.get("accessories", [])
	else:
		out["body"] = [build]
		out["outfit"] = ["%s_%s" % [app.get("outfit", "civilian"), build]]
		var cyber: Array = []
		for c: Variant in app.get("body_cyber", []):
			cyber.append("%s_%s" % [c, build])
		for c: Variant in app.get("cyber", []):
			if BODY_CYBER_FROM_PORTRAIT.has(str(c)):
				cyber.append("%s_%s" % [BODY_CYBER_FROM_PORTRAIT[str(c)], build])
		out["cyber"] = cyber
		out["hair"] = [app.get("hair", "short")]
	return out


static func _fetch(view: StringName, app: Dictionary) -> Texture2D:
	var key := "%s|%s" % [view, JSON.stringify(app, "", true)]
	if _cache.has(key):
		return _cache[key]
	var tex := _build(view, app)
	_cache[key] = tex
	_cache_order.append(key)
	if _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())
	return tex


static func _build(view: StringName, app: Dictionary) -> ImageTexture:
	var size := PORTRAIT_SIZE if view == &"portrait" else BODY_SIZE
	var m := manifest()
	var view_parts: Dictionary = m.get("views", {}).get(String(view), {})
	var order: Array = m.get("layer_order", {}).get(String(view), [])
	var out := PackedByteArray()
	out.resize(size.x * size.y * 4)
	var pal := PixelArt.build_palette(app)
	var wanted := parts_for(view, app)
	for slot: Variant in order:
		var ids: Array = wanted.get(str(slot), [])
		var available: Dictionary = view_parts.get(str(slot), {})
		for pid: Variant in ids:
			var path: String = available.get(str(pid), "")
			if path.is_empty():
				continue
			var layer := _layer(path)
			if layer and layer.get_width() == size.x and layer.get_height() == size.y:
				PixelArt.blit_indexed(out, layer, pal)
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, out))


static func _layer(path: String) -> Image:
	if not _layers.has(path):
		_layers[path] = PixelArt.image(path)
	return _layers[path]


## Whether every part an appearance refers to exists (used by tests).
static func validate(app: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var m := manifest()
	for view: StringName in [&"portrait", &"body"]:
		var view_parts: Dictionary = m.get("views", {}).get(String(view), {})
		var wanted := parts_for(view, app)
		for slot: Variant in wanted:
			for pid: Variant in wanted[slot]:
				if str(pid) != "" and not view_parts.get(str(slot), {}).has(str(pid)):
					missing.append("%s/%s/%s" % [view, slot, pid])
	return missing
