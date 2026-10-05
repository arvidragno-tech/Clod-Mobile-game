extends Node
## The clinic as a business. Work happens in days: each day the active
## clinic can take `surgery_capacity` jobs (your own surgeries plus jobs
## assigned to staff). Closing for the night settles the books: rent and
## running costs for every owned clinic, upgrade upkeep, salaries, income
## from staff-run clinics, debt interest. Every categorised money movement
## (EventBus.transaction) lands in today's ledger so the business screen can
## show revenue, costs and profit per category and per day.
##
## Unpaid bills become debt (8% a day). The Landlord notices.

const HISTORY_DAYS := 30
const DEBT_INTEREST := 0.08
const DEBT_WARNING := 500

const INCOME := [&"revenue", &"staff_revenue", &"black_market", &"events", &"other"]
const LABELS := {
	&"revenue": "Surgery revenue", &"staff_revenue": "Staff-run clinics", &"black_market": "Black market",
	&"events": "Deals and incidents", &"clinics": "Clinic purchases", &"upgrades": "Upgrades",
	&"supplies": "Medical supplies", &"cyberware": "Cyberware stock", &"tools": "Tools and service",
	&"rent": "Rent", &"operating": "Running costs", &"upkeep": "Upgrade upkeep", &"salaries": "Salaries",
	&"security": "Security", &"bribes": "Bribes", &"debt": "Debt repayment", &"interest": "Debt interest",
	&"other": "Other",
}

var day: int = 1
var jobs_today: int = 0
var today: Dictionary = {}  # category -> delta
var history: Array[Dictionary] = []  # newest last: {day, ledger, profit, debt, notes}
var totals: Dictionary = {}  # category -> delta (lifetime)
var debt: int = 0
var days_in_debt: int = 0


func _ready() -> void:
	EventBus.transaction.connect(_on_transaction)
	reset_state()


func reset_state() -> void:
	day = 1
	jobs_today = 0
	today.clear()
	history.clear()
	totals.clear()
	debt = 0
	days_in_debt = 0


func _on_transaction(category: StringName, delta: int) -> void:
	today[category] = int(today.get(category, 0)) + delta
	totals[category] = int(totals.get(category, 0)) + delta


static func label(category: StringName) -> String:
	return str(LABELS.get(category, String(category).capitalize()))


# --- Day flow --------------------------------------------------------------------

func capacity() -> int:
	return ClinicManager.surgery_capacity()


func jobs_left() -> int:
	return maxi(0, capacity() - jobs_today)


func is_day_full() -> bool:
	return jobs_today >= capacity()


func record_job() -> void:
	jobs_today += 1


## Tonight's bills before paying them: [{category, amount, note}].
func projected_costs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ClinicManager.owned:
		var c := ClinicManager.daily_costs(i)
		var nm := str(ClinicManager.get_tier_data(i).get("name", ""))
		out.append({"category": &"rent", "amount": _scaled(int(c["rent"])), "note": nm})
		out.append({"category": &"operating", "amount": _scaled(int(c["operating"])), "note": nm})
		var sec := 0
		for lv in range(1, ClinicManager.upgrade_level(&"security", i) + 1):
			sec += int(ClinicManager.upgrade_def(&"security", lv).get("upkeep", 0))
		if sec > 0:
			out.append({"category": &"security", "amount": sec, "note": nm})
		if int(c["upkeep"]) - sec > 0:
			out.append({"category": &"upkeep", "amount": int(c["upkeep"]) - sec, "note": nm})
	var staff := _staff()
	if staff:
		var sal := int(staff.call("daily_salaries"))
		if sal > 0:
			out.append({"category": &"salaries", "amount": sal, "note": "%d staff" % int(staff.call("count"))})
	if debt > 0:
		out.append({"category": &"interest", "amount": int(ceil(debt * DEBT_INTEREST)), "note": "on %d" % debt})
	return out


func projected_total() -> int:
	var n := 0
	for c in projected_costs():
		n += int(c["amount"])
	return n


static func _scaled(v: int) -> int:
	return int(round(v * Difficulty.cost_mult()))


## Closes the clinic for the night and settles the books. Returns the report.
func end_day() -> Dictionary:
	var notes: Array[String] = []
	var staff := _staff()
	if staff:
		for n: Variant in staff.call("end_of_day"):
			notes.append(str(n))
	for c in projected_costs():
		var amt := int(c["amount"])
		if c["category"] == &"interest":
			debt += amt
			today[&"interest"] = int(today.get(&"interest", 0)) - amt
			notes.append("Debt interest: +%d owed" % amt)
			continue
		_charge(StringName(c["category"]), amt)
	var rep := int(ModifierManager.value(&"reputation.daily")) + int(ClinicManager.get_tier_data().get("reputation", 0)) / 5
	if rep != 0:
		ReputationManager.change(rep)
		notes.append("The address earns you %+d reputation" % rep)
	if debt > 0:
		days_in_debt += 1
		if debt >= DEBT_WARNING:
			StoryManager.set_flag(&"in_debt")
	else:
		days_in_debt = 0
		StoryManager.set_flag(&"in_debt", false)
	var ledger := today.duplicate()
	var report := {"day": day, "ledger": ledger, "profit": _sum(ledger), "debt": debt, "money": EconomyManager.money,
		"jobs": jobs_today, "notes": notes, "clinic": ClinicManager.get_tier_name()}
	history.append(report)
	while history.size() > HISTORY_DAYS:
		history.pop_front()
	EventBus.day_ended.emit(day, report)
	day += 1
	jobs_today = 0
	today.clear()
	EventBus.day_started.emit(day)
	return report


## Pays a bill; whatever can't be paid becomes debt.
func _charge(category: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var paid := mini(amount, maxi(EconomyManager.money, 0))
	if paid > 0:
		EconomyManager.spend(paid, category)
	if amount > paid:
		debt += amount - paid
		today[category] = int(today.get(category, 0)) - (amount - paid)


func pay_debt(amount: int = -1) -> int:
	var n := debt if amount < 0 else mini(amount, debt)
	n = mini(n, EconomyManager.money)
	if n <= 0 or not EconomyManager.spend(n, &"debt"):
		return 0
	debt -= n
	if debt == 0:
		days_in_debt = 0
		StoryManager.set_flag(&"in_debt", false)
	return n


## Borrow from the Landlord (adds debt, gives cash now).
func borrow(amount: int) -> void:
	debt += int(amount * 1.15)
	EconomyManager.add_money(amount, &"other")


# --- Reporting -------------------------------------------------------------------

func _sum(ledger: Dictionary) -> int:
	var n := 0
	for k: Variant in ledger:
		n += int(ledger[k])
	return n


func profit_today() -> int:
	return _sum(today)


## Sum of a ledger category over the last n closed days (+ today).
func category_over(category: StringName, n: int = 7) -> int:
	var total := int(today.get(category, 0))
	for i in range(maxi(0, history.size() - n), history.size()):
		total += int(history[i]["ledger"].get(category, 0))
	return total


func income_and_costs(ledger: Dictionary) -> Dictionary:
	var inc := 0
	var cost := 0
	for k: Variant in ledger:
		var v := int(ledger[k])
		if v >= 0:
			inc += v
		else:
			cost -= v
	return {"income": inc, "costs": cost}


func last_report() -> Dictionary:
	return history[history.size() - 1] if not history.is_empty() else {}


func _staff() -> Node:
	return get_node_or_null("/root/StaffManager")


func get_save_data() -> Dictionary:
	var td := {}
	for k: Variant in today:
		td[String(k)] = today[k]
	var tt := {}
	for k: Variant in totals:
		tt[String(k)] = totals[k]
	var hist: Array = []
	for h in history:
		var l := {}
		for k: Variant in h["ledger"]:
			l[String(k)] = h["ledger"][k]
		var hh := h.duplicate()
		hh["ledger"] = l
		hist.append(hh)
	return {"day": day, "jobs_today": jobs_today, "today": td, "totals": tt, "history": hist, "debt": debt, "days_in_debt": days_in_debt}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	day = maxi(1, int(data.get("day", 1)))
	jobs_today = int(data.get("jobs_today", 0))
	debt = maxi(0, int(data.get("debt", 0)))
	days_in_debt = int(data.get("days_in_debt", 0))
	var td: Dictionary = data.get("today", {})
	for k: Variant in td:
		today[StringName(str(k))] = int(td[k])
	var tt: Dictionary = data.get("totals", {})
	for k: Variant in tt:
		totals[StringName(str(k))] = int(tt[k])
	for h: Variant in data.get("history", []):
		if h is Dictionary:
			var l := {}
			for k: Variant in h.get("ledger", {}):
				l[StringName(str(k))] = int(h["ledger"][k])
			var hh: Dictionary = (h as Dictionary).duplicate()
			hh["ledger"] = l
			history.append(hh)
