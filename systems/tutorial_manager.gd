extends Node
## Short first-shift tutorial: eight coach marks over the first customer,
## each pointing at the control to use. It never blocks input; it advances
## when the player reaches the next context (screen, plan, surgery stage)
## and can be skipped at any time. Progress is part of the game save.

signal step_changed(step: Dictionary)

## Each step: id, context (screen id, "plan", or "stage:<type>"), target
## node name to highlight (optional) and the text.
const STEPS: Array[Dictionary] = [
	{"id": "arrive", "context": "clinic", "target": "SeeButton", "title": "YOUR FIRST PATIENT",
		"text": "Someone is at the door. Click SEE CUSTOMER (or press {customer_info})."},
	{"id": "intake", "context": "customer", "target": "AcceptButton", "title": "THE FILE",
		"text": "Who they are, what chrome they want, what they pay. Click ACCEPT JOB (or press ENTER)."},
	{"id": "diagnose", "context": "diagnosis", "target": "ScanView", "title": "1 / DIAGNOSIS",
		"text": "Click 2 glowing body regions to scan. Pick the diagnosis the findings point to, then CONFIRM."},
	{"id": "plan", "context": "plan", "target": "BeginButton", "title": "2 / PROCEDURE",
		"text": "The plan: implant, tools, supplies, risk. All checks show +. Click BEGIN OPERATION."},
	{"id": "tools", "context": "stage:anesthesia", "target": "ControlsHost", "title": "3 / TOOLS",
		"text": "Each step's instrument is put in your hand for you; it glows in the rack on the right (keys {tool_1}-{tool_9} switch). First, HOLD the button or {context} to sedate and release in the green."},
	{"id": "cut", "context": "stage:incision", "target": "TrayScroll", "title": "4 / SURGERY",
		"text": "The SCALPEL is in your hand. Drag along the dotted guide from the marker. Go slow: straying causes bleeding. Right-click puts a tool down."},
	{"id": "install", "context": "stage:install_implant", "target": "FieldArea", "title": "5 / INSTALL",
		"text": "Drag the implant into the socket, turn it with the mouse wheel or {rotate_left} and {rotate_right} until it lines up, then SEAT ({context})."},
	{"id": "close", "context": "stage:close_incision", "target": "FieldArea", "title": "6 / FINISH",
		"text": "Click the stitch points in number order to close up."},
	{"id": "payment", "context": "results", "target": "ContinueButton", "title": "7 / PAYMENT",
		"text": "Credits, XP and street rep. Clean, fast work pays more."},
	{"id": "upgrade", "context": "clinic_after", "target": "Nav_skills", "title": "8 / UPGRADE",
		"text": "You earned a skill point. Spend it in SKILLS on the left. SUPPLY sells tools and implants. {pause} opens the menu. Good luck, ripper."},
]

const HELP_TEXT := "1. See the customer (click them or press {customer_info}) and accept the job (ENTER).\n2. Scan 2+ body regions, then pick the diagnosis.\n3. Check the plan and BEGIN.\n4. Each stage puts its instrument in your hand (it glows in the rack; switch with {tool_1}-{tool_9} or {tool_prev}/{tool_next}); follow the instruction bar. Right-click puts the tool down; the wheel zooms the field.\n5. Complications: hit the flashing emergency action ({quick_coag} COAG / {quick_sedate} SEDATE / {quick_stabilize} STABIL).\n6. Get paid, spend skill points, upgrade your clinic.\n7. The clinic room is clickable; wheel or double-click to zoom. {inventory} inventory, {database} database, {journal} journal, {map} city map, {changes} recent changes, {help} field guide (click any stat to explain it), {quicksave} quick save, {pause} menu.\nColours: cyan = tech/OK, amber = careful, red = danger, magenta = black market. Every colour also carries a symbol or a word.\nAll keys can be changed in SETTINGS > CONTROLS."


## The help text with the player's current keys.
static func help_text() -> String:
	return Controls.fill(HELP_TEXT)

var active: bool = false
var step_index: int = -1
var completed: bool = false

var _coach: CoachMark


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
	var step: Dictionary = STEPS[i]
	_hide()
	var host := UIManager.get_overlay_host()
	if host == null:
		return
	_coach = CoachMark.new()
	_coach.name = "CoachMark"
	host.add_child(_coach)
	host.move_child(_coach, 0)
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
	_hide()
	SaveManager.save_game()


func _hide() -> void:
	if is_instance_valid(_coach):
		_coach.queue_free()
	_coach = null


func get_save_data() -> Dictionary:
	return {"active": active, "step": step_index, "completed": completed}


func load_save_data(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	step_index = int(data.get("step", -1))
	completed = bool(data.get("completed", true))


## Saves from before the tutorial existed count as completed.
func reset_state() -> void:
	active = false
	completed = true
	step_index = -1
	_hide()
