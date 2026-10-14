extends Node
## The clinic clock (data/time.json). A business day runs from opening
## (09:00) to 04:00. The clock moves with what happens, never on its own:
## the gap before the next customer, each operation (20 min for routine
## chrome, two hours for complex neural work), talking someone down. The
## gaps spread the day's jobs over the whole day, so a normal day passes
## through MORNING, DAY, EVENING, NIGHT and LATE NIGHT.
##
## The period biases who walks in, which incidents happen, prices, staff
## performance, the room's light, the ambience and what people say: all as
## weights, never hard rules. Some things happen at a time of day
## (appointments): the supplier's van in the morning, an inspection during
## business hours when heat is up, a midnight deal, a 02:00 emergency.

const MINUTES_PER_DAY := 1440

var data: Dictionary = {}
var periods: Array = []
var minute: int = 540
## Today's appointments: [{id, minute, label, event, hidden, done}]
var agenda: Array[Dictionary] = []
var _period: StringName = &""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_TIME)
	if d is Dictionary:
		data = d
		periods = d.get("periods", [])
	EventBus.day_started.connect(_on_day_started)
	reset_state()


func reset_state() -> void:
	minute = open_minute()
	agenda.clear()
	_period = period()
	_season_ambience.call_deferred()


func open_minute() -> int:
	return int(data.get("open", 540))


func close_minute() -> int:
	return int(data.get("close", 1680))


# --- Reading the clock ---------------------------------------------------------------------

## "23:40"
func clock_text(m: int = -1) -> String:
	var t := (minute if m < 0 else m) % MINUTES_PER_DAY
	return "%02d:%02d" % [t / 60, t % 60]


func period_data(m: int = -1) -> Dictionary:
	var t := minute if m < 0 else m
	# Periods are defined on a 06:00..30:00 dial (after midnight = +1440).
	if t < 360:
		t += MINUTES_PER_DAY
	for p: Dictionary in periods:
		if t >= int(p["start"]) and t < int(p["end"]):
			return p
	return periods[periods.size() - 1] if not periods.is_empty() else {}


func period(m: int = -1) -> StringName:
	return StringName(str(period_data(m).get("id", "day")))


func period_label(m: int = -1) -> String:
	return str(period_data(m).get("label", "DAY"))


func is_night() -> bool:
	return period() in [&"night", &"late_night"]


## "DAY 3 · AUTUMN · 23:40 · NIGHT"
func stamp() -> String:
	return "DAY %d · %s · %s · %s" % [BusinessManager.day, season_label(), clock_text(), period_label()]


func minutes_left() -> int:
	return maxi(0, close_minute() - minute)


func is_closing_time() -> bool:
	return minute >= close_minute()


## How long a procedure takes, by install difficulty (minutes).
func procedure_minutes(difficulty: int, emergency: bool = false) -> int:
	if emergency:
		return int(data.get("emergency_minutes", 25)) + 15 * maxi(0, difficulty - 1)
	return int(data.get("durations", {}).get(str(clampi(difficulty, 1, 5)), 40))


static func duration_text(mins: int) -> String:
	if mins < 60:
		return "%d min" % mins
	return "%dh%s" % [mins / 60, (" %02d" % (mins % 60)) if mins % 60 else ""]


# --- Moving the clock --------------------------------------------------------------------------

## Advances the clock. Fires appointments that come due and announces
## period changes.
func advance(mins: int) -> void:
	if mins <= 0:
		return
	minute = mini(minute + mins, close_minute() + 120)
	EventBus.time_changed.emit(minute, period())
	var p := period()
	if p != _period:
		_period = p
		EventBus.period_changed.emit(p)
		EventBus.modifiers_changed.emit()
		_apply_ambience()
	_run_agenda()


## The wait before the next customer: today's remaining jobs are spread
## over the remaining hours, with some randomness.
func arrival_gap() -> int:
	var left := maxi(1, BusinessManager.jobs_left())
	var span := float(minutes_left()) / float(left + 1)
	return clampi(int(span * _rng.randf_range(0.3, 1.3)), 10, 300)


func on_customer_arrived(emergency: bool) -> void:
	advance(5 if emergency else arrival_gap())


func on_operation(difficulty: int, emergency: bool = false) -> void:
	advance(procedure_minutes(difficulty, emergency))


func on_talk() -> void:
	advance(int(data.get("talk_minutes", 10)))


# --- Influence ---------------------------------------------------------------------------------

func archetype_weight(id: String) -> float:
	return float(period_data().get("archetypes", {}).get(id, 1.0))


func event_weight(id: StringName) -> float:
	return float(period_data().get("events", {}).get(String(id), 1.0))


func get_modifiers() -> Dictionary:
	return period_data().get("mods", {})


func bm_price_mult() -> float:
	return float(period_data().get("bm_price", 1.0))


## Night owls sharpen after dark; everyone else is slower at 03:00.
func staff_modifier(e: Dictionary) -> float:
	var night_owl := EmployeeAI.has_trait(e, "night_owl")
	match period():
		&"night":
			return 0.05 if night_owl else 0.0
		&"late_night":
			return 0.07 if night_owl else -0.04
		&"morning":
			return -0.03 if night_owl else 0.0
	return 0.0


## The room's colour at this hour: rgba laid over the clinic art.
func tint() -> Color:
	var t: Array = period_data().get("tint", [0, 0, 0, 0])
	return Color(float(t[0]), float(t[1]), float(t[2]), float(t[3]))


## Sometimes people mention the hour, or the weather.
func greeting_line() -> String:
	var lines: Array = period_data().get("lines", [])
	if _rng.randf() < 0.3:
		lines = season_def().get("lines", lines)
	return str(lines[_rng.randi() % lines.size()]) if not lines.is_empty() and _rng.randf() < 0.45 else ""


# --- Seasons ------------------------------------------------------------------------------------
# The calendar follows the business day (no extra save state): autumn from
# day 1, then winter, spring and summer, days_per_season days each. The last
# blend_days of a season fade toward the next one.

func _seasons() -> Dictionary:
	return data.get("seasons", {})


func season_length() -> int:
	return maxi(1, int(_seasons().get("days_per_season", 7)))


func _season_order() -> Array:
	var o: Array = _seasons().get("order", [])
	return o if not o.is_empty() else ["autumn"]


## Season id on a business day (default: today).
func season(day: int = -1) -> StringName:
	var d := maxi(1, BusinessManager.day if day < 0 else day)
	var o := _season_order()
	return StringName(str(o[((d - 1) / season_length()) % o.size()]))


func season_def(id: StringName = &"") -> Dictionary:
	return _seasons().get("list", {}).get(String(id if id != &"" else season()), {})


func season_label(day: int = -1) -> String:
	return str(season_def(season(day)).get("label", String(season(day)).to_upper()))


## 1 .. days_per_season
func day_in_season(day: int = -1) -> int:
	var d := maxi(1, BusinessManager.day if day < 0 else day)
	return (d - 1) % season_length() + 1


## How far today has faded toward the next season: {from, to, t (0..1)}.
func season_blend(day: int = -1) -> Dictionary:
	var d := maxi(1, BusinessManager.day if day < 0 else day)
	var b := clampi(int(_seasons().get("blend_days", 2)), 0, season_length() - 1)
	var into := day_in_season(d) - (season_length() - b)
	var t := float(into) / float(b + 1) if into > 0 else 0.0
	return {"from": season(d), "to": season(d + season_length() - day_in_season(d) + 1), "t": t}


## A number from the season's data, blended toward the next season.
func season_value(section: String, key: String, fallback: float = 1.0, day: int = -1) -> float:
	var b := season_blend(day)
	var a := float(season_def(b["from"]).get(section, {}).get(key, fallback))
	var z := float(season_def(b["to"]).get(section, {}).get(key, fallback))
	return lerpf(a, z, float(b["t"]))


## The season's colour over the room and the street (rgba, a = strength).
func season_tint(day: int = -1) -> Color:
	var b := season_blend(day)
	var out := Color(0, 0, 0, 0)
	for pair: Array in [[b["from"], 1.0 - float(b["t"])], [b["to"], float(b["t"])]]:
		var t: Array = season_def(pair[0]).get("tint", [1, 1, 1, 0])
		out += Color(float(t[0]), float(t[1]), float(t[2]), float(t[3])) * float(pair[1])
	return out


## Today's weather on the streets: {kind, next, mix, second, density}.
## Fixed per day (a hash of the day), so every street agrees and a reload
## shows the same sky. density 0 = a dry day.
func weather(day: int = -1) -> Dictionary:
	var d := maxi(1, BusinessManager.day if day < 0 else day)
	var b := season_blend(d)
	var w: Dictionary = season_def(b["from"]).get("weather", {})
	var wn: Dictionary = season_def(b["to"]).get("weather", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather:%d" % d)
	var roll := rng.randf()
	var chance := lerpf(float(w.get("chance", 0.5)), float(wn.get("chance", 0.5)), float(b["t"]))
	var density := lerpf(float(w.get("density", 1.0)), float(wn.get("density", 1.0)), float(b["t"])) if roll < chance else 0.0
	return {"kind": str(w.get("kind", "rain")), "next": str(wn.get("kind", "rain")), "mix": float(b["t"]),
		"second": str(w.get("second", "")), "density": density}


func _season_ambience() -> void:
	var mods := {}
	for k: String in ["rain", "pump", "vent", "hum", "city", "crt"]:
		var v := season_value("ambience", k, 1.0)
		if not is_equal_approx(v, 1.0):
			mods[k] = v
	# A dry day is quieter on the grates.
	if float(weather()["density"]) <= 0.0:
		mods["rain"] = float(mods.get("rain", 1.0)) * 0.3
	AudioManager.set_mix_mod(&"season", mods)


func _apply_ambience() -> void:
	AudioManager.set_mix_mod(&"time", period_data().get("ambience", {}))


# --- Appointments --------------------------------------------------------------------------------

func _on_day_started(_day: int) -> void:
	minute = open_minute()
	_period = period()
	_roll_agenda()
	EventBus.time_changed.emit(minute, _period)
	EventBus.period_changed.emit(_period)
	EventBus.modifiers_changed.emit()
	_apply_ambience()
	_season_ambience()
	if day_in_season(_day) == 1 and _day > 1:
		EventBus.season_changed.emit(season(_day))


func _roll_agenda() -> void:
	agenda.clear()
	for a: Dictionary in data.get("appointments", []):
		if FactionManager.heat < float(a.get("min_heat", -1.0)):
			continue
		if not EventManager.events.has(StringName(str(a["event"]))):
			continue
		if _rng.randf() >= float(a.get("chance", 1.0)):
			continue
		agenda.append({"id": str(a["id"]), "minute": int(a["minute"]), "label": str(a.get("label", "")),
			"event": str(a["event"]), "hidden": bool(a.get("hidden", false)), "done": false})
	agenda.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["minute"]) < int(y["minute"]))


## Appointments whose time has come turn into incidents (if nothing else
## is already waiting, and the incident makes sense right now).
func _run_agenda() -> void:
	for a in agenda:
		if bool(a["done"]) or int(a["minute"]) > minute:
			continue
		a["done"] = true
		var ev := StringName(str(a["event"]))
		if not EventManager.has_pending() and EventManager.is_eligible(ev):
			EventManager.queue_event(ev)


## What's coming up today (visible appointments, not yet past).
func upcoming() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in agenda:
		if not bool(a["done"]) and not bool(a["hidden"]):
			out.append(a)
	return out


# --- Save --------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"minute": minute, "agenda": agenda.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	minute = clampi(int(d.get("minute", open_minute())), 0, close_minute() + 120)
	for a: Variant in d.get("agenda", []):
		if a is Dictionary:
			agenda.append(a)
	_period = period()
	EventBus.modifiers_changed.emit()
	_apply_ambience()
	_season_ambience()
