extends Node
## Data-driven character looks (data/appearance_rules.json).
##
## generate(): builds a v2 appearance from occupation + faction + wealth +
## age + personality + installed cyberware, so a character's look tells who
## they are before they speak (silhouette from occupation/posture, palette
## and rim light from faction, wear from wealth, features from age).
## normalize(): upgrades v1 appearance dicts (old saves, old data).
## apply_event(): visible consequences (lost eye, new arm, scars, promotion,
## faction corruption) so recurring characters change over time.

const RULES_PATH := "res://data/appearance_rules.json"

var rules: Dictionary = {}


func _ready() -> void:
	var d: Variant = DataLoader.load_json(RULES_PATH)
	rules = d if typeof(d) == TYPE_DICTIONARY else {}


func occupations() -> Array:
	return rules.get("occupations", {}).keys()


func occupation_label(id: String) -> String:
	return str(rules.get("occupations", {}).get(id, {}).get("label", id.capitalize()))


static func _pick_w(rng: RandomNumberGenerator, weights: Variant) -> String:
	if weights is Array:
		var arr: Array = weights
		return str(arr[rng.randi() % arr.size()]) if not arr.is_empty() else ""
	var d: Dictionary = weights if weights is Dictionary else {}
	var total := 0.0
	for k: Variant in d:
		total += float(d[k])
	if total <= 0.0:
		return ""
	var r := rng.randf() * total
	for k: Variant in d:
		r -= float(d[k])
		if r <= 0.0:
			return str(k)
	return str(d.keys()[d.size() - 1])


## ctx: occupation, faction, wealth (0-3), age, personality, presentation,
## cyberware (Array of CyberwareData ids), seed.
func generate(ctx: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = int(ctx.get("seed", randi()))
	var occ_id := str(ctx.get("occupation", "civilian"))
	var occ: Dictionary = rules.get("occupations", {}).get(occ_id, rules.get("occupations", {}).get("civilian", {}))
	var faction := str(ctx.get("faction", occ.get("faction_default", "none")))
	var fac: Dictionary = rules.get("factions", {}).get(faction, rules.get("factions", {}).get("none", {}))
	var wealth := int(ctx.get("wealth", occ.get("wealth", 1)))
	var age := int(ctx.get("age", 30))
	var pres := str(ctx.get("presentation", _pick_w(rng, rules.get("presentations", {"masc": 1}))))
	var a := {
		"v": 2,
		"presentation": pres,
		"build": _pick_w(rng, occ.get("builds", {"average": 1})),
		"posture": _pick_w(rng, occ.get("postures", {"upright": 1})),
		"face": _pick_w(rng, occ.get("faces", rules.get("faces", {"oval": 1}))),
		"nose": _pick_w(rng, rules.get("noses", {"straight": 1})),
		"brows": "heavy" if pres == "masc" and rng.randf() < 0.6 else "thin",
		"age_look": "young" if age < 28 else ("adult" if age < 52 else "old"),
		"expr": str(rules.get("expr_by_personality", {}).get(str(ctx.get("personality", "calm")), "neutral")),
		"outfit": _pick_w(rng, occ.get("outfit", {"civilian": 1})),
		"skin": rng.randi_range(0, 6),
		"iris": _pick_w(rng, rules.get("iris", ["brown"])),
		"facial_hair": "",
		"scars": [], "tattoos": [], "makeup": [], "piercings": [], "cyber": [], "accessories": [],
		"body_cyber": [], "body_acc": [],
		"metal": _pick_w(rng, fac.get("metal", ["chrome"])),
		"glow": _pick_w(rng, fac.get("glow", ["cyan"])),
		"rim": str(fac.get("rim", "3b9da0")),
	}
	var palette: Dictionary = fac.get("palette", {})
	for k in ["cloth_a", "cloth_b", "cloth_c"]:
		a[k] = _pick_w(rng, palette.get(k, ["charcoal"]))
	# Occupation colours dominate for uniforms; faction colours for the rest.
	if a["outfit"] == "worker":
		a["cloth_b"] = "safety"
		a["cloth_a"] = _pick_w(rng, ["work_blue", "work_brown", "charcoal"])
	elif a["outfit"] == "medic":
		a["cloth_a"] = "scrub_green"
		a["cloth_b"] = "dirty_white"
	elif a["outfit"] == "military":
		a["cloth_a"] = "military_olive"
	elif a["outfit"] == "patient":
		a["cloth_a"] = "dirty_white"
	# Hair: style by presentation, colour by age / subculture.
	var hair_w: Dictionary = rules.get("hair_by_presentation", {}).get(pres, {"short": 1})
	a["hair"] = _pick_w(rng, hair_w)
	if age >= 55 and rng.randf() < 0.75:
		a["hair_color"] = "white" if age > 68 and rng.randf() < 0.6 else "gray"
		if a["hair"] in ["mohawk", "topknot"]:
			a["hair"] = "receding" if pres == "masc" else "tied"
	elif rng.randf() < float(occ.get("dye_chance", 0.1)):
		a["hair_color"] = _pick_w(rng, rules.get("dyed_hair", ["dye_cyan"]))
	else:
		a["hair_color"] = _pick_w(rng, rules.get("natural_hair", ["black"]))
	if pres == "masc" and age > 20 and rng.randf() < 0.55:
		a["facial_hair"] = _pick_w(rng, {"stubble": 4, "beard": 2, "goatee": 1, "mustache": 1, "full": 1, "chops": 1})
	# Marks of a hard life.
	if rng.randf() < float(occ.get("scar", 0.2)):
		a["scars"].append(_pick_w(rng, ["cheek", "brow", "lip", "slash", "burn", "stitched"]))
	if rng.randf() < float(occ.get("tattoo", 0.2)):
		a["tattoos"].append(_pick_w(rng, occ.get("tattoos", ["neck_code", "cheek_lines", "tear", "jaw_ink"])))
	if rng.randf() < float(occ.get("piercing", 0.2)):
		a["piercings"].append(_pick_w(rng, ["brow_ring", "nose_ring", "lip_ring", "ear_gauges", "septum", "studs"]))
	var mk := float(occ.get("makeup", 0.1)) * (1.6 if pres == "femme" else (0.7 if pres == "andro" else 0.35))
	if rng.randf() < mk:
		a["makeup"].append(_pick_w(rng, occ.get("makeups", ["liner", "lipstick", "smudge"])))
	# Accessories (portrait) and kit (body).
	var acc := _pick_w(rng, occ.get("accessories", {"none": 1}))
	if acc != "none" and acc != "":
		a["accessories"].append(acc)
	var bacc := _pick_w(rng, occ.get("body_acc", {"none": 1}))
	if bacc != "none" and bacc != "":
		a["body_acc"].append(bacc)
	if occ.has("body_cyber"):
		var bcy := _pick_w(rng, occ["body_cyber"])
		if bcy != "none" and bcy != "":
			a["body_cyber"].append(bcy)
	if acc == "hood":
		a["body_acc"].append("hood")
	elif acc == "helmet":
		a["body_acc"].append("helmet")
	elif acc == "cigarette" and not a["body_acc"].has("cigarette"):
		a["body_acc"].append("cigarette")
	# Cyberware the character really has drives what you see.
	var had_cyber := false
	for id: Variant in ctx.get("cyberware", []):
		var item := CyberwareManager.get_cyberware(StringName(str(id)))
		if item == null:
			continue
		var cat := String(item.category)
		var v := _pick_w(rng, rules.get("cyber_by_category", {}).get(cat, {}))
		if v != "" and not a["cyber"].has(v):
			a["cyber"].append(v)
			had_cyber = true
		var bv := _pick_w(rng, rules.get("body_cyber_by_category", {}).get(cat, {}))
		if bv != "" and not a["body_cyber"].has(bv):
			a["body_cyber"].append(bv)
		if item.tier >= 3:
			a["metal"] = "gunmetal" if item.tier == 3 else "ceramic"
		if item.black_market:
			a["metal"] = "blackened"
	if not had_cyber and rng.randf() < 0.45:
		var v := _pick_w(rng, occ.get("cyber", {}))
		if v != "":
			a["cyber"].append(v)
	if a["cyber"].has("optic") or a["cyber"].has("face_half"):
		a["body_cyber"].append("eye")
	if a["cyber"].has("visor") or a["cyber"].has("twin_optics") or a["cyber"].has("face_half"):
		a["accessories"].erase("shades")
		a["accessories"].erase("glasses")
	# Poverty shows: cheap brass, patched implants; wealth hides chrome.
	if wealth <= 0 and rng.randf() < 0.5:
		a["metal"] = "brass"
		if not a["cyber"].is_empty() and rng.randf() < 0.5:
			a["cyber"].append("patched_implant")
	if wealth >= 3 and a["cyber"].has("patched_implant"):
		a["cyber"].erase("patched_implant")
	return a


# --- v1 -> v2 -------------------------------------------------------------------

const V1_FACE := {"narrow": "long", "broad": "square", "round": "round"}
const V1_EXPR := {"neutral": "neutral", "hard": "angry", "smirk": "smirk", "tired": "sad"}
const V1_OUTFIT := {"mercenary": "mercenary", "gang": "gang", "corporate": "corporate", "smuggler": "civilian", "dock": "worker",
	"bounty": "mercenary", "fixer": "fixer", "criminal": "gang", "civilian": "civilian", "bm_tech": "technician",
	"medical": "medic", "boss": "executive"}
const V1_CYBER := {"eye": "optic", "visor": "visor", "jaw": "jaw_plate", "temple_port": "temple_ports", "circuit": "cheek_leds",
	"neck_ports": "neck_ports", "skull_plate": "skull_plate", "cheek_mesh": "skin_seam", "arm_shoulder": "shoulder_chrome",
	"dermal": "serial_marks", "respirator": ""}
const V1_ACC := {"earring": "", "shades": "shades", "goggles": "goggles", "headset": "headset", "mask": "surgical_mask",
	"nose_ring": "", "beanie": "beanie", "hood": "hood", "cap": "cap"}
const V1_BODY_CYBER := {"arm": "arm_r", "legs": "legs", "eye": "eye", "visor": "eye", "spine": "spine"}
const POSTURE_BY_OUTFIT := {"gang": "wide", "mercenary": "wide", "worker": "slouch", "corporate": "upright", "executive": "upright",
	"security": "upright", "addict": "hunched", "elder": "hunched", "civilian": "slouch", "technician": "slouch"}


func normalize(app: Dictionary) -> Dictionary:
	if app.is_empty() or int(app.get("v", 1)) >= 2:
		return app
	var a := {
		"v": 2,
		"presentation": "andro",
		"build": str(app.get("build", "average")),
		"face": V1_FACE.get(str(app.get("face", "round")), "oval"),
		"expr": V1_EXPR.get(str(app.get("expr", "neutral")), "neutral"),
		"outfit": V1_OUTFIT.get(str(app.get("outfit", "civilian")), "civilian"),
		"hair": str(app.get("hair", "short")),
		"nose": "straight", "brows": "thin", "age_look": "adult",
		"facial_hair": str(app.get("facial_hair", "")),
		"scars": [], "tattoos": [], "makeup": [], "piercings": [], "cyber": [], "accessories": [],
		"body_cyber": [], "body_acc": [],
	}
	if a["hair"] == "bald" or a["hair"] == "":
		a["hair"] = "bald"
	a["posture"] = POSTURE_BY_OUTFIT.get(a["outfit"], "upright")
	if a["build"] not in ["slim", "average", "heavy", "muscular"]:
		a["build"] = "average"
	var fh: String = a["facial_hair"]
	if fh != "" and fh not in ["stubble", "beard", "goatee", "mustache", "full", "chops"]:
		a["facial_hair"] = ""
	if a["facial_hair"] != "":
		a["presentation"] = "masc"
		a["brows"] = "heavy"
	var scar := str(app.get("scar", ""))
	if scar in ["cheek", "brow", "lip"]:
		a["scars"].append(scar)
	for t: Variant in app.get("tattoos", []):
		var tt: String = {"neck_code": "neck_code", "face_lines": "cheek_lines", "gang_mark": "gang_throat", "tear": "tear"}.get(str(t), "")
		if tt != "":
			a["tattoos"].append(tt)
	for c: Variant in app.get("cyber", []):
		var cc: String = V1_CYBER.get(str(c), "")
		if cc != "":
			a["cyber"].append(cc)
		elif str(c) == "respirator":
			a["accessories"].append("respirator")
	for x: Variant in app.get("accessories", []):
		var ac: String = V1_ACC.get(str(x), "")
		if ac != "":
			a["accessories"].append(ac)
		elif str(x) == "earring":
			a["piercings"].append("studs")
		elif str(x) == "nose_ring":
			a["piercings"].append("nose_ring")
	for b: Variant in app.get("body_cyber", []):
		var bc: String = V1_BODY_CYBER.get(str(b), "")
		if bc != "" and not a["body_cyber"].has(bc):
			a["body_cyber"].append(bc)
	if a["accessories"].has("hood"):
		a["body_acc"].append("hood")
	for k in ["skin", "hair_color", "iris", "cloth_a", "cloth_b", "metal", "glow"]:
		if app.has(k):
			a[k] = app[k]
	a["cloth_c"] = app.get("cloth_b", "black")
	return a


# --- Visible consequences ----------------------------------------------------------

## Applies a story/progression event to an appearance (returns a copy).
## Events: lose_eye, cyber_eye, cyber_arm, cyber_legs, injury, scar:<kind>,
## upgrade_outfit:<outfit>, accessory:<id>, remove_accessory:<id>,
## cyber:<id>, faction:<faction_id>, wealth_up, wealth_down, age_up, expr:<e>.
func apply_event(app: Dictionary, event: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash(event)
	if app.is_empty():
		return app  # no face to change (e.g. a record from before appearances)
	var a := normalize(app).duplicate(true)
	for k in ["scars", "cyber", "body_cyber", "accessories", "body_acc"]:
		if not a.get(k) is Array:
			a[k] = []
	var parts := event.split(":")
	var kind := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match kind:
		"lose_eye", "cyber_eye":
			if not a["cyber"].has("optic"):
				a["cyber"].append("optic")
			if not a["body_cyber"].has("eye"):
				a["body_cyber"].append("eye")
			if kind == "lose_eye" and not a["scars"].has("brow"):
				a["scars"].append("brow")
		"cyber_arm":
			if not a["body_cyber"].has("arm_r"):
				a["body_cyber"].append("arm_r")
			if not a["cyber"].has("shoulder_chrome"):
				a["cyber"].append("shoulder_chrome")
		"cyber_legs":
			if not a["body_cyber"].has("legs"):
				a["body_cyber"].append("legs")
		"injury":
			var options := ["cheek", "brow", "lip", "slash", "stitched", "burn"].filter(func(s: String) -> bool: return not a["scars"].has(s))
			if not options.is_empty():
				a["scars"].append(options[rng.randi() % options.size()])
		"scar":
			if not a["scars"].has(arg):
				a["scars"].append(arg)
		"upgrade_outfit":
			a["outfit"] = arg
		"accessory":
			if not a["accessories"].has(arg):
				a["accessories"].append(arg)
		"body_acc":
			if not a["body_acc"].has(arg):
				a["body_acc"].append(arg)
		"remove_accessory":
			a["accessories"].erase(arg)
			a["body_acc"].erase(arg)
		"cyber":
			if not a["cyber"].has(arg):
				a["cyber"].append(arg)
		"faction":
			var fac: Dictionary = rules.get("factions", {}).get(arg, {})
			if not fac.is_empty():
				a["glow"] = _pick_w(rng, fac.get("glow", ["cyan"]))
				a["rim"] = str(fac.get("rim", a.get("rim", "3b9da0")))
				a["cloth_c"] = _pick_w(rng, fac.get("palette", {}).get("cloth_c", [a.get("cloth_c", "black")]))
		"wealth_up":
			a["metal"] = "ceramic" if a.get("metal", "") in ["chrome", "gunmetal"] else "chrome"
			a["cyber"].erase("patched_implant")
		"wealth_down":
			a["metal"] = "brass"
		"age_up":
			a["age_look"] = "old" if a.get("age_look", "adult") == "adult" else "adult"
		"expr":
			a["expr"] = arg
	return a
