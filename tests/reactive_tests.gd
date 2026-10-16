extends RefCounted
## 3.12 tests: a world that reacts. Rivals react to the sides you take
## (FactionManager.change_by_choice, the previews that show it), the story
## conditions that read standing and trust, the reactive cases (the Crews or
## Aegis, the independent courier, Bed 14's two returns, Pike's grudge or
## favour, the clerk's tip-off or disappearance), their delayed echoes, the
## mutually exclusive branches, saves, repeats, and the clearer UI wording
## (the NEXT line for a waiting decision, the plan's advice, the risk line).
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	var cs_was := CutscenePlayer.enabled
	GameManager.is_running = true
	CutscenePlayer.enabled = false
	SaveManager.reset_all()
	_rivals()
	_rival_previews()
	_story_conditions()
	_data_integrity()
	_crews_branch_kept()
	_crews_branch_sold()
	_aegis_branch()
	_courier_neutral()
	_sable_returns()
	_pike_and_hester()
	_no_repeats_and_saves()
	_ui_wording()
	SaveManager.reset_all()
	CutscenePlayer.enabled = cs_was
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _new_day(day: int) -> void:
	BusinessManager.day = day
	BusinessManager.jobs_today = 0
	EventBus.day_started.emit(day)


## Puts the story at `act` with every other case already behind you, so
## `due_case()` answers only for the case under test.
func _only_case(act: int, case_id: String, day_in_act: int = 3) -> void:
	StoryManager.act = act
	StoryManager.act_started_day = BusinessManager.day - day_in_act
	StoryManager.last_case_day = -99
	for sc: Dictionary in StoryManager.cases:
		var id := str(sc["id"])
		if id != case_id and not StoryManager.case_state.has(id):
			StoryManager.case_state[id] = "missed"


func _set_rep(f: StringName, v: int) -> void:
	FactionManager.rep[f] = v


## Runs a case from the door to its decision; returns the patient.
func _play_case(case_id: String) -> CustomerData:
	var sc := StoryManager.get_case(StringName(case_id))
	var c := CustomerManager.make_case_customer(sc)
	CustomerManager.debug_set_customer(c)
	CustomerManager.dismiss_current()
	StoryManager.case_finished(c, "success")
	return c


func _inbox_has(template: String) -> Dictionary:
	for m: Dictionary in CommsManager.inbox:
		if str(m.get("template", "")) == template:
			return m
	return {}


# --- Rivals --------------------------------------------------------------------------------

func _rivals() -> void:
	SaveManager.reset_all()
	var corp := FactionManager.get_rep(&"corporate_security")
	var board := FactionManager.get_rep(&"medical_authorities")
	var bm := FactionManager.get_rep(&"black_market")
	FactionManager.change_by_choice(&"street_gangs", 6, "test")
	check(FactionManager.get_rep(&"corporate_security") == corp - 2 and FactionManager.get_rep(&"medical_authorities") == board - 2,
		"rivals: siding with the Crews (+6) costs Aegis and the Board 2 each")
	check(FactionManager.get_rep(&"black_market") == bm, "rivals: factions that aren't rivals don't move")
	var before := FactionManager.get_rep(&"corporate_security")
	FactionManager.change_by_choice(&"street_gangs", 2, "test")
	check(FactionManager.get_rep(&"corporate_security") == before, "rivals: a small gain (+2) goes unnoticed")
	check(int(FactionManager.rival_losses(&"medical_authorities", 25).get(&"black_market", 0)) == -FactionManager.RIVAL_MAX_LOSS,
		"rivals: a big gain costs rivals at most %d" % FactionManager.RIVAL_MAX_LOSS)
	check(FactionManager.rival_losses(&"independent_mercs", 10).is_empty(), "rivals: the Free Contractors have no rivals (neutral work stays neutral)")
	check(FactionManager.rival_losses(&"street_gangs", -8).is_empty(), "rivals: losing standing doesn't please anyone else")
	# Routine work (operations, quest rewards) uses change() and stays neutral.
	before = FactionManager.get_rep(&"corporate_security")
	FactionManager.change(&"street_gangs", GameConfig.FACTION_REP_SUCCESS * 2)
	check(FactionManager.get_rep(&"corporate_security") == before, "rivals: paid work for a faction doesn't anger its rivals")
	# Decisions do: an event choice and a conversation's effects.
	SaveManager.reset_all()
	corp = FactionManager.get_rep(&"corporate_security")
	EventManager.apply_outcomes({"faction": {"street_gangs": 5}})
	check(FactionManager.get_rep(&"corporate_security") == corp - 2, "rivals: an event choice that favours the Crews costs Aegis")
	corp = FactionManager.get_rep(&"corporate_security")
	StoryManager.apply_effects({"faction": {"street_gangs": 5}})
	check(FactionManager.get_rep(&"corporate_security") == corp - 2, "rivals: so does a line in a conversation or a reply")
	var why := false
	for e: Dictionary in ChangeLog.standing:
		why = why or (str(e.get("group", "")) == "faction:corporate_security" and str(e.get("reason", "")).contains("Rustline"))
	check(why, "rivals: the standing history says why (you sided with the Rustline Crews)")
	SaveManager.reset_all()


func _rival_previews() -> void:
	var ev := EventManager.get_event(&"case_lieutenant_after")
	var sell: Dictionary = ev["choices"][1]["outcomes"]
	var p := Standing.preview(sell)
	check(p.contains("Aegis Meridian Security +6") and p.contains("Rustline Crews -10") and p.contains("The Undermarket -2"),
		"preview: selling Hook shows Aegis +6, the Crews -10 (-8 and -2 as Aegis's rival) and the Undermarket -2 (%s)" % p)
	var keep: Dictionary = ev["choices"][0]["outcomes"]
	var k := Standing.preview(keep)
	check(k.contains("Rustline Crews +6") and k.contains("Aegis Meridian Security -2 (rivals)"), "preview: keeping him hidden shows what Aegis thinks of it (%s)" % k)
	# Real numbers match the preview.
	SaveManager.reset_all()
	var g := FactionManager.get_rep(&"street_gangs")
	var c := FactionManager.get_rep(&"corporate_security")
	EventManager.apply_outcomes({"faction": sell["faction"]})
	check(FactionManager.get_rep(&"street_gangs") == g - 10 and FactionManager.get_rep(&"corporate_security") == c + 6, "preview: the real change matches what was shown")
	# Conversations preview rivals too (DialogueManager.known_effects).
	var known := DialogueManager.known_effects({"effects": {"faction": {"medical_authorities": 20}}})
	check(known.contains("The Undermarket -5 (rivals)"), "preview: a conversation line shows the rivals' reaction (%s)" % known)
	SaveManager.reset_all()


# --- Conditions ----------------------------------------------------------------------------

func _story_conditions() -> void:
	SaveManager.reset_all()
	check(StoryManager.cond({"rel_min": {"rook_varga": 10}}) == false, "cond: rel_min reads a character's trust (none yet)")
	CharacterManager.change_relationship(&"rook_varga", 20)
	check(StoryManager.cond({"rel_min": {"rook_varga": 10}}) and not StoryManager.cond({"rel_max": {"rook_varga": 10}}), "cond: rel_min / rel_max")
	check(not StoryManager.cond({"dim_min": {"criminal": 5}}), "cond: dim_min reads a reputation type")
	ReputationManager.change_dim(&"criminal", 6)
	check(StoryManager.cond({"dim_min": {"criminal": 5}}), "cond: dim_min holds once you're known for it")
	_set_rep(&"street_gangs", 30)
	check(not StoryManager.cond({"faction_max": {"street_gangs": 14}}) and StoryManager.cond({"faction_max": {"black_market": 14}}), "cond: faction_max")
	FactionManager.heat = 40.0
	check(not StoryManager.cond({"max_heat": 30}), "cond: max_heat")
	StoryManager.set_flag(&"sided_crews")
	check(not StoryManager.cond({"not_flag_any": ["sided_aegis", "sided_crews"]}), "cond: not_flag_any")
	check(StoryManager.cond({"any": [{"flag": "nope"}, {"flag": "sided_crews"}]}) and not StoryManager.cond({"any": [{"flag": "nope"}, {"min_rep": 999}]}), "cond: any of several")
	check(EventManager.conditions_met({"story": {"flag": "sided_crews"}}) and not EventManager.conditions_met({"story": {"flag": "sided_aegis"}}), "cond: events can use the story's conditions")
	SaveManager.reset_all()


func _data_integrity() -> void:
	var new_cases := ["case_crew_lieutenant", "case_aegis_retainer", "case_courier_offer", "case_pike_grudge", "case_sable_returns", "case_sable_liaison"]
	var ok := true
	for id in new_cases:
		ok = ok and not StoryManager.get_case(StringName(id)).is_empty()
	check(ok, "data: the six reactive cases are loaded")
	# Every echo they or the changed decisions schedule exists.
	var ids := ["case_lieutenant_after", "ev_crew_reprisal", "case_retainer_after", "ev_aegis_audit", "case_courier_after", "case_pike_after",
		"ev_pike_boards", "ev_hester_tipoff", "case_sable_after", "case_liaison_after", "case_clerk_after", "case_dial_tone_after"]
	var refs := true
	var missing := ""
	for id in ids:
		var ev := EventManager.get_event(StringName(id))
		refs = refs and not ev.is_empty()
		for ch: Dictionary in ev.get("choices", []):
			var o: Dictionary = ch.get("outcomes", {})
			for b: Dictionary in [o, o.get("risk", {}).get("success", {}), o.get("risk", {}).get("fail", {})]:
				var e: Dictionary = b.get("effects", {})
				if e.has("consequence"):
					var cid := str(e["consequence"]["id"])
					if not (CommsManager.templates.has(cid) or EventManager.events.has(StringName(cid)) or DialogueManager.has_dialogue(StringName(cid))):
						refs = false
						missing += " " + cid
				for s: Variant in e.get("supplier", {}):
					if SupplierManager.supplier(str(s)).is_empty():
						refs = false
						missing += " supplier " + str(s)
				if e.has("quest") and not QuestManager.quests.has(StringName(str(e["quest"]))):
					refs = false
					missing += " quest " + str(e["quest"])
	check(refs, "data: every decision, echo, contact and quest they name exists%s" % missing)
	# Story decisions are never rolled at random, and play once.
	var once := true
	for id in ids:
		var ev := EventManager.get_event(StringName(id))
		once = once and float(ev.get("weight", 1)) == 0.0 and bool(ev.get("once", false))
	check(once, "data: decisions and echoes are weight 0, once")
	# None of it is needed to finish the story: act changes don't read it.
	var new_flags := ["sided_crews", "sided_aegis", "hook_sold", "independent_contact", "pike_enemy", "pike_ally", "lyra_chart", "liaison_signed", "aegis_informant"]
	var free := true
	for a: Dictionary in StoryManager.acts:
		var adv := JSON.stringify(a.get("advance", {}))
		for f in new_flags:
			free = free and not adv.contains(f)
	check(free, "data: act progress never depends on a reactive branch (missing one blocks nothing)")


# --- The Crews or Aegis ------------------------------------------------------------------------

func _crews_branch_kept() -> void:
	SaveManager.reset_all()
	_new_day(8)
	EventManager.operations = 12
	_set_rep(&"street_gangs", 20)
	_set_rep(&"corporate_security", 0)
	_only_case(2, "case_crew_lieutenant")
	var sc := StoryManager.due_case()
	check(str(sc.get("id", "")) == "case_crew_lieutenant", "crews: in good with the Crews, Rook sends a lieutenant (%s)" % str(sc.get("id", "")))
	var routine := CustomerManager.generator.generate({"archetype": "gang_member", "faction": "street_gangs", "category": "arms"})
	var c := CustomerManager.make_case_customer(sc)
	check(c.referred_by == "Rook Varga" and c.display_name == "Dace Marrow", "crews: the patient says who sent him (Rook Varga)")
	check(c.pay_multiplier > routine.pay_multiplier and c.budget >= CustomerGenerator.estimate_fee(c), "crews: Rook's job pays better than a routine one, and he can afford it")
	CustomerManager.debug_set_customer(c)
	CustomerManager.dismiss_current()
	StoryManager.case_finished(c, "success")
	check(EventManager.pending_event == &"case_lieutenant_after", "crews: THE BOUNTY follows the operation")
	var rook := CharacterManager.relationship(&"rook_varga")
	EventManager.resolve(0)
	check(StoryManager.has_flag(&"sided_crews") and CharacterManager.relationship(&"rook_varga") > rook and MemoryManager.has(&"rook_varga", &"PLAYER_KEPT_SECRET"),
		"crews: keeping him hidden: you're with the Crews, and Rook remembers you kept quiet")
	# Aegis never comes now, however high Aegis rates you.
	_set_rep(&"corporate_security", 40)
	_set_rep(&"street_gangs", 0)
	_only_case(2, "case_aegis_retainer")
	check(StoryManager.due_case().is_empty(), "crews: having sided with the Crews, Aegis never offers its retainer (mutually exclusive)")
	# Three days later Rook asks a favour, and it opens a door.
	_new_day(10)
	check(_inbox_has("c_rook_favor").is_empty(), "crews: nothing from Rook two days later")
	_new_day(11)
	var m := _inbox_has("c_rook_favor")
	check(not m.is_empty(), "crews: three days later Rook calls in a favour")
	InventoryManager.supplies = 6
	CommsManager.act(int(m["uid"]), 0)
	check(InventoryManager.supplies == 4 and bool(SupplierManager.st("sallow").get("discovered", false)) and SupplierManager.has_unlock("sallow", "credit"),
		"crews: sending the crates costs 2 supplies and introduces Sallow, with credit from the start")
	SaveManager.reset_all()


func _crews_branch_sold() -> void:
	SaveManager.reset_all()
	_new_day(8)
	EventManager.operations = 12
	_set_rep(&"street_gangs", 20)
	_set_rep(&"corporate_security", 0)
	_only_case(2, "case_crew_lieutenant")
	_play_case("case_crew_lieutenant")
	var money := EconomyManager.money
	EventManager.resolve(1)
	check(EconomyManager.money == money + 800 and StoryManager.has_flag(&"sided_aegis") and StoryManager.has_flag(&"hook_sold"), "sold: Aegis pays 800 and you're on their side now")
	check(CharacterManager.relationship_state(&"rook_varga") == "hostile" and MemoryManager.has(&"rook_varga", &"PLAYER_BETRAYED_FACTION"),
		"sold: Rook becomes an enemy, and remembers why (%s)" % CharacterManager.relationship_state(&"rook_varga"))
	_new_day(9)
	check(not EventManager.has_pending(), "sold: Rook doesn't come the next day")
	_new_day(10)
	check(EventManager.pending_event == &"ev_crew_reprisal", "sold: two days later Rook comes to collect (PAID IN KIND)")
	check(EventManager.get_event(&"ev_crew_reprisal").get("character", "") == "rook_varga", "sold: it's Rook at the door (his portrait on the decision)")
	EconomyManager.money = 100
	check(EventManager.get_choice_block_reason(EventManager.get_event(&"ev_crew_reprisal")["choices"][0]) != "", "sold: you can't pay him with money you don't have")
	InventoryManager.supplies = 5
	EventManager.resolve(1)
	check(InventoryManager.supplies == 2, "sold: the runners take three crates instead")
	# The Crews' case never comes back, and Aegis's doesn't either: you already chose.
	_only_case(2, "case_aegis_retainer")
	_set_rep(&"corporate_security", 40)
	_set_rep(&"street_gangs", 0)
	check(StoryManager.due_case().is_empty(), "sold: the retainer isn't offered on top (you're already Aegis's)")
	SaveManager.reset_all()


func _aegis_branch() -> void:
	SaveManager.reset_all()
	_new_day(8)
	EventManager.operations = 12
	_set_rep(&"corporate_security", 20)
	_set_rep(&"street_gangs", 0)
	_only_case(2, "case_aegis_retainer")
	check(str(StoryManager.due_case().get("id", "")) == "case_aegis_retainer", "aegis: trusted by Aegis, Lieutenant Sato comes in")
	_set_rep(&"street_gangs", 20)
	_only_case(2, "case_crew_lieutenant")
	StoryManager.case_state.erase("case_crew_lieutenant")
	_set_rep(&"corporate_security", 20)
	check(StoryManager.due_case().is_empty(), "aegis / crews: trusted by both, neither side asks you to choose yet")
	_set_rep(&"street_gangs", 0)
	StoryManager.case_state["case_crew_lieutenant"] = "missed"
	_play_case("case_aegis_retainer")
	check(EventManager.pending_event == &"case_retainer_after", "aegis: THE RETAINER follows")
	var money := EconomyManager.money
	EventManager.resolve(1)
	check(EconomyManager.money == money + 500 and not StoryManager.has_flag(&"sided_aegis"), "aegis: signing and sending nothing pays, without taking a side yet")
	for d in range(9, 13):
		_new_day(d)
		check(EventManager.pending_event != &"ev_aegis_audit", "aegis: no audit on day %d" % d)
	_new_day(13)
	check(EventManager.pending_event == &"ev_aegis_audit", "aegis: five days later Sato audits the blank reports")
	var heat := FactionManager.heat
	var corp := FactionManager.get_rep(&"corporate_security")
	EventManager.resolve(2)
	check(FactionManager.heat > heat and FactionManager.get_rep(&"corporate_security") == corp - 10 and StoryManager.has_flag(&"retainer_torn"),
		"aegis: tearing up the card costs Aegis's goodwill and brings the inspectors back")
	# Sending the names instead: Glass opens up, and the Crews notice.
	SaveManager.reset_all()
	_new_day(8)
	_set_rep(&"corporate_security", 20)
	_only_case(2, "case_aegis_retainer")
	_play_case("case_aegis_retainer")
	FactionManager.heat = 30.0
	EventManager.resolve(0)
	check(StoryManager.has_flag(&"sided_aegis") and FactionManager.heat < 30.0 and bool(SupplierManager.st("glass").get("discovered", false)),
		"aegis: sending the names keeps the inspectors off and introduces Glass")
	_new_day(12)
	var m := _inbox_has("c_crews_notice")
	check(not m.is_empty(), "aegis: four days later Rook asks about the fresh stitches")
	CommsManager.act(int(m["uid"]), 1)
	check(MemoryManager.has(&"rook_varga", &"PLAYER_BETRAYED_FACTION"), "aegis: 'business is business' - Rook remembers")
	SaveManager.reset_all()


func _courier_neutral() -> void:
	SaveManager.reset_all()
	_new_day(9)
	EventManager.operations = 12
	_only_case(2, "case_courier_offer", 5)
	check(str(StoryManager.due_case().get("id", "")) == "case_courier_offer", "neutral: owing nobody, an independent courier comes in")
	StoryManager.set_flag(&"sided_crews")
	check(StoryManager.due_case().is_empty(), "neutral: not once you've taken a side")
	StoryManager.set_flag(&"sided_crews", false)
	_set_rep(&"street_gangs", 30)
	check(StoryManager.due_case().is_empty(), "neutral: nor when you're deep with one faction")
	# Turning down a profitable retainer opens this door even to Aegis's friends.
	_set_rep(&"street_gangs", 0)
	_set_rep(&"corporate_security", 30)
	StoryManager.set_flag(&"retainer_declined")
	var sc := StoryManager.due_case()
	check(str(sc.get("id", "")) == "case_courier_offer" and StoryManager.case_text(sc, "line").contains("handed an Aegis retainer back"),
		"neutral: refusing Aegis's retainer brings the courier anyway, and he's heard about it")
	_play_case("case_courier_offer")
	var board := FactionManager.get_rep(&"medical_authorities")
	EventManager.resolve(0)
	check(StoryManager.has_flag(&"independent_contact") and bool(SupplierManager.st("okafor").get("discovered", false)) and FactionManager.get_rep(&"medical_authorities") == board,
		"neutral: the introduction to Okafor costs no one's goodwill")
	SaveManager.reset_all()


# --- Returning characters ---------------------------------------------------------------------

func _sable_returns() -> void:
	SaveManager.reset_all()
	_new_day(26)
	EventManager.operations = 40
	StoryManager.set_flag(&"runaway_freed")
	_only_case(4, "case_sable_returns")
	StoryManager.case_state.erase("case_sable_liaison")
	check(str(StoryManager.due_case().get("id", "")) == "case_sable_returns", "bed 14 (freed): Sable comes back in act IV as a friend")
	_play_case("case_sable_returns")
	check(SupplierManager.has_unlock("curator", "rare"), "bed 14 (freed): she introduces the Curator, who sells you rare chrome")
	EventManager.resolve(0)
	check(StoryManager.has_flag(&"lyra_chart") and ClinicLifeManager.has_pin("case_chart"), "bed 14 (freed): the trial chart goes up behind the Wall")
	DialogueManager.start(&"d_moor_evidence")
	check(DialogueManager.node_text(DialogueManager.current_node()).contains("trial chart"), "bed 14 (freed): Moor knows about the chart when she asks for evidence")
	DialogueManager.end()
	_only_case(4, "case_sable_liaison")
	StoryManager.last_case_day = -99
	check(StoryManager.due_case().is_empty(), "bed 14 (freed): the Lyra liaison never comes")
	# Sold: she comes back as Lyra's.
	SaveManager.reset_all()
	_new_day(26)
	EventManager.operations = 40
	StoryManager.set_flag(&"runaway_sold")
	_only_case(4, "case_sable_liaison")
	check(str(StoryManager.due_case().get("id", "")) == "case_sable_liaison", "bed 14 (sold): Sable comes back as Lyra's liaison")
	var c := _play_case("case_sable_liaison")
	check(c.referred_by == "Lyra Biocomp" and c.occupation.contains("Lyra"), "bed 14 (sold): her file says who she works for now")
	EventManager.resolve(0)
	check(QuestManager.is_active(&"q_thread_installs") and StoryManager.has_flag(&"liaison_signed"), "bed 14 (sold): signing starts Lyra's stabiliser contract")
	SaveManager.reset_all()


func _pike_and_hester() -> void:
	# Pike, sold: he comes back for it, and makes it public.
	SaveManager.reset_all()
	_new_day(20)
	EventManager.operations = 30
	StoryManager.set_flag(&"thread_log_sold")
	_only_case(3, "case_pike_grudge")
	check(str(StoryManager.due_case().get("id", "")) == "case_pike_grudge", "pike (sold): he comes back in act III")
	_play_case("case_pike_grudge")
	EventManager.resolve(1)
	_new_day(23)
	check(EventManager.pending_event == &"ev_pike_boards", "pike (sold): 'business' - three days later your face is on every board")
	var heat := FactionManager.heat
	EventManager.resolve(1)
	check(FactionManager.heat > heat, "pike (sold): letting it stand draws heat")
	# Pike, copied: an ally, with a way in.
	SaveManager.reset_all()
	_new_day(10)
	EventManager.queue_event(&"case_dial_tone_after")
	EventManager.resolve(0)
	_new_day(14)
	var m := _inbox_has("c_pike_thanks")
	check(not m.is_empty(), "pike (copied): four days later he offers you a way into Lyra's annex")
	CommsManager.act(int(m["uid"]), 0)
	check(StoryManager.has_flag(&"pike_ally") and LocationManager.is_known(&"lyra_annex"), "pike (copied): the annex is on your map")
	_only_case(3, "case_pike_grudge")
	check(StoryManager.due_case().is_empty(), "pike (copied): no grudge visit")
	# The clerk: a tip-off, or gone.
	SaveManager.reset_all()
	_new_day(10)
	EventManager.queue_event(&"case_clerk_after")
	EventManager.resolve(0)
	_new_day(16)
	check(EventManager.pending_event == &"ev_hester_tipoff", "clerk (files): six days later Hester tips you off about an inspection")
	FactionManager.heat = 30.0
	InventoryManager.supplies = 4
	EventManager.resolve(0)
	check(FactionManager.heat < 30.0 and InventoryManager.supplies == 3, "clerk (files): cleaning up costs a supply and cools the heat")
	SaveManager.reset_all()
	_new_day(10)
	EventManager.queue_event(&"case_clerk_after")
	EventManager.resolve(1)
	_new_day(15)
	check(not _inbox_has("c_hester_transferred").is_empty(), "clerk (warned): five days later she's been transferred and her files are gone")
	SaveManager.reset_all()


# --- Repeats and saves -------------------------------------------------------------------------

func _no_repeats_and_saves() -> void:
	SaveManager.reset_all()
	_new_day(8)
	EventManager.operations = 12
	_set_rep(&"street_gangs", 20)
	_only_case(2, "case_crew_lieutenant")
	var c := _play_case("case_crew_lieutenant")
	EventManager.resolve(0)
	StoryManager.case_finished(c, "success")
	check(not EventManager.has_pending(), "repeats: finishing a case twice never repeats its decision")
	_new_day(30)
	_only_case(2, "case_crew_lieutenant")
	StoryManager.last_case_day = -99
	check(StoryManager.due_case().is_empty(), "repeats: a case comes once")
	var favors := 0
	for m: Dictionary in CommsManager.inbox:
		if str(m.get("template", "")) == "c_rook_favor":
			favors += 1
	check(favors == 1, "repeats: the favour is asked once (%d)" % favors)
	# Saves keep the branch; a reloaded save doesn't reopen the other side.
	var story := StoryManager.get_save_data()
	var fac := FactionManager.get_save_data()
	var chars := CharacterManager.get_save_data()
	SaveManager.reset_all()
	StoryManager.load_save_data(story)
	FactionManager.load_save_data(fac)
	CharacterManager.load_save_data(chars)
	check(StoryManager.has_flag(&"sided_crews") and str(StoryManager.case_state.get("case_crew_lieutenant", "")) == "done", "saves: the side you took survives a reload")
	_set_rep(&"corporate_security", 40)
	_set_rep(&"street_gangs", 0)
	BusinessManager.day = 30
	_only_case(2, "case_aegis_retainer")
	check(StoryManager.due_case().is_empty(), "saves: after a reload, Aegis still doesn't offer the retainer")
	# An old save (3.11) has none of the new flags: nothing reactive fires by mistake.
	SaveManager.reset_all()
	StoryManager.load_save_data({"act": 4, "act_started_day": 20, "flags": {"met_bram": true}, "cases": {"case_crane_hands": "done"}})
	BusinessManager.day = 26
	for id in ["case_sable_returns", "case_sable_liaison", "case_pike_grudge"]:
		_only_case(4, id)
		StoryManager.last_case_day = -99
		check(StoryManager.due_case().get("id", "") != id, "old saves: %s needs its earlier decision, so it doesn't appear" % id)
		StoryManager.case_state.erase(id)
	SaveManager.reset_all()


# --- Wording -----------------------------------------------------------------------------------

func _ui_wording() -> void:
	SaveManager.reset_all()
	EventManager.queue_event(&"case_lieutenant_after")
	var o := GameManager.get_next_objective()
	check(str(o["text"]) == "Decide: THE BOUNTY" and (o.get("link", {}) as Dictionary).has("answer"), "next: a waiting decision is named, and the line brings it back (%s)" % str(o["text"]))
	check(Nav.can_open({"answer": true}), "next: the link works while something waits")
	EventManager.pending_event = &""
	check(not Nav.can_open({"answer": true}), "next: and does nothing once answered")
	# A story patient says there's more to them; a routine one doesn't.
	var c := CustomerManager.make_case_customer(StoryManager.get_case(&"case_crane_hands"))
	CustomerManager.debug_set_customer(c)
	check(str(GameManager.get_next_objective()["why"]).contains("may come back"), "next: a story patient hints that the decision matters later")
	CustomerManager.dismiss_current()
	# The overall-risk line is plain words.
	var r := CustomerManager.generator.generate({"full_difficulty": true})
	r.hidden_conditions.clear()
	r.revealed_conditions.clear()
	var plain := true
	for e: Dictionary in IntakeRecord.risks(r):
		plain = plain and not str(e["why"]).contains("physiology") and not str(e["why"]).contains("isn't identified")
	check(plain, "wording: the risk line says what it means, not 'physiology ... isn't identified'")
	check(JobVerdict.watch_phrase({"key": "implant", "label": "IMPLANT", "value": "buy one (220 cr)"}) == "you'll have to buy the implant"
		and JobVerdict.watch_phrase({"key": "risk", "label": "RISK", "value": "MEDIUM"}) == "the patient is medium risk", "wording: the plan's advice names what to watch in words")
	SaveManager.reset_all()
