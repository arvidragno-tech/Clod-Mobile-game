extends Node
## Resolves "who is this" into a portrait: current appearance (story cast,
## staff or customer), backdrop by place/faction, animation profile, and
## pre-composites expression variants before a dialogue so swaps are
## instant. The compositing itself lives in CharacterArt.

const BACKDROP_BY_FACTION := {
	&"corporate_security": &"corporate", &"lyra_biocomp": &"corporate", &"street_gangs": &"street",
	&"black_market": &"market", &"medical_authorities": &"medical", &"independent_mercs": &"industrial",
}
const PROFILE_BY_PERSONALITY := {
	&"calm": &"calm", &"stoic": &"still", &"cold": &"still", &"nervous": &"nervous", &"paranoid": &"nervous",
	&"hard": &"aggressive", &"volatile": &"aggressive", &"cocky": &"fidget", &"tired": &"calm", &"desperate": &"withdrawal",
	&"friendly": &"fidget",
}


## {appearance, name, subtitle, faction, backdrop, profile, accent, relationship}
func describe(id: StringName) -> Dictionary:
	if CharacterManager.has_character(id):
		var c := CharacterManager.get_character(id)
		var st := CharacterManager.relationship_state(id)
		return {"appearance": CharacterManager.appearance(id), "name": c.title(), "subtitle": c.occupation,
			"faction": c.faction_name(), "backdrop": c.portrait_bg, "profile": c.anim_profile,
			"accent": _faction_color(c.faction_id), "relationship": st, "voice": c.voice_pitch}
	var staff := get_node_or_null("/root/StaffManager")
	if staff:
		var e: Dictionary = staff.call("get_employee", id)
		if not e.is_empty():
			return {"appearance": e["appearance"], "name": str(e["name"]), "subtitle": str(staff.call("spec_label", e)),
				"faction": "Clinic staff", "backdrop": &"clinic", "profile": StringName(str(e.get("anim", "calm"))),
				"accent": Palette.ACCENT, "relationship": str(staff.call("loyalty_label", e)), "voice": 1.0}
	var cust := CustomerManager.get_customer(id) if CustomerManager.characters.has(id) else null
	if cust == null and CustomerManager.current_customer and CustomerManager.current_customer.id == id:
		cust = CustomerManager.current_customer
	if cust:
		return {"appearance": CharacterAppearanceManager.normalize(cust.appearance), "name": cust.get_display_title(),
			"subtitle": cust.occupation, "faction": FactionManager.get_name_of(cust.faction_id),
			"backdrop": BACKDROP_BY_FACTION.get(cust.faction_id, &"street"),
			"profile": PROFILE_BY_PERSONALITY.get(cust.personality, &"calm"),
			"accent": _faction_color(cust.faction_id), "relationship": "customer", "voice": 1.0}
	return {}


func _faction_color(f: StringName) -> Color:
	return FactionManager.get_color(f) if FactionManager.factions.has(f) else Palette.ACCENT


## Builds every expression for a character up front (dialogue start).
func prewarm(id: StringName, expressions: Array = ["neutral", "angry", "smirk", "sad", "fear", "pain"]) -> void:
	var d := describe(id)
	if d.is_empty():
		return
	for e: Variant in expressions:
		CharacterArt.portrait_layers(d["appearance"], str(e), "center")
