extends RefCounted
## A choice that spends something needs it: with too few supplies (or parts,
## tokens, credits) the reply or event choice is blocked, in the COMMS screen
## and in the backend alike, and nothing it promised arrives. With exactly
## enough it works and empties the stock. A blocked reply still waits after
## a save and reload. Every event, street encounter and surgical dilemma
## keeps at least one choice you can make with nothing.
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	var cs_was := CutscenePlayer.enabled
	GameManager.is_running = true
	CutscenePlayer.enabled = false
	SaveManager.reset_all()
	_rook_favor()
	_hester_tipoff()
	_crew_reprisal()
	_costs_always_block_when_empty()
	SaveManager.reset_all()
	CutscenePlayer.enabled = cs_was
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _empty() -> void:
	EconomyManager.money = 0
	InventoryManager.supplies = 0
	InventoryManager.parts = 0
	InventoryManager.tokens = 0


## COMMS: Rook's favour costs two crates of supplies.
func _rook_favor() -> void:
	SaveManager.reset_all()
	_empty()
	var uid := CommsManager.send(&"c_rook_favor")
	var send: Dictionary = CommsManager.get_message(uid)["actions"][0]
	var rel := CharacterManager.relationship(&"rook_varga")
	var gangs := FactionManager.get_rep(&"street_gangs")
	var trust := int(SupplierManager.st("sallow").get("trust", 0))
	for have in [0, 1]:
		InventoryManager.supplies = have
		check(CommsManager.block_reason(send) != "", "Rook's favour: blocked with %d of 2 supplies" % have)
		check(not CommsManager.act(uid, 0), "Rook's favour: can't be sent with %d supplies" % have)
		check(CharacterManager.relationship(&"rook_varga") == rel and FactionManager.get_rep(&"street_gangs") == gangs
			and int(SupplierManager.st("sallow").get("trust", 0)) == trust and not bool(SupplierManager.st("sallow").get("discovered", false)),
			"Rook's favour: nothing promised arrives with %d supplies" % have)
		check(int(CommsManager.get_message(uid)["resolved"]) < 0 and InventoryManager.supplies == have, "Rook's favour: still waiting, stock untouched (%d)" % have)
	check(CommsManager.block_reason(CommsManager.get_message(uid)["actions"][1]) == "", "Rook's favour: saying no is always possible")
	# Save with the favour unanswered: it still waits, still blocked.
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	check(SaveManager.load_game(), "Rook's favour: game loads")
	_empty()
	check(int(CommsManager.get_message(uid).get("resolved", 0)) < 0 and not CommsManager.act(uid, 0), "Rook's favour: after reload, still waiting and still blocked")
	InventoryManager.supplies = 2
	check(CommsManager.block_reason(send) == "" and CommsManager.act(uid, 0), "Rook's favour: exactly two supplies is enough")
	check(InventoryManager.supplies == 0 and CharacterManager.relationship(&"rook_varga") > rel and bool(SupplierManager.st("sallow").get("discovered", false)),
		"Rook's favour: the crates go and the introduction comes")


## Event: Hester's tip-off costs one supply to clean up.
func _hester_tipoff() -> void:
	SaveManager.reset_all()
	_empty()
	FactionManager.heat = 40.0
	EventManager.queue_event(&"ev_hester_tipoff")
	var clean: Dictionary = EventManager.get_event(&"ev_hester_tipoff")["choices"][0]
	check(EventManager.get_choice_block_reason(clean) != "", "Hester: cleaning up needs a supply")
	check(EventManager.resolve(0) == "" and EventManager.pending_event == &"ev_hester_tipoff" and is_equal_approx(FactionManager.heat, 40.0),
		"Hester: with none, choosing it does nothing and the event waits")
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	SaveManager.load_game()
	_empty()
	check(EventManager.pending_event == &"ev_hester_tipoff" and EventManager.resolve(0) == "", "Hester: after reload, still waiting and still blocked")
	InventoryManager.supplies = 1
	FactionManager.heat = 40.0
	check(EventManager.resolve(0) != "" and InventoryManager.supplies == 0 and FactionManager.heat < 40.0, "Hester: one supply is exactly enough, and the heat drops")


## Event: the crew's reprisal. You pay, they take crates, or you take the hit.
func _crew_reprisal() -> void:
	SaveManager.reset_all()
	_empty()
	EventManager.queue_event(&"ev_crew_reprisal")
	var ch: Array = EventManager.get_event(&"ev_crew_reprisal")["choices"]
	InventoryManager.supplies = 2
	EconomyManager.money = 599
	check(EventManager.get_choice_block_reason(ch[0]) != "" and EventManager.get_choice_block_reason(ch[1]) != "", "reprisal: 599 cr and two crates cover neither price")
	check(EventManager.resolve(1) == "" and InventoryManager.supplies == 2 and EventManager.pending_event == &"ev_crew_reprisal", "reprisal: 'let them take supplies' can't be had for less than three")
	check(EventManager.get_choice_block_reason(ch[2]) == "", "reprisal: standing in the doorway is always possible")
	var gangs := FactionManager.get_rep(&"street_gangs")
	var mods := EventManager.temp_modifiers.size()
	check(EventManager.resolve(2) != "" and FactionManager.get_rep(&"street_gangs") < gangs and EventManager.temp_modifiers.size() == mods + 1,
		"reprisal: refusing costs standing and your steady hands")
	EventManager.history.erase(&"ev_crew_reprisal")
	EventManager.queue_event(&"ev_crew_reprisal")
	InventoryManager.supplies = 3
	check(EventManager.resolve(1) != "" and InventoryManager.supplies == 0, "reprisal: three crates is exactly enough")


## The rule holds everywhere: with nothing, a choice that spends is blocked,
## and something is always left to choose.
func _costs_always_block_when_empty() -> void:
	SaveManager.reset_all()
	_empty()
	var sets := {}
	for e: Dictionary in EventManager.events.values():
		sets["event %s" % str(e["id"])] = e.get("choices", [])
	_collect(LocationManager.data, "place", sets)
	# Events and street encounters stop you until you answer; a place's
	# goings-on, COMMS messages and travel you can walk away from.
	var must_answer := sets.keys().filter(func(k: String) -> bool: return k.begins_with("event "))
	for d: Dictionary in LocationManager.data.get("travel", {}).get("encounters", []):
		if (d.get("choices", []) as Array).is_empty():
			continue  # something you only see on the way
		sets["street %s" % str(d["id"])] = d.get("choices", [])
		must_answer.append("street %s" % str(d["id"]))
	for id: String in CommsManager.templates:
		var acts: Array = CommsManager.templates[id].get("actions", [])
		if not acts.is_empty():
			sets["comms %s" % id] = acts
	var leaks := []
	var stuck := []
	for k: String in sets:
		var any := false
		for c: Dictionary in sets[k]:
			var blocked := EventManager.get_choice_block_reason(c) != ""
			if not EventManager.choice_costs(c).is_empty() and not blocked:
				leaks.append("%s: %s" % [k, str(c.get("label", ""))])
			var flag_only: bool = (c.get("requires", {}) as Dictionary).has("flag")
			any = any or (not blocked) or flag_only
		if not any and must_answer.has(k):
			stuck.append(k)
	check(sets.size() > 40, "the rule is checked across events and COMMS (%d choice sets)" % sets.size())
	check(leaks.is_empty(), "with an empty stock every choice that spends is blocked %s" % str(leaks))
	check(stuck.is_empty(), "with nothing, every choice set still has an answer %s" % str(stuck))
	for d: Dictionary in SurgicalDilemmas.data().get("dilemmas", []):
		var free := false
		for c: Dictionary in d["choices"]:
			free = free or ((c.get("requires", {}) as Dictionary).is_empty())
		check(free, "dilemma %s: one choice needs nothing" % str(d["id"]))


## Every {id, choices} found anywhere in the city data (place events and the like).
func _collect(n: Variant, where: String, sets: Dictionary) -> void:
	if n is Dictionary:
		if (n as Dictionary).has("choices") and n["choices"] is Array:
			sets["%s %s" % [where, str(n.get("id", "?"))]] = n["choices"]
			return
		for k: Variant in n:
			_collect(n[k], where, sets)
	elif n is Array:
		for x: Variant in n:
			_collect(x, where, sets)
