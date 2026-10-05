extends Node
## Threats (data/security.json). Nothing here is combat and the clinic is
## never damaged: things go missing and people come asking.
##
## HEAT LEVELS: LOW, MEDIUM (surveillance), HIGH (interrogation: cooperate,
## stonewall or bribe), CRITICAL (confiscation of illegal stock: hand it
## over, hide it, bribe, or turn informant). Each arrives as a COMMS choice.
##
## THEFT: at night someone may take money, chrome, supplies, parts, records,
## an instrument or something personal. Who did it depends on the clinic:
## desperate or gambling staff, an informant, a light-fingered patient,
## street thieves (district danger), a faction sending a message, a corrupt
## inspector when heat is high. Security upgrades make it rarer.
##
## INVESTIGATION: every theft opens a case. Check the cameras (needs
## security), question your staff (friends cover, rivals talk, the innocent
## resent it), ask around (costs), then confront a suspect. Right: you get
## most of it back. Wrong: you've accused someone innocent, and they know.

signal cases_changed()

var data: Dictionary = {}
## [{id, day, loot: {kind, amount, item, uid, tool}, loot_text, culprit: {kind, id, name},
##   clues: [String], used: [String], status: open/solved/wrong/closed, outcome}]
var cases: Array[Dictionary] = []
var informant: bool = false
## Night-time rolls (tests turn this off for determinism).
var auto_roll: bool = true
var _next_case: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_SECURITY)
	if d is Dictionary:
		data = d
	EventBus.day_ended.connect(_on_day_ended)
	reset_state()


func reset_state() -> void:
	cases.clear()
	informant = false
	_next_case = 1


# --- Heat levels ---------------------------------------------------------------------------

func level(h: float = -1.0) -> Dictionary:
	var heat := FactionManager.heat if h < 0.0 else h
	var out: Dictionary = {}
	for l: Dictionary in data.get("levels", []):
		if heat >= float(l["min"]):
			out = l
	return out


func level_id() -> StringName:
	return StringName(str(level().get("id", "low")))


func level_label() -> String:
	return str(level().get("label", "LOW"))


func open_cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cases:
		if str(c["status"]) == "open":
			out.append(c)
	return out


func get_case(id: int) -> Dictionary:
	for c in cases:
		if int(c["id"]) == id:
			return c
	return {}


# --- Nights ---------------------------------------------------------------------------------

func _on_day_ended(_day: int, report: Dictionary) -> void:
	if not auto_roll:
		return
	var notes: Array = report.get("notes", [])
	var c := roll_theft()
	if not c.is_empty():
		notes.append("Break-in overnight: %s is gone. Open SECURITY to investigate." % str(c["loot_text"]))
	var p := roll_pressure()
	if p != "":
		notes.append(p)


func theft_chance() -> float:
	var t: Dictionary = data.get("theft", {})
	var p := float(t.get("base", 0.06))
	p += FactionManager.heat * float(t.get("per_heat", 0.0015))
	p += float(WorldManager.current_district().get("danger", 1)) * float(t.get("per_danger", 0.03))
	p += maxf(0.0, ReputationManager.dim(&"criminal")) * float(t.get("criminal_dim", 0.002))
	for e in StaffManager.at_clinic(ClinicManager.tier):
		if bool(StaffLifeManager.ensure_life(e).get("desperate", false)) or float(e["loyalty"]) < 25.0:
			p += 0.05
	p -= float(t.get("security_cut", 0.035)) * maxi(0, ClinicManager.security_rating() - 1)
	return clampf(p, 0.01, float(t.get("max", 0.45)))


## Rolls (or forces) a night theft. Returns the new case ({} = nothing).
func roll_theft(force: bool = false) -> Dictionary:
	if not force and (_rng.randf() >= theft_chance() or Difficulty.ops() < 3):
		return {}
	var culprit := _pick_culprit()
	var loot := _take_loot()
	if loot.is_empty():
		return {}
	var c := {"id": _next_case, "day": BusinessManager.day, "loot": loot, "loot_text": str(loot["text"]), "culprit": culprit,
		"clues": [], "used": [], "status": "open", "outcome": ""}
	_next_case += 1
	cases.append(c)
	while cases.size() > 20:
		cases.pop_front()
	CommsManager.send_raw("message", "", "Break-in: %s" % str(loot["text"]), "The lock's fine. Whoever it was knew what they wanted. Open SECURITY on the clinic screen to look into it.", [], "theft")
	if str(culprit["kind"]) in ["employee", "insider"] and str(loot["kind"]) == "cyberware":
		# A rare piece of chrome walking out with your staff is a story.
		StoryManager.set_flag(&"inside_theft")
		c["quest"] = true
		QuestManager.start(&"q_inside_job")
	cases_changed.emit()
	return c


func _pick_culprit() -> Dictionary:
	var options := {}
	var who := {}
	var staff := StaffManager.at_clinic(ClinicManager.tier)
	var shady := staff.filter(func(e: Dictionary) -> bool:
		return bool(StaffLifeManager.ensure_life(e).get("desperate", false)) or EmployeeAI.has_trait(e, "gambler") or float(e["loyalty"]) < 30.0)
	if not shady.is_empty():
		options["employee"] = 3.5 * shady.size()
		who["employee"] = shady[_rng.randi() % shady.size()]
	var agents := staff.filter(func(e: Dictionary) -> bool: return EmployeeAI.has_trait(e, "secret_agent"))
	if not agents.is_empty():
		options["insider"] = 1.5
		who["insider"] = agents[0]
	var today: Array = []
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if int(p.get("last_day", -1)) == BusinessManager.day and ((p.get("traits", []) as Array).has("greedy") or (p.get("traits", []) as Array).has("aggressive")):
			today.append(p)
	if not today.is_empty():
		options["customer"] = 2.0
		who["customer"] = today[_rng.randi() % today.size()]
	options["external"] = 2.0 + float(WorldManager.current_district().get("danger", 1))
	for f: StringName in FactionManager.order:
		if FactionManager.get_rep(f) <= -20:
			options["faction"] = 1.5
			who["faction"] = f
			break
	if FactionManager.heat >= 50.0:
		options["corruption"] = 1.5
	var kind := str(CustomerGenerator.new(_rng).pick_weighted(options))
	match kind:
		"employee", "insider":
			return {"kind": kind, "id": str(who[kind]["id"]), "name": str(who[kind]["name"])}
		"customer":
			return {"kind": kind, "id": str(who[kind]["id"]), "name": str(who[kind]["name"])}
		"faction":
			return {"kind": kind, "id": String(who[kind]), "name": FactionManager.get_name_of(who[kind])}
	return {"kind": kind, "id": kind, "name": str(data.get("culprits", {}).get(kind, {}).get("label", kind))}


## Takes something real from the clinic.
func _take_loot() -> Dictionary:
	var lt: Dictionary = data.get("loot_text", {})
	var weights: Dictionary = (data.get("loot", {}) as Dictionary).duplicate()
	if EconomyManager.money < 60:
		weights.erase("money")
	if InventoryManager.get_instances().is_empty():
		weights.erase("cyberware")
	if InventoryManager.supplies <= 0:
		weights.erase("supplies")
	if InventoryManager.parts <= 0:
		weights.erase("parts")
	var tools := InventoryManager.owned_tools.filter(func(id: StringName) -> bool:
		var t := InventoryManager.get_tool(id)
		return t != null and not t.starter)
	if tools.is_empty():
		weights.erase("equipment")
	if weights.is_empty():
		return {}
	var kind := str(CustomerGenerator.new(_rng).pick_weighted(weights))
	var out := {"kind": kind}
	match kind:
		"money":
			var n := mini(EconomyManager.money, maxi(40, int(EconomyManager.money * _rng.randf_range(0.08, 0.2))))
			EconomyManager.spend(n, &"other")
			out["amount"] = n
			out["text"] = str(lt.get("money", "%d credits")) % n
		"cyberware":
			var list := InventoryManager.get_instances()
			list.sort_custom(func(a: ImplantInstance, b: ImplantInstance) -> bool: return (a.get_data().price if a.get_data() else 0) > (b.get_data().price if b.get_data() else 0))
			var inst: ImplantInstance = list[0] if _rng.randf() < 0.6 else list[_rng.randi() % list.size()]
			out["item"] = inst.to_dict()
			InventoryManager.remove_instance(inst.uid)
			out["text"] = str(lt.get("cyberware", "a %s")) % inst.display_name()
		"supplies":
			var n2 := mini(InventoryManager.supplies, _rng.randi_range(2, 5))
			InventoryManager.supplies -= n2
			EventBus.resources_changed.emit()
			out["amount"] = n2
			out["text"] = str(lt.get("supplies", "%d packs")) % n2
		"parts":
			var n3 := mini(InventoryManager.parts, _rng.randi_range(2, 4))
			InventoryManager.add_parts(-n3)
			out["amount"] = n3
			out["text"] = str(lt.get("parts", "%d parts")) % n3
		"data":
			FactionManager.add_heat(4.0)
			out["text"] = str(lt.get("data", "patient records"))
		"equipment":
			var tid: StringName = tools[_rng.randi() % tools.size()]
			InventoryManager.owned_tools.erase(tid)
			EventBus.inventory_changed.emit()
			EventBus.modifiers_changed.emit()
			out["tool"] = String(tid)
			out["text"] = str(lt.get("equipment", "your %s")) % InventoryManager.get_tool(tid).display_name
		_:
			out["text"] = str(lt.get("belongings", "your things"))
	return out


# --- Investigation ----------------------------------------------------------------------------

## Who you could accuse: [{key, label}].
func suspects(case_id: int) -> Array[Dictionary]:
	var c := get_case(case_id)
	var out: Array[Dictionary] = []
	for e in StaffManager.at_clinic(ClinicManager.tier):
		out.append({"key": "staff:%s" % e["id"], "label": str(e["name"])})
	var cul: Dictionary = c.get("culprit", {})
	if str(cul.get("kind", "")) in ["employee", "insider"] and not out.any(func(s: Dictionary) -> bool: return str(s["key"]) == "staff:%s" % cul["id"]):
		out.append({"key": "staff:%s" % cul["id"], "label": str(cul["name"])})
	var seen := 0
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if int(p.get("last_day", -1)) == int(c.get("day", -1)) and seen < 3:
			out.append({"key": "customer:%s" % k, "label": "%s (patient)" % p["name"]})
			seen += 1
	if str(cul.get("kind", "")) == "customer" and not out.any(func(s: Dictionary) -> bool: return str(s["key"]) == "customer:%s" % cul["id"]):
		out.append({"key": "customer:%s" % cul["id"], "label": "%s (patient)" % cul["name"]})
	out.append({"key": "external", "label": "Street thieves"})
	out.append({"key": "corruption", "label": "A corrupt inspector"})
	for f: StringName in FactionManager.order:
		if FactionManager.get_rep(f) <= -20 or (str(cul.get("kind", "")) == "faction" and str(cul["id"]) == String(f)):
			out.append({"key": "faction:%s" % f, "label": FactionManager.get_name_of(f)})
	return out


func _culprit_key(c: Dictionary) -> String:
	var cul: Dictionary = c["culprit"]
	match str(cul["kind"]):
		"employee", "insider":
			return "staff:%s" % cul["id"]
		"customer":
			return "customer:%s" % cul["id"]
		"faction":
			return "faction:%s" % cul["id"]
	return str(cul["kind"])


func can_use(case_id: int, action: String) -> String:
	var c := get_case(case_id)
	if c.is_empty() or str(c["status"]) != "open":
		return "Closed"
	if (c["used"] as Array).has(action):
		return "Done"
	match action:
		"cameras":
			if ClinicManager.upgrade_level(&"security") < 1 and ClinicManager.security_rating() < 3:
				return "No cameras: install SECURITY"
		"question":
			if StaffManager.at_clinic(ClinicManager.tier).is_empty():
				return "No staff to question"
		"ask":
			if not EconomyManager.can_afford(100):
				return "Costs 100 cr"
	return ""


func investigate(case_id: int, action: String) -> String:
	if can_use(case_id, action) != "":
		return ""
	var c := get_case(case_id)
	(c["used"] as Array).append(action)
	var kind := str(c["culprit"]["kind"])
	var name := str(c["culprit"]["name"])
	var clue := ""
	match action:
		"cameras":
			var sharp := ClinicManager.upgrade_level(&"security") >= 2
			match kind:
				"employee", "insider":
					clue = "Footage: someone lets themselves in with a staff key at 03:12." + (" It's %s." % name if sharp else "")
				"customer":
					clue = "Footage: a patient from earlier lingers by the shelves." + (" It's %s." % name if sharp else "")
				"external":
					clue = "Footage: two masked figures through the back door, in and out in a minute."
				"faction":
					clue = "Footage: they sprayed a mark on the way out: %s." % name
				"corruption":
					clue = "Footage: a uniform, a badge, a bag. No warrant on file."
		"question":
			for e in StaffManager.at_clinic(ClinicManager.tier):
				var guilty := str(e["id"]) == str(c["culprit"].get("id", ""))
				if guilty:
					clue = "%s won't meet your eyes and has a new coat." % e["name"] if _rng.randf() < 0.7 else "%s has an alibi that sounds rehearsed." % e["name"]
				else:
					e["loyalty"] = maxf(0.0, float(e["loyalty"]) - 3.0)
			if clue == "":
				match kind:
					"external":
						clue = "Your staff saw a fixer's crew casing the alley yesterday."
					"faction":
						clue = "Your staff say %s people were asking about your stock." % name
					"corruption":
						clue = "Your staff say an inspector came by after closing 'to check the locks'."
					"customer":
						clue = "Your staff remember %s asking where you keep the good chrome." % name
					_:
						clue = "Nobody saw anything. Everyone resents being asked."
		"ask":
			EconomyManager.spend(100, &"other")
			match kind:
				"external":
					clue = "Word on the street: a crew from the canal is fencing clinic gear."
				"faction":
					clue = "Word on the street: %s did it to remind you who runs things." % name
				"corruption":
					clue = "Word on the street: an inspector has been selling seized chrome."
				"customer":
					clue = "Word on the street: %s has been bragging about free chrome." % name
				_:
					clue = "Word on the street: it was an inside job."
	(c["clues"] as Array).append(clue)
	cases_changed.emit()
	return clue


## Accuse someone. Right: most of it comes back. Wrong: an innocent is hurt.
func confront(case_id: int, key: String) -> Dictionary:
	var c := get_case(case_id)
	if c.is_empty() or str(c["status"]) != "open":
		return {}
	var right := key == _culprit_key(c)
	var text := ""
	if right:
		c["status"] = "solved"
		var back := _recover(c)
		match str(c["culprit"]["kind"]):
			"employee", "insider":
				var e := StaffManager.get_employee(StringName(str(c["culprit"]["id"])))
				if not e.is_empty():
					e["loyalty"] = 0.0
					StaffManager.employees.erase(e)
					StaffManager.staff_changed.emit()
					if str(c["culprit"]["kind"]) == "insider":
						e["secret_known"] = true
						StoryManager.set_flag(&"informant_found")
				text = "%s confesses and empties their locker on the way out. %s" % [c["culprit"]["name"], back]
			"customer":
				var pid := StringName(str(c["culprit"]["id"]))
				PeopleManager.change_rel(pid, -30)
				PeopleManager.note(pid, "Caught stealing from the clinic.")
				text = "%s hands it back with a story nobody believes. %s" % [c["culprit"]["name"], back]
			"faction":
				FactionManager.change(StringName(str(c["culprit"]["id"])), -3)
				FactionManager.add_heat(2.0)
				text = "You go to %s and ask nicely, twice. %s" % [c["culprit"]["name"], back]
			"corruption":
				FactionManager.add_heat(4.0)
				text = "You name the inspector to the right people. It costs you heat. %s" % back
			_:
				ReputationManager.change_dim(&"criminal", 2)
				text = "A word with the right fence and the crew brings it back. %s" % back
	else:
		c["status"] = "wrong"
		var parts := key.split(":")
		match parts[0]:
			"staff":
				var e2 := StaffManager.get_employee(StringName(parts[1]))
				if not e2.is_empty():
					e2["loyalty"] = maxf(0.0, float(e2["loyalty"]) - 15.0)
					MemoryManager.remember(StringName(parts[1]), &"PLAYER_LIED")
				text = "%s didn't do it, and now they know you thought they did." % (e2.get("name", "They") if not e2.is_empty() else "They")
			"customer":
				MemoryManager.remember(StringName(parts[1]), &"PLAYER_LIED")
				PeopleManager.change_rel(StringName(parts[1]), -15)
				text = "You accused a patient who didn't do it. They'll tell everyone."
			_:
				text = "Wrong door. Whoever did it is long gone."
	c["outcome"] = text
	if bool(c.get("quest", false)):
		if right:
			StoryManager.set_flag(&"inside_job_solved")
			QuestManager.check(&"q_inside_job")
		elif QuestManager.is_active(&"q_inside_job"):
			QuestManager.fail(&"q_inside_job")
	cases_changed.emit()
	return {"right": right, "text": text}


func close_case(case_id: int) -> void:
	var c := get_case(case_id)
	if not c.is_empty() and str(c["status"]) == "open":
		c["status"] = "closed"
		c["outcome"] = "You let it go."
		cases_changed.emit()


func _recover(c: Dictionary) -> String:
	var loot: Dictionary = c["loot"]
	match str(loot["kind"]):
		"money":
			var n := int(round(int(loot.get("amount", 0)) * 0.7))
			EconomyManager.add_money(n, &"other")
			return "You get %d back." % n
		"cyberware":
			InventoryManager.add_instance(ImplantInstance.from_dict(loot["item"]))
			return "The chrome is back on your shelf."
		"supplies":
			InventoryManager.add_supplies(int(loot.get("amount", 0)))
			return "The packs are back."
		"parts":
			InventoryManager.add_parts(int(loot.get("amount", 0)))
			return "The parts are back."
		"equipment":
			var tid := StringName(str(loot.get("tool", "")))
			if not InventoryManager.owns_tool(tid):
				InventoryManager.owned_tools.append(tid)
				EventBus.inventory_changed.emit()
				EventBus.modifiers_changed.emit()
			return "Your instrument is back."
	return "Some of it, anyway."


# --- Pressure (heat levels) -------------------------------------------------------------------

## At night, the heat level may bring someone knocking. Returns a note.
func roll_pressure(force_level: String = "") -> String:
	var lid := force_level if force_level != "" else String(level_id())
	var p: Dictionary = data.get("pressure", {}).get(lid, {})
	if p.is_empty() or (force_level == "" and _rng.randf() >= float(p.get("chance", 0.3))):
		return ""
	var acts: Array = (p.get("actions", []) as Array).duplicate(true)
	CommsManager.send_raw("message", "", str(p["subject"]), str(p["body"]), acts, "heat_%s" % lid)
	if lid == "critical":
		StoryManager.set_flag(&"heat_critical")
	return "%s (COMMS)." % str(p["subject"])


## A COMMS answer to security pressure.
func apply(fx: Dictionary) -> void:
	if fx.has("money"):
		var m := int(fx["money"])
		if not EconomyManager.spend(-m, &"bribes"):
			CommsManager.notify("You can't cover the bribe. They take it as a no.")
			FactionManager.add_heat(8.0)
			return
	if fx.has("heat"):
		FactionManager.add_heat(float(fx["heat"]))
	if fx.has("dims"):
		ReputationManager.change_dims(fx["dims"])
	if fx.has("suppliers_suspicion"):
		for id in SupplierManager.discovered():
			SupplierManager.change_suspicion(id, int(fx["suppliers_suspicion"]))
	if bool(fx.get("betray", false)):
		_betray()
	if str(fx.get("confiscate", "")) == "all":
		confiscate()
	if bool(fx.get("hide", false)):
		if _rng.randf() < 0.35 + 0.12 * ClinicManager.security_rating():
			FactionManager.add_heat(5.0)
			CommsManager.notify("They search for an hour and find nothing. They'll be back.")
		else:
			confiscate()
			FactionManager.add_heat(10.0)
			CommsManager.notify("They found the hiding place. Everything illegal is gone.")
	if bool(fx.get("informant", false)):
		informant = true
		StoryManager.set_flag(&"player_informant")
	cases_changed.emit()


## Security takes black-market chrome and stored contraband.
func confiscate() -> int:
	var n := 0
	for inst in InventoryManager.get_instances():
		if inst.source == &"black_market":
			InventoryManager.remove_instance(inst.uid)
			n += 1
	for c in SupplierManager.contraband:
		SupplierManager.change_suspicion(str(c["supplier"]), 20)
		SupplierManager.change_trust(str(c["supplier"]), -10)
		n += 1
	SupplierManager.contraband.clear()
	return n


## Cooperating means naming names: the street remembers.
func _betray() -> void:
	FactionManager.change(&"black_market", -6)
	FactionManager.change(&"street_gangs", -4)
	var told := 0
	for k: String in PeopleManager.people:
		var p: Dictionary = PeopleManager.people[k]
		if told < 3 and str(p.get("faction", "")) in ["street_gangs", "black_market"] and str(p.get("status", "")) == "alive":
			MemoryManager.remember(StringName(k), &"PLAYER_BETRAYED_FACTION")
			told += 1


# --- Save -------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"cases": cases.duplicate(true), "informant": informant, "next_case": _next_case}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	for c: Variant in d.get("cases", []):
		if c is Dictionary:
			cases.append(c)
	informant = bool(d.get("informant", false))
	_next_case = int(d.get("next_case", cases.size() + 1))
