extends BaseScreen
## Skill tree, one category per tab, readable on a phone: each skill is a
## card with rank pips, what the next rank gives, and an UPGRADE button.

var _list: VBoxContainer
var _points: Label
var _tab: int = 0


func on_enter(_params: Dictionary) -> void:
	var m := UIKit.full_rect(UIKit.margin(10, 8, 10, 10))
	add_child(m)
	var col := UIKit.vbox(8)
	m.add_child(col)
	col.add_child(UIKit.header("RIPPER · TRAINING", "SKILLS", GameManager.go_to_clinic))
	_points = UIKit.label("", &"MonoLabel", false, Palette.ACCENT)
	col.add_child(_points)
	var names: Array = []
	for c: Dictionary in SkillManager.categories:
		names.append(str(c["name"]))
	col.add_child(UIKit.tabs(names, _on_tab, "SkillTab"))
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = UIKit.vbox(8)
	UIKit.expand(_list)
	sc.add_child(_list)
	EventBus.skills_changed.connect(_rebuild)
	_rebuild()


func _on_tab(i: int) -> void:
	_tab = i
	_rebuild()


func _rebuild() -> void:
	if _list == null:
		return
	_points.text = "SKILL POINTS: %d   ·   LV %d" % [SkillManager.points, ProgressionManager.level]
	UIKit.clear(_list)
	var cat: Dictionary = SkillManager.categories[_tab]
	var color := Color(str(cat.get("color", "2ee6c8")))
	for id in SkillManager.get_skills_in(StringName(str(cat["id"]))):
		_list.add_child(_skill_card(id, color))
	var active := ModifierManager.get_all()
	if not active.is_empty():
		_list.add_child(UIKit.label("ACTIVE BONUSES (skills, clinic, tools, events)", &"SubHeaderLabel"))
		_list.add_child(UIKit.label(UIKit.describe_modifiers(active), &"DimLabel", true, null, 13))


func _skill_card(id: StringName, color: Color) -> Control:
	var s := SkillManager.get_skill(id)
	var rank := SkillManager.get_rank(id)
	var max_rank := int(s.get("max_rank", 3))
	var card := UIKit.panel(&"CardPanel")
	var v := UIKit.vbox(4)
	card.add_child(v)
	var top := UIKit.hbox(8)
	v.add_child(top)
	var title := UIKit.label(str(s.get("name", id)).to_upper(), &"HeaderLabel", false, color)
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
