extends Node
## The clinic terminal's inbox: messages, calls, emails, encrypted drops and
## contracts (data/comms.json templates). The story, staff, debt and quest
## systems send them; contracts carry actions with effects. Unread items
## badge the journal.

signal received(uid: int)
signal changed()

const KIND_LABELS := {"message": "MESSAGE", "call": "CALL", "email": "EMAIL", "encrypted": "ENCRYPTED", "contract": "CONTRACT"}

var templates: Dictionary = {}
var inbox: Array[Dictionary] = []  # newest last
var _next_uid: int = 1
var _last_debt_warning: int = -10


func _ready() -> void:
	var d: Variant = DataLoader.load_json(GameConfig.DATA_COMMS)
	if d is Dictionary:
		templates = d.get("comms", {})
	EventBus.day_ended.connect(_on_day_ended)
	reset_state()


func reset_state() -> void:
	inbox.clear()
	_next_uid = 1
	_last_debt_warning = -10


## Sends template `id`; {key} placeholders are filled from vars.
func send(id: StringName, vars: Dictionary = {}) -> int:
	var t: Dictionary = templates.get(String(id), {})
	if t.is_empty():
		return -1
	var body := str(t.get("body", ""))
	var subject := str(t.get("subject", ""))
	for k: Variant in vars:
		body = body.replace("{%s}" % k, str(vars[k]))
		subject = subject.replace("{%s}" % k, str(vars[k]))
	return send_raw(str(t.get("kind", "message")), str(vars.get("from", t.get("from", ""))), subject, body, t.get("actions", []), String(id))


func send_raw(kind: String, from: String, subject: String, body: String, actions: Array = [], template: String = "") -> int:
	var m := {"uid": _next_uid, "kind": kind, "from": from, "subject": subject, "body": body, "day": BusinessManager.day,
		"read": false, "actions": actions.duplicate(true), "resolved": -1, "template": template}
	_next_uid += 1
	inbox.append(m)
	while inbox.size() > 80:
		inbox.pop_front()
	received.emit(int(m["uid"]))
	changed.emit()
	notify("%s from %s: %s" % [str(KIND_LABELS.get(kind, "MESSAGE")), sender_name(m), subject])
	return int(m["uid"])


func sender_name(m: Dictionary) -> String:
	var f := StringName(str(m.get("from", "")))
	if CharacterManager.has_character(f):
		return CharacterManager.get_character(f).display_name
	return str(m.get("from", "")) if str(m.get("from", "")) != "" else "Unknown"


func get_message(uid: int) -> Dictionary:
	for m in inbox:
		if int(m["uid"]) == uid:
			return m
	return {}


func unread_count() -> int:
	var n := 0
	for m in inbox:
		if not bool(m["read"]):
			n += 1
	return n


func mark_read(uid: int) -> void:
	var m := get_message(uid)
	if not m.is_empty() and not bool(m["read"]):
		m["read"] = true
		changed.emit()


## Contract / reply action.
func act(uid: int, index: int) -> bool:
	var m := get_message(uid)
	var acts: Array = m.get("actions", [])
	if m.is_empty() or int(m["resolved"]) >= 0 or index < 0 or index >= acts.size():
		return false
	m["resolved"] = index
	m["read"] = true
	var a: Dictionary = acts[index]
	StoryManager.apply_effects(a.get("effects", {}), StringName(str(m.get("from", ""))))
	if a.has("staff"):
		StaffLifeManager.apply_staff(a["staff"], m.get("vars", {}))
	if a.has("security"):
		SecurityManager.apply(a["security"])
	if a.has("supplier_favor"):
		SupplierManager.apply_favor(a["supplier_favor"])
	if a.has("person"):
		WorldEventManager.apply_person(a["person"], m.get("vars", {}))
	if a.has("dialogue"):
		StoryManager.queue_talk(StringName(str(a["dialogue"])))
	changed.emit()
	StoryManager.check()
	return true


## Small on-screen notice (only while playing).
func notify(text: String) -> void:
	if GameManager.is_running:
		UIManager.show_toast(text, &"info")


func _on_day_ended(day: int, _report: Dictionary) -> void:
	if BusinessManager.debt >= BusinessManager.DEBT_WARNING and day - _last_debt_warning >= 3:
		_last_debt_warning = day
		send(&"c_debt_warning", {"debt": BusinessManager.debt})


func get_save_data() -> Dictionary:
	return {"inbox": inbox.duplicate(true), "next_uid": _next_uid, "last_debt": _last_debt_warning}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	for m: Variant in data.get("inbox", []):
		if m is Dictionary:
			inbox.append(m)
	_next_uid = int(data.get("next_uid", inbox.size() + 1))
	_last_debt_warning = int(data.get("last_debt", -10))
