class_name Difficulty
extends RefCounted
## The learning curve, in one place. Everything keys off the number of
## completed operations (EventManager.operations), so a new player gets:
##   op 0  (tutorial)  wide tolerances, no complications, guided steps
##   ops 1-2           still forgiving, one slow complication, no hidden
##                     conditions, calm customers, no random events
##   ops 3-7           assists fade, hidden conditions, second complications,
##                     events and the black market start to appear
##   ops 8+            full game: risk scales with chrome, tier and load.

## Tolerance multiplier per completed-op count (index = ops, last repeats).
const ASSIST := [1.5, 1.3, 1.22, 1.15, 1.1, 1.06, 1.03, 1.0]
## Complication countdown multiplier (more time early).
const COMPLICATION_TIME := [1.6, 1.45, 1.3, 1.2, 1.1, 1.05, 1.0]
## Ops before random events can trigger.
const EVENTS_FROM_OP := 2
## Ops before hidden conditions roll / second complications can happen.
const HIDDEN_CONDITIONS_FROM_OP := 2
const SECOND_COMPLICATION_FROM_OP := 3
## Neural-load cap for generated customers while learning (keeps the first
## patients in the stable band).
const EARLY_LOAD_CAP := 45.0
const EARLY_LOAD_CAP_UNTIL_OP := 4


static func ops() -> int:
	return EventManager.operations


static func _pick(table: Array, i: int) -> float:
	return float(table[clampi(i, 0, table.size() - 1)])


static func assist(op_count: int = -1) -> float:
	return _pick(ASSIST, ops() if op_count < 0 else op_count)


static func complication_time(op_count: int = -1) -> float:
	return _pick(COMPLICATION_TIME, ops() if op_count < 0 else op_count)


## How many complications an operation may have at most.
static func max_complications(op_count: int = -1) -> int:
	var o := ops() if op_count < 0 else op_count
	if o == 0 and TutorialManager.is_active():
		return 0
	return 1 if o < SECOND_COMPLICATION_FROM_OP else 99


static func events_allowed() -> bool:
	return ops() >= EVENTS_FROM_OP


static func hidden_conditions_allowed() -> bool:
	return ops() >= HIDDEN_CONDITIONS_FROM_OP


static func early_load_cap() -> float:
	return EARLY_LOAD_CAP if ops() < EARLY_LOAD_CAP_UNTIL_OP else INF


## Short label for the HUD / dossier ("LEARNING", "STREET", "DEEP").
static func phase_name() -> String:
	var o := ops()
	if o < 3:
		return "LEARNING"
	if o < 8:
		return "STREET"
	return "UNDERCITY"
