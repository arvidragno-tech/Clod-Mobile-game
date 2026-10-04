extends BaseScreen
## What the clinic has learned about the world: factions, contacts,
## rumors and the operation record.

const TABS := ["FACTIONS", "CONTACTS", "RUMORS", "RECORDS"]

var _list: GridContainer
var _tab: int = 0


func on_enter(_params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"dossier")
	col.add_child(UIKit.header("CLINIC · INTEL", "JOURNAL", GameManager.go_to_clinic))
	var tabs := UIKit.tabs(TABS, _on_tab, "DossierTab")
	tabs.custom_minimum_size.x = 900
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tabs)
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = GridContainer.new()
	_list.add_theme_constant_override(&"h_separation", 14)
	_list.add_theme_constant_override(&"v_separation", 12)
	UIKit.expand(_list)
	sc.add_child(_list)
	_rebuild()


func _on_tab(i: int) -> void:
	_tab = i
	_rebuild()


func _rebuild() -> void:
	UIKit.clear(_list)
	_list.columns = 1 if _tab == 3 else 2
	match _tab:
		0:
			_list.columns = 3
			var heat := UIKit.panel(&"DangerPanel" if FactionManager.heat >= 35 else &"HudPanel")
			UIKit.expand(heat)
			heat.add_child(UIKit.label("HEAT %d / 100\nInspections start around 35. Black-market work and failed jobs raise it." % roundi(FactionManager.heat), &"MonoLabel", true, Palette.DANGER if FactionManager.heat >= 35 else Palette.TEXT_DIM))
			_list.add_child(heat)
			for id in FactionManager.order:
				_list.add_child(_faction_card(id))
		1:
			var any := false
			for id in StoryManager.met_characters:
				var c := CustomerManager.get_customer(id)
				if c:
					_list.add_child(_contact_card(c, str(CustomerManager.characters[id].get("role", "")).to_upper()))
					any = true
			if not any:
				_list.add_child(UIKit.label("No contacts yet. Keep the clinic open and people will find you.", &"DimLabel", true))
		2:
			if StoryManager.unlocked_rumors.is_empty():
				_list.add_child(UIKit.label("Nothing on the street yet.", &"DimLabel"))
			for id in StoryManager.unlocked_rumors:
				var card := UIKit.panel(&"CardPanel")
				UIKit.expand(card)
				card.add_child(UIKit.label(StoryManager.get_rumor_text(id), &"MonoLabel", true, Palette.ACCENT, 18))
				_list.add_child(card)
		3:
			_records()


func _faction_card(id: StringName) -> Control:
	var f := FactionManager.get_faction(id)
	var color := FactionManager.get_color(id)
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card)
	var v := UIKit.vbox(4)
	card.add_child(v)
	var top := UIKit.hbox(8)
	v.add_child(top)
	top.add_child(UIKit.icon(str(f.get("emblem", "")), 16))
	var names := UIKit.vbox(0)
	UIKit.expand(names)
	names.add_child(UIKit.label(str(f.get("name", id)).to_upper(), &"HeaderLabel", true, color))
	names.add_child(UIKit.label("%s · %+d" % [FactionManager.get_standing(id), FactionManager.get_rep(id)], &"SubHeaderLabel"))
	top.add_child(names)
	var bar := UIKit.meter((FactionManager.get_rep(id) + 100) / 200.0, color, 6)
	v.add_child(bar)
	v.add_child(UIKit.label(str(f.get("description", "")), &"DimLabel", true, null, 13))
	return card


func _contact_card(c: CustomerData, role: String) -> Control:
	var card := UIKit.panel(&"CardPanel")
	UIKit.expand(card)
	var row := UIKit.hbox(10)
	card.add_child(row)
	var p := PixelPortrait.new()
	p.framing = PixelPortrait.Framing.HEAD
	row.add_child(p)
	if CharacterManager.has_character(c.id):
		p.set_character(c.id)
	else:
		p.set_appearance(c.appearance, FactionManager.get_color(c.faction_id))
	var v := UIKit.vbox(2)
	UIKit.expand(v)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	v.add_child(UIKit.label(c.get_display_title(), &"HeaderLabel", true))
	v.add_child(UIKit.label("%s · %s" % [role, FactionManager.get_name_of(c.faction_id)], &"SubHeaderLabel", true, FactionManager.get_color(c.faction_id)))
	v.add_child(UIKit.label(c.occupation, &"DimLabel", true, null, 13))
	return card


func _records() -> void:
	var lines := [
		"Level %d · %d XP" % [ProgressionManager.level, ProgressionManager.total_xp],
		"Reputation %d · %s" % [ReputationManager.reputation, ReputationManager.get_tier_name()],
		"Operations: %d · customers served %d" % [EventManager.operations, ProgressionManager.customers_served],
		"Clinic: %s" % ClinicManager.get_tier_name(),
	]
	for l: String in lines:
		_list.add_child(UIKit.label(l, &"MonoLabel", true, null, 18))
	for sid: String in ProgressionManager.surgery_records:
		var rec: Dictionary = ProgressionManager.surgery_records[sid]
		var s := SurgeryManager.get_surgery(StringName(sid))
		_list.add_child(UIKit.label("%s: %d done, %d failed, best %s" % [s.display_name if s else sid, rec.get("completed", 0), rec.get("failed", 0), str(rec.get("best_grade", "-"))], &"DimLabel", true))
	_list.add_child(UIKit.label("RECENT PATIENTS", &"SubHeaderLabel"))
	var hist := CustomerManager.history.duplicate()
	hist.reverse()
	for h: Dictionary in hist.slice(0, 12):
		var ok := str(h.get("outcome", "")) == "success"
		var tag := " · REGULAR" if bool(h.get("regular", false)) else ""
		_list.add_child(UIKit.label("%s  %s  %s%s" % [str(h.get("grade", "?")), str(h.get("name", "?")), "OK" if ok else str(h.get("outcome", "")).to_upper(), tag], &"MonoLabel", true, Palette.TEXT if ok else Palette.DANGER, 17))
