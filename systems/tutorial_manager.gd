extends Node
## Short first-shift tutorial: eight coach marks over the first customer,
## each pointing at the control to use. It never blocks input; it advances
## when the player reaches the next context (screen, plan, surgery stage)
## and can be skipped at any time. Progress is part of the game save.

signal step_changed(step: Dictionary)

## Each step: id, context (screen id, "plan", or "stage:<type>"), target
## node name to highlight (optional) and the text.
const STEPS: Array[Dictionary] = [
	{"id": "arrive", "context": "clinic", "target": "SeeButton", "title": "THE CLINIC",
		"text": "A patient is at the door. Click SEE PATIENT (or the patient in the room)."},
	{"id": "intake", "context": "summary", "target": "AcceptButton", "title": "THE PATIENT",
		"text": "What they want, the main risk, what you'd keep. Click ACCEPT JOB."},
	{"id": "diagnose", "context": "diagnosis", "target": "ScanView", "title": "1 · SCAN",
		"text": "Click two glowing regions on the body, then pick the diagnosis that fits and CONFIRM."},
	{"id": "plan", "context": "plan", "target": "BeginButton", "title": "2 · PLAN",
		"text": "Implant, tools and supplies all show +. Click BEGIN OPERATION."},
	{"id": "tools", "context": "stage:anesthesia", "target": "ControlsHost", "title": "3 · SEDATE",
		"text": "Hold {context} (or the button) and let go in the green band."},
	{"id": "cut", "context": "stage:incision", "target": "TrayScroll", "title": "4 · CUT",
		"text": "Drag the scalpel along the dotted line from the marker. Slowly."},
	{"id": "install", "context": "stage:install_implant", "target": "FieldArea", "title": "5 · INSTALL",
		"text": "Drag the implant into the socket, turn it with the wheel until it lines up, then SEAT ({context})."},
	{"id": "close", "context": "stage:close_incision", "target": "FieldArea", "title": "6 · CLOSE",
		"text": "Click the stitch points in number order."},
	{"id": "payment", "context": "results", "target": "ContinueButton", "title": "7 · RESULT",
		"text": "What you earned and what the job used up. Click CONTINUE."},
	{"id": "upgrade", "context": "clinic_after", "target": "Nav_skills", "title": "NEW · SKILLS",
		"text": "You earned a skill point. Spend it in SKILLS, new in the side bar."},
]

const HELP_TEXT := "1. SEE PATIENT (click them or press {customer_info}): what they want, the main risk, what you keep. ACCEPT JOB (ENTER).\n2. Scan 2+ body regions, then pick the diagnosis.\n3. Check the plan and BEGIN.\n4. Each stage puts its instrument in your hand (it glows in the rack; switch with {tool_1}-{tool_9} or {tool_prev}/{tool_next}); follow the instruction bar. Right-click puts the tool down; the wheel zooms the field.\n5. Complications: hit the flashing emergency action ({quick_coag} COAG / {quick_sedate} SEDATE / {quick_stabilize} STABIL).\n6. Get paid, spend skill points, upgrade your clinic.\n7. The clinic room is clickable; wheel or double-click to zoom. {inventory} inventory, {database} database, {journal} journal, {map} city map, {changes} recent changes, {help} field guide (click any stat to explain it), {quicksave} quick save, {pause} menu.\nColours: cyan = tech/OK, amber = careful, red = danger, magenta = black market. Every colour also carries a symbol or a word.\nAll keys can be changed in SETTINGS > CONTROLS."


## The help text with the player's current keys.
static func help_text() -> String:
	return Controls.fill(HELP_TEXT)

var active: bool = false
var step_index: int = -1
var completed: bool = false
## PROGRESSIVE FEATURES (Features): feature id -> the day it was introduced,
## and the intro cards still to show. Saved with the game.
var introduced: Dictionary = {}
var intro_pending: Array = []
## The "day" given to sections a player already had (old saves, resets).
const INTRODUCED_BEFORE := -9999

var _coach: CoachMark
## The section whose introduction is on screen ("" = none).
var _feature_intro: String = ""


func _ready() -> void:
	EventBus.screen_changed.connect(_on_screen_changed)
	SurgeryManager.stage_started.connect(_on_stage_started)


func is_active() -> bool:
	return active and not completed


func current_step() -> Dictionary:
	return STEPS[step_index] if step_index >= 0 and step_index < STEPS.size() else {}


## Called by GameManager.start_new_game().
func start() -> void:
	active = true
	completed = false
	step_index = -1
	# A new clinic starts small: sections appear as they become relevant.
	introduced = {}
	intro_pending = []
	# Tutorial hints off: no coach marks, no scripted first patient.
	if not Settings.tutorial_hints:
		completed = true
		active = false


func skip() -> void:
	completed = true
	active = false
	_hide()
	SaveManager.save_game()


## Context notifications from screens ("plan") and surgery stages.
func notify(context: String) -> void:
	if not is_active():
		return
	for i in range(maxi(step_index, 0), STEPS.size()):
		if str(STEPS[i]["context"]) == context:
			_show_step(i)
			return


func _on_screen_changed(screen_id: StringName) -> void:
	if _feature_intro != "":
		# Opening the new section is the introduction's action: done.
		if Features.LIST.get(StringName(_feature_intro), {}).get("screen", &"") == screen_id:
			finish_feature_intro()
		else:
			_hide()  # it comes back on the clinic until seen
			_feature_intro = ""
		return
	if not is_active():
		_hide()
		return
	var ctx := String(screen_id)
	if screen_id == UIManager.SCREEN_CLINIC and step_index >= _index_of("payment"):
		ctx = "clinic_after"
	elif screen_id == UIManager.SCREEN_SKILLS and step_index >= _index_of("upgrade"):
		_finish()
		return
	_hide()
	notify.call_deferred(ctx)


func _on_stage_started(_index: int, stage: SurgeryStageData) -> void:
	if is_active() and stage:
		_hide()
		notify.call_deferred("stage:%s" % stage.type)


func _index_of(id: String) -> int:
	for i in STEPS.size():
		if str(STEPS[i]["id"]) == id:
			return i
	return -1


func _show_step(i: int) -> void:
	step_index = i
	_feature_intro = ""
	var step: Dictionary = STEPS[i]
	_hide()
	var host := UIManager.get_overlay_host()
	if host == null:
		return
	_coach = CoachMark.new()
	_coach.name = "CoachMark"
	host.add_child(_coach)
	# Normally under dialogs; a step that points into a dialog (the patient
	# summary) sits above it so its highlight isn't dimmed out.
	host.move_child(_coach, host.get_child_count() - 1 if str(step.get("context", "")) == "summary" else 0)
	_coach.setup(step, i + 1, STEPS.size())
	_coach.skip_pressed.connect(_confirm_skip)
	_coach.done_pressed.connect(_finish)
	AudioManager.play_sfx(&"tutorial", 0.0)
	step_changed.emit(step)


func _confirm_skip() -> void:
	UIManager.confirm("SKIP TUTORIAL?", "You can read the basics any time from the clinic menu (HOW TO PLAY).", "SKIP", skip)


func _finish() -> void:
	completed = true
	active = false
	# The last step introduced SKILLS: no second card for it.
	intro_pending.erase("skills")
	_hide()
	SaveManager.save_game()


## A section's introduction: one coach card pointing at its new side-bar
## entry (what it is and why, in a sentence). Opening it, or GOT IT, ends it.
func show_feature_intro(key: String) -> void:
	var f: Dictionary = Features.LIST.get(StringName(key), {})
	var host := UIManager.get_overlay_host()
	if f.is_empty() or host == null:
		return
	_hide()
	_feature_intro = key
	_coach = CoachMark.new()
	_coach.name = "CoachMark"
	host.add_child(_coach)
	host.move_child(_coach, 0)
	_coach.setup({"id": "feature_" + key, "context": "clinic", "target": "Nav_%s" % key, "title": "NEW · %s" % str(f["title"]), "text": str(f["intro"])}, 0, 0)
	_coach.done_pressed.connect(finish_feature_intro)
	AudioManager.play_sfx(&"tutorial", 0.0)


func has_feature_intro() -> bool:
	return _feature_intro != "" and is_instance_valid(_coach)


func finish_feature_intro() -> void:
	intro_pending.erase(_feature_intro)
	_feature_intro = ""
	_hide()


func _hide() -> void:
	if is_instance_valid(_coach):
		_coach.queue_free()
	_coach = null


func get_save_data() -> Dictionary:
	return {"active": active, "step": step_index, "completed": completed, "introduced": introduced.duplicate(), "intro_pending": intro_pending.duplicate()}


func load_save_data(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	step_index = int(data.get("step", -1))
	completed = bool(data.get("completed", true))
	if data.has("introduced") and data["introduced"] is Dictionary:
		introduced = (data["introduced"] as Dictionary).duplicate()
		intro_pending = (data.get("intro_pending", []) as Array).duplicate() if data.get("intro_pending", []) is Array else []
	else:
		# Saves from before 3.7 had every section on screen: keep it that way
		# (no cards, nothing hidden that was there before).
		_introduce_all()
	# Validation: anything relevant is introduced (a lost flag never locks).
	Features.refresh.call_deferred()


func _introduce_all() -> void:
	introduced = {}
	for id: StringName in Features.LIST:
		introduced[String(id)] = INTRODUCED_BEFORE  # long known: never marked NEW
	intro_pending = []


## Saves from before the tutorial existed count as completed.
func reset_state() -> void:
	active = false
	completed = true
	step_index = -1
	_introduce_all()
	_hide()
