extends BaseScreen
## Skill tree: the four categories side by side. Each skill is a card with
## rank pips, what it gives now and next, and an UPGRADE button.

var _columns: HBoxContainer
var _points: Label
var _bonuses: Label
var _panels: Array[Control] = []


func on_enter(_params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"skills")
	var head := UIKit.header("RIPPER · TRAINING", "SKILLS", GameManager.go_to_clinic)
	col.add_child(head)
	_points = UIKit.label("", &"BigMonoLabel", false, Palette.ACCENT)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIKit.expand(_points)
	head.add_child(_points)
	_columns = UIKit.hbox(14)
	UIKit.expand(_columns, true, true)
	col.add_child(_columns)
	_bonuses = UIKit.label("", &"DimLabel", true)
	col.add_child(_bonuses)
	EventBus.skills_changed.connect(_rebuild)
	_rebuild()


func get_panels() -> Array[Control]:
	return _panels


## One column per skill category, side by side (4 on a 1920 screen).
func _rebuild() -> void:
	if _columns == null:
		return
	_points.text = "%d SKILL POINT%s  ·  LV %d" % [SkillManager.points, "" if SkillManager.points == 1 else "S", ProgressionManager.level]
	UIKit.clear(_columns)
	_panels.clear()
	for cat: Dictionary in SkillManager.categories:
		var color := Color(str(cat.get("color", "2ee6c8")))
		var panel := UIKit.panel(&"CardPanel")
		UIKit.expand(panel, true, true)
		_columns.add_child(panel)
		_panels.append(panel)
		var v := UIKit.vbox(10)
		panel.add_child(v)
		v.add_child(UIKit.label(str(cat["name"]).to_upper(), &"HeaderLabel", false, color))
		var sc := UIKit.scroll()
		v.add_child(sc)
		var list := UIKit.vbox(10)
		UIKit.expand(list)
		sc.add_child(list)
		for id in SkillManager.get_skills_in(StringName(str(cat["id"]))):
			list.add_child(_skill_card(id, color))
	var active := ModifierManager.get_all()
	_bonuses.text = "ACTIVE BONUSES (skills, clinic, tools, events): " + UIKit.describe_modifiers(active) if not active.is_empty() else ""


func _skill_card(id: StringName, color: Color) -> Control:
	var s := SkillManager.get_skill(id)
	var rank := SkillManager.get_rank(id)
	var max_rank := int(s.get("max_rank", 3))
	var card := UIKit.panel(&"HudPanel")
	var v := UIKit.vbox(4)
	card.add_child(v)
	var top := UIKit.hbox(8)
	v.add_child(top)
	var title := UIKit.label(str(s.get("name", id)).to_upper(), &"MonoLabel", true, color)
	UIKit.expand(title)
	top.add_child(title)
	var pips := RankPips.new(rank, max_rank, color)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pips)
	v.add_child(UIKit.label(str(s.get("description", "")), &"DimLabel", true))
	var eff: Dictionary = s.get("effect_per_rank", {})
	var now := UIKit.describe_modifiers(eff, rank) if rank > 0 else "nothing yet"
	v.add_child(UIKit.label("Now: " + now, &"DimLabel", true, Palette.TEXT, 13))
	var reason := SkillManager.get_block_reason(id)
	if rank < max_rank:
		v.add_child(UIKit.label("Next: " + UIKit.describe_modifiers(eff), &"DimLabel", true, color, 13))
		var b := UIKit.button("UPGRADE (%d PT)" % SkillManager.next_cost(id) if reason == "" else reason.to_upper(), &"AccentButton", func() -> void: _upgrade(id), "Upgrade_%s" % id, 44)
		b.disabled = reason != ""
		v.add_child(b)
	return card


func _upgrade(id: StringName) -> void:
	if SkillManager.upgrade(id):
		UIManager.celebrate(&"unlock")
		SaveManager.save_game()
