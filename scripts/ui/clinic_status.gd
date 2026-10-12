class_name ClinicStatus
extends RefCounted
## CLINIC STATUS: six systems summarised in one word each (money, standing,
## staff, supplies, authority heat, the black market), each marked ✓ / ! / ✕
## (never colour alone), plus the one thing that matters most right now and
## what to do about it. Reads live state; stores nothing.

const GOOD := &"good"
const WARN := &"warn"
const BAD := &"bad"


## [{key, label, state, level, detail, advice, term, link}]
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var money := EconomyManager.money
	var bill := BusinessManager.projected_total()
	var fin_lv := GOOD
	var fin := "Stable"
	if BusinessManager.debt > 0 or money < bill:
		fin_lv = BAD
		fin = "Short"
	elif money < bill * 2:
		fin_lv = WARN
		fin = "Tight"
	out.append({"key": "money", "label": "FINANCIAL", "state": fin, "level": fin_lv,
		"detail": "%s on hand · tonight's bill %s%s" % [EconomyManager.format_money(money), EconomyManager.format_money(bill),
			(" · debt %s" % EconomyManager.format_money(BusinessManager.debt)) if BusinessManager.debt > 0 else ""],
		"advice": _money_advice(),
		"term": "credits", "link": {"screen": &"business"}})
	var rep := ReputationManager.reputation
	var rt := ChangeLog.standing_trend("rep", 3)
	out.append({"key": "rep", "label": "REPUTATION", "state": "%s %d%s" % [ReputationManager.get_tier_name(), rep, (" ▲" if rt > 0.5 else (" ▼" if rt < -0.5 else ""))],
		"level": GOOD if rep >= 10 else (WARN if rep >= 0 else BAD),
		"detail": "street reputation %d · %s" % [rep, Standing.next_rep_threshold()], "advice": "Your name is mud. Clean, careful work brings people back.",
		"term": "rep", "link": {"screen": &"dossier", "params": {"tab_name": "STANDING"}}})
	var staff: Array = StaffManager.employees
	var st_lv := GOOD
	var st := "None hired" if staff.is_empty() else "Steady"
	var worst := 0.0
	var raise := false
	for e: Dictionary in staff:
		worst = maxf(worst, float(e.get("stress", 0)))
		raise = raise or bool(e.get("raise_pending", false))
	if worst >= 75.0:
		st_lv = BAD
		st = "Burning out"
	elif worst >= 50.0 or raise:
		st_lv = WARN
		st = "Stressed" if worst >= 50.0 else "Wants a raise"
	out.append({"key": "staff", "label": "STAFF", "state": st, "level": st_lv,
		"detail": "%d on the team · worst stress %d" % [staff.size(), roundi(worst)],
		"advice": "Someone on your team is close to breaking. Give them lighter work or a day off in STAFF.",
		"term": "stress", "link": {"screen": &"staff"}})
	var sup := InventoryManager.supplies
	var scap := maxi(1, ClinicManager.get_supplies_capacity())
	out.append({"key": "supplies", "label": "SUPPLIES", "state": "Out" if sup <= 0 else ("Low" if sup < 2 else "Good"),
		"level": BAD if sup <= 0 else (WARN if sup < 2 else GOOD), "detail": "%d / %d · %d implants in stock" % [sup, scap, InventoryManager.get_instances().size()],
		"advice": "You're out of medical supplies: no operation can start. Restock in SUPPLY.",
		"term": "supplies", "link": {"screen": &"shop"}})
	var heat := FactionManager.heat
	# The real heat levels (data/security.json): MEDIUM 25, HIGH 50, CRITICAL 75.
	out.append({"key": "heat", "label": "AUTHORITY HEAT", "state": SecurityManager.level_label().capitalize(),
		"level": BAD if heat >= 50.0 else (WARN if heat >= 25.0 else GOOD), "detail": "%d / 100 · %s" % [roundi(heat), SecurityManager.level_label()],
		"advice": "Authority attention is rising. Cut black-market work, do clean jobs, or improve SECURITY.",
		"term": "heat", "link": {"term": "heat"}})
	var bm := FactionManager.get_rep(&"black_market")
	out.append({"key": "black_market", "label": "BLACK MARKET", "state": FactionManager.get_standing(&"black_market").capitalize(),
		"level": GOOD if bm >= 10 else (WARN if bm >= -10 else BAD), "detail": "standing %+d" % bm,
		"advice": "The market doesn't trust you. Pay your debts and keep deals quiet.",
		"term": "black_market", "link": {"screen": &"dossier", "params": {"tab_name": "STANDING"}}})
	return out


## The rows the clinic card shows at the player's GUIDANCE setting:
## MINIMAL hides the ones that are fine.
static func visible_rows() -> Array[Dictionary]:
	var all := rows()
	if Settings.is_minimal():
		return all.filter(func(r: Dictionary) -> bool: return r["level"] != GOOD)
	return all


## THE DASHBOARD (3.7): one headline state and only the issues that need
## you, most urgent first, each with why it matters and where to fix it.
## Everything is derived from the rows above, the patient at the door
## (GameManager.get_surgery_readiness via PatientBrief's blocking checks)
## and the business: nothing is tracked twice.
##   {headline: {key, text, why, level, link}, issues: [{key, text, why, level, link}]}
## Rows for sections the player hasn't been introduced to (staff, the
## black market) never show; during the first patient only the headline.
static func dashboard(max_issues: int = 3) -> Dictionary:
	var rs := rows()
	var by := {}
	for r in rs:
		by[str(r["key"])] = r
	var c: CustomerData = CustomerManager.current_customer
	var blocking: Array = []
	if c and not c.is_emergency:
		for x in JobVerdict.checks(c):
			if x["level"] == BAD and PatientBrief.BLOCKING.has(str(x["key"])):
				blocking.append(x)
	var waiting := ClinicLifeManager.waiting_customers().size()
	var head := {}
	if SurgeryManager.is_active:
		head = {"key": "operating", "text": "OPERATION IN PROGRESS", "why": "Finish it before anything else.", "level": WARN, "link": {}}
	elif EventManager.has_pending() or StoryManager.has_talk():
		head = {"key": "action", "text": "ACTION REQUIRED", "why": "Someone is waiting for your answer.", "level": WARN, "link": {"screen": &"clinic"}}
	elif InventoryManager.supplies <= 0:
		head = {"key": "supplies", "text": "CAN'T OPERATE: NO SUPPLIES", "why": "Every operation uses medical supplies. Restock in SUPPLY.", "level": BAD, "link": {"screen": &"shop"}}
	elif not blocking.is_empty():
		var x: Dictionary = blocking[0]
		head = {"key": "missing", "text": "PATIENT WAITING: MISSING %s" % str(x["label"]).to_upper(), "why": "%s. %s" % [str(x["value"]).capitalize(), "Buy it in SUPPLY, or hand the job to staff." if Features.is_on(&"staff") else "Buy it in SUPPLY or turn the job down."],
			"level": BAD, "link": {"screen": &"shop"} if str(x["key"]) in ["tools", "supplies"] else {"customer": true}}
	elif by["money"]["level"] == BAD and Features.is_on(&"business"):
		head = {"key": "money", "text": "FINANCIAL CONCERN", "why": str(by["money"]["advice"]), "level": BAD, "link": {"screen": &"business"}}
	elif not BusinessManager.doors_open:
		head = {"key": "doors", "text": "DOORS CLOSED", "why": "No walk-ins until you open them. Take your time.", "level": WARN, "link": {"doors": "open"}}
	elif BusinessManager.is_day_full() and c == null:
		head = {"key": "day_done", "text": "DAY'S WORK DONE", "why": "Close for the night: rent and wages are paid, the books are shown.", "level": GOOD, "link": {}}
	else:
		var who := "A patient is at the door." if c else ("%d waiting in the waiting room." % waiting if waiting > 0 else "Nobody at the door yet.")
		head = {"key": "ready", "text": "READY FOR PATIENTS", "why": who, "level": GOOD, "link": {"customer": true} if c else {}}
	var issues: Array[Dictionary] = []
	var learning := TutorialManager.is_active() or Difficulty.ops() == 0
	if not learning:
		var gated := {"staff": &"staff", "black_market": &"blackmarket", "money": &"business"}
		for lv in [BAD, WARN]:
			for r in rs:
				var key := str(r["key"])
				if r["level"] != lv or key == str(head["key"]) or (key == "supplies" and str(head["key"]) == "supplies"):
					continue
				if gated.has(key) and not Features.is_on(gated[key]):
					continue
				# A new name isn't a problem: only a bad reputation is.
				if key == "rep" and lv != BAD:
					continue
				if key == "money" and str(head["key"]) == "money":
					continue
				var why := str(r["advice"]) if lv == BAD else _warn_tip(key)
				issues.append({"key": key, "text": "%s: %s" % [str(r["label"]).capitalize(), str(r["state"]).to_lower()], "why": why,
					"detail": str(r["detail"]), "level": lv, "link": r["link"]})
		if Settings.is_minimal():
			issues = issues.filter(func(i: Dictionary) -> bool: return i["level"] == BAD)
	return {"headline": head, "issues": issues.slice(0, max_issues)}


## Guidance ids the dashboard already shows (WHAT MATTERS doesn't repeat them).
const DASHBOARD_IDS := ["supplies_out", "supplies_low", "debt", "heat", "heat_high", "doors", "day_done"]


## The single line that matters most: {text, level, link}.
static func most_important() -> Dictionary:
	var rs := rows()
	for lv in [BAD, WARN]:
		for r in rs:
			if r["level"] == lv:
				return {"text": str(r["advice"]) if lv == BAD else "%s: %s. %s" % [str(r["label"]).capitalize(), str(r["state"]).to_lower(), _warn_tip(str(r["key"]))],
					"level": lv, "link": r["link"]}
	return {"text": "Everything is stable. A good night to take risks or expand.", "level": GOOD, "link": {}}


## The business outlook's main cause when there is one, else the usual tip.
static func _money_advice() -> String:
	var o := BusinessManager.outlook(3)
	if str(o["cause"]) != "":
		return "%s: %s. %s" % [o["verdict"], o["cause"], o["advice"]]
	return "Money is short for tonight's bill. Take paying jobs, sell spare chrome or cut costs in BUSINESS."


static func _warn_tip(key: String) -> String:
	match key:
		"money":
			return "Keep a night's bill in hand."
		"rep":
			return "Good work raises it."
		"staff":
			return "Watch their stress in STAFF."
		"supplies":
			return "Restock soon."
		"heat":
			return "Consider fewer illegal jobs."
		"black_market":
			return "Settle what you owe."
	return ""


static func mark(level: StringName) -> String:
	return "✓" if level == GOOD else ("!" if level == WARN else "✕")


static func color(level: StringName) -> Color:
	return Palette.OK if level == GOOD else (Palette.WARN if level == WARN else Palette.DANGER)
