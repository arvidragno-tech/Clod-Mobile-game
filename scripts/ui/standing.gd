class_name Standing
extends RefCounted
## YOUR STANDING (3.6): every standing value explained from the real game
## state and the real thresholds in the data and the code. Nothing here is
## stored; history comes from ChangeLog.standing (recorded when it happened).
##
## Four different things, never merged into one score:
##   REPUTATION  how a group sees you (street reputation, factions)
##   RELATIONSHIP how one person feels about you (the cast, patients, staff)
##   TRUST       how reliable a supplier thinks you are
##   ATTENTION   how much the authorities are watching (heat)
##
## A row: {group, kind, name, value, scale, category, level, trend, trend_text,
##         affects: Array[String], next: String, term, link}

const GOOD := &"good"
const WARN := &"warn"
const BAD := &"bad"


# --- Rows ---------------------------------------------------------------------------------

## The rows shown by default: street reputation, heat, the black market and
## the factions that matter most right now (strongest feelings or recent
## changes). `all` adds every faction.
static func overview(all: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = [rep_row(), heat_row(), faction_row(&"black_market")]
	var ids: Array = FactionManager.order.filter(func(id: StringName) -> bool: return id != &"black_market")
	if not all:
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _relevance(a) > _relevance(b))
		ids = ids.slice(0, 2)
	for id: StringName in ids:
		out.append(faction_row(id))
	return out


static func _relevance(id: StringName) -> float:
	return absf(FactionManager.get_rep(id)) + 4.0 * absf(ChangeLog.standing_trend("faction:%s" % id, 3))


static func rep_row() -> Dictionary:
	var r := ReputationManager.reputation
	var affects: Array[String] = []
	if ReputationManager.is_black_market_unlocked() or StoryManager.has_flag(&"bm_access"):
		affects.append("The Undermarket deals with you")
	var types: Array[String] = []
	for a: Dictionary in CustomerManager.archetypes:
		var need := int(a.get("min_rep", -100))
		if need > 0 and r >= need:
			types.append(str(a.get("name", a.get("id", ""))))
	if not types.is_empty():
		affects.append("Brings in: " + ", ".join(types))
	affects.append("Better addresses and districts open up as it rises")
	if r < 0:
		affects.append("Below zero, fewer people trust you with their bodies")
	var trend := ChangeLog.standing_trend("rep", 3)
	return {"group": "rep", "kind": "reputation", "name": "Street reputation", "value": r, "scale": "-100..100",
		"category": ReputationManager.get_tier_name(), "level": GOOD if r >= 10 else (WARN if r >= 0 else BAD),
		"trend": trend, "trend_text": trend_text(trend, true), "affects": affects, "next": next_rep_threshold(),
		"term": "rep", "link": {"screen": &"dossier", "params": {"tab_name": "STANDING"}}}


## The next thing street reputation unlocks, from the data.
static func next_rep_threshold() -> String:
	var r := ReputationManager.reputation
	# (Lambdas capture locals by value: keep the running best in a dictionary.)
	var acc := {"best": 1000, "what": [] as Array[String]}
	var consider := func(need: int, text: String) -> void:
		if need <= r:
			return
		if need < int(acc["best"]):
			acc["best"] = need
			acc["what"] = [text] as Array[String]
		elif need == int(acc["best"]):
			(acc["what"] as Array[String]).append(text)
	if not ReputationManager.is_black_market_unlocked():
		consider.call(GameConfig.BLACK_MARKET_REPUTATION, "black-market contacts")
	for i in ClinicManager.tiers.size():
		var t: Dictionary = ClinicManager.tiers[i]
		if not ClinicManager.owns(i):
			consider.call(int(t.get("min_reputation", -100)), "lease the %s" % str(t.get("name", "")))
	for id: StringName in WorldManager.order:
		var u: Dictionary = WorldManager.get_district(id).get("unlock", {})
		if not u.is_empty():
			consider.call(int(u.get("reputation", -100)), "%s district" % WorldManager.district_name(id))
	for a: Dictionary in CustomerManager.archetypes:
		consider.call(int(a.get("min_rep", -100)), "%s customers" % str(a.get("name", a.get("id", ""))).to_lower())
	for tier: Array in ReputationManager.TIERS:
		consider.call(int(tier[0]), "\"%s\"" % tier[1])
	var what: Array[String] = acc["what"]
	if what.is_empty():
		return "Nothing left to unlock: keep it up."
	return "At %d: %s (%+d to go)" % [int(acc["best"]), ", ".join(what), int(acc["best"]) - r]


static func heat_row() -> Dictionary:
	var h := FactionManager.heat
	var lv := SecurityManager.level()
	var affects: Array[String] = []
	affects.append(str(lv.get("text", "")))
	if h >= 20.0:
		affects.append("Inspections, patrols and stings can happen")
	if h >= 40.0:
		affects.append("More police on the streets")
	if h >= 60.0:
		affects.append("Contracts dry up and suppliers hold back stock")
	affects.append("Higher heat raises the chance of a break-in")
	var next := ""
	for l: Dictionary in SecurityManager.data.get("levels", []):
		if float(l["min"]) > h:
			next = "At %d it becomes %s (%+d)" % [int(l["min"]), str(l["label"]), int(ceil(float(l["min"]) - h))]
			break
	if next == "":
		next = "At the top: cool it down with clean work and fewer black-market jobs."
	if h >= 25.0:
		next += " · Below %d it calms down." % int(SecurityManager.level().get("min", 0))
	var trend := ChangeLog.standing_trend("heat", 3)
	return {"group": "heat", "kind": "attention", "name": "Authority attention (heat)", "value": roundi(h), "scale": "0..100",
		"category": str(lv.get("label", "LOW")), "level": BAD if h >= 50.0 else (WARN if h >= 25.0 else GOOD),
		"trend": trend, "trend_text": trend_text(trend, false), "affects": affects, "next": next, "term": "heat", "link": {"term": "heat"}}


static func faction_row(id: StringName) -> Dictionary:
	var r := FactionManager.get_rep(id)
	var name := FactionManager.get_name_of(id)
	var affects: Array[String] = []
	var pm := FactionManager.price_multiplier(id)
	if absf(pm - 1.0) >= 0.02:
		affects.append("Their goods cost %+d%%" % roundi((pm - 1.0) * 100.0))
	var cw := FactionManager.customer_weight(id)
	if absf(cw - 1.0) >= 0.1:
		affects.append("Their people come to you %s" % ("more often (x%.1f)" % cw if cw > 1.0 else "less often (x%.1f)" % cw))
	if r >= 40:
		affects.append("Their places charge you 15% less")
	elif r >= 15:
		affects.append("Their places charge you 7% less")
	elif r <= -40:
		affects.append("Their places charge you 30% more")
	elif r <= -15:
		affects.append("Their places charge you 12% more")
	if r >= 20:
		affects.append("Their suppliers will deal with you")
	if r <= -20:
		affects.append("They may send thieves to your clinic")
	if r <= -50:
		affects.append("You're not welcome where they run things")
	if affects.is_empty():
		affects.append("No effect yet: they don't know you well enough")
	var trend := ChangeLog.standing_trend("faction:%s" % id, 3)
	return {"group": "faction:%s" % id, "kind": "reputation", "name": name, "value": r, "scale": "-100..100",
		"category": FactionManager.get_standing(id), "level": GOOD if r >= 15 else (WARN if r > -15 else BAD),
		"trend": trend, "trend_text": trend_text(trend, true), "affects": affects, "next": next_faction_threshold(r),
		"term": "factions", "link": {"screen": &"dossier", "params": {"tab_name": "STANDING"}}}


## The next standing / effect boundary above (and the one that would be lost below).
static func next_faction_threshold(r: int) -> String:
	var marks := [[-50, "no longer unwelcome"], [-40, "prices only +12%"], [-20, "no more thieves"], [-15, "NEUTRAL"],
		[15, "FRIENDLY: prices -7%"], [20, "their suppliers deal with you"], [40, "ALLIED: prices -15%"]]
	for m: Array in marks:
		if int(m[0]) > r:
			return "At %+d: %s (%+d to go)" % [int(m[0]), str(m[1]), int(m[0]) - r]
	return "As good as it gets."


## The five reputation dimensions: who the street thinks you are.
static func identity_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: StringName in ReputationManager.DIMENSIONS:
		var v := ReputationManager.dim(d)
		var t := ChangeLog.standing_trend("dim:%s" % d, 3)
		out.append({"group": "dim:%s" % d, "name": "%s reputation" % ReputationManager.DIMENSION_LABELS.get(d, d), "value": v,
			"trend": t, "trend_text": trend_text(t, true), "level": GOOD if v >= 10 else (WARN if v >= -10 else BAD)})
	return out


## The people you deal with: their own feelings next to their group's view.
static func people() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in CharacterManager.met_characters():
		var c := CharacterManager.get_character(id)
		if c == null:
			continue
		var fid := c.faction_id
		out.append({"id": id, "name": c.display_name, "role": c.occupation, "personal": CharacterManager.relationship_state(id),
			"rel": CharacterManager.relationship(id), "trend": ChangeLog.standing_trend("person:%s" % id, 3),
			"faction": FactionManager.get_name_of(fid) if FactionManager.factions.has(fid) else "",
			"faction_standing": FactionManager.get_standing(fid) if FactionManager.factions.has(fid) else ""})
	return out


## Suppliers you know: TRUST, not reputation.
static func suppliers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in SupplierManager.discovered():
		var s := SupplierManager.st(id)
		var nxt := SupplierManager.next_unlock(id)
		out.append({"id": id, "name": str(SupplierManager.supplier(id).get("name", id)), "standing": SupplierManager.standing(id),
			"trust": int(s.get("trust", 0)), "debt": int(s.get("debt", 0)), "next": str(nxt.get("text", nxt.get("label", ""))) if not nxt.is_empty() else ""})
	return out


## What a choice will do to your standing, before you pick it (event
## outcomes). Exact numbers when they're fixed; a risky choice says so
## instead of promising a result. "" when it doesn't touch standing.
static func preview(o: Dictionary) -> String:
	if o.is_empty():
		return ""
	if o.has("risk"):
		var r: Dictionary = o["risk"]
		var a := preview(r.get("success", {}))
		var b := preview(r.get("fail", {}))
		if a == "" and b == "":
			return ""
		return "Risky (%d%%): %s / if it goes wrong: %s" % [roundi(float(r.get("chance", 0.5)) * 100.0), a if a != "" else "no standing change", b if b != "" else "no standing change"]
	var parts: Array[String] = []
	# Faction and heat changes as the managers will apply them, in the order
	# they're applied (the choice's own, then its story effects): gains
	# scaled by Faction Relations and heat modifiers, capped, with what the
	# rivals of a faction you side with lose folded in.
	var fx: Dictionary = o.get("effects", {}) if o.get("effects", {}) is Dictionary else {}
	var sides := {}
	var total := {}
	var reps := {}
	var heat := 0.0
	var rep := 0
	var steps: Array[Dictionary] = [o, fx]
	for i in steps.size():
		var step := steps[i]
		# Street reputation first, as apply_outcomes / apply_effects do, with
		# its diminishing returns and cap.
		var dr := int(step.get("reputation" if i == 0 else "rep", 0))
		if dr != 0:
			rep += ReputationManager.applied_change(dr, ReputationManager.reputation + rep)
		var fac: Dictionary = step.get("faction", {})
		for f: Variant in fac:
			var id := StringName(str(f))
			sides[id] = true
			var ch := FactionManager.preview_by_choice(id, int(fac[f]), reps)
			for r: StringName in ch:
				total[r] = int(total.get(r, 0)) + int(ch[r])
		if step.has("heat"):
			heat += FactionManager.preview_heat(float(step["heat"]), FactionManager.heat + heat)
	if rep != 0:
		parts.append("REP %+d" % rep)
	for id: StringName in total:
		if int(total[id]) == 0:
			continue
		parts.append("%s %+d%s" % [FactionManager.get_name_of(id), int(total[id]), "" if sides.has(id) else " (rivals)"])
	if absf(heat) >= 0.5:
		parts.append("heat %+d" % roundi(heat))
	return ", ".join(parts)


# --- Helpers --------------------------------------------------------------------------------

## "▲ improving" / "▼ declining" / "– steady" (heat: going down is improving).
static func trend_text(t: float, up_is_good: bool) -> String:
	if absf(t) < 0.5:
		return "– steady"
	var better := (t > 0.0) == up_is_good
	return ("▲ " if t > 0.0 else "▼ ") + ("improving" if better else "worsening") + " (%+d, 3 days)" % roundi(t)


static func mark(level: StringName) -> String:
	return "✓" if level == GOOD else ("!" if level == WARN else "✕")


static func color(level: StringName) -> Color:
	return Palette.OK if level == GOOD else (Palette.WARN if level == WARN else Palette.DANGER)


## One history line: "D3 14:20  Gangs +4  · Operation on Kenji (grade A)".
static func history_line(e: Dictionary) -> String:
	var d := float(e["delta"])
	var amount := ("%+d" % roundi(d)) if absf(d) >= 1.0 else ("%+.1f" % d)
	return "D%d %s  %s %s  · %s" % [int(e["day"]), TimeManager.clock_text(int(e["minute"])), str(e["label"]), amount, str(e["reason"])]
