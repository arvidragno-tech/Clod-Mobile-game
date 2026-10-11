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
		"advice": "Money is short for tonight's bill. Take paying jobs, sell spare chrome or cut costs in BUSINESS.",
		"term": "credits", "link": {"screen": &"business"}})
	var rep := ReputationManager.reputation
	out.append({"key": "rep", "label": "REPUTATION", "state": str(rep), "level": GOOD if rep >= 10 else (WARN if rep >= 0 else BAD),
		"detail": "street reputation %d" % rep, "advice": "Your name is mud. Clean, careful work brings people back.",
		"term": "rep", "link": {"screen": &"dossier", "params": {"tab_name": "FACTIONS"}}})
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
	out.append({"key": "heat", "label": "AUTHORITY HEAT", "state": "High" if heat >= 60.0 else ("Watched" if heat >= 35.0 else "Low"),
		"level": BAD if heat >= 60.0 else (WARN if heat >= 35.0 else GOOD), "detail": "%d / 100 · %s" % [roundi(heat), SecurityManager.level_label()],
		"advice": "Authority attention is rising. Cut black-market work, do clean jobs, or improve SECURITY.",
		"term": "heat", "link": {"term": "heat"}})
	var bm := FactionManager.get_rep(&"black_market")
	out.append({"key": "black_market", "label": "BLACK MARKET", "state": FactionManager.get_standing(&"black_market").capitalize(),
		"level": GOOD if bm >= 10 else (WARN if bm >= -10 else BAD), "detail": "standing %+d" % bm,
		"advice": "The market doesn't trust you. Pay your debts and keep deals quiet.",
		"term": "black_market", "link": {"screen": &"dossier", "params": {"tab_name": "FACTIONS"}}})
	return out


## The single line that matters most: {text, level, link}.
static func most_important() -> Dictionary:
	var rs := rows()
	for lv in [BAD, WARN]:
		for r in rs:
			if r["level"] == lv:
				return {"text": str(r["advice"]) if lv == BAD else "%s: %s. %s" % [str(r["label"]).capitalize(), str(r["state"]).to_lower(), _warn_tip(str(r["key"]))],
					"level": lv, "link": r["link"]}
	return {"text": "Everything is stable. A good night to take risks or expand.", "level": GOOD, "link": {}}


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
