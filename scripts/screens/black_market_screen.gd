extends BaseScreen
## The Undermarket: illegal, stolen and experimental chrome with unknown
## properties. Distinct identity: darker, magenta light, corrupted text,
## tape-patched panels and a signal-tear shader.

const TABS := ["OFFERS", "STASH", "CASES"]
const DEN := "res://assets/sprites/blackmarket/den.png"
## Part of the den art shown as the header strip (art pixels).
const DEN_CROP := Rect2(0, 30, 180, 96)

var _list: VBoxContainer
var _money: Label
var _tab: int = 0


func on_enter(_params: Dictionary) -> void:
	if not BlackMarketManager.is_unlocked():
		GameManager.go_to_clinic.call_deferred()
		return
	if BlackMarketManager.stock.is_empty():
		BlackMarketManager.refresh_stock()
	var bg := ColorRect.new()
	bg.color = Color("08050a")
	add_child(UIKit.full_rect(bg))
	var m := UIKit.full_rect(UIKit.margin(10, 8, 10, 10))
	add_child(m)
	var col := UIKit.vbox(8)
	m.add_child(col)
	col.add_child(UIKit.header("UNDERMARKET · FLOOD TUNNELS", "BLACK MARKET", GameManager.go_to_clinic))
	(col.get_child(0).find_child("Title", true, false) as Label).add_theme_color_override(&"font_color", Palette.BRAND)
	col.add_child(_den_strip())
	_money = UIKit.label("", &"MonoLabel", true, Color("ffb0cc"), 18)
	col.add_child(_money)
	var tabs := UIKit.tabs(TABS, _on_tab, "BMTab")
	col.add_child(tabs)
	var sc := UIKit.scroll()
	col.add_child(sc)
	_list = UIKit.vbox(8)
	UIKit.expand(_list)
	sc.add_child(_list)
	var glitch := ColorRect.new()
	glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/bm_glitch.gdshader")
	glitch.material = mat
	mat.set_shader_parameter(&"intensity", 0.0 if Settings.reduce_motion else 0.6)
	add_child(UIKit.full_rect(glitch))
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _rebuild())
	EventBus.inventory_changed.connect(_rebuild)
	EventBus.resources_changed.connect(_rebuild)
	EventBus.black_market_changed.connect(_rebuild)
	AudioManager.play_sfx(&"glitch", 0.15)
	_rebuild()


func _den_strip() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = DEN_CROP.size * GameConfig.PIXEL_SCALE * Vector2(0, 1) + Vector2(0, 0)
	holder.clip_contents = true
	var tex := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = PixelArt.scaled(DEN)
	at.region = Rect2(DEN_CROP.position * GameConfig.PIXEL_SCALE, DEN_CROP.size * GameConfig.PIXEL_SCALE)
	tex.texture = at
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(UIKit.full_rect(tex))
	var row := UIKit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = 6
	row.offset_top = -80
	holder.add_child(row)
	var wire := CustomerManager.get_customer(&"vesna_kalo")
	if wire:
		var p := PixelPortrait.new()
		p.crop = Rect2i(14, 6, 36, 36)
		row.add_child(p)
		p.set_appearance(wire.appearance, Palette.BRAND)
	var quote := UIKit.vbox(0)
	quote.size_flags_vertical = Control.SIZE_SHRINK_END
	var name := GlitchLabel.new()
	name.theme_type_variation = &"BMLabel"
	name.set_base_text("WIRE // NO NAMES")
	quote.add_child(name)
	var line := UIKit.label("\"Cash only. No refunds. No questions.\"", &"DimLabel", false, Color("ffb0cc"), 13)
	line.add_theme_color_override(&"font_outline_color", Color.BLACK)
	line.add_theme_constant_override(&"outline_size", 4)
	quote.add_child(line)
	row.add_child(quote)
	return holder


func _on_tab(i: int) -> void:
	_tab = i
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or _list == null:
		return
	_money.text = "CR %d  ·  TOKENS %d  ·  PARTS %d  ·  HEAT %d" % [EconomyManager.money, InventoryManager.tokens, InventoryManager.parts, roundi(FactionManager.heat)]
	UIKit.clear(_list)
	match _tab:
		0:
			if BlackMarketManager.stock.is_empty():
				_list.add_child(UIKit.label("Sold out. New shipment after your next operations.", &"DimLabel", true))
			for i in BlackMarketManager.stock.size():
				_list.add_child(_offer_card(i))
		1:
			var stash := InventoryManager.get_instances()
			if stash.is_empty():
				_list.add_child(UIKit.label("Your stash is empty.", &"DimLabel"))
			for i in stash.size():
				_list.add_child(_stash_card(i, stash[i]))
		2:
			_list.add_child(_cases_card())


func _item_header(row: HBoxContainer, inst: ImplantInstance) -> VBoxContainer:
	var data := inst.get_data()
	row.add_child(UIKit.icon(data.icon_path, 32))
	var info := UIKit.vbox(2)
	UIKit.expand(info)
	row.add_child(info)
	var title: Label
	if data.unknown_traits > 0 and inst.has_unknown_traits():
		var g := GlitchLabel.new()
		g.set_base_text(data.display_name)
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title = g
	else:
		title = UIKit.label(data.display_name, &"", true)
	info.add_child(title)
	info.add_child(UIKit.label("T%d %s · %s" % [data.tier, data.get_tier_name(), data.category.to_upper()], &"SubHeaderLabel", true, data.get_rarity_color()))
	if data.origin != "":
		info.add_child(UIKit.label("ORIGIN: " + data.origin.to_upper(), &"SubHeaderLabel", true, Color("a8327a")))
	var cond := UIKit.hbox(6)
	cond.add_child(UIKit.label("COND %d%%" % roundi(inst.condition), &"MonoLabel", false, Palette.WARN if inst.condition < 70 else Palette.OK, 17))
	var bar := UIKit.meter(inst.condition / 100.0, Palette.WARN if inst.condition < 70 else Palette.OK, 4)
	UIKit.expand(bar)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cond.add_child(bar)
	info.add_child(cond)
	var known := ", ".join(data.benefits.filter(func(b: String) -> bool: return b != "???"))
	info.add_child(UIKit.label("Known: " + known, &"DimLabel", true, null, 13))
	for t in inst.traits:
		var td := BlackMarketManager.get_trait(t)
		if inst.revealed.has(t):
			var good := bool(td.get("positive", false))
			info.add_child(UIKit.label(("+ " if good else "- ") + str(td.get("name", t)) + ": " + str(td.get("description", "")), &"DimLabel", true, Palette.OK if good else Palette.DANGER, 13))
		else:
			info.add_child(UIKit.label("??? UNKNOWN PROPERTY", &"MonoLabel", true, Palette.BRAND, 17))
	info.add_child(UIKit.label("LOAD +%d%%" % roundi(inst.get_neural_load()), &"MonoLabel", false, Palette.TEXT_DIM, 16))
	return info


func _offer_card(i: int) -> Control:
	var offer: Dictionary = BlackMarketManager.stock[i]
	var inst: ImplantInstance = offer["instance"]
	var card := UIKit.panel(&"BMCardPanel")
	var row := UIKit.hbox(10)
	card.add_child(row)
	_item_header(row, inst)
	var b := UIKit.button(EconomyManager.format_money(int(offer["price"])), &"BMButton", func() -> void: _buy(i), "BMBuy_%d" % i)
	b.custom_minimum_size.x = 86
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not EconomyManager.can_afford(int(offer["price"]))
	row.add_child(b)
	return card


func _stash_card(i: int, inst: ImplantInstance) -> Control:
	var card := UIKit.panel(&"BMCardPanel")
	var v := UIKit.vbox(6)
	card.add_child(v)
	var row := UIKit.hbox(10)
	v.add_child(row)
	_item_header(row, inst)
	var actions := UIKit.hbox(4)
	v.add_child(actions)
	var study := UIKit.button("STUDY", &"BMButton", func() -> void: _study(inst.uid), "Study_%d" % i, 44)
	study.disabled = not inst.has_unknown_traits()
	study.tooltip_text = "%d parts or %s" % [BlackMarketManager.study_cost_parts(), EconomyManager.format_money(int(BlackMarketManager.config.get("study_cost_money", 120)))]
	var modify := UIKit.button("MODIFY", &"BMButton", func() -> void: _modify(inst.uid), "Modify_%d" % i, 44)
	modify.disabled = InventoryManager.parts < BlackMarketManager.modify_cost_parts()
	var sell := UIKit.button("SELL %s" % EconomyManager.format_money(BlackMarketManager.sell_value(inst)), &"GhostButton", func() -> void: _sell(inst.uid), "Sell_%d" % i, 44)
	var scrap := UIKit.button("SCRAP", &"GhostButton", func() -> void: _scrap(inst.uid), "Scrap_%d" % i, 44)
	for b: Button in [study, modify, sell, scrap]:
		b.add_theme_font_size_override(&"font_size", 12)
		UIKit.expand(b)
		actions.add_child(b)
	return card


func _cases_card() -> Control:
	var card := UIKit.panel(&"BMPanel")
	var v := UIKit.vbox(8)
	card.add_child(v)
	v.add_child(UIKit.label("SEALED CARGO CASE", &"BMLabel"))
	v.add_child(UIKit.label("Lifted from somewhere it shouldn't have left. Could be scrap. Could be military.", &"DimLabel", true))
	var cost := int(BlackMarketManager.config.get("mystery_case_tokens", 2))
	var b := UIKit.button("OPEN CASE (%d TOKENS)" % cost, &"BMButton", _open_case, "OpenCase")
	b.disabled = InventoryManager.tokens < cost
	v.add_child(b)
	v.add_child(UIKit.label("Earn tokens by selling black-market chrome and through deals.", &"DimLabel", true, null, 13))
	return card


func _buy(i: int) -> void:
	if BlackMarketManager.buy(i):
		UIManager.celebrate(&"bm_purchase")
		UIManager.show_toast("Bought. Don't ask where it came from.", &"success")
		SaveManager.save_game()
	else:
		UIManager.show_toast("Not enough credits", &"danger")


func _study(uid: String) -> void:
	var inst := InventoryManager.get_instance(uid)
	if BlackMarketManager.study(uid):
		var t := inst.revealed[inst.revealed.size() - 1]
		UIManager.show_toast("Revealed: %s" % str(BlackMarketManager.get_trait(t).get("name", t)), &"info")
		UIManager.celebrate(&"unlock")
		SaveManager.save_game()
	else:
		UIManager.show_toast("Can't study: need parts or credits", &"danger")


func _modify(uid: String) -> void:
	var msg := BlackMarketManager.modify(uid)
	if msg != "":
		UIManager.show_toast(msg, &"success")
		AudioManager.play_sfx(&"stitch")
		SaveManager.save_game()


func _sell(uid: String) -> void:
	var v := BlackMarketManager.sell(uid)
	if v > 0:
		UIManager.show_toast("Sold for %s" % EconomyManager.format_money(v), &"success")
		UIManager.celebrate(&"sell")
		SaveManager.save_game()


func _scrap(uid: String) -> void:
	var n := BlackMarketManager.scrap(uid)
	if n > 0:
		UIManager.show_toast("+%d parts" % n, &"info")
		SaveManager.save_game()


func _open_case() -> void:
	var inst := BlackMarketManager.open_mystery_case()
	if inst:
		UIManager.show_toast("Inside: %s" % inst.get_data().display_name, &"success")
		AudioManager.play_sfx(&"implant")
		SaveManager.save_game()
