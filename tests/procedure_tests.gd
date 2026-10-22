extends RefCounted
## Every kind of chrome is put in its own way: each implant category's
## operation has a sequence of steps no other category shares, and a
## signature step only it has (docs/PROCEDURES.md lists them). Every
## step's interaction exists, its points sit on the operating field, and
## every mistake it can make has a cost, a label and a tip.
## Run by tests/test_runner.gd.

const SIGNATURE := {
	"neural": "map_cortex", "spine": "thread_bus", "arms": "tension_tendons", "legs": "load_test",
	"eyes": "fix_gaze", "dermal": "lay_plates", "respiratory": "seal_airway", "internal": "clamp_vessels",
}

## Ramp index of the sterile drape in the region art (tools/art/regions.py DR).
const DRAPE_RAMP := 12

var t: Node


func run(runner: Node) -> void:
	t = runner
	var by_cat := {}
	for id: StringName in SurgeryManager.surgeries:
		var s: SurgeryData = SurgeryManager.surgeries[id]
		by_cat[String(s.category)] = s
	t.check(by_cat.size() == SIGNATURE.size(), "an operation for each of the %d implant categories (%s)" % [SIGNATURE.size(), str(by_cat.keys())])
	var sequences := {}
	var step_owner := {}
	for cat: String in by_cat:
		var s: SurgeryData = by_cat[cat]
		var types := []
		for st in s.stages:
			types.append(String(st.type))
			step_owner[String(st.id)] = (step_owner.get(String(st.id), []) as Array) + [cat]
		var key := " > ".join(types)
		t.check(not sequences.has(key), "%s: its steps are its own (%s)" % [cat, key])
		sequences[key] = cat
	for cat: String in SIGNATURE:
		var sig: String = SIGNATURE[cat]
		t.check(step_owner.get(sig, []) == [cat], "%s: the signature step %s exists and belongs to it alone" % [cat, sig])
	var bad := []
	var kinds := {}
	for cat: String in by_cat:
		for st in (by_cat[cat] as SurgeryData).stages:
			if not SurgeryStageRegistry.STAGE_TYPES.has(st.type):
				bad.append("%s/%s: no interaction for %s" % [cat, st.id, st.type])
			for k in ["points", "anchors", "clamps", "path"]:
				for p in st.param_vec2_array(k):
					if p.x < 0.05 or p.x > 0.95 or p.y < 0.05 or p.y > 0.95:
						bad.append("%s/%s: %s point %s off the field" % [cat, st.id, k, p])
			if st.params.has("mistake"):
				kinds[str(st.params["mistake"])] = true
	t.check(bad.is_empty(), "every step has an interaction and its points on the field %s" % str(bad))
	_check_points_on_skin()
	var missing := []
	for k: String in kinds:
		var kn := StringName(k)
		if not GameConfig.MISTAKE_EFFECTS.has(kn) or not GameConfig.MISTAKE_LABELS.has(kn) or not SurgeryScreen.MISTAKE_TIPS.has(kn):
			missing.append(k)
	t.check(kinds.size() >= 8 and missing.is_empty(), "every signature mistake has a cost, a label and a tip (%d kinds) %s" % [kinds.size(), str(missing)])


## The drape covers everything but the opening: no point a step asks you
## to touch may land on it (iodine-prepped skin counts as skin).
func _check_points_on_skin() -> void:
	var images := {}
	var on_drape := []
	var n := 0
	for id: StringName in SurgeryManager.surgeries:
		var s: SurgeryData = SurgeryManager.surgeries[id]
		var region := s.get_region()
		if not images.has(region):
			images[region] = (load(SurgicalSiteView.REGION_TEXTURES[region]) as Texture2D).get_image()
		var img: Image = images[region]
		var pts: Array[Vector2] = []
		for st in s.stages:
			for k in ["points", "anchors", "clamps", "path"]:
				pts.append_array(st.param_vec2_array(k))
			if st.params.has("anchor"):
				pts.append(st.param_vec2("anchor", Vector2.ZERO))
		for p in pts:
			n += 1
			var px := img.get_pixel(clampi(int(p.x * img.get_width()), 0, img.get_width() - 1), clampi(int(p.y * img.get_height()), 0, img.get_height() - 1))
			if px.a == 0.0 or (px.r8 + 8) >> 4 == DRAPE_RAMP:
				on_drape.append("%s %s" % [id, p])
	# The check can see the drape at all: every region's corner is under it.
	var corners_draped := 0
	for region in images:
		var img: Image = images[region]
		corners_draped += 1 if (img.get_pixel(2, 2).r8 + 8) >> 4 == DRAPE_RAMP else 0
	t.check(corners_draped == images.size(), "the drape covers the corner of all %d region images" % images.size())
	t.check(n > 50 and on_drape.is_empty(), "every point a step uses (%d) lies on the exposed skin, not the drape %s" % [n, str(on_drape)])
