class_name CharacterData
extends Resource
## A named character (story cast, staff). Identity, personality and a v2
## appearance; runtime state (relationship, appearance changes) lives in
## CharacterManager so this stays pure data.

@export var id: StringName
@export var display_name: String
@export var alias: String = ""
@export var age: int = 30
@export var presentation: String = "andro"
@export var occupation: String = ""
@export var faction_id: StringName = &"none"
@export var role: StringName = &""
## corporate / gang / fixer / doctor / worker / street / official
@export var dialogue_style: StringName = &"street"
@export var personality: Array[String] = []
@export_multiline var background: String = ""
@export_multiline var motivation: String = ""
@export_multiline var arc: String = ""
@export_multiline var silhouette: String = ""
@export var appearance: Dictionary = {}
@export var portrait_bg: StringName = &"street"
@export var anim_profile: StringName = &"calm"
@export var voice_pitch: float = 1.0
@export var start_relationship: int = 0
@export var start_state: String = "neutral"
@export var relations: Dictionary = {}
@export var staff: Dictionary = {}


static func from_dict(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.id = StringName(str(d.get("id", "")))
	c.display_name = str(d.get("name", ""))
	c.alias = str(d.get("alias", ""))
	c.age = int(d.get("age", 30))
	c.presentation = str(d.get("presentation", "andro"))
	c.occupation = str(d.get("occupation", ""))
	c.faction_id = StringName(str(d.get("faction", "none")))
	c.role = StringName(str(d.get("role", "")))
	c.dialogue_style = StringName(str(d.get("dialogue_style", "street")))
	for p: Variant in d.get("personality", []):
		c.personality.append(str(p))
	c.background = str(d.get("background", ""))
	c.motivation = str(d.get("motivation", ""))
	c.arc = str(d.get("arc", ""))
	c.silhouette = str(d.get("silhouette", ""))
	c.appearance = d.get("appearance", {})
	c.portrait_bg = StringName(str(d.get("portrait_bg", "street")))
	c.anim_profile = StringName(str(d.get("anim", "calm")))
	c.voice_pitch = float(d.get("voice", 1.0))
	c.start_relationship = int(d.get("relationship", 0))
	c.start_state = str(d.get("relationship_state", "neutral"))
	c.relations = d.get("relations", {})
	c.staff = d.get("staff", {})
	return c


func title() -> String:
	return "%s \"%s\"" % [display_name, alias] if alias != "" else display_name


func faction_name() -> String:
	return FactionManager.get_name_of(faction_id) if faction_id != &"none" and FactionManager.factions.has(faction_id) else "Unaffiliated"
