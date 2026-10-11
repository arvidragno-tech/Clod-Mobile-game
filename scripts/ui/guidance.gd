class_name Guidance
extends RefCounted
## WHAT MATTERS NOW: a short, prioritised list of what currently needs the
## player, built from the real game state every time it's asked (nothing
## is stored). Not a quest log: at most a handful of lines, the most urgent
## first, each with a clear symbol (never colour alone) and a link that goes
## straight to the patient, person, place, screen or explanation.
##
## Levels: CRITICAL (■, act now), IMPORTANT (▲, decide soon), INFO (·).

const CRITICAL := &"critical"
const IMPORTANT := &"important"
const INFO := &"info"
const MARKS := {&"critical": "■", &"important": "▲", &"info": "·"}
const MAX_ITEMS := 7


## [{id, level, icon, text, link}] most urgent first, at most `n`.
static func items(n: int = MAX_ITEMS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var add := func(id: String, level: StringName, icon: String, text: String, link: Dictionary = {}) -> void:
		out.append({"id": id, "level": level, "icon": icon, "text": text, "link": link})
	var c: CustomerData = CustomerManager.current_customer
	# --- Critical ---------------------------------------------------------------------
	if c and c.is_emergency:
		var left := CustomerManager.emergency_seconds_left()
		add.call("emergency", CRITICAL, "✚", "Emergency: %s is bleeding at the door%s" % [c.display_name,
			(" · %ds" % ceili(left)) if left > 0.0 else ""], {"customer": true})
	if EventManager.has_pending():
		add.call("incident", CRITICAL, "!", "Someone is waiting: deal with the incident", {"screen": &"clinic"})
	if InventoryManager.supplies <= 0:
		add.call("supplies_out", CRITICAL, "✚", "No medical supplies: you can't operate. Restock in SUPPLY", {"screen": &"shop"})
	if FactionManager.heat >= 85.0:
		add.call("heat", CRITICAL, "!", "Authority heat %d: a raid is close. Lie low, do clean work" % roundi(FactionManager.heat), {"term": "heat"})
	if BusinessManager.debt >= BusinessManager.DEBT_WARNING:
		add.call("debt", CRITICAL if BusinessManager.days_in_debt > 1 else IMPORTANT, "¤",
			"You owe %s: pay it down in BUSINESS" % EconomyManager.format_money(BusinessManager.debt), {"screen": &"business"})
	# --- Important ---------------------------------------------------------------------
	if StoryManager.has_talk():
		var who := CharacterManager.get_character(StringName(str(DialogueManager.get_dialogue(StoryManager.peek_talk()).get("character", ""))))
		add.call("talk", IMPORTANT, "»", "%s wants to speak with you" % (who.display_name if who else "Someone"), {"screen": &"clinic"})
	if c and not c.is_emergency:
		var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
		add.call("door", IMPORTANT, "●", "%s is at the door · wants %s · pays ≈%s" % [c.display_name, item.display_name if item else "work",
			EconomyManager.format_money(CustomerGenerator.estimate_fee(c))], {"customer": true})
	var waiting := ClinicLifeManager.waiting_customers().size()
	if waiting > 0:
		add.call("waiting", IMPORTANT if waiting >= 2 else INFO, "●", "%d waiting in your waiting room" % waiting, {"screen": &"clinic"})
	for f: Dictionary in Follows.live():
		if bool(f["soon"]):
			add.call("follow:%s" % f["id"], IMPORTANT, "◆", "%s · %s%s" % [f["title"], f["detail"] if str(f["detail"]) != "" else f["when"],
				(" · " + str(f["when"])) if str(f["detail"]) != "" and str(f["when"]) not in ["", "now"] else ""], f["link"])
	var unread := CommsManager.unread_count()
	if unread > 0:
		add.call("comms", IMPORTANT, "✉", "%d unread message%s" % [unread, "" if unread == 1 else "s"], {"screen": &"dossier", "params": {"tab_name": "MAIN"}})
	for qid in QuestManager.by_state("active"):
		var q := QuestManager.get_quest(qid)
		var dl := int(q.get("deadline_days", 0))
		if dl > 0:
			var left := dl - (BusinessManager.day - int(QuestManager.states[qid]["started_day"]))
			if left <= 1:
				add.call("quest:%s" % qid, IMPORTANT, "◆", "%s: %s (%s)" % [str(q.get("title", "")), QuestManager.progress_text(qid),
					"last day" if left <= 0 else "1 day left"], {"screen": &"dossier", "params": {"tab_name": "MAIN"}})
	var due := PeopleManager.due_people()
	if not due.is_empty():
		add.call("returning", INFO, "↺", "%d patient%s due back today" % [due.size(), "" if due.size() == 1 else "s"], {"screen": &"dossier", "params": {"tab_name": "PATIENTS"}})
	if not SupplierManager.deliveries.is_empty():
		add.call("delivery", INFO, "▣", "%d supplier deliver%s arriving tomorrow morning" % [SupplierManager.deliveries.size(),
			"y" if SupplierManager.deliveries.size() == 1 else "ies"], {"screen": &"business"})
	for a: Dictionary in TimeManager.upcoming():
		var mins := int(a["minute"]) - TimeManager.minute
		if mins >= 0 and mins <= 180 and str(a.get("label", "")) != "":
			add.call("agenda:%s" % a["id"], IMPORTANT if mins <= 60 else INFO, "◷", "%s at %s" % [str(a["label"]), TimeManager.clock_text(int(a["minute"]))], {"screen": &"clinic"})
			break
	for e: Dictionary in StaffManager.employees:
		if bool(e.get("raise_pending", false)):
			add.call("raise:%s" % e["id"], IMPORTANT, "☺", "%s wants a raise" % str(e["name"]), {"screen": &"staff"})
		elif float(e.get("stress", 0)) >= 75.0:
			add.call("stress:%s" % e["id"], IMPORTANT, "☺", "%s is badly stressed (%d)" % [str(e["name"]), roundi(float(e["stress"]))], {"screen": &"staff"})
	var cases := SecurityManager.open_cases().size()
	if cases > 0:
		add.call("security", IMPORTANT, "!", "%d open security case%s: something went missing" % [cases, "" if cases == 1 else "s"], {"screen": &"clinic"})
	if InventoryManager.supplies > 0 and InventoryManager.supplies < 2:
		add.call("supplies_low", IMPORTANT, "✚", "Supplies low (%d): restock in SUPPLY" % InventoryManager.supplies, {"screen": &"shop"})
	if FactionManager.heat >= 60.0 and FactionManager.heat < 85.0:
		add.call("heat_high", IMPORTANT, "!", "Authority heat %d and rising: careful with black-market work" % roundi(FactionManager.heat), {"term": "heat"})
	# --- Info ----------------------------------------------------------------------------
	if SkillManager.points > 0:
		add.call("skills", INFO, "+", "%d skill point%s to spend in SKILLS" % [SkillManager.points, "" if SkillManager.points == 1 else "s"], {"screen": &"skills"})
	for loc in LocationManager.known_locations():
		if WorldSimulationManager.has_flag(loc, &"lead") or WorldSimulationManager.has_flag(loc, &"event"):
			add.call("lead:%s" % loc, INFO, "◆", "Something is happening at %s" % LocationManager.location_name(loc), {"location": loc})
			break
	if not BusinessManager.doors_open:
		add.call("doors", INFO, "▮", "Doors closed: no walk-ins. Open them when you're ready", {"doors": "open"})
	if c == null and waiting == 0 and BusinessManager.is_day_full():
		add.call("day_done", INFO, "☾", "Day's work done: close for the night", {"screen": &"clinic"})
	elif c == null and waiting == 0 and out.is_empty():
		add.call("quiet", INFO, "·", "Quiet. Restock, check the journal, or go out into the city (%s)" % Controls.key_name("map"), {"screen": &"map"})
	# Most urgent first (stable within a level).
	var ranked: Array[Dictionary] = []
	for lv in [CRITICAL, IMPORTANT, INFO]:
		for it in out:
			if it["level"] == lv:
				ranked.append(it)
	return ranked.slice(0, n)


## The single most important line (the clinic's NEXT strip).
static func top() -> Dictionary:
	var all := items(1)
	return all[0] if not all.is_empty() else {}


static func color(level: StringName) -> Color:
	match level:
		CRITICAL:
			return Palette.DANGER
		IMPORTANT:
			return Palette.WARN
	return Palette.TEXT_DIM
