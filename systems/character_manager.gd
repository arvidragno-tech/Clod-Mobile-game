extends Node
## Registry of named characters (data/cast.json) and their runtime state:
## relationship value + state, fear, met / romance flags, and the
## appearance after every story event (so a character who lost an eye or
## joined a faction keeps looking like it). Customers stay in
## CustomerManager; staff appearances are owned by StaffManager.

signal relationship_changed(id: StringName, value: int, state: String)
signal appearance_changed(id: StringName)

const CAST_PATH := "res://data/cast.json"
## Display order of relationship states.
const STATES := ["hostile", "fearful", "suspicious", "neutral", "transactional", "respectful", "friendly", "loyal", "romantic"]
const STATE_COLORS := {"hostile": "ff4d4d", "fearful": "c46aff", "suspicious": "ffb43d", "neutral": "8e9aa8",
	"transactional": "c9a24a", "respectful": "6aa8ff", "friendly": "6dff8a", "loyal": "2ee6c8", "romantic": "ff7ab0"}
## Roles whose warm relationships read as respect rather than friendship.
const RESPECT_ROLES := [&"corporate", &"inspector", &"rival", &"gang_leader", &"mentor"]
const TRANSACTIONAL_ROLES := [&"fixer", &"creditor"]

var cast: Dictionary = {}  # id -> CharacterData
var state: Dictionary = {}  # id -> {rel, fear, met, romance, appearance, events, notes}


func _ready() -> void:
	var d: Variant = DataLoader.load_json(CAST_PATH)
	if typeof(d) == TYPE_DICTIONARY:
		for e: Variant in d.get("cast", []):
			var c := CharacterData.from_dict(e)
			cast[c.id] = c
	reset_state()


func reset_state() -> void:
	state.clear()
	for id: StringName in cast:
		var c: CharacterData = cast[id]
		state[id] = {"rel": c.start_relationship, "fear": 0, "met": false, "romance": false,
			"appearance": c.appearance.duplicate(true), "events": [], "notes": []}


func has_character(id: StringName) -> bool:
	return cast.has(id)


func get_character(id: StringName) -> CharacterData:
	return cast.get(id) as CharacterData


func appearance(id: StringName) -> Dictionary:
	if state.has(id):
		return state[id]["appearance"]
	return {}


func relationship(id: StringName) -> int:
	return int(state.get(id, {}).get("rel", 0))


func relationship_state(id: StringName) -> String:
	if not state.has(id):
		return "neutral"
	var s: Dictionary = state[id]
	var c: CharacterData = cast[id]
	var v := int(s["rel"])
	if bool(s.get("romance", false)) and v >= 40:
		return "romantic"
	if int(s.get("fear", 0)) >= 50 and v < 40:
		return "fearful"
	if v <= -50:
		return "hostile"
	if v <= -10:
		return "suspicious"
	if c.role in TRANSACTIONAL_ROLES and v < 45:
		return "transactional"
	if v < 15:
		return "neutral"
	if v >= 60:
		return "loyal"
	return "respectful" if c.role in RESPECT_ROLES else "friendly"


func state_color(st: String) -> Color:
	return Color(str(STATE_COLORS.get(st, "8e9aa8")))


func change_relationship(id: StringName, delta: int, fear_delta: int = 0) -> void:
	if not state.has(id):
		return
	var s: Dictionary = state[id]
	s["rel"] = clampi(int(s["rel"]) + delta, -100, 100)
	s["fear"] = clampi(int(s.get("fear", 0)) + fear_delta, 0, 100)
	relationship_changed.emit(id, int(s["rel"]), relationship_state(id))


func set_romance(id: StringName, on: bool) -> void:
	if state.has(id):
		state[id]["romance"] = on
		relationship_changed.emit(id, relationship(id), relationship_state(id))


func mark_met(id: StringName) -> void:
	if state.has(id) and not bool(state[id]["met"]):
		state[id]["met"] = true
		StoryManager.meet(id)


func has_met(id: StringName) -> bool:
	return bool(state.get(id, {}).get("met", false))


func met_characters() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in state:
		if bool(state[id]["met"]):
			out.append(id)
	return out


## A story event that changes how the character looks (lost an eye, new
## arm, faction colours...). Kept in history and saved.
func apply_appearance_event(id: StringName, event: String) -> void:
	if not state.has(id):
		return
	var s: Dictionary = state[id]
	s["appearance"] = CharacterAppearanceManager.apply_event(s["appearance"], event)
	s["events"].append(event)
	appearance_changed.emit(id)


func appearance_events(id: StringName) -> Array:
	return state.get(id, {}).get("events", [])


func add_note(id: StringName, note: String) -> void:
	if state.has(id):
		state[id]["notes"].append(note)


func get_save_data() -> Dictionary:
	var out := {}
	for id: StringName in state:
		var s: Dictionary = state[id]
		out[String(id)] = {"rel": s["rel"], "fear": s["fear"], "met": s["met"], "romance": s["romance"],
			"events": s["events"], "notes": s["notes"]}
	return out


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for key: Variant in data:
		var id := StringName(str(key))
		if not state.has(id) or typeof(data[key]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = data[key]
		var s: Dictionary = state[id]
		s["rel"] = clampi(int(d.get("rel", s["rel"])), -100, 100)
		s["fear"] = clampi(int(d.get("fear", 0)), 0, 100)
		s["met"] = bool(d.get("met", false))
		s["romance"] = bool(d.get("romance", false))
		s["notes"] = d.get("notes", [])
		# Re-apply appearance events in order (appearance is derived).
		for ev: Variant in d.get("events", []):
			s["appearance"] = CharacterAppearanceManager.apply_event(s["appearance"], str(ev))
			s["events"].append(str(ev))
