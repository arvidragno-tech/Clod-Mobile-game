class_name Compare
extends RefCounted
## CURRENT vs NEW comparison tables (cyberware database, inventory, supply).
## Every row is tagged BETTER / WORSE / SAME / UNKNOWN / INCOMPATIBLE and
## shown with a symbol as well as a colour so it reads without colour too.

enum Verdict { SAME, BETTER, WORSE, UNKNOWN, INCOMPATIBLE }

const SYMBOLS := {Verdict.SAME: "=", Verdict.BETTER: "▲ BETTER", Verdict.WORSE: "▼ WORSE", Verdict.UNKNOWN: "? UNKNOWN", Verdict.INCOMPATIBLE: "✕ INCOMPATIBLE"}
const COLORS := {Verdict.SAME: Palette.TEXT_DIM, Verdict.BETTER: Palette.OK, Verdict.WORSE: Palette.DANGER, Verdict.UNKNOWN: Palette.WARN, Verdict.INCOMPATIBLE: Palette.BRAND}


static func verdict(current: float, new: float, higher_is_better: bool) -> Verdict:
	if is_equal_approx(current, new):
		return Verdict.SAME
	return Verdict.BETTER if (new > current) == higher_is_better else Verdict.WORSE


## Rows describing a cyberware model (optionally a physical unit).
## Each row: [caption, value_text, number, higher_is_better, unknown].
static func cyberware_rows(item: CyberwareData, inst: ImplantInstance = null) -> Array:
	var load := inst.get_neural_load() if inst else item.neural_load
	var perf := item.base_performance * (inst.get_quality() if inst else 1.0)
	var risk := inst.get_extra_risk() if inst else item.failure_risk
	var unknown := (inst != null and inst.has_unknown_traits()) or (inst == null and item.unknown_traits > 0)
	return [
		["TIER", "T%d %s" % [item.tier, item.get_tier_name()], float(item.tier), true, false],
		["PERFORMANCE", "%d%%" % roundi(perf * 100.0), perf, true, unknown],
		["NEURAL LOAD", "+%d%%" % roundi(load), load, false, unknown],
		["DIFFICULTY", "%d/5" % item.install_difficulty, float(item.install_difficulty), false, false],
		["FAILURE RISK", "%d%%" % roundi(risk * 100.0), risk, false, unknown],
		["CONDITION", "%d%%" % roundi(inst.condition if inst else 100.0), inst.condition if inst else 100.0, true, false],
		["PRICE", EconomyManager.format_money(item.price), float(item.price), false, false],
	]


## Builds the CURRENT vs NEW table into `parent`. `current` may be null
## (nothing to compare with: every row is just listed).
static func build_cyberware_table(parent: Control, current: CyberwareData, new: CyberwareData, current_inst: ImplantInstance = null, new_inst: ImplantInstance = null) -> void:
	var incompatible := current != null and current.category != new.category
	var head := UIKit.hbox(10)
	parent.add_child(head)
	var a := UIKit.label("CURRENT: %s" % (current.display_name if current else "none"), &"SubHeaderLabel", true)
	UIKit.expand(a)
	head.add_child(a)
	var b := UIKit.label("NEW: %s" % new.display_name, &"SubHeaderLabel", true, Palette.ACCENT)
	UIKit.expand(b)
	head.add_child(b)
	if incompatible:
		parent.add_child(UIKit.label("✕ INCOMPATIBLE: %s slot vs %s slot. Not a replacement." % [String(current.category).to_upper(), String(new.category).to_upper()], &"MonoLabel", true, Palette.BRAND))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override(&"h_separation", 18)
	g.add_theme_constant_override(&"v_separation", 4)
	parent.add_child(g)
	for caption in ["STAT", "CURRENT", "NEW", ""]:
		g.add_child(UIKit.label(caption, &"SubHeaderLabel"))
	var cur_rows := cyberware_rows(current, current_inst) if current else []
	var new_rows := cyberware_rows(new, new_inst)
	for i in new_rows.size():
		var nr: Array = new_rows[i]
		g.add_child(UIKit.caption(str(nr[0])))
		g.add_child(UIKit.label(str(cur_rows[i][1]) if current else "-", &"MonoLabel", false, Palette.TEXT_DIM))
		g.add_child(UIKit.label(str(nr[1]), &"MonoLabel"))
		var v := Verdict.SAME
		if incompatible:
			v = Verdict.INCOMPATIBLE
		elif bool(nr[4]) or (current and bool(cur_rows[i][4])):
			v = Verdict.UNKNOWN
		elif current:
			v = verdict(float(cur_rows[i][2]), float(nr[2]), bool(nr[3]))
		var l := UIKit.label(SYMBOLS[v] if current or v == Verdict.UNKNOWN else "", &"SubHeaderLabel", false, COLORS[v])
		l.name = "Verdict_%s" % str(nr[0]).replace(" ", "_")
		g.add_child(l)


## Tool vs the best owned tool of the same category.
static func build_tool_table(parent: Control, current: ToolData, new: ToolData) -> void:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override(&"h_separation", 18)
	g.add_theme_constant_override(&"v_separation", 4)
	parent.add_child(g)
	for caption in ["STAT", "OWNED", "NEW", ""]:
		g.add_child(UIKit.label(caption, &"SubHeaderLabel"))
	var rows := [
		["PRECISION", current.precision if current else 0.0, new.precision, true],
		["SPEED", current.speed if current else 0.0, new.speed, true],
		["RISK", current.risk if current else 0.0, new.risk, false],
		["TIER", float(current.tier) if current else 0.0, float(new.tier), true],
	]
	for r: Array in rows:
		g.add_child(UIKit.caption(str(r[0])))
		g.add_child(UIKit.label("x%.2f" % float(r[1]) if current else "-", &"MonoLabel", false, Palette.TEXT_DIM))
		g.add_child(UIKit.label("x%.2f" % float(r[2]), &"MonoLabel"))
		var v := verdict(float(r[1]), float(r[2]), bool(r[3])) if current else Verdict.BETTER
		g.add_child(UIKit.label(SYMBOLS[v], &"SubHeaderLabel", false, COLORS[v]))
