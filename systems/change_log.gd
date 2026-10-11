extends Node
## RECENT CHANGES: a short, merged history of what changed while the player
## was busy, built from the real game signals (factions, heat, reputation,
## money, supplies, quests, places, staff, relationships, messages, news).
## Every entry says who/what changed, by how much and when, carries a
## priority (CRITICAL / IMPORTANT / INFO) and, when it has one, a link that
## takes the player straight to the thing (see Nav.open).
##
## Repeated changes to the same thing within an hour of game time merge into
## one line ("Medical supplies -3" instead of three "-1"s). Only CRITICAL
## entries interrupt with a toast (DETAILED guidance adds IMPORTANT ones
## outside surgery and dialogue); the rest wait in the panel (G).

signal added(entry: Dictionary)
signal read_changed()

const MAX_ENTRIES := 80
const MERGE_MINUTES := 60
const CRITICAL := &"critical"
const IMPORTANT := &"important"
const INFO := &"info"
## Symbol per level, so priority never depends on colour alone.
const LEVEL_MARKS := {&"critical": "■", &"important": "▲", &"info": "·"}

var entries: Array[Dictionary] = []  # oldest first

## STANDING HISTORY (3.6): every change to street reputation, the five
## reputation dimensions, faction standing, authority heat and personal
## relationships, with the cause that was recorded when it happened (never
## reconstructed later). Minor repeats (same thing, same cause, same hour)
## are batched; the list is bounded and saved.
## {day, minute, group, label, delta, value, reason}
const MAX_STANDING := 200
const NO_CAUSE := "No recorded cause"
var standing: Array[Dictionary] = []
## Causes pushed by whatever is happening (an operation, an event, a
## conversation...): a change without an explicit reason uses the newest.
var _causes: Array[String] = []
var seen_seq: int = 0
var _seq: int = 0
var _supplies: int = -1
var muted: bool = false


func _ready() -> void:
	EventBus.faction_changed.connect(_on_faction)
	EventBus.heat_changed.connect(_on_heat)
	EventBus.reputation_changed.connect(_on_rep)
	EventBus.transaction.connect(_on_money)
	EventBus.level_up.connect(func(lv: int) -> void:
		add("level", "You", "Reached level %d · new skill point" % lv, IMPORTANT, {"screen": &"skills"}))
	EventBus.location_discovered.connect(func(id: StringName) -> void:
		add("place", LocationManager.location_name(id), "New place on your map", IMPORTANT, {"location": id}))
	EventBus.news_posted.connect(func(item: Dictionary) -> void:
		if bool(item.get("about_you", false)):
			add("news", "In the news", str(item.get("headline", "")), IMPORTANT, {"screen": &"dossier", "params": {"tab_name": "DISCOVERIES"}}))
	EventBus.resources_changed.connect(_on_resources)
	EventBus.rumor_unlocked.connect(func(id: StringName) -> void:
		add("lead", "New lead", StoryManager.get_rumor_text(id), IMPORTANT, {"screen": &"dossier", "params": {"tab_name": "DISCOVERIES", "view": "NEWS"}}))
	EventBus.clinic_upgrade_installed.connect(func(cat: StringName, lv: int) -> void:
		add("clinic", "Clinic", "%s upgraded to level %d" % [String(cat).replace("_", " ").capitalize(), lv], INFO, {"screen": &"upgrades"}))
	EventBus.new_game_started.connect(clear)
	QuestManager.quest_started.connect(func(id: StringName) -> void:
		add("quest", str(QuestManager.get_quest(id).get("title", id)), "New objective", IMPORTANT, {"screen": &"dossier", "params": {"tab_name": "MAIN"}}))
	QuestManager.quest_completed.connect(func(id: StringName) -> void:
		add("quest", str(QuestManager.get_quest(id).get("title", id)), "Completed · %s" % QuestManager.reward_text(id), IMPORTANT, {"screen": &"dossier", "params": {"tab_name": "MAIN"}}))
	QuestManager.quest_failed.connect(func(id: StringName) -> void:
		add("quest", str(QuestManager.get_quest(id).get("title", id)), "Failed", IMPORTANT, {"screen": &"dossier", "params": {"tab_name": "MAIN"}}))
	StaffManager.employee_event.connect(func(id: StringName, text: String) -> void:
		add("staff", str(StaffManager.get_employee(id).get("name", "Staff")), text, INFO, {"screen": &"staff"}, 0.0, "staff:%s:%s" % [id, text]))
	CharacterManager.relationship_changed.connect(func(id: StringName, _value: int, state: String) -> void:
		var c := CharacterManager.get_character(id)
		add("people", c.display_name if c else String(id), "Relationship: %s" % state.to_lower(), INFO, {"screen": &"dossier", "params": {"tab_name": "PEOPLE"}}, 0.0, "rel:%s" % id))
	CommsManager.received.connect(func(uid: int) -> void:
		var m := CommsManager.get_message(uid)
		add("message", CommsManager.sender_name(m), str(m.get("subject", "")), IMPORTANT, {"screen": &"dossier", "params": {"tab_name": "MAIN"}}))
	CustomerManager.emergency_crashed.connect(func(who: String, died: bool) -> void:
		add("patient", who, "Died waiting at your door" if died else "Crashed while waiting", CRITICAL))


# --- Standing history ----------------------------------------------------------------------

func push_cause(text: String) -> void:
	_causes.append(text)


func pop_cause() -> void:
	if not _causes.is_empty():
		_causes.pop_back()


func current_cause() -> String:
	return _causes[_causes.size() - 1] if not _causes.is_empty() else ""


## Records one standing change. group: "rep", "dim:<d>", "faction:<id>",
## "heat", "person:<id>". `reason` overrides the current cause.
func record_standing(group: String, label: String, delta: float, value: float, reason: String = "") -> void:
	if muted or not GameManager.is_running or absf(delta) < 0.01:
		return
	var why := reason if reason != "" else current_cause()
	if why == "":
		why = NO_CAUSE
	var day := BusinessManager.day
	var minute := TimeManager.minute
	if not standing.is_empty():
		var last: Dictionary = standing[standing.size() - 1]
		if str(last["group"]) == group and str(last["reason"]) == why and int(last["day"]) == day and absi(minute - int(last["minute"])) <= MERGE_MINUTES:
			last["delta"] = float(last["delta"]) + delta
			last["value"] = value
			return
	standing.append({"day": day, "minute": minute, "group": group, "label": label, "delta": delta, "value": value, "reason": why})
	while standing.size() > MAX_STANDING:
		standing.pop_front()


## Newest first; `prefix` filters by group ("faction:", "rep", ...).
func standing_history(prefix: String = "", n: int = 50) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(standing.size() - 1, -1, -1):
		var e: Dictionary = standing[i]
		if prefix == "" or str(e["group"]).begins_with(prefix):
			out.append(e)
			if out.size() >= n:
				break
	return out


## Net change of one group over the last `days` days (trend arrows).
func standing_trend(group: String, days: int = 3) -> float:
	var since := BusinessManager.day - days + 1
	var t := 0.0
	for e in standing:
		if str(e["group"]) == group and int(e["day"]) >= since:
			t += float(e["delta"])
	return t


# --- Entries -----------------------------------------------------------------------------

## Adds (or merges into) an entry. `delta` merges numerically when the same
## merge key repeats within MERGE_MINUTES; text with a %+d is re-rendered.
func add(cat: String, subject: String, text: String, level: StringName = INFO, link: Dictionary = {},
		delta: float = 0.0, merge_key: String = "", fmt: String = "") -> void:
	if muted or not GameManager.is_running:
		return
	var key := merge_key if merge_key != "" else "%s:%s:%s" % [cat, subject, text]
	var now := _now()
	if not entries.is_empty():
		for i in range(entries.size() - 1, maxi(-1, entries.size() - 6), -1):
			var e: Dictionary = entries[i]
			if str(e["key"]) == key and now - int(e["at"]) <= MERGE_MINUTES:
				e["delta"] = float(e["delta"]) + delta
				e["text"] = fmt % e["delta"] if fmt != "" else text
				e["at"] = now
				e["minute"] = TimeManager.minute
				e["seq"] = _next_seq()
				if _rank(level) > _rank(StringName(str(e["level"]))):
					e["level"] = level
				entries.remove_at(i)
				entries.append(e)
				added.emit(e)
				read_changed.emit()
				return
	var entry := {"seq": _next_seq(), "key": key, "cat": cat, "subject": subject, "text": fmt % delta if fmt != "" else text, "level": level,
		"link": link, "delta": delta, "day": BusinessManager.day, "minute": TimeManager.minute, "at": now}
	entries.append(entry)
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	added.emit(entry)
	read_changed.emit()
	if level == CRITICAL:
		UIManager.show_toast("%s %s: %s" % [LEVEL_MARKS[level], subject, text], &"danger")
	elif level == IMPORTANT and Settings.is_detailed() and not _busy():
		# DETAILED guidance also announces important changes, but never over
		# an operation or a conversation (they wait in CHANGES).
		UIManager.show_toast("%s %s: %s" % [LEVEL_MARKS[level], subject, text], &"warn")


## The player is operating or talking: only critical news interrupts.
static func _busy() -> bool:
	return SurgeryManager.is_active or DialogueManager.is_active()


func _now() -> int:
	return BusinessManager.day * 2000 + TimeManager.minute


func _next_seq() -> int:
	_seq += 1
	return _seq


static func _rank(level: StringName) -> int:
	return {&"info": 0, &"important": 1, &"critical": 2}.get(level, 0)


## The current sequence number (to find what happened after a moment).
func mark() -> int:
	return _seq


## Entries after `seq` in the given categories (oldest first).
func since(seq: int, cats: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if int(e["seq"]) > seq and (cats.is_empty() or cats.has(str(e["cat"]))):
			out.append(e)
	return out


func unread_count() -> int:
	var n := 0
	for e in entries:
		if int(e["seq"]) > seen_seq:
			n += 1
	return n


func mark_all_read() -> void:
	seen_seq = _seq
	read_changed.emit()


func is_unread(e: Dictionary) -> bool:
	return int(e["seq"]) > seen_seq


## Newest first, optionally only the last `n`.
func recent(n: int = MAX_ENTRIES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(entries.size() - 1, -1, -1):
		out.append(entries[i])
		if out.size() >= n:
			break
	return out


func clear() -> void:
	entries.clear()
	standing.clear()
	_causes.clear()
	seen_seq = _seq
	_supplies = -1


# --- Signal adapters ---------------------------------------------------------------------

func _on_faction(id: StringName, value: int, delta: int) -> void:
	if delta == 0:
		return
	var lv := IMPORTANT if absi(delta) >= 5 else INFO
	var was := _standing(value - delta)
	var now := _standing(value)
	if was != now:
		add("faction_standing", FactionManager.get_name_of(id), "Now %s (was %s)" % [now, was], IMPORTANT,
			{"screen": &"dossier", "params": {"tab_name": "STANDING"}})
	add("faction", FactionManager.get_name_of(id), "", lv, {"screen": &"dossier", "params": {"tab_name": "STANDING"}},
		float(delta), "faction:%s" % id, "Standing %+.0f · now " + str(value))


static func _standing(v: int) -> String:
	for st: Array in GameConfig.FACTION_STANDINGS:
		if v < int(st[0]):
			return String(st[1])
	return "ALLIED"


func _on_heat(value: float, delta: float) -> void:
	if absf(delta) < 1.0:
		return
	if delta > 0.0:
		(func() -> void: Hints.first("heat")).call_deferred()
	var lv := IMPORTANT if value >= 50.0 and delta > 0.0 else INFO
	if value >= 75.0 and delta > 0.0:
		lv = CRITICAL
	add("heat", "Authority heat", "", lv, {"screen": &"dossier", "params": {"tab_name": "STANDING"}},
		delta, "heat", "%+.0f · now " + str(roundi(value)))


func _on_rep(value: int, delta: int) -> void:
	if delta == 0:
		return
	add("rep", "Reputation", "", INFO, {}, float(delta), "rep", "%+.0f · now " + str(value))


func _on_money(category: StringName, delta: int) -> void:
	if absi(delta) < 1:
		return
	var lv := IMPORTANT if delta <= -500 else INFO
	add("money", "Credits", "", lv, {"screen": &"business"}, float(delta), "money:%s" % category,
		"%+.0f cr · " + String(category).replace("_", " "))


func _on_resources() -> void:
	var now := InventoryManager.supplies
	if _supplies >= 0 and now != _supplies:
		var d := now - _supplies
		var lv := IMPORTANT if now <= 2 and d < 0 else INFO
		add("supplies", "Medical supplies", "", lv, {"screen": &"shop"}, float(d), "supplies", "%+.0f · now " + str(now))
	_supplies = now


# --- Save --------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"entries": entries.duplicate(true), "seen": seen_seq, "seq": _seq, "standing": standing.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	entries.clear()
	for e: Variant in d.get("entries", []):
		if e is Dictionary and (e as Dictionary).has("seq"):
			var x: Dictionary = e
			x["level"] = StringName(str(x.get("level", "info")))
			entries.append(x)
	standing.clear()
	for e: Variant in d.get("standing", []):
		if e is Dictionary and (e as Dictionary).has("group"):
			standing.append(e)
	while standing.size() > MAX_STANDING:
		standing.pop_front()
	_seq = int(d.get("seq", entries.size()))
	seen_seq = int(d.get("seen", _seq))
	_supplies = InventoryManager.supplies


func reset_state() -> void:
	entries.clear()
	standing.clear()
	_causes.clear()
	_seq = 0
	seen_seq = 0
	_supplies = -1
