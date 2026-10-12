extends Node
## The black-market supplier network (data/suppliers.json).
##
## Six original contacts (a scavenger, a military quartermaster, a
## corporate leak, a street dealer, an experimental broker, a fixer), each
## with what they sell (stolen, military surplus, experimental, restricted
## equipment, illegal pharmaceuticals, counterfeit, salvaged, prototype,
## rare tools, unknown tech), the grades they deal in, and a relationship
## with you: trust, suspicion, debt, favours, loyalty. Trust unlocks better
## prices, credit ("pay after your next three jobs"), emergency delivery at
## any hour, rare items and a secret inventory. Too much suspicion, or
## unpaid credit, and they cut you off.
##
## You find them gradually: a customer mentions a name, an employee knows
## someone, a fixer passes a number, a faction vouches, a quest opens a
## door, a favour is repaid with a lead. Inventory refreshes daily and bends
## with the hour, the district, heat, world events, your reputation and what
## you've been buying; prices drift day to day.

signal changed()

var data: Dictionary = {}
## id -> {discovered, trust, suspicion, debt, debt_jobs, favors_done, loyalty,
##        cut_off_until, stock: [{offer}], price_drift, bought, lead_from}
var state: Dictionary = {}
## Contraband you agreed to store: [{supplier, days_left}]
var contraband: Array[Dictionary] = []
## Orders waiting for tomorrow's delivery: [{supplier, offer}]
var deliveries: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_SUPPLIERS)
	if d is Dictionary:
		data = d
	EventBus.day_started.connect(_on_day_started)
	EventBus.customer_left.connect(_on_customer_left)
	EventBus.period_changed.connect(_on_period_changed)
	reset_state()


func reset_state() -> void:
	state.clear()
	contraband.clear()
	deliveries.clear()
	for s: Dictionary in data.get("suppliers", []):
		state[str(s["id"])] = {"discovered": false, "trust": int(s.get("trust", 0)), "suspicion": 0, "debt": 0, "debt_jobs": 0,
			"favors_done": 0, "loyalty": 0, "cut_off_until": -1, "stock": [], "price_drift": 1.0, "bought": 0, "lead_from": ""}


# --- Queries --------------------------------------------------------------------------------

func supplier(id: String) -> Dictionary:
	for s: Dictionary in data.get("suppliers", []):
		if str(s["id"]) == id:
			return s
	return {}


func st(id: String) -> Dictionary:
	return state.get(id, {})


func ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in data.get("suppliers", []):
		out.append(str(s["id"]))
	return out


func discovered() -> Array[String]:
	return ids().filter(func(i: String) -> bool: return bool(st(i).get("discovered", false)))


func category_def(c: String) -> Dictionary:
	return data.get("categories", {}).get(c, {})


func grade_def(g: StringName) -> Dictionary:
	return data.get("grades", {}).get(String(g), {})


func is_cut_off(id: String) -> bool:
	var c := int(st(id).get("cut_off_until", -1))
	return c == 9999 or c >= BusinessManager.day


func has_unlock(id: String, unlock: String) -> bool:
	for u: Dictionary in data.get("unlocks", []):
		if str(u["id"]) == unlock:
			return int(st(id).get("trust", 0)) >= int(u["trust"])
	return false


func next_unlock(id: String) -> Dictionary:
	for u: Dictionary in data.get("unlocks", []):
		if int(st(id).get("trust", 0)) < int(u["trust"]):
			return u
	return {}


func standing(id: String) -> String:
	if is_cut_off(id):
		return "CUT YOU OFF"
	var t := int(st(id).get("trust", 0))
	if int(st(id).get("suspicion", 0)) >= 50:
		return "SUSPICIOUS"
	if t >= 75:
		return "INNER CIRCLE"
	if t >= 50:
		return "TRUSTED"
	if t >= 20:
		return "KNOWN"
	return "STRANGER"


# --- Discovery ------------------------------------------------------------------------------

## Reveals a supplier. how: customer, staff, fixer, faction, quest, favour, rumour.
func discover(id: String, how: String = "") -> bool:
	var s := st(id)
	if s.is_empty() or bool(s["discovered"]):
		return false
	s["discovered"] = true
	s["lead_from"] = how
	_refresh(id)
	CommsManager.send_raw("message", "", "New contact: %s" % supplier(id).get("name", id), str(supplier(id).get("lead", "")), [], "supplier_lead")
	changed.emit()
	EventBus.black_market_changed.emit()
	return true


## A lead to someone you don't know yet ("" = everyone known).
func reveal_random_lead(how: String = "rumour") -> String:
	var unknown := ids().filter(func(i: String) -> bool: return not bool(st(i).get("discovered", false)))
	if unknown.is_empty():
		return ""
	var id: String = unknown[_rng.randi() % unknown.size()]
	discover(id, how)
	return id


## Text form for tests / favours ("" = everyone already known).
func reveal_random_supplier_lead_text() -> String:
	return reveal_random_lead("favour")


## Customers talk on their way out (after a decent job).
func _on_customer_left(c: CustomerData) -> void:
	if c == null or not BlackMarketManager.is_unlocked() or PeopleManager.rel_state(c.id) in ["hostile", "wary"]:
		return
	for s: Dictionary in data.get("suppliers", []):
		var id := str(s["id"])
		if bool(st(id)["discovered"]):
			continue
		var dsc: Dictionary = s.get("discover", {})
		if (dsc.get("archetypes", []) as Array).has(String(c.archetype_id)) and _rng.randf() < 0.18 + float(PeopleManager.get_person(c.id).get("rel", 0)) / 200.0:
			discover(id, "customer:%s" % c.display_name)
			return


## Factions, reputation, flags and staff open other doors (checked daily).
func _check_discovery() -> void:
	if not BlackMarketManager.is_unlocked():
		return
	for s: Dictionary in data.get("suppliers", []):
		var id := str(s["id"])
		if bool(st(id)["discovered"]):
			continue
		var dsc: Dictionary = s.get("discover", {})
		if dsc.has("flag") and StoryManager.has_flag(StringName(str(dsc["flag"]))):
			discover(id, "quest")
		elif dsc.has("faction") and FactionManager.get_rep(StringName(str(dsc["faction"]))) >= int(dsc.get("faction_rep", 20)):
			discover(id, "faction")
		elif dsc.has("dim") and ReputationManager.dim(StringName(str(dsc["dim"]))) >= int(dsc.get("dim_min", 10)):
			discover(id, "reputation")
		elif StaffManager.employees.any(func(e: Dictionary) -> bool: return str(e.get("specialization", "")) in ["black_market", "military"]) and _rng.randf() < 0.15:
			discover(id, "staff")
		else:
			continue
		return


# --- Inventory --------------------------------------------------------------------------------

func _on_day_started(_day: int) -> void:
	_deliver_pending()
	for id in ids():
		var s := st(id)
		# Prices drift a little every day.
		s["price_drift"] = clampf(float(s["price_drift"]) * _rng.randf_range(0.92, 1.08), 0.75, 1.35)
		s["suspicion"] = maxi(0, int(s["suspicion"]) - 2)
		if bool(s["discovered"]):
			_refresh(id)
	for i in range(contraband.size() - 1, -1, -1):
		contraband[i]["days_left"] = int(contraband[i]["days_left"]) - 1
		if int(contraband[i]["days_left"]) <= 0:
			var sid := str(contraband[i]["supplier"])
			contraband.remove_at(i)
			change_trust(sid, 6)
			CommsManager.notify("%s collected their crate. Trust up." % supplier(sid).get("name", sid))
	_check_discovery()
	_maybe_favor()
	changed.emit()


## Today's stock for a supplier, shaped by everything going on.
func _refresh(id: String) -> void:
	var sd := supplier(id)
	var s := st(id)
	var stock: Array = []
	if is_cut_off(id):
		s["stock"] = stock
		return
	var rng: Array = sd.get("stock", [2, 4])
	var n := _rng.randi_range(int(rng[0]), int(rng[1]))
	if TimeManager.is_night():
		n = int(round(n * float(sd.get("night", 1.0))))
	if FactionManager.heat >= 60.0:
		n -= 1  # nobody wants to sell to a clinic under surveillance
	if WorldEventManager.is_active(&"fixer_gone") and id == "juno":
		n = 0
	if WorldManager.current_district().get("factions", {}).has("black_market"):
		n += 1
	if has_unlock(id, "rare"):
		n += 1
	for i in maxi(0, n):
		var o := _make_offer(id, has_unlock(id, "secret") and i == n - 1)
		if not o.is_empty():
			stock.append(o)
	s["stock"] = stock


func _make_offer(id: String, secret: bool) -> Dictionary:
	var sd := supplier(id)
	var cats: Dictionary = (sd.get("categories", {}) as Dictionary).duplicate()
	if WorldEventManager.is_active(&"gang_war") and cats.has("military_surplus"):
		cats["military_surplus"] = float(cats["military_surplus"]) * 2.0
	var gen := CustomerGenerator.new(_rng)
	var cat := str(gen.pick_weighted(cats))
	var grade := StringName(str(gen.pick_weighted(sd.get("grades", {"used": 1}))))
	if secret:
		grade = &"prototype" if grade != &"military" else &"military"
	var cd := category_def(cat)
	var offer := {"category": cat, "grade": String(grade), "secret": secret}
	match cat:
		"restricted_equipment", "rare_tools":
			var t := _pick_tool(cat == "rare_tools")
			if t == null:
				return {}
			offer["kind"] = "tool"
			offer["tool"] = String(t.id)
			offer["price"] = int(round(t.price * float(cd.get("price", 1.3)) * _price_mult(id)))
		"illegal_pharma":
			offer["kind"] = "supplies"
			offer["amount"] = _rng.randi_range(3, 6)
			offer["price"] = int(round(int(offer["amount"]) * 30 * float(cd.get("price", 0.6)) * _price_mult(id)))
		_:
			var item := _pick_implant(cat, secret)
			if item == null:
				return {}
			var gd := grade_def(grade)
			var cr: Array = gd.get("cond", [50, 90])
			var inst := ImplantInstance.create(item.id, _rng.randf_range(float(cr[0]), float(cr[1])), &"black_market")
			inst.grade = grade
			inst.supplier = id
			if cd.has("traits") and _rng.randf() < float(cd["traits"]) and inst.traits.is_empty():
				inst.traits.append(StringName(BlackMarketManager.traits.keys()[_rng.randi() % BlackMarketManager.traits.size()]))
			if cd.has("flaw") and _rng.randf() < float(cd["flaw"]):
				inst.traits.append(&"unstable")
			if cd.has("tracker") and _rng.randf() < float(cd["tracker"]) and not inst.traits.has(&"tracker"):
				inst.traits.append(&"tracker")
			BlackMarketManager.roll_traits(inst, _rng)
			if bool(cd.get("unknown", false)):
				inst.identified = false
			offer["kind"] = "implant"
			offer["instance"] = inst.to_dict()
			offer["price"] = int(round(item.price * float(cd.get("price", 1.0)) * (0.6 + 0.4 * inst.condition / 100.0) * _price_mult(id)))
	offer["price"] = maxi(10, int(offer["price"]))
	return offer


func _pick_implant(cat: String, secret: bool) -> CyberwareData:
	var pool: Array[CyberwareData] = []
	for c: CyberwareData in CyberwareManager.catalog.values():
		match cat:
			"military_surplus":
				if c.manufacturer.begins_with("Aegis") or c.id == &"unknown_military_core":
					pool.append(c)
			"prototype", "experimental":
				if c.black_market or c.tier >= 3 or c.manufacturer == "Lyra Biocomp Lab":
					pool.append(c)
			"unknown_tech":
				if c.black_market or c.tier >= 2:
					pool.append(c)
			_:
				if not c.black_market and c.tier <= (4 if secret else 3):
					pool.append(c)
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else null


func _pick_tool(rare: bool) -> ToolData:
	var pool: Array[ToolData] = []
	for t: ToolData in InventoryManager.tool_catalog.values():
		if t.price > 0 and not InventoryManager.owns_tool(t.id) and (t.tier >= 2 if not rare else t.tier >= 2 and t.price >= 900):
			pool.append(t)
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else null


## Supplier-specific price: daily drift, trust discount, your street
## standing, time of day, world events, and how much you've bought lately.
func _price_mult(id: String) -> float:
	var s := st(id)
	var m := float(s.get("price_drift", 1.0))
	if has_unlock(id, "discount"):
		m *= 0.9
	m *= TimeManager.bm_price_mult()
	m *= ModifierManager.mult(&"bm.price")
	m *= 1.0 - clampf(ReputationManager.dim(&"black_market") / 400.0, -0.15, 0.15)
	return m


func offer_risk(o: Dictionary) -> String:
	var cd := category_def(str(o.get("category", "")))
	return str(cd.get("risk", ""))


# --- Buying ---------------------------------------------------------------------------------

## "" if this offer can be bought now (mode: cash, credit, rush).
func buy_block_reason(id: String, index: int, mode: String = "cash") -> String:
	var s := st(id)
	if is_cut_off(id):
		return "They won't sell to you"
	if index < 0 or index >= (s.get("stock", []) as Array).size():
		return "Gone"
	var o: Dictionary = s["stock"][index]
	if str(o.get("kind", "")) == "tool":
		var tid := StringName(str(o["tool"]))
		if InventoryManager.owns_tool(tid) or deliveries.any(func(dv: Dictionary) -> bool: return str(dv["offer"].get("tool", "")) == String(tid)):
			return "You already have one"
	var price := price_for(id, index, mode)
	match mode:
		"credit":
			if not has_unlock(id, "credit"):
				return "Needs more trust"
			if int(s["debt"]) > 0:
				return "Pay what you owe first"
		"rush":
			if not has_unlock(id, "rush"):
				return "Needs more trust"
	if mode != "credit" and not EconomyManager.can_afford(price):
		return "Not enough credits"
	return ""


func price_for(id: String, index: int, mode: String = "cash") -> int:
	var o: Dictionary = st(id)["stock"][index]
	return int(round(int(o["price"]) * (1.5 if mode == "rush" else 1.0)))


## Buys an offer. Returns what you got (text) or "" on failure.
## Records why standing changes in here (ChangeLog standing history).
func buy(id: String, index: int, mode: String = "cash") -> String:
	ChangeLog.push_cause("Bought from %s" % str(supplier(id).get("name", id)))
	var r: String = _buy_impl(id, index, mode)
	ChangeLog.pop_cause()
	return r


func _buy_impl(id: String, index: int, mode: String = "cash") -> String:
	if buy_block_reason(id, index, mode) != "":
		return ""
	var s := st(id)
	var o: Dictionary = s["stock"][index]
	var price := price_for(id, index, mode)
	if mode == "credit":
		s["debt"] = int(s["debt"]) + price
		s["debt_jobs"] = int(data.get("credit_jobs", 3))
	elif not EconomyManager.spend(price, &"black_market"):
		return ""
	(s["stock"] as Array).remove_at(index)
	var cd := category_def(str(o["category"]))
	FactionManager.add_heat(float(cd.get("heat", 2)))
	FactionManager.change(&"black_market", 1)
	ReputationManager.change_dim(&"black_market", 1)
	change_trust(id, 3)
	s["bought"] = int(s["bought"]) + 1
	var text := ""
	if mode == "rush":
		text = _deliver(id, o)
	else:
		# Ordinary orders come with tomorrow's first run; RUSH is now.
		deliveries.append({"supplier": id, "offer": o.duplicate(true)})
		text = "%s: arrives at opening tomorrow." % _offer_name(o)
	StoryManager.bump(&"bm_buy")
	changed.emit()
	EventBus.black_market_changed.emit()
	return text


## Hands an order over: tools, packs or chrome. Unreliable suppliers
## sometimes deliver worse than promised.
func _deliver(id: String, o: Dictionary) -> String:
	var damaged := _rng.randf() > float(supplier(id).get("reliability", 0.8))
	match str(o["kind"]):
		"tool":
			var t := InventoryManager.get_tool(StringName(str(o["tool"])))
			if t == null:
				return ""
			if not InventoryManager.owns_tool(t.id):
				InventoryManager.owned_tools.append(t.id)
			EventBus.inventory_changed.emit()
			EventBus.modifiers_changed.emit()
			return "%s, no serial." % t.display_name
		"supplies":
			InventoryManager.add_supplies(int(o["amount"]))
			return "%d sterile packs%s." % [int(o["amount"]), ", some look opened" if damaged else ""]
		_:
			var inst := ImplantInstance.from_dict(o["instance"])
			inst.uid = "imp_%d_%d" % [Time.get_ticks_usec(), _rng.randi() % 100000]
			if damaged:
				inst.condition = maxf(10.0, inst.condition - 25.0)
			InventoryManager.add_instance(inst)
			return "%s%s." % [inst.display_name(), " (arrived damaged)" if damaged else ""]


func _offer_name(o: Dictionary) -> String:
	match str(o.get("kind", "")):
		"tool":
			var t := InventoryManager.get_tool(StringName(str(o["tool"])))
			return t.display_name if t else "Tool"
		"supplies":
			return "%d sterile packs" % int(o["amount"])
	return ImplantInstance.from_dict(o["instance"]).display_name()


## Orders placed yesterday arrive with the morning run.
func _deliver_pending() -> void:
	var lines: Array[String] = []
	for dv in deliveries:
		var t := _deliver(str(dv["supplier"]), dv["offer"])
		if t != "":
			lines.append("%s: %s" % [supplier(str(dv["supplier"])).get("name", ""), t])
	deliveries.clear()
	if not lines.is_empty():
		CommsManager.send_raw("message", "", "Morning delivery", "Left at the back door before opening:\n" + "\n".join(lines), [], "supplier_delivery")


## After dark, contacts bring out more (night stock multipliers).
func _on_period_changed(p: StringName) -> void:
	if p != &"night":
		return
	for id in discovered():
		if is_cut_off(id):
			continue
		var extra := int(round((float(supplier(id).get("night", 1.0)) - 1.0) * 4.0))
		for i in maxi(0, extra):
			var o := _make_offer(id, false)
			if not o.is_empty():
				(st(id)["stock"] as Array).append(o)
	changed.emit()


# --- Relationship ------------------------------------------------------------------------------

func change_trust(id: String, delta: int) -> void:
	var s := st(id)
	if s.is_empty():
		return
	s["trust"] = clampi(int(s["trust"]) + delta, 0, 100)
	s["loyalty"] = clampi(int(s["loyalty"]) + (1 if delta > 0 else -1), 0, 100)


func change_suspicion(id: String, delta: int) -> void:
	var s := st(id)
	if s.is_empty():
		return
	s["suspicion"] = clampi(int(s["suspicion"]) + delta, 0, 100)
	if int(s["suspicion"]) >= int(data.get("cutoff_suspicion", 80)):
		cut_off(id, 5)


## They stop answering (days; 9999 = for good).
func cut_off(id: String, days: int) -> void:
	var s := st(id)
	s["cut_off_until"] = 9999 if days >= 9999 else BusinessManager.day + days
	s["stock"] = []
	change_trust(id, -15)
	CommsManager.send_raw("message", "", "%s stopped answering" % supplier(id).get("name", id), "The number rings out. Word is they don't trust you right now.", [], "supplier_cutoff")
	changed.emit()


## Credit comes due after a number of jobs.
func on_job_done() -> void:
	for id in ids():
		var s := st(id)
		if int(s["debt"]) <= 0:
			continue
		s["debt_jobs"] = int(s["debt_jobs"]) - 1
		if int(s["debt_jobs"]) > 0:
			continue
		if EconomyManager.spend(int(s["debt"]), &"black_market"):
			CommsManager.notify("Paid %s the %d you owed." % [supplier(id).get("name", id), int(s["debt"])])
			s["debt"] = 0
			change_trust(id, 4)
		else:
			# Overdue: they get nervous, then they get angry.
			change_suspicion(id, 25)
			change_trust(id, -8)
			s["debt_jobs"] = 1
			CommsManager.notify("%s wants their %d. You can't pay." % [supplier(id).get("name", id), int(s["debt"])])


func pay_debt(id: String) -> bool:
	var s := st(id)
	if int(s.get("debt", 0)) <= 0 or not EconomyManager.spend(int(s["debt"]), &"black_market"):
		return false
	s["debt"] = 0
	change_trust(id, 3)
	changed.emit()
	return true


# --- Favours ------------------------------------------------------------------------------------

## Now and then a contact asks for something (COMMS with accept / decline).
func _maybe_favor() -> void:
	var known := discovered().filter(func(i: String) -> bool: return not is_cut_off(i))
	if known.is_empty() or _rng.randf() > 0.3:
		return
	var id: String = known[_rng.randi() % known.size()]
	var favs: Array = data.get("favors", [])
	ask_favor(id, str(favs[_rng.randi() % favs.size()]["id"]))


func ask_favor(id: String, favor_id: String) -> int:
	var f: Dictionary = {}
	for x: Dictionary in data.get("favors", []):
		if str(x["id"]) == favor_id:
			f = x
	if f.is_empty():
		return -1
	var name := str(supplier(id).get("name", id))
	var acts := [{"label": "AGREE", "supplier_favor": {"id": id, "fx": f.get("accept", {})}},
		{"label": "REFUSE", "supplier_favor": {"id": id, "fx": f.get("decline", {})}}]
	return CommsManager.send_raw("message", name, "%s asks a favour: %s" % [name, str(f["label"]).to_lower()], str(f["body"]).replace("{supplier}", name), acts, "supplier_favor")


## A favour answered from COMMS.
## Records why standing changes in here (ChangeLog standing history).
func apply_favor(spec: Dictionary) -> void:
	ChangeLog.push_cause("A supplier favour")
	_apply_favor_impl(spec)
	ChangeLog.pop_cause()


func _apply_favor_impl(spec: Dictionary) -> void:
	var id := str(spec.get("id", ""))
	var fx: Dictionary = spec.get("fx", {})
	if fx.has("parts") and InventoryManager.parts < -int(fx["parts"]):
		change_trust(id, -3)
		CommsManager.notify("You don't have the parts. %s is unimpressed." % supplier(id).get("name", id))
		return
	if fx.has("trust"):
		change_trust(id, int(fx["trust"]))
	if fx.has("suspicion"):
		change_suspicion(id, int(fx["suspicion"]))
	if fx.has("heat"):
		FactionManager.add_heat(float(fx["heat"]))
	if fx.has("money"):
		EconomyManager.add_money(int(fx["money"]), &"black_market")
	if fx.has("parts"):
		InventoryManager.add_parts(int(fx["parts"]))
	if fx.has("contraband"):
		contraband.append({"supplier": id, "days_left": int(fx["contraband"])})
	if bool(fx.get("patient", false)):
		var c := CustomerManager.generator.generate({"archetype": "criminal", "faction": "black_market"})
		c.dialogue = "%s sent me. They said you'd keep it quiet." % supplier(id).get("name", id)
		c.terms = &"free"
		CustomerManager.queue.append({"customer": c.to_save_dict(), "due_op": 0, "due_day": BusinessManager.day + 1})
	if int(fx.get("trust", 0)) > 0:
		st(id)["favors_done"] = int(st(id)["favors_done"]) + 1
	changed.emit()


## Give an unidentified device to the experimental broker: trust and cash.
func give_to_specialist(uid: String) -> int:
	var inst := InventoryManager.get_instance(uid)
	if inst == null or not bool(st("curator").get("discovered", false)) or is_cut_off("curator"):
		return 0
	var item := inst.get_data()
	var pay := int(round((item.price if item else 200) * 0.7))
	InventoryManager.remove_instance(uid)
	EconomyManager.add_money(pay, &"black_market")
	change_trust("curator", 10)
	changed.emit()
	return pay


## Analyse an unidentified device: model, condition and one trait.
func identify(uid: String) -> bool:
	var inst := InventoryManager.get_instance(uid)
	if inst == null or inst.identified:
		return false
	if InventoryManager.parts >= 2:
		InventoryManager.add_parts(-2)
	elif not EconomyManager.spend(150, &"black_market"):
		return false
	inst.identified = true
	InventoryManager.notify_changed()
	return true


# --- Save -----------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"state": state.duplicate(true), "contraband": contraband.duplicate(true), "deliveries": deliveries.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	var s: Dictionary = d.get("state", {})
	for k: Variant in s:
		if state.has(str(k)) and s[k] is Dictionary:
			for f: Variant in s[k]:
				state[str(k)][str(f)] = s[k][f]
	for c: Variant in d.get("contraband", []):
		if c is Dictionary:
			contraband.append(c)
	for dv: Variant in d.get("deliveries", []):
		if dv is Dictionary:
			deliveries.append(dv)
