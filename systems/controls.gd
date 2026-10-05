extends Node
## Keyboard + mouse control scheme. Registers every game action in the
## InputMap with its default bindings, applies the player's remaps from
## Settings, and powers the Controls settings tab: two slots per action
## (each a key or a mouse button), duplicate / conflict detection per
## context, reset one binding or all of them. Movement bindings also drive
## the built-in ui_* actions, so menus follow the player's layout.
##
## A binding code is an int: a physical keycode (> 0), or the negated mouse
## button index for mouse buttons (< 0); 0 = empty slot. (Keycodes for
## special keys run above 0x400000, so mouse codes must not be positive.)

signal bindings_changed

const SLOTS := 2

## Categories in display order; context decides which actions can clash
## (global ones clash with everything).
const CATEGORIES := {
	"Movement": "global", "Interaction": "global", "Surgery": "surgery", "Tools": "surgery", "Inventory": "global",
	"Map": "global", "Journal": "global", "Dialogue": "dialogue", "Camera": "surgery", "General": "global",
}

## id -> {label, group, keys: Array[int] (codes)}. Order is the tab order.
const ACTIONS := {
	"move_up": {"label": "Move / navigate up", "group": "Movement", "keys": [KEY_W, KEY_UP]},
	"move_down": {"label": "Move / navigate down", "group": "Movement", "keys": [KEY_S, KEY_DOWN]},
	"move_left": {"label": "Move / navigate left", "group": "Movement", "keys": [KEY_A, KEY_LEFT]},
	"move_right": {"label": "Move / navigate right", "group": "Movement", "keys": [KEY_D, KEY_RIGHT]},
	"interact": {"label": "Interact", "group": "Interaction", "keys": [KEY_E]},
	"context": {"label": "Contextual action", "group": "Interaction", "keys": [KEY_SPACE]},
	"inspect": {"label": "Inspect", "group": "Interaction", "keys": [KEY_F, -MOUSE_BUTTON_MIDDLE]},
	"customer_info": {"label": "Customer information", "group": "Interaction", "keys": [KEY_C]},
	"tool_prev": {"label": "Previous tool", "group": "Surgery", "keys": [KEY_Q, -MOUSE_BUTTON_XBUTTON1]},
	"tool_next": {"label": "Next tool", "group": "Surgery", "keys": [KEY_R, -MOUSE_BUTTON_XBUTTON2]},
	"quick_coag": {"label": "Emergency: COAG", "group": "Surgery", "keys": [KEY_Z]},
	"quick_sedate": {"label": "Emergency: SEDATE", "group": "Surgery", "keys": [KEY_X]},
	"quick_stabilize": {"label": "Emergency: STABIL", "group": "Surgery", "keys": [KEY_V]},
	"rotate_left": {"label": "Rotate implant left", "group": "Surgery", "keys": [KEY_COMMA]},
	"rotate_right": {"label": "Rotate implant right", "group": "Surgery", "keys": [KEY_PERIOD]},
	"tool_1": {"label": "Tool slot 1", "group": "Tools", "keys": [KEY_1]},
	"tool_2": {"label": "Tool slot 2", "group": "Tools", "keys": [KEY_2]},
	"tool_3": {"label": "Tool slot 3", "group": "Tools", "keys": [KEY_3]},
	"tool_4": {"label": "Tool slot 4", "group": "Tools", "keys": [KEY_4]},
	"tool_5": {"label": "Tool slot 5", "group": "Tools", "keys": [KEY_5]},
	"tool_6": {"label": "Tool slot 6", "group": "Tools", "keys": [KEY_6]},
	"tool_7": {"label": "Tool slot 7", "group": "Tools", "keys": [KEY_7]},
	"tool_8": {"label": "Tool slot 8", "group": "Tools", "keys": [KEY_8]},
	"tool_9": {"label": "Tool slot 9", "group": "Tools", "keys": [KEY_9]},
	"inventory": {"label": "Inventory", "group": "Inventory", "keys": [KEY_I]},
	"database": {"label": "Cyberware database", "group": "Inventory", "keys": [KEY_B]},
	"supply": {"label": "Supply shop", "group": "Inventory", "keys": [KEY_U]},
	"map": {"label": "City map", "group": "Map", "keys": [KEY_M]},
	"facility": {"label": "Facility and property", "group": "Map", "keys": [KEY_K]},
	"business": {"label": "Business ledger", "group": "Map", "keys": [KEY_L]},
	"staff": {"label": "Staff", "group": "Map", "keys": [KEY_T]},
	"journal": {"label": "Journal", "group": "Journal", "keys": [KEY_J]},
	"comms": {"label": "Comms inbox", "group": "Journal", "keys": [KEY_N]},
	"dialogue_next": {"label": "Continue / skip text", "group": "Dialogue", "keys": [KEY_ENTER, KEY_KP_ENTER]},
	"dialogue_1": {"label": "Answer 1", "group": "Dialogue", "keys": [KEY_1]},
	"dialogue_2": {"label": "Answer 2", "group": "Dialogue", "keys": [KEY_2]},
	"dialogue_3": {"label": "Answer 3", "group": "Dialogue", "keys": [KEY_3]},
	"dialogue_4": {"label": "Answer 4", "group": "Dialogue", "keys": [KEY_4]},
	"zoom_in": {"label": "Zoom in", "group": "Camera", "keys": [KEY_EQUAL]},
	"zoom_out": {"label": "Zoom out", "group": "Camera", "keys": [KEY_MINUS]},
	"pause": {"label": "Pause / back", "group": "General", "keys": [KEY_ESCAPE]},
	"cycle_panel": {"label": "Cycle panels", "group": "General", "keys": [KEY_TAB]},
	"quicksave": {"label": "Quick save", "group": "General", "keys": [KEY_F5]},
	"quickload": {"label": "Quick load", "group": "General", "keys": [KEY_F9]},
}
## Movement actions feed Godot's built-in menu navigation.
const UI_FROM := {"ui_up": "move_up", "ui_down": "move_down", "ui_left": "move_left", "ui_right": "move_right"}
## Keys the player may not take away from menus (always also navigate).
const UI_FIXED := {"ui_up": KEY_UP, "ui_down": KEY_DOWN, "ui_left": KEY_LEFT, "ui_right": KEY_RIGHT}

var _ui_added: Array[InputEvent] = []


func _ready() -> void:
	apply_bindings()
	Settings.changed.connect(apply_bindings)


# --- Codes -----------------------------------------------------------------------------

static func mouse(button: int) -> int:
	return -button


static func is_mouse(code: int) -> bool:
	return code < 0


static func event_for(code: int) -> InputEvent:
	if is_mouse(code):
		var m := InputEventMouseButton.new()
		m.button_index = -code as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	return k


## Code for a pressed key / mouse button (0 if not bindable).
static func code_for(event: InputEvent) -> int:
	var k := event as InputEventKey
	if k:
		return int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	var m := event as InputEventMouseButton
	if m and m.button_index != MOUSE_BUTTON_LEFT:
		return -int(m.button_index)
	return 0


const MOUSE_NAMES := {MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB", MOUSE_BUTTON_WHEEL_UP: "WHEEL UP",
	MOUSE_BUTTON_WHEEL_DOWN: "WHEEL DOWN", MOUSE_BUTTON_XBUTTON1: "MOUSE 4", MOUSE_BUTTON_XBUTTON2: "MOUSE 5",
	MOUSE_BUTTON_WHEEL_LEFT: "WHEEL L", MOUSE_BUTTON_WHEEL_RIGHT: "WHEEL R"}
const SHORT_NAMES := {"Escape": "ESC", "Comma": ",", "Period": ".", "Equal": "=", "Minus": "-",
	"Backspace": "BKSP", "Enter": "ENTER", "Space": "SPACE", "Tab": "TAB", "Slash": "/", "Semicolon": ";",
	"Apostrophe": "'", "BracketLeft": "[", "BracketRight": "]", "Backslash": "\\", "QuoteLeft": "`"}


static func code_name(code: int) -> String:
	if code == 0:
		return "-"
	if is_mouse(code):
		return str(MOUSE_NAMES.get(-code, "MOUSE %d" % -code))
	return keycode_name(code)


static func keycode_name(key: int) -> String:
	var n := OS.get_keycode_string(key)
	return str(SHORT_NAMES.get(n, n.to_upper()))


# --- Bindings --------------------------------------------------------------------------

## The action's codes per slot (length SLOTS, 0 = empty).
func get_slots(id: String) -> Array[int]:
	var out: Array[int] = []
	var src: Array = ACTIONS[id]["keys"]
	var overrides: Dictionary = Settings.bindings
	if overrides.has(id):
		var v: Variant = overrides[id]
		src = v if v is Array else [int(v)]  # v1 settings stored one int
	for i in SLOTS:
		out.append(int(src[i]) if i < src.size() else 0)
	return out


## Non-empty codes (old API name).
func get_keys(id: String) -> Array:
	return get_slots(id).filter(func(c: int) -> bool: return c != 0)


func default_slots(id: String) -> Array[int]:
	var out: Array[int] = []
	var src: Array = ACTIONS[id]["keys"]
	for i in SLOTS:
		out.append(int(src[i]) if i < src.size() else 0)
	return out


func is_default(id: String) -> bool:
	return get_slots(id) == default_slots(id)


func apply_bindings() -> void:
	for id: String in ACTIONS:
		if InputMap.has_action(id):
			InputMap.action_erase_events(id)
		else:
			InputMap.add_action(id)
		for code in get_keys(id):
			InputMap.action_add_event(id, event_for(code))
	# Menus follow the movement bindings (plus the fixed arrows).
	for ui: String in UI_FROM:
		if not InputMap.has_action(ui):
			continue
		for ev in _ui_added:
			if InputMap.action_has_event(ui, ev):
				InputMap.action_erase_event(ui, ev)
	_ui_added.clear()
	for ui: String in UI_FROM:
		if not InputMap.has_action(ui):
			continue
		for code in get_keys(UI_FROM[ui]):
			if code == UI_FIXED[ui]:
				continue
			var ev := event_for(code)
			InputMap.action_add_event(ui, ev)
			_ui_added.append(ev)
	bindings_changed.emit()


func context_of(id: String) -> String:
	return str(CATEGORIES.get(str(ACTIONS[id]["group"]), "global"))


static func contexts_clash(a: String, b: String) -> bool:
	return a == b or a == "global" or b == "global"


## Other actions sharing `code` in an overlapping context.
func conflicts_for(id: String, code: int) -> Array[String]:
	var out: Array[String] = []
	if code == 0:
		return out
	for other: String in ACTIONS:
		if other != id and get_keys(other).has(code) and contexts_clash(context_of(id), context_of(other)):
			out.append(other)
	return out


## Every action whose binding clashes with something else.
func all_conflicts() -> Dictionary:
	var out := {}
	for id: String in ACTIONS:
		for code in get_keys(id):
			var c := conflicts_for(id, code)
			if not c.is_empty():
				out[id] = c
	return out


## Binds `code` to slot `slot` of `id`. mode: "keep" leaves conflicting
## actions alone (duplicate allowed), "swap" moves this action's old code
## onto them. Returns the conflicting action ids found.
func rebind(id: String, code: int, slot: int = 0, mode: String = "swap") -> Array[String]:
	var hit: Array[String] = []
	if not ACTIONS.has(id) or code == 0 or slot < 0 or slot >= SLOTS:
		return hit
	hit = conflicts_for(id, code)
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	var mine := get_slots(id)
	var old := mine[slot]
	if mode == "swap":
		for other in hit:
			var os := get_slots(other)
			for i in SLOTS:
				if os[i] == code:
					os[i] = old
			overrides[other] = os
	# The same code twice on one action is pointless.
	for i in SLOTS:
		if i != slot and mine[i] == code:
			mine[i] = 0
	mine[slot] = code
	overrides[id] = mine
	Settings.set_value("bindings", overrides)
	return hit


func clear_slot(id: String, slot: int) -> void:
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	var mine := get_slots(id)
	mine[slot] = 0
	overrides[id] = mine
	Settings.set_value("bindings", overrides)


func reset_action(id: String) -> void:
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	overrides.erase(id)
	Settings.set_value("bindings", overrides)


func reset_bindings() -> void:
	Settings.set_value("bindings", {})


func key_name(id: String) -> String:
	var keys := get_keys(id)
	return code_name(int(keys[0])) if not keys.is_empty() else "-"


## "[E]"-style hint for UI labels.
func hint(id: String) -> String:
	return "[%s]" % key_name(id)
