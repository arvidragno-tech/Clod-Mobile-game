extends BaseScreen
## Clinic progression: from a wet basement to an elite ripper facility.
## Each tier shows a window into its art (at game pixel density), features,
## bonuses, requirements and cost.

## Art window into each tier background (art pixels).
const PREVIEW := Rect2(110, 60, 220, 100)

var _row: HBoxContainer
var _ladder: HBoxContainer
var _panels: Array[Control] = []


func on_enter(_params: Dictionary) -> void:
	var col := UIKit.workstation(self, &"upgrades")
	col.add_child(UIKit.header("CLINIC · FACILITY", "UPGRADES", GameManager.go_to_clinic))
	_row = UIKit.hbox(18)
	UIKit.expand(_row, true, true)
	col.add_child(_row)
	col.add_child(UIKit.label("PROGRESSION", &"SubHeaderLabel", false, Palette.ACCENT))
	_ladder = UIKit.hbox(10)
	col.add_child(_ladder)
	EventBus.clinic_upgraded.connect(func(_t: int) -> void: _rebuild())
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild())
	_rebuild()


func get_panels() -> Array[Control]:
	return _panels


func _rebuild() -> void:
	UIKit.clear(_row)
	UIKit.clear(_ladder)
	_panels.clear()
	var cur := _tier_card(ClinicManager.tier, true)
	_row.add_child(cur)
	_panels.append(cur)
	if not ClinicManager.is_max_tier():
		var arrow := UIKit.label(">>", &"BigMonoLabel", false, Palette.ACCENT)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(arrow)
		var nxt := _tier_card(ClinicManager.tier + 1, false)
		_row.add_child(nxt)
		_panels.append(nxt)
	# Horizontal tier ladder: every facility from basement to elite.
	for i in ClinicManager.tiers.size():
		var t: Dictionary = ClinicManager.tiers[i]
		var step := UIKit.panel(&"AccentPanel" if i == ClinicManager.tier else &"HudPanel")
		UIKit.expand(step)
		step.modulate.a = 1.0 if i <= ClinicManager.tier + 1 else 0.55
		var v := UIKit.vbox(2)
		step.add_child(v)
		var color := Palette.ACCENT if i == ClinicManager.tier else (Palette.OK if i < ClinicManager.tier else Palette.TEXT_DIM)
		v.add_child(UIKit.label("%s TIER %d" % ["✓" if i < ClinicManager.tier else ("▶" if i == ClinicManager.tier else "·"), i], &"SubHeaderLabel", false, color))
		v.add_child(UIKit.label(str(t["name"]).to_upper(), &"", true, color, 14))
		v.add_child(UIKit.label("T%d chrome · %s" % [int(t["max_cyberware_tier"]), EconomyManager.format_money(int(t.get("cost", 0)))], &"SubHeaderLabel"))
		step.tooltip_text = str(t.get("description", ""))
		_ladder.add_child(step)


func _tier_card(index: int, current: bool) -> Control:
	var t := ClinicManager.get_tier_data(index)
	var card := UIKit.panel(&"AccentPanel" if current else &"CardPanel")
	UIKit.expand(card, true, true)
	var v := UIKit.vbox(8)
	v.add_child(UIKit.label("CURRENT FACILITY" if current else "NEXT UPGRADE", &"SubHeaderLabel", false, Palette.ACCENT))
	card.add_child(v)
	v.add_child(UIKit.label(str(t["name"]).to_upper(), &"HeaderLabel"))
	var preview := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = PixelArt.scaled(str(t["background"]))
	at.region = Rect2(PREVIEW.position * GameConfig.PIXEL_SCALE, PREVIEW.size * GameConfig.PIXEL_SCALE)
	preview.texture = at
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	preview.custom_minimum_size.y = PREVIEW.size.y * GameConfig.PIXEL_SCALE
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
		var b := UIKit.button("UPGRADE · %s" % EconomyManager.format_money(int(t["cost"])) if reason == "" else reason.to_upper(), &"BrandButton", _upgrade, "UpgradeClinic", 60)
		b.disabled = reason != ""
		v.add_child(b)
	return card


func _upgrade() -> void:
	if ClinicManager.upgrade():
		UIManager.celebrate(&"upgrade", "Welcome to the %s" % ClinicManager.get_tier_name())
		SaveManager.save_game()
