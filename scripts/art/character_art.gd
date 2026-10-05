class_name CharacterArt
extends RefCounted
## Composites character sprites from the v2 part atlases
## (tools/art/characters2.py -> data/character_parts.json): a 96x112
## portrait (bust) and a 40x80 in-room body. Every part is palette-indexed
## and cropped to its bounding box, so a composite only touches the pixels
## the parts cover (a few ms), which makes expression / gaze / blink
## variants cheap. A second texture holds only the emissive cyberware
## pixels so animation can flicker them.

const CACHE_LIMIT := 96
const GLOW_RAMP := 5

static var _manifest: Dictionary = {}
static var _atlases: Dictionary = {}  # "view/slot" -> PackedByteArray (RGBA8) + width
static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []


static func clear_cache() -> void:
	_atlases.clear()
	_cache.clear()
	_cache_order.clear()


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = DataLoader.load_json(GameConfig.DATA_CHARACTER_PARTS)
		if typeof(parsed) == TYPE_DICTIONARY:
			_manifest = parsed
	return _manifest


static func size_of(view: StringName) -> Vector2i:
	var s: Array = manifest().get("sizes", {}).get(String(view), [96, 112] if view == &"portrait" else [40, 80])
	return Vector2i(int(s[0]), int(s[1]))


## Portrait for an appearance. expr / gaze override the appearance's own.
static func portrait(app: Dictionary, expr: String = "", gaze: String = "center") -> Texture2D:
	return _fetch(&"portrait", app, expr, gaze)[0]


## [texture, glow_texture] for animated portraits.
static func portrait_layers(app: Dictionary, expr: String = "", gaze: String = "center") -> Array:
	return _fetch(&"portrait", app, expr, gaze)


static func body(app: Dictionary) -> Texture2D:
	return _fetch(&"body", app, "", "")[0]


static func body_layers(app: Dictionary) -> Array:
	return _fetch(&"body", app, "", "")


## Part ids per slot an appearance uses in a view (v2 appearance schema,
## see CharacterAppearanceManager).
static func parts_for(view: StringName, app: Dictionary, expr: String = "", gaze: String = "center") -> Dictionary:
	var build := str(app.get("build", "average"))
	var out := {}
	if view == &"portrait":
		var e := expr if expr != "" else str(app.get("expr", "neutral"))
		var face := str(app.get("face", "oval"))
		var hair := str(app.get("hair", "short"))
		var covered := _covers_hair(app)
		out["hair_back"] = [hair] if hair in ["long", "tied", "locs", "braids"] and not covered else []
		out["body"] = [build]
		out["outfit"] = ["%s_%s" % [app.get("outfit", "civilian"), build]]
		out["head"] = [face]
		var age := str(app.get("age_look", "adult"))
		out["age"] = [] if age == "young" else [age]
		out["nose"] = [app.get("nose", "straight")]
		out["mouth"] = [e]
		out["brows"] = ["%s_%s" % [e, app.get("brows", "thin")]]
		out["eyes"] = ["%s_%s" % [e, gaze]]
		var fh := str(app.get("facial_hair", ""))
		out["facial_hair"] = ["%s_%s" % [fh, face]] if fh != "" else []
		out["scar"] = app.get("scars", [])
		out["tattoo"] = app.get("tattoos", [])
		out["makeup"] = app.get("makeup", [])
		out["piercing"] = app.get("piercings", [])
		out["cyber_low"] = app.get("cyber", [])
		out["cyber"] = app.get("cyber", [])
		out["hair"] = [] if covered or hair == "bald" else [hair]
		out["accessory"] = app.get("accessories", [])
	else:
		var key := "%s_%s" % [build, app.get("posture", "upright")]
		out["body"] = [key]
		out["outfit"] = ["%s_%s" % [app.get("outfit", "civilian"), key]]
		var cy: Array = []
		for c: Variant in app.get("body_cyber", []):
			cy.append("%s_%s" % [c, key])
		out["cyber"] = cy
		var acc: Array = []
		for a: Variant in app.get("body_acc", []):
			acc.append("%s_%s" % [a, key])
		# What the portrait wears on the face and head shows on the body too.
		for a: Variant in app.get("accessories", []):
			var mapped := str(PORTRAIT_TO_BODY.get(str(a), ""))
			if mapped != "" and not acc.has("%s_%s" % [mapped, key]):
				acc.append("%s_%s" % [mapped, key])
		out["acc"] = acc
		var hair := str(app.get("hair", "short"))
		var hooded := false
		for a: Variant in app.get("body_acc", []):
			hooded = hooded or str(a) in ["hood", "helmet"]
		out["hair"] = [] if hooded or hair == "bald" else ["%s_%s" % [hair, key]]
	return out


## Portrait accessories that have a body-sprite version.
const PORTRAIT_TO_BODY := {
	"bandana": "mask", "scarf": "mask", "surgical_mask": "mask", "respirator": "respirator",
	"shades": "eyewear", "goggles": "eyewear", "glasses": "eyewear", "monocle": "eyewear",
	"beanie": "beanie", "cap": "cap", "hood": "hood", "helmet": "helmet",
}


static func _covers_hair(app: Dictionary) -> bool:
	for a: Variant in app.get("accessories", []):
		if str(a) in ["hood", "helmet"]:
			return true
	return false


static func _fetch(view: StringName, app: Dictionary, expr: String, gaze: String) -> Array:
	var key := "%s|%s|%s|%s" % [view, expr, gaze, JSON.stringify(app, "", true)]
	if _cache.has(key):
		return _cache[key]
	var res := _build(view, app, expr, gaze)
	_cache[key] = res
	_cache_order.append(key)
	if _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())
	return res


static func _atlas(view: StringName, slot: String) -> Dictionary:
	var k := "%s/%s" % [view, slot]
	if not _atlases.has(k):
		var path: String = manifest().get("atlases", {}).get(k, "")
		var img: Image = PixelArt.image(path) if path != "" else null
		if img:
			img.convert(Image.FORMAT_RGBA8)
			_atlases[k] = {"data": img.get_data(), "w": img.get_width()}
		else:
			_atlases[k] = {}
	return _atlases[k]


static func _build(view: StringName, app: Dictionary, expr: String, gaze: String) -> Array:
	var size := size_of(view)
	var m := manifest()
	var order: Array = m.get("layer_order", {}).get(String(view), [])
	var parts: Dictionary = m.get("parts", {}).get(String(view), {})
	var out := PackedByteArray()
	out.resize(size.x * size.y * 4)
	var glow := PackedByteArray()
	glow.resize(size.x * size.y * 4)
	var pal := PixelArt.build_palette(app)
	var wanted := parts_for(view, app, expr, gaze)
	for slot: Variant in order:
		var ids: Array = wanted.get(str(slot), [])
		if ids.is_empty():
			continue
		var available: Dictionary = parts.get(str(slot), {})
		var atlas := _atlas(view, str(slot))
		if atlas.is_empty():
			continue
		for pid: Variant in ids:
			var r: Array = available.get(str(pid), [])
			if r.size() < 6:
				continue
			_blit(out, glow, size.x, atlas["data"], int(atlas["w"]), r, pal)
	var tex := ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, out))
	var gtex := ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, glow))
	return [tex, gtex]


## Copies one cropped part (atlas rect r = [ax, ay, w, h, ox, oy]) into the
## composite, recolouring through the palette. Emissive (glow ramp) pixels
## are mirrored into `glow`; any other pixel clears glow underneath it.
static func _blit(out: PackedByteArray, glow: PackedByteArray, ow: int, src: PackedByteArray, sw: int, r: Array, pal: PackedByteArray) -> void:
	var ax := int(r[0])
	var ay := int(r[1])
	var w := int(r[2])
	var h := int(r[3])
	var ox := int(r[4])
	var oy := int(r[5])
	for yy in h:
		var si := ((ay + yy) * sw + ax) * 4
		var di := ((oy + yy) * ow + ox) * 4
		for xx in w:
			if src[si + 3] > 0:
				var ramp_i := clampi((src[si] + 8) >> 4, 0, PixelArt.RAMP_COUNT - 1)
				var shade := clampi((src[si + 1] + 16) >> 5, 0, 7)
				var p := (ramp_i * 8 + shade) * 4
				out[di] = pal[p]
				out[di + 1] = pal[p + 1]
				out[di + 2] = pal[p + 2]
				out[di + 3] = 255
				if ramp_i == GLOW_RAMP and shade >= 3:
					glow[di] = pal[p]
					glow[di + 1] = pal[p + 1]
					glow[di + 2] = pal[p + 2]
					glow[di + 3] = 255
				else:
					glow[di + 3] = 0
			si += 4
			di += 4


## Missing part ids for an appearance (used by tests).
static func validate(app: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var parts: Dictionary = manifest().get("parts", {})
	for view: StringName in [&"portrait", &"body"]:
		var wanted := parts_for(view, app)
		for slot: Variant in wanted:
			for pid: Variant in wanted[slot]:
				var slot_parts: Dictionary = parts.get(String(view), {}).get(str(slot), {})
				# cyber ids live in either cyber or cyber_low
				if str(slot) in ["cyber", "cyber_low"]:
					var all_c: Dictionary = parts.get(String(view), {}).get("cyber", {}).duplicate()
					all_c.merge(parts.get(String(view), {}).get("cyber_low", {}))
					slot_parts = all_c
				if str(pid) != "" and not slot_parts.has(str(pid)):
					missing.append("%s/%s/%s" % [view, slot, pid])
	return missing
