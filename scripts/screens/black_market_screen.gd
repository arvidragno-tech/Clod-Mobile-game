extends BaseScreen
## The Undermarket: illegal, stolen and experimental chrome with unknown
## properties. Distinct identity: darker, magenta light, corrupted text,
## tape-patched panels and a signal-tear shader.

const TABS := ["/OFFERS", "/STASH", "/CASES", "/CONTACTS"]
const DEN := "res://assets/sprites/blackmarket/den.png"
## Part of the den art shown as the header strip (art pixels).
## The HD banner (tools/art/streets_hd.py) is shown whole at ART_SCALE.
const DEN_CROP := Rect2(0, 0, 900, 111)
const GLYPHS := "#$%&*+=?@ABCDEF0123456789/<>[]{}"
const FEED := [
	"SHIPMENT: military optics, serials ground off. Ask twice, price doubles.",
	"AEGIS SWEEP: patrols on sublevel 2 tonight. Keep heat low.",
	"WIRE: 'Unknown properties are a feature, ripper. STUDY before you install.'",
	"RUMOUR: a prototype spine is moving through the flood tunnels.",
	"NOTICE: no refunds. no names. no traces.",
]

var _list: GridContainer
var _money: Label
var _tab: int = 0
var _feed: Label
var _feed_target: String = ""
var _feed_progress: float = 0.0
var _feed_index: int = 0
var _hex: Label
var _time: float = 0.0
var _feed_tick: float = 0.0
var _panels: Array[Control] = []


func on_enter(_params: Dictionary) -> void:
	if not BlackMarketManager.is_unlocked():
		GameManager.go_to_clinic.call_deferred()
		return
	if BlackMarketManager.stock.is_empty():
		BlackMarketManager.refresh_stock()
	# Your first contact comes with the access.
	if SupplierManager.discovered().is_empty():
		SupplierManager.discover("juno", "quest")
	var bg := ColorRect.new()
	bg.color = Color("08050a")
	add_child(UIKit.full_rect(bg))
	var m := UIKit.full_rect(UIKit.margin(40, 24, 40, 24))
	add_child(m)
	var col := UIKit.vbox(12)
	m.add_child(col)
	var head := UIKit.header("UNDERMARKET · FLOOD TUNNELS · ENCRYPTED LINK", "BLACK MARKET", GameManager.go_to_clinic)
	(head.find_child("Title", true, false) as Label).add_theme_color_override(&"font_color", Palette.BRAND)
	col.add_child(head)
	_hex = UIKit.label("", &"MonoLabel", false, Color("a8327a"))
	_hex.clip_text = true
	UIKit.expand(_hex)
	head.add_child(_hex)
	_money = UIKit.label("", &"MonoLabel", false, Color("ffb0cc"))
	head.add_child(_money)
	col.add_child(_den_strip())
	var row := UIKit.hbox(18)
	UIKit.expand(row, true, true)
	col.add_child(row)
	var main := UIKit.vbox(10)
	UIKit.expand(main, true, true)
	row.add_child(main)
	var tabs := UIKit.tabs(TABS, _on_tab, "BMTab")
	tabs.custom_minimum_size.x = 860
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	main.add_child(tabs)
	var sc := UIKit.scroll()
	main.add_child(sc)
	_panels.append(sc)
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override(&"h_separation", 12)
	_list.add_theme_constant_override(&"v_separation", 12)
	UIKit.expand(_list)
	sc.add_child(_list)
	# Right: the vendor and an encrypted feed that decodes as you watch.
	var side := UIKit.panel(&"BMPanel")
	side.custom_minimum_size.x = 440
	row.add_child(side)
	_panels.append(side)
	var sv := UIKit.vbox(10)
	side.add_child(sv)
	var vendor := GlitchLabel.new()
	vendor.theme_type_variation = &"BMLabel"
	vendor.set_base_text("VENDOR: WIRE // NO NAMES")
	sv.add_child(vendor)
	var wire := CustomerManager.get_customer(&"vesna_kalo")
	if wire:
		var p := PixelPortrait.new()
		p.framing = PixelPortrait.Framing.BUST
		sv.add_child(p)
		p.set_character(&"vesna_kalo")
	sv.add_child(UIKit.label("\"Cash only. No refunds. No questions.\"", &"DimLabel", true, Color("ffb0cc")))
	sv.add_child(UIKit.label("> ENCRYPTED FEED", &"SubHeaderLabel", false, Palette.BRAND))
	_feed = UIKit.label("", &"MonoLabel", true, Color("ff7ab0"))
	_feed.name = "Feed"
	sv.add_child(_feed)
	_next_feed()
	sv.add_child(UIKit.expand(Control.new(), false, true))
	sv.add_child(UIKit.label("Unknown chrome can carry hidden traits. STUDY reveals one; MODIFY purges a bad one or repairs. Selling here earns tokens.", &"DimLabel", true))
	var glitch := ColorRect.new()
	glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/bm_glitch.gdshader")
	glitch.material = mat
	var intensity := 0.0 if Settings.reduce_motion or not Settings.flashing_allowed() or Settings.effects_level() == 0 else (0.35 if Settings.effects_quality == 1 else 0.6)
	mat.set_shader_parameter(&"intensity", intensity)
	# The shader samples the whole screen: skip the pass entirely when off.
	glitch.visible = intensity > 0.0
	add_child(UIKit.full_rect(glitch))
	# One purchase emits several signals: rebuild once, after them all.
	EventBus.money_changed.connect(func(_a: int, _d: int) -> void: _queue_rebuild())
	EventBus.inventory_changed.connect(_queue_rebuild)
	EventBus.resources_changed.connect(_queue_rebuild)
	EventBus.black_market_changed.connect(_queue_rebuild)
	SupplierManager.changed.connect(_queue_rebuild)
	AudioManager.play_sfx(&"glitch", 0.15)
	_rebuild()


func get_panels() -> Array[Control]:
	return _panels


func _next_feed() -> void:
	_feed_target = FEED[_feed_index % FEED.size()]
	_feed_index += 1
	_feed_progress = 0.0


## Decrypting feed: resolved prefix + scrambled remainder, like a cipher
## being cracked live. Plus a rolling hex session id in the header.
func _process(delta: float) -> void:
	if _feed == null:
		return
	_time += delta
	_feed_progress += delta * (60.0 if Settings.reduce_motion else 22.0)
	# Re-scramble at 20 Hz, not every frame (each change re-shapes the text).
	_feed_tick -= delta
	if _feed_tick > 0.0:
		return
	_feed_tick = 0.05
	var n := mini(int(_feed_progress), _feed_target.length())
	var tail := ""
	for i in range(n, _feed_target.length()):
		tail += " " if _feed_target[i] == " " else GLYPHS[randi() % GLYPHS.length()]
	_feed.text = _feed_target.substr(0, n) + tail
	if _feed_progress > _feed_target.length() + 90.0:
		_next_feed()
	if fmod(_time, 0.25) < 0.05:
		_hex.text = "  SESSION 0x%08X  ·  ROUTE %d HOPS  ·  TRACE %s" % [randi(), 3 + randi() % 6, "CLEAN" if FactionManager.heat < 35.0 else "WARM"]


func _den_strip() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, DEN_CROP.size.y * GameConfig.ART_SCALE)
	holder.clip_contents = true
	var tex := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = PixelArt.scaled(DEN, GameConfig.ART_SCALE)
	at.region = Rect2(DEN_CROP.position * GameConfig.ART_SCALE, DEN_CROP.size * GameConfig.ART_SCALE)
	tex.texture = at
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(UIKit.full_rect(tex))
	return holder


func _on_tab(i: int) -> void:
	_tab = i
	_rebuild()


var _rebuild_queued: bool = false


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree() or _list == null:
		return
	_money.text = "CR %d · TOKENS %d · PARTS %d · HEAT %d" % [EconomyManager.money, InventoryManager.tokens, InventoryManager.parts, roundi(FactionManager.heat)]
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
		3:
			_contacts()
	_list.columns = 1 if _tab >= 2 else 2


func _item_header(row: HBoxContainer, inst: ImplantInstance) -> VBoxContainer:
	var data := inst.get_data()
	if not inst.identified:
		# Partial information only: the slot it fits and the seller's word.
		row.add_child(UIKit.icon("res://assets/sprites/ui/icons/warning.png", 16))
		var uinfo := UIKit.vbox(2)
		UIKit.expand(uinfo)
		row.add_child(uinfo)
		var g0 := GlitchLabel.new()
		g0.set_base_text("UNIDENTIFIED DEVICE")
		uinfo.add_child(g0)
		uinfo.add_child(UIKit.label("FITS: %s SLOT · GRADE UNKNOWN" % data.category.to_upper(), &"SubHeaderLabel", true, Color("a8327a")))
		uinfo.add_child(UIKit.label("Model, condition and properties unknown. ANALYSE it, install it blind, sell it, keep it, or give it to the Curator.", &"DimLabel", true, null, 13))
		return uinfo
	row.add_child(CyberwareIcon.make(data))
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
	if inst.grade != &"":
		info.add_child(UIKit.label("GRADE: %s%s" % [str(SupplierManager.grade_def(inst.grade).get("label", inst.grade)), ("  · FROM " + str(SupplierManager.supplier(inst.supplier).get("name", "")).to_upper()) if inst.supplier != "" else ""], &"SubHeaderLabel", true, Palette.WARN))
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
	UIKit.expand(card)
	# The button holds the offer's own uid, never its list position: after a
	# purchase the list shifts and an index would point at the next offer.
	var uid := inst.uid
	var b := UIKit.button(EconomyManager.format_money(int(offer["price"])), &"BMButton", func() -> void: _buy(uid), "BMBuy_%d" % i)
	b.custom_minimum_size.x = 140
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not EconomyManager.can_afford(int(offer["price"]))
	# Known consequences of buying here (BlackMarketManager.buy): heat and standing.
	b.tooltip_text = "%s\nAuthority heat +%d · black-market standing +%d.\nHidden traits (??) are only known once you scan or fit it." % [DecisionPreview.summary(int(offer["price"])), roundi(BlackMarketManager.BUY_HEAT), BlackMarketManager.BUY_STANDING]
	row.add_child(b)
	return card


func _stash_card(i: int, inst: ImplantInstance) -> Control:
	var card := UIKit.panel(&"BMCardPanel")
	UIKit.expand(card)
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
	var row_btns: Array[Button] = [study, modify, sell, scrap]
	if not inst.identified:
		var an := UIKit.button("ANALYSE", &"BMButton", func() -> void:
			if SupplierManager.identify(inst.uid):
				UIManager.show_toast("Identified: %s" % inst.display_name(), &"success")
				SaveManager.save_game()
			else:
				UIManager.show_toast("Needs 2 parts or 150 cr.", &"warn"), "Analyse_%d" % i, 44)
		an.tooltip_text = "2 parts or 150 cr: reveals model and condition"
		study.disabled = true
		modify.disabled = true
		var cur := UIKit.button("TO THE CURATOR", &"GhostButton", func() -> void:
			var pay := SupplierManager.give_to_specialist(inst.uid)
			if pay > 0:
				UIManager.show_toast("The Curator pays %d and owes you one." % pay, &"success")
				SaveManager.save_game()
			else:
				UIManager.show_toast("The Curator isn't taking your calls.", &"warn"), "Curator_%d" % i, 44)
		cur.disabled = not bool(SupplierManager.st("curator").get("discovered", false)) or SupplierManager.is_cut_off("curator")
		cur.tooltip_text = "Give it to a specialist who collects mysteries: 70% of its value and their trust." if not cur.disabled else "You don't know a specialist yet."
		row_btns = [an, cur, sell, scrap]
	for b: Button in row_btns:
		b.add_theme_font_size_override(&"font_size", 18)
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


func _buy(uid: String) -> void:
	if not UIKit.debounce("bm_buy_" + uid):
		return
	var i := BlackMarketManager.index_of(uid)
	if i < 0:
		UIManager.show_toast("That offer is gone.", &"warn")
		return
	var before := Consequence.snapshot()
	if BlackMarketManager.buy(i):
		Consequence.show("You bought off the books. The market remembers; so might the authorities.", before)
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
	var before := Consequence.snapshot()
	var v := BlackMarketManager.sell(uid)
	if v > 0:
		Consequence.show("Sold to the market.", before)
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


# --- Contacts (SupplierManager) ---------------------------------------------------------

func _contacts() -> void:
	var known := SupplierManager.discovered()
	var hidden := SupplierManager.ids().size() - known.size()
	_list.add_child(UIKit.label("%d contact%s known · %s" % [known.size(), "" if known.size() == 1 else "s",
		("%d more out there. Customers, staff, fixers and factions know names." % hidden) if hidden > 0 else "you know everyone worth knowing."], &"DimLabel", true, Color("ffb0cc")))
	for id in known:
		_list.add_child(_contact_card(id))


func _contact_card(id: String) -> Control:
	var sd := SupplierManager.supplier(id)
	var s := SupplierManager.st(id)
	var card := UIKit.panel(&"BMCardPanel")
	card.name = "Contact_%s" % id
	UIKit.expand(card)
	var v := UIKit.vbox(6)
	card.add_child(v)
	var head := UIKit.hbox(12)
	v.add_child(head)
	var name := UIKit.label("%s · %s" % [str(sd["name"]).to_upper(), str(sd.get("archetype", "")).to_upper()], &"BMLabel")
	UIKit.expand(name)
	head.add_child(name)
	var standing := SupplierManager.standing(id)
	head.add_child(UIKit.label(standing, &"SubHeaderLabel", false, Palette.DANGER if standing in ["CUT YOU OFF", "SUSPICIOUS"] else Palette.OK))
	v.add_child(UIKit.label(str(sd.get("desc", "")), &"DimLabel", true, null, 13))
	var stats := UIKit.hbox(14)
	v.add_child(stats)
	stats.add_child(UIKit.label("TRUST %d" % int(s["trust"]), &"MonoLabel", false, Palette.OK, 16))
	var tb := UIKit.meter(int(s["trust"]) / 100.0, Palette.OK, 6)
	tb.custom_minimum_size.x = 160
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.add_child(tb)
	stats.add_child(UIKit.label("SUSPICION %d" % int(s["suspicion"]), &"MonoLabel", false, Palette.DANGER if int(s["suspicion"]) >= 50 else Palette.TEXT_DIM, 16))
	stats.add_child(UIKit.label("RELIABILITY %d%%" % roundi(float(sd.get("reliability", 0.8)) * 100.0), &"MonoLabel", false, Palette.TEXT_DIM, 16))
	var nx := SupplierManager.next_unlock(id)
	var unl: Array[String] = []
	for u: Dictionary in SupplierManager.data.get("unlocks", []):
		if SupplierManager.has_unlock(id, str(u["id"])):
			unl.append(str(u["label"]))
	v.add_child(UIKit.label("Unlocked: %s%s" % [", ".join(unl) if not unl.is_empty() else "nothing yet", ("  ·  next at trust %d: %s" % [int(nx["trust"]), str(nx["label"])]) if not nx.is_empty() else ""], &"DimLabel", true, Palette.ACCENT, 13))
	if int(s["debt"]) > 0:
		var dr := UIKit.hbox(8)
		v.add_child(dr)
		dr.add_child(UIKit.label("YOU OWE %d · due after %d more job%s" % [int(s["debt"]), int(s["debt_jobs"]), "" if int(s["debt_jobs"]) == 1 else "s"], &"SubHeaderLabel", false, Palette.WARN))
		var pb := UIKit.button("PAY NOW", &"BMButton", func() -> void:
			if SupplierManager.pay_debt(id):
				SaveManager.save_game(), "PaySupplier_%s" % id, 34)
		pb.disabled = not EconomyManager.can_afford(int(s["debt"]))
		dr.add_child(pb)
	if SupplierManager.is_cut_off(id):
		v.add_child(UIKit.label("They aren't answering. Give it time, or settle what you owe.", &"DimLabel", true, Palette.DANGER))
		return card
	var stock: Array = s.get("stock", [])
	if stock.is_empty():
		v.add_child(UIKit.label("Nothing today. Check back tomorrow (stock is bigger at night).", &"DimLabel", true))
	for i in stock.size():
		v.add_child(_supplier_offer(id, i, stock[i]))
	return card


func _supplier_offer(id: String, i: int, o: Dictionary) -> Control:
	var row := UIKit.hbox(10)
	row.name = "SupplierOffer_%s_%d" % [id, i]
	var info := UIKit.vbox(2)
	UIKit.expand(info)
	row.add_child(info)
	var what := ""
	match str(o["kind"]):
		"tool":
			var t := InventoryManager.get_tool(StringName(str(o["tool"])))
			what = "%s (T%d %s)" % [t.display_name, t.tier, String(t.category).to_upper()] if t else str(o["tool"])
		"supplies":
			what = "%d sterile packs and stims" % int(o["amount"])
		_:
			var inst := ImplantInstance.from_dict(o["instance"])
			var d := inst.get_data()
			what = (inst.display_name() + ("  · T%d %s · COND %d%%" % [d.tier, d.category.to_upper(), roundi(inst.condition)])) if inst.identified and d else "Unidentified device  · fits %s" % (d.category.to_upper() if d else "?")
	var cat := SupplierManager.category_def(str(o["category"]))
	info.add_child(UIKit.label("%s%s · %s" % ["SECRET · " if bool(o.get("secret", false)) else "", str(cat.get("label", "")), str(SupplierManager.grade_def(StringName(str(o["grade"]))).get("label", "")) if str(o["kind"]) == "implant" else "EQUIPMENT"], &"SubHeaderLabel", true, Color("ff7ab0")))
	info.add_child(UIKit.label(what, &"", true, Palette.TEXT, 15))
	info.add_child(UIKit.label("RISK: " + SupplierManager.offer_risk(o), &"DimLabel", true, Palette.WARN, 12))
	var btns := UIKit.vbox(4)
	row.add_child(btns)
	for mode: String in ["cash", "credit", "rush"]:
		var why := SupplierManager.buy_block_reason(id, i, mode)
		if mode != "cash" and why == "Needs more trust":
			continue
		var label: String = str({"cash": "BUY %s", "credit": "ON CREDIT %s", "rush": "RUSH NOW %s"}[mode]) % EconomyManager.format_money(SupplierManager.price_for(id, i, mode))
		var b := UIKit.button(label, &"BMButton" if mode == "cash" else &"GhostButton", _buy_supplier.bind(id, SupplierManager.st(id)["stock"][i], mode), "SupplierBuy_%s_%d_%s" % [id, i, mode], 34)
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else {"cash": "Pay now; delivered at opening tomorrow.", "credit": "Delivered tomorrow; pay after your next %d jobs. Miss it and they get suspicious." % int(SupplierManager.data.get("credit_jobs", 3)), "rush": "Delivered right now, any hour: +50%."}[mode]
		if why == "" and mode != "credit":
			b.tooltip_text += "\n" + DecisionPreview.summary(SupplierManager.price_for(id, i, mode))
		b.custom_minimum_size.x = 210
		btns.add_child(b)
	return row


## `offer` is the stock entry itself (not its position, which shifts after
## a purchase).
func _buy_supplier(id: String, offer: Dictionary, mode: String) -> void:
	if not UIKit.debounce("supplier_%s_%s" % [id, mode]):
		return
	var i := (SupplierManager.st(id)["stock"] as Array).find(offer)
	if i < 0:
		UIManager.show_toast("That offer is gone.", &"warn")
		return
	var got := SupplierManager.buy(id, i, mode)
	if got == "":
		AudioManager.play_sfx(&"denied", 0.0)
		return
	UIManager.celebrate(&"bm_purchase")
	UIManager.show_toast("Got it: %s" % got, &"success")
	SaveManager.save_game()
