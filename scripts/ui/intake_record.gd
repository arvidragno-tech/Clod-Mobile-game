class_name IntakeRecord
extends RefCounted
## The PATIENT INTAKE FORM's contents: what the clinic knows about a patient,
## sorted by where it comes from, built only from existing patient data and
## the game's existing rules. Presentation only: nothing here rolls, reveals
## or changes anything.
##
## Where a line comes from (its status):
##   REPORTED   the patient says so (their statement, the history they give)
##   ON FILE    the clinic's records (installed chrome, past operations here,
##              debts, a documented chrome dependency)
##   CONFIRMED  found by an examination: conditions in revealed_conditions
##              (a scan, or an earlier visit), measured neural stability
##   SUSPECTED  the existing coarse risk rating (CustomerData.get_risk_level)
##              says something raises the risk without saying what
##   UNKNOWN    not known to the clinic yet: hidden conditions and the true
##              diagnosis stay unknown until the scan finds them
##
## The visibility boundary is the game's own: unrevealed hidden conditions
## are never named or counted, pre-generated scan findings aren't shown, and
## neural load is the doctor-visible figure (NeuralLoad.compute_visible).
##
## Emphasis reuses existing classifications only: the neural-load bands, the
## 1-3 risk rating, JobVerdict's good / warn / bad, and the emergency flag.
## Conditions have no severity in the data, so each is a CAUTION with its
## effect in words; nothing is scored.

const REPORTED := "REPORTED"
const ON_FILE := "ON FILE"
const CONFIRMED := "CONFIRMED"
const SUSPECTED := "SUSPECTED"
const UNKNOWN := "UNKNOWN"

## Emphasis (always shown with a word and a mark, never colour alone).
const NONE := &"none"
const CAUTION := &"caution"
const SIGNIFICANT := &"significant"
const CRITICAL := &"critical"

## What each condition modifier does in the operation (CustomerData.apply_condition
## and the systems that read those fields).
const MODIFIER_EFFECTS := {
	"bleed": ["bleeds faster during surgery", "bleeding"],
	"neural_sensitivity": ["the neural link destabilises faster", "neural sync"],
	"pain_tolerance": ["changes how much sedation they need", "sedation"],
	"complication_risk": ["raises the chance of complications", "complications"],
	"health_drain": ["health drops faster while they bleed", "health"],
	"start_neural": ["the neural link starts weaker", "neural sync"],
	"post_op": ["raises the chance of trouble after the operation", "post-op"],
	"neural_load": ["adds neural load", "neural load"],
}


## {doc_id, stamp, patient: [...], request: [...], history: [...], risks: [...]}
## Each entry: {label, value, status, level, why, affects, key}
static func build(c: CustomerData) -> Dictionary:
	if c == null:
		return {}
	return {
		"doc_id": "INT-%04d-%s" % [BusinessManager.day, String(c.id).md5_text().substr(0, 6).to_upper()],
		"stamp": TimeManager.stamp(),
		"patient": _patient(c),
		"request": _request(c),
		"history": _history(c),
		"risks": risks(c),
	}


static func _e(key: String, label: String, value: String, status: String, level: StringName = NONE, why: String = "", affects: String = "") -> Dictionary:
	return {"key": key, "label": label, "value": value, "status": status, "level": level, "why": why, "affects": affects}


# --- A. Patient information ---------------------------------------------------------

static func _patient(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# (Their name heads the summary; the form starts with what matters.)
	out.append(_e("occupation", "AGE · WORK", "%d · %s" % [c.age, c.occupation.capitalize()], REPORTED,
		CAUTION if c.age < 18 else NONE, "A minor: some of your staff refuse to operate on minors." if c.age < 18 else ""))
	out.append(_e("faction", "AFFILIATION", FactionManager.get_name_of(c.faction_id), REPORTED, NONE,
		"Standing with them moves with how this job goes.", "faction standing"))
	if c.backer != &"":
		out.append(_e("backer", "PAID FOR BY", FactionManager.get_name_of(c.backer), REPORTED, NONE, "", "payment"))
	if c.visits > 0 or PeopleManager.has_person(c.id):
		out.append(_e("visits", "VISITS", "returning patient (visit %d)" % (c.visits + 1), ON_FILE))
	var owed := PeopleManager.owed_by(c.id)
	if owed > 0:
		out.append(_e("owes", "OWES THE CLINIC", EconomyManager.format_money(owed), ON_FILE, CAUTION, "An open debt from an earlier visit.", "payment"))
	out.append(_e("patience", "PATIENCE", "%d / 100" % c.patience, CONFIRMED, NONE,
		"If the operation runs past its target time, impatient patients knock more off the fee; it also decides whether they come back after being deferred.", "pay if you run over, deferring"))
	return out


# --- B. Requested procedure -----------------------------------------------------------

static func _request(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var surgery := SurgeryManager.get_surgery(c.requested_surgery_id)
	if item == null or surgery == null:
		out.append(_e("request", "REQUEST", "can't be done here", ON_FILE, SIGNIFICANT))
		return out
	out.append(_e("implant", "IMPLANT", "%s · T%d %s" % [item.display_name, item.tier, String(item.category).to_upper()], REPORTED))
	out.append(_e("procedure", "PROCEDURE", "%s · %d steps · ≈ %s" % [surgery.display_name, surgery.stages.size(),
		TimeManager.duration_text(TimeManager.procedure_minutes(item.install_difficulty, c.is_emergency))], ON_FILE))
	out.append(_e("difficulty", "DIFFICULTY", "%s (%d / 5)" % [PatientBrief.difficulty_word(item.install_difficulty), item.install_difficulty], ON_FILE,
		NONE if item.install_difficulty <= 2 else CAUTION, "", "your odds"))
	# Tools: the same check the plan uses.
	var tools: Array[String] = []
	var missing := false
	for req in item.get_tool_requirements():
		var have := InventoryManager.has_tool_category(StringName(str(req["category"])), int(req["tier"]))
		missing = missing or not have
		tools.append("%s %s T%d" % ["[x]" if have else "[ ]", String(req["category"]).to_upper(), int(req["tier"])])
	out.append(_e("tools", "INSTRUMENTS", "  ".join(tools) if not tools.is_empty() else "[x] standard kit", ON_FILE,
		SIGNIFICANT if missing else NONE, "Missing instruments: the operation can't begin." if missing else ""))
	out.append(_e("load", "ADDS NEURAL LOAD", "+%d%%" % roundi(item.neural_load * maxf(0.2, ModifierManager.mult(&"neural.load"))), ON_FILE))
	for id in c.existing_cyberware:
		var e := CyberwareManager.get_cyberware(id)
		if e and e.category == item.category:
			out.append(_e("replaces", "IN THE SAME SLOT", "%s (installed)" % e.display_name, ON_FILE, CAUTION, "Old chrome sits where the new one goes."))
	return out


# --- C. History and disclosures --------------------------------------------------------

static func _history(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in c.medical_history:
		out.append(_e("history", "PATIENT HISTORY", h, REPORTED))
	if c.existing_cyberware.is_empty():
		out.append(_e("chrome", "INSTALLED CHROME", "none", ON_FILE))
	for id in c.existing_cyberware:
		var e := CyberwareManager.get_cyberware(id)
		if e:
			out.append(_e("chrome", "INSTALLED CHROME", "%s · load %d%%" % [e.display_name, roundi(e.neural_load)], ON_FILE))
	var ops := CustomerManager.get_previous_operations(c)
	if not ops.is_empty():
		var h: Dictionary = ops[0]
		out.append(_e("previous", "LAST JOB HERE", "%s · %s" % [str(h.get("surgery", "Operation")), "OK" if str(h.get("outcome", "")) == "success" else str(h.get("outcome", "")).replace("_", " ")],
			ON_FILE, NONE if str(h.get("outcome", "")) == "success" else CAUTION))
	if c.dependency > 0:
		out.append(_e("dependency", "CHROME DEPENDENCY", PeopleManager.DEPENDENCY_LABELS[clampi(c.dependency, 0, 4)], ON_FILE, CAUTION,
			"It has worn down their neural stability; their file has the care options.", "neural stability"))
	for cid in c.revealed_conditions:
		var cond := CustomerManager.get_condition(cid)
		out.append(_e("condition", "FINDING", str(cond.get("name", cid)), CONFIRMED, CAUTION))
	# What the clinic doesn't know yet (never how many, never which).
	var scanned := GameManager.chosen_diagnosis_id != &""
	out.append(_e("hidden", "HIDDEN CONDITIONS", "not screened yet: the body scan can find some" if not scanned else "only what the scan found is known", UNKNOWN, NONE,
		"Scanning the body before you cut can reveal conditions the patient doesn't mention."))
	out.append(_e("diagnosis", "DIAGNOSIS", "pending the scan" if not scanned else "chosen at the scan table", UNKNOWN if not scanned else ON_FILE))
	return out


# --- D. Complications and risk factors ---------------------------------------------------

## Only what can make this operation go worse, from what the clinic can see.
static func risks(c: CustomerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c == null:
		return out
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	if c.is_emergency:
		out.append(_e("emergency", "EMERGENCY", "bleeding at the door", CONFIRMED, CRITICAL,
			"They bleed faster and complications are likelier; the decision is on a clock.", "bleeding, complications, time"))
	# Confirmed conditions, with what they change (from the condition's own modifiers).
	for cid in c.revealed_conditions:
		var cond := CustomerManager.get_condition(cid)
		var effects: Array[String] = []
		var affects: Array[String] = []
		for k: String in (cond.get("modifiers", {}) as Dictionary):
			if MODIFIER_EFFECTS.has(k):
				var m: Array = MODIFIER_EFFECTS[k]
				if k == "pain_tolerance":
					effects.append("needs more sedation" if float(cond["modifiers"][k]) < 0.0 else "tolerates pain better")
				elif k == "neural_load":
					effects.append("adds %d%% neural load" % roundi(float(cond["modifiers"][k])))
				else:
					effects.append(str(m[0]))
				if not affects.has(str(m[1])):
					affects.append(str(m[1]))
		out.append(_e("cond_%s" % cid, str(cond.get("name", cid)).to_upper(), str(cond.get("description", "")), CONFIRMED, CAUTION,
			"; ".join(effects).capitalize() + "." if not effects.is_empty() else "", ", ".join(affects)))
	# Neural load after the implant (doctor-visible), by the existing bands.
	if item:
		var after := NeuralLoad.projected_visible(c, ImplantInstance.create(item.id))
		var band: Dictionary = NeuralLoad.band(after)
		var lvl := NONE
		match band["id"]:
			&"minor":
				lvl = CAUTION
			&"unstable":
				lvl = SIGNIFICANT
			&"severe", &"critical":
				lvl = CRITICAL
		if lvl != NONE:
			var why := "Above 50%% every point adds to the complication chance and drains the neural link faster."
			if band["id"] in [&"severe", &"critical"]:
				why += " At this level patients with little appetite for risk refuse the unit."
			out.append(_e("neural", "NEURAL LOAD AFTER", "≈ %d%% · %s" % [roundi(after), str(band["name"]).to_lower()], CONFIRMED, lvl, why, "complications, neural sync, consent"))
	# Neural stability measured at intake (the dossier's own threshold).
	if c.neural_stability < 70.0:
		out.append(_e("stability", "NEURAL STABILITY", "%d%%" % roundi(c.neural_stability), CONFIRMED, CAUTION,
			"The neural link starts lower, so it has less room before it fails.", "neural sync"))
	# The existing coarse rating: something raises the risk, cause not identified.
	var risk := c.get_risk_level()
	if risk >= 2:
		out.append(_e("overall", "OVERALL RISK", ["", "low", "medium", "high"][risk], SUSPECTED, CAUTION if risk == 2 else SIGNIFICANT,
			"The intake exam rates this patient's physiology as %s risk; the cause isn't identified. A scan can reveal conditions." % ["", "low", "medium", "high"][risk],
			"bleeding, sedation, complications"))
	# The implant's own failure risk (data), which feeds the complication chance.
	if item and item.failure_risk > 0.0:
		out.append(_e("failure", "IMPLANT FAILURE RISK", "%d%%" % roundi(item.failure_risk * 100.0), CONFIRMED, CAUTION,
			"This model's own failure rate adds to the complication chance.", "complications"))
	# Will they accept the unit you'd use (GameManager's existing consent rule)?
	if c == GameManager.get_current_customer() and not bool(GameManager.get_surgery_readiness().get("accepts", true)):
		out.append(_e("consent", "CONSENT", "won't accept the unit you'd use", CONFIRMED, SIGNIFICANT,
			"Pick another unit in the operation plan, or buy the right one.", "whether you can begin"))
	return out


## THE one risk sentence for the patient's default view: the most serious
## risk factor the clinic can see (same data, same order of severity), or {}.
static func key_risk(c: CustomerData) -> Dictionary:
	var best := {}
	var rank := {CAUTION: 1, SIGNIFICANT: 2, CRITICAL: 3}
	for e: Dictionary in risks(c):
		if best.is_empty() or int(rank.get(e["level"], 0)) > int(rank.get(best["level"], 0)):
			best = e
	if best.is_empty():
		return {}
	var why := str(best["why"])
	var first := why.get_slice(". ", 0).trim_suffix(".")
	return {"text": "%s: %s%s" % [str(best["label"]).capitalize(), str(best["value"]), (". " + first + ".") if first != "" else "."],
		"level": best["level"], "key": best["key"]}


static func color(level: StringName) -> Color:
	match level:
		CAUTION:
			return Palette.WARN
		SIGNIFICANT, CRITICAL:
			return Palette.DANGER
	return Palette.TEXT


static func mark(level: StringName) -> String:
	match level:
		CAUTION:
			return "!"
		SIGNIFICANT:
			return "✕"
		CRITICAL:
			return "✕✕"
	return "·"


static func level_word(level: StringName) -> String:
	match level:
		CAUTION:
			return "CAUTION"
		SIGNIFICANT:
			return "SIGNIFICANT"
		CRITICAL:
			return "CRITICAL"
	return ""
