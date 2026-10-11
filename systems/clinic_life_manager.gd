extends Node
## The clinic between operations (data/clinic_life.json).
##
## WAITING ROOM: while you work, the clock moves and people walk in and sit
## down. They wait their turn (the next customer comes from the bench),
## talk, complain, fall asleep, and give up and leave when their patience
## runs out (they remember that). People from rival crews waiting together
## make a scene.
##
## CLINIC LIFE: small vignettes as the hours pass (lunch over the sink, a
## courier's crate, a fixer smoking outside, a patrol drone at the window),
## shown as a caption in the room. Some have small effects.
##
## THE WALL: the clinic's memory. Notes for milestones, photos of loyal
## patients, names scratched in for the ones you lost, clippings, wanted
## notices, faction symbols. Pinned automatically; shown on the room's back
## wall and in the journal.

signal caption_posted(text: String)
signal waiting_changed()
signal wall_changed()

var data: Dictionary = {}
## [{customer: CustomerData, since: int (minute)}]
var waiting: Array[Dictionary] = []
var wall: Array[Dictionary] = []
var captions: Array[String] = []
var _last_minute: int = -1
var _scenes_seen: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var d: Variant = DataLoader.load_json(GameConfig.DATA_CLINIC_LIFE)
	if d is Dictionary:
		data = d
	EventBus.time_changed.connect(_on_time_changed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.surgery_rewarded.connect(_on_surgery)
	EventBus.clinic_purchased.connect(_on_clinic_purchased)
	EventBus.heat_changed.connect(_on_heat)
	EventBus.faction_changed.connect(_on_faction)
	PeopleManager.person_changed.connect(_on_person_changed)
	reset_state()


func reset_state() -> void:
	waiting.clear()
	wall.clear()
	captions.clear()
	_scenes_seen.clear()
	_last_minute = -1


# --- Waiting room ---------------------------------------------------------------------------

func capacity() -> int:
	var w: Dictionary = data.get("waiting", {})
	return int(w.get("base_capacity", 1)) + int(w.get("per_customer_upgrade", 1)) * ClinicManager.upgrade_level(&"customer")


## Minutes this person will sit before giving up.
func wait_limit(c: CustomerData) -> int:
	var w: Dictionary = data.get("waiting", {})
	var m := float(w.get("base_wait", 40)) + float(w.get("wait_per_patience", 1.6)) * c.patience
	if PeopleManager.rel_state(c.id) in ["loyal", "grateful"]:
		m *= 1.5
	return int(m)


## Room for one more without overbooking the day.
func can_seat() -> bool:
	var booked := BusinessManager.jobs_today + waiting.size() + (1 if CustomerManager.has_customer() else 0)
	return waiting.size() < capacity() and booked < BusinessManager.capacity() and not TimeManager.is_closing_time()


func seat(c: CustomerData) -> bool:
	if c == null or not can_seat():
		return false
	waiting.append({"customer": c, "since": TimeManager.minute})
	waiting_changed.emit()
	post("%s sits down in the waiting room." % c.display_name)
	_check_rivals()
	return true


## The next person off the bench (called when the door is free).
func take_next() -> CustomerData:
	if waiting.is_empty():
		return null
	var w: Dictionary = waiting.pop_front()
	waiting_changed.emit()
	return w["customer"]


func waiting_customers() -> Array[CustomerData]:
	var out: Array[CustomerData] = []
	for w in waiting:
		out.append(w["customer"])
	return out


func minutes_waited(i: int) -> int:
	return TimeManager.minute - int(waiting[i]["since"])


func _patience_check() -> void:
	for i in range(waiting.size() - 1, -1, -1):
		var c: CustomerData = waiting[i]["customer"]
		if minutes_waited(i) > wait_limit(c):
			waiting.remove_at(i)
			PeopleManager.after_visit(c, "left")
			post("%s gave up waiting and walked out." % c.display_name)
			waiting_changed.emit()


## Rival crews in one small room: someone leaves, the street hears.
func _check_rivals() -> void:
	var rivals: Array = data.get("rivals", [])
	for i in waiting.size():
		for j in range(i + 1, waiting.size()):
			var a: CustomerData = waiting[i]["customer"]
			var b: CustomerData = waiting[j]["customer"]
			var key := "%s|%s" % [a.id, b.id]
			if _scenes_seen.has(key):
				continue
			for pair: Array in rivals:
				if (String(a.faction_id) == str(pair[0]) and String(b.faction_id) == str(pair[1])) or (String(a.faction_id) == str(pair[1]) and String(b.faction_id) == str(pair[0])):
					_scenes_seen[key] = true
					_scene(i, j)
					return


## Records why standing changes in here (ChangeLog standing history).
func _scene(i: int, j: int) -> void:
	ChangeLog.push_cause("In the waiting room")
	_scene_impl(i, j)
	ChangeLog.pop_cause()


func _scene_impl(i: int, j: int) -> void:
	var a: CustomerData = waiting[i]["customer"]
	var b: CustomerData = waiting[j]["customer"]
	var leaver := j if b.patience <= a.patience else i
	var stays: CustomerData = (a if leaver == j else b)
	var gone: CustomerData = waiting[leaver]["customer"]
	waiting.remove_at(leaver)
	ReputationManager.change_dim(&"civilian", -1)
	FactionManager.add_heat(1.0)
	PeopleManager.after_visit(gone, "left")
	post("%s (%s) and %s (%s) square up in the waiting room. %s storms out." % [a.display_name, FactionManager.get_name_of(a.faction_id),
		b.display_name, FactionManager.get_name_of(b.faction_id), gone.display_name])
	if stays.traits.has(&"aggressive"):
		MemoryManager.remember(gone.id, &"PLAYER_MADE_ME_WAIT")
	waiting_changed.emit()


# --- Time passing -----------------------------------------------------------------------------

func _on_day_started(_day: int) -> void:
	# Nobody sleeps in the waiting room overnight.
	for w in waiting:
		PeopleManager.after_visit(w["customer"], "left")
	waiting.clear()
	_scenes_seen.clear()
	_last_minute = TimeManager.minute
	waiting_changed.emit()


func _on_time_changed(minute: int, _period: StringName) -> void:
	if _last_minute < 0 or minute < _last_minute:
		_last_minute = minute
		return
	var hours := (minute - _last_minute) / 60.0
	_last_minute = minute
	if hours <= 0.0 or not GameManager.is_running:
		return
	_patience_check()
	var w: Dictionary = data.get("waiting", {})
	# Walk-ins while you're busy with someone.
	if BusinessManager.doors_open and (CustomerManager.has_customer() or SurgeryManager.is_active or LocationManager.is_away()):
		var p := 1.0 - pow(1.0 - float(w.get("walk_in_per_hour", 0.35)), hours)
		if _rng.randf() < p and can_seat():
			seat(CustomerManager.generator.generate())
	var pv := 1.0 - pow(1.0 - float(data.get("chance_per_hour", 0.5)), hours)
	if _rng.randf() < pv:
		vignette()


## Picks and plays one fitting vignette. Returns its id.
func vignette() -> String:
	var period := String(TimeManager.period())
	var staff := StaffManager.at_clinic(ClinicManager.tier).filter(func(e: Dictionary) -> bool: return str(e.get("status", "")) == "working")
	var weights := {}
	var list: Array = data.get("vignettes", [])
	for i in list.size():
		var v: Dictionary = list[i]
		if v.has("periods") and not (v["periods"] as Array).has(period):
			continue
		if FactionManager.heat < float(v.get("min_heat", -1)):
			continue
		match str(v.get("needs", "")):
			"staff":
				if staff.is_empty():
					continue
			"waiting":
				if waiting.is_empty():
					continue
		weights[i] = float(v.get("weight", 1))
	if weights.is_empty():
		return ""
	var v: Dictionary = list[int(CustomerGenerator.new(_rng).pick_weighted(weights))]
	var text := str(v["text"])
	if not staff.is_empty():
		text = text.replace("{staff}", str(staff[_rng.randi() % staff.size()]["name"]))
	if not waiting.is_empty():
		text = text.replace("{patient}", (waiting[_rng.randi() % waiting.size()]["customer"] as CustomerData).display_name)
	_apply(v.get("effects", {}))
	post(text)
	EventBus.clinic_life.emit({"id": str(v["id"]), "text": text})
	return str(v["id"])


## Records why standing changes in here (ChangeLog standing history).
func _apply(fx: Dictionary) -> void:
	ChangeLog.push_cause("In the waiting room")
	_apply_impl(fx)
	ChangeLog.pop_cause()


func _apply_impl(fx: Dictionary) -> void:
	if fx.has("supplies"):
		InventoryManager.add_supplies(int(fx["supplies"]))
	if fx.has("parts"):
		InventoryManager.add_parts(int(fx["parts"]))
	if fx.has("dims"):
		ReputationManager.change_dims(fx["dims"])
	if fx.has("heat"):
		FactionManager.add_heat(float(fx["heat"]))
	if fx.has("stress"):
		for e in StaffManager.at_clinic(ClinicManager.tier):
			e["stress"] = clampf(float(e["stress"]) + float(fx["stress"]), 0.0, 100.0)
	if fx.has("patience"):
		for w in waiting:
			# Negative patience = they've effectively waited longer.
			w["since"] = int(w["since"]) + int(fx["patience"])


func post(text: String) -> void:
	captions.append("%s  %s" % [TimeManager.clock_text(), text])
	while captions.size() > 30:
		captions.pop_front()
	caption_posted.emit(text)


# --- The Wall ---------------------------------------------------------------------------------

func pin(kind: String, title: String, text: String = "", ref: String = "") -> void:
	if ref != "" and has_pin(ref):
		return
	wall.append({"kind": kind, "title": title, "text": text, "day": BusinessManager.day, "ref": ref})
	while wall.size() > int(data.get("wall", {}).get("max", 24)):
		# Old notes come down first; losses and wanted notices stay up.
		var idx := 0
		for i in wall.size():
			if not str(wall[i]["kind"]) in ["loss", "wanted"]:
				idx = i
				break
		wall.remove_at(idx)
	wall_changed.emit()


func has_pin(ref: String) -> bool:
	return wall.any(func(p: Dictionary) -> bool: return str(p.get("ref", "")) == ref)


func pin_color(kind: String) -> Color:
	var c: Array = data.get("wall", {}).get("kinds", {}).get(kind, {}).get("color", [0.8, 0.8, 0.7])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func kind_label(kind: String) -> String:
	return str(data.get("wall", {}).get("kinds", {}).get(kind, {}).get("label", kind.capitalize()))


func _on_surgery(r: SurgeryResult) -> void:
	if r.success and not has_pin("first_op"):
		pin("milestone", "First job", "%s, day %d. Hands still shaking." % [r.customer_name, BusinessManager.day], "first_op")
	if r.grade == "S" and not has_pin("first_s"):
		pin("milestone", "Perfect work", "%s on %s. Grade S." % [r.surgery_name, r.customer_name], "first_s")
	if r.failure_reason == &"flatline":
		pin("loss", r.customer_name, "Died on the table, day %d." % BusinessManager.day, "loss_%d_%s" % [BusinessManager.day, r.customer_name])


func _on_clinic_purchased(i: int) -> void:
	if i >= 0:
		pin("milestone", "New address", "Bought %s." % ClinicManager.get_tier_data(i).get("name", ""), "clinic_%d" % i)


func _on_heat(value: float, _d: float) -> void:
	if value >= 75.0 and not has_pin("wanted_%d" % (BusinessManager.day / 7)):
		pin("wanted", "WANTED", "Your face on a corporate security notice. Somebody tore it down and brought it to you.", "wanted_%d" % (BusinessManager.day / 7))


func _on_faction(id: StringName, value: int, _d: int) -> void:
	if value >= 30:
		pin("faction", FactionManager.get_name_of(id), "Their mark, sprayed on your door. You're under their eye now.", "faction_%s" % id)


func _on_person_changed(id: StringName) -> void:
	var p := PeopleManager.get_person(id)
	if not p.is_empty() and bool(p.get("loyal", false)):
		pin("patient", str(p["name"]), "A regular. Brought you a photo of themselves, grinning, new chrome.", "patient_%s" % id)


# --- Save -------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var ws: Array = []
	for w in waiting:
		ws.append({"customer": (w["customer"] as CustomerData).to_save_dict(), "since": int(w["since"])})
	return {"waiting": ws, "wall": wall.duplicate(true), "captions": captions.duplicate()}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	for w: Variant in d.get("waiting", []):
		if w is Dictionary and (w as Dictionary).get("customer", null) is Dictionary:
			waiting.append({"customer": CustomerData.from_save_dict(w["customer"]), "since": int(w.get("since", 0))})
	for p: Variant in d.get("wall", []):
		if p is Dictionary:
			wall.append(p)
	for c: Variant in d.get("captions", []):
		captions.append(str(c))
	_last_minute = TimeManager.minute
	waiting_changed.emit()
	wall_changed.emit()
