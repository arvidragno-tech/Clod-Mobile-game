extends BaseScreen
## Clinic progression: from a wet basement to an elite ripper facility.
## Each tier shows a window into its art (at game pixel density), features,
## bonuses, requirements and cost.

## Art window into each tier background (art pixels).
const PREVIEW := Rect2(0, 62, 180, 84)

var _list: VBoxContainer


func on_enter(_params: Dictionary) -> void:
	var m := UIKit.full_rect(UIKit.margin(10, 8, 10, 10))
	add_child(m)
	var col := UIKit.vbox(8)
	m.add_child(col)
	col.add_child(UIKit.header("CLINIC · FACILITY", "UPGRADES", GameManager.go_to_clinic))
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = UIKit.vbox(10)
	UIKit.expand(_list)
	sc.add_child(_list)
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: _rebuild())
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild())
	_rebuild()


func _rebuild() -> void:
	UIKit.clear(_list)
	_list.add_child(UIKit.label("CURRENT", &"SubHeaderLabel"))
	_list.add_child(_tier_card(ClinicManager.tier, true))
	if not ClinicManager.is_max_tier():
		_list.add_child(UIKit.label("NEXT", &"SubHeaderLabel"))
		_list.add_child(_tier_card(ClinicManager.tier + 1, false))
	_list.add_child(UIKit.label("PROGRESSION", &"SubHeaderLabel"))
	var ladder := UIKit.vbox(2)
	for i in ClinicManager.tiers.size():
		var t: Dictionary = ClinicManager.tiers[i]
		var mark := "> " if i == ClinicManager.tier else ("  " if i > ClinicManager.tier else "  ")
		var color := Palette.ACCENT if i == ClinicManager.tier else (Palette.TEXT if i < ClinicManager.tier else Palette.TEXT_DIM)
		ladder.add_child(UIKit.label("%s%d  %s  ·  T%d CHROME" % [mark, i, str(t["name"]).to_upper(), int(t["max_cyberware_tier"])], &"MonoLabel", true, color, 18))
	_list.add_child(ladder)


func _tier_card(index: int, current: bool) -> Control:
	var t := ClinicManager.get_tier_data(index)
	var card := UIKit.panel(&"AccentPanel" if current else &"CardPanel")
	var v := UIKit.vbox(6)
	card.add_child(v)
	v.add_child(UIKit.label(str(t["name"]).to_upper(), &"HeaderLabel"))
	var preview := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = PixelArt.scaled(str(t["background"]))
	at.region = Rect2(PREVIEW.position * GameConfig.PIXEL_SCALE, PREVIEW.size * GameConfig.PIXEL_SCALE)
	preview.texture = at
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	preview.custom_minimum_size.y = PREVIEW.size.y * GameConfig.PIXEL_SCALE * 0.75
	preview.clip_contents = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(preview)
	v.add_child(UIKit.label(str(t.get("description", "")), &"DimLabel", true))
	v.add_child(UIKit.label("Features: " + ", ".join(t.get("features", [])), &"DimLabel", true, Palette.TEXT, 13))
	var mods: Dictionary = t.get("modifiers", {})
	if not mods.is_empty():
		v.add_child(UIKit.label("Bonuses: " + UIKit.describe_modifiers(mods), &"DimLabel", true, Palette.ACCENT, 13))
	v.add_child(UIKit.label("Cyberware up to T%d · supplies %d" % [int(t["max_cyberware_tier"]), int(t["supplies_capacity"])], &"MonoLabel", true, Palette.TEXT_DIM, 17))
	if not current:
		v.add_child(UIKit.label("Requires LV %d · REP %d" % [int(t["min_level"]), int(t["min_reputation"])], &"MonoLabel", false, Palette.WARN, 17))
		var reason := ClinicManager.get_upgrade_block_reason()
		var b := UIKit.button("UPGRADE · %s" % EconomyManager.format_money(int(t["cost"])) if reason == "" else reason.to_upper(), &"BrandButton", _upgrade, "UpgradeClinic")
		b.disabled = reason != ""
		v.add_child(b)
	return card


func _upgrade() -> void:
	if ClinicManager.upgrade():
		UIManager.celebrate(&"upgrade", "Welcome to the %s" % ClinicManager.get_tier_name())
		SaveManager.save_game()
