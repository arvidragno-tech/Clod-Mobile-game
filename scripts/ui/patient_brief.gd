class_name PatientBrief
extends RefCounted
## The patient summary's facts, in one place: who they are, what they want,
## how hard it is, your estimated odds, what's missing, and the money. It
## only reads the game's own rules, so it always agrees with the dossier,
## the operation plan and the results:
##  - money: JobEstimate.for_customer (payment, implant, supplies, margin);
##  - odds: Recommend.self_estimate (your record on the procedure, the
##    difficulty against your level, SurgeryManager's complication odds);
##  - readiness: GameManager.get_surgery_readiness via JobVerdict.checks.
## Every number that depends on the operation is labelled an estimate.

## Checks that stop an operation from starting (the rest are risks).
const BLOCKING := ["request", "tools", "supplies", "accepts"]

const DIFFICULTY_WORDS := ["", "EASY", "MODERATE", "HARD", "VERY HARD", "EXTREME"]

## What a missing requirement can be fixed with: key -> [button label, link].
const FIXES := {
	"tools": ["BUY TOOLS IN SUPPLY", {"screen": &"shop"}],
	"supplies": ["RESTOCK IN SUPPLY", {"screen": &"shop"}],
	"implant": ["SEE IMPLANTS IN SUPPLY", {"screen": &"shop"}],
}


static func difficulty_word(d: int) -> String:
	return DIFFICULTY_WORDS[clampi(d, 1, 5)]


## {name, alias, faction, occupation, emergency, request: {...}, operation: {...},
##  finance: {...}, missing: [...], recommendation: {text, level}, decline: {...}}
static func build(c: CustomerData) -> Dictionary:
	var out := {}
	if c == null:
		return out
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	out["name"] = c.display_name
	out["alias"] = c.alias
	out["faction"] = FactionManager.get_name_of(c.faction_id)
	out["occupation"] = c.occupation
	out["emergency"] = c.is_emergency
	out["statement"] = c.dialogue
	# --- Request ----------------------------------------------------------------
	var known: Array[String] = []
	for cid in c.revealed_conditions:
		known.append(String(cid).replace("_", " "))
	out["request"] = {
		"implant": item.display_name if item else "?",
		"tier": item.tier if item else 0,
		"category": String(item.category).to_upper() if item else "",
		"does": (item.benefits[0] if item and not item.benefits.is_empty() else ""),
		"procedure": surgery.display_name if surgery else "?",
		"known_conditions": known,
		"returning": c.visits > 0 or PeopleManager.has_person(c.id),
	}
	# --- Operation -------------------------------------------------------------
	var d := item.install_difficulty if item else 2
	var me := Recommend.self_estimate(c)
	var risks: Array[String] = []
	for t in Recommend.possible_complications(c, 2):
		risks.append(t)
	var r := GameManager.get_surgery_readiness()
	if str(r.get("implant_source", "")) == "salvaged":
		risks.append("no new implant available: salvaged parts (lower quality)")
	# Patient-level risk factors (conditions, neural load, stability...) are on
	# the intake form, from what the doctor can see (IntakeRecord.risks).
	var factors: Array[String] = [str(me["record"])]
	for f in me["factors"]:
		factors.append(str(f))
	if float(me["extra"]) > 0.0:
		factors.append("%d%% chance of an extra complication" % roundi(float(me["extra"]) * 100.0))
	out["operation"] = {
		"difficulty": d,
		"difficulty_word": difficulty_word(d),
		"minutes": TimeManager.procedure_minutes(d, c.is_emergency),
		"success": float(me["chance"]),
		"factors": factors,
		# Hidden conditions and how the operation itself goes are unknown.
		"uncertain": true,
		"risk_level": c.get_risk_level(),
		"risks": risks,
	}
	# --- Missing requirements (from the same checks as the dossier) -------------
	var missing: Array[Dictionary] = []
	for x in JobVerdict.checks(c):
		if x["level"] != &"bad" or not BLOCKING.has(str(x["key"])):
			continue
		var fix: Array = FIXES.get(str(x["key"]), [])
		missing.append({"key": str(x["key"]), "text": "%s: %s" % [str(x["label"]).capitalize(), str(x["value"])],
			"fix": str(fix[0]) if not fix.is_empty() else "", "link": fix[1] if not fix.is_empty() else {}})
	out["missing"] = missing
	# --- Money -----------------------------------------------------------------
	var est := JobEstimate.for_customer(c, r)
	out["finance"] = {
		"fee": int(est["fee"]),
		"pays_now": int(est["can_pay"]),
		"owed": int(est["owed"]),
		"implant_cost": int(est["implant_cost"]),
		"implant_source": str(est["implant_source"]),
		"supplies": int(est["supplies"]),
		"supplies_cost": int(est["supplies_cost"]),
		"direct_cost": int(est["implant_cost"]) + int(est["supplies_cost"]),
		"margin": int(est["net"]),
		"cash_today": int(est["cash_net"]),
	}
	out["recommendation"] = recommendation(c, out)
	out["decline"] = {"rep": GameConfig.DECLINE_REPUTATION_PENALTY, "faction": FactionManager.get_name_of(c.faction_id), "faction_delta": GameConfig.DECLINE_FACTION_PENALTY}
	return out


## One neutral line, grounded in the numbers above (the player decides).
static func recommendation(c: CustomerData, b: Dictionary) -> Dictionary:
	var fin: Dictionary = b["finance"]
	var op: Dictionary = b["operation"]
	var missing: Array = b["missing"]
	if c.is_emergency:
		return {"text": "Emergency: they won't wait. Decide fast; MORE DETAILS has the triage options.", "level": &"warn"}
	if not missing.is_empty():
		var first: Dictionary = missing[0]
		return {"text": "You can't start yet: %s." % str(first["text"]).to_lower(), "level": &"bad"}
	var chance := float(op["success"])
	var margin := int(fin["margin"])
	if chance < 0.55:
		return {"text": "High risk for you right now (≈%d%%). Consider a staff member, better tools, or declining." % roundi(chance * 100.0), "level": &"bad"}
	if margin < 0 and str(fin["implant_source"]) == "stock" and int(fin["cash_today"]) > 0:
		return {"text": "Uses an implant you already own: you take in ≈%s, a little less than the unit is worth." % EconomyManager.format_money(int(fin["cash_today"])), "level": &"good"}
	if margin < 0:
		return {"text": "Doable, but it costs you more than it pays (≈%s)." % EconomyManager.format_money(margin), "level": &"warn"}
	if str(fin["implant_source"]) == "buy":
		return {"text": "Profitable, but you'll have to buy the implant (%s, bought when you begin)." % EconomyManager.format_money(int(fin["implant_cost"])), "level": &"warn"}
	if int(fin["owed"]) > 0:
		return {"text": "A good fit, but they can only pay %s now; the rest comes in instalments." % EconomyManager.format_money(int(fin["pays_now"])), "level": &"warn"}
	if chance >= 0.8:
		return {"text": "A good match for your skills and equipment.", "level": &"good"}
	return {"text": "Workable. Scan carefully: the estimate assumes a correct diagnosis.", "level": &"good"}
