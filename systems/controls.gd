extends Node
## Keyboard + mouse control scheme. Registers every game action in the
## InputMap with its default bindings, applies the player's remaps from
## Settings, and powers the Controls settings tab: two slots per action
## (each a key or a mouse button), duplicate / conflict detection per
## context, reset one binding or all of them. Movement bindings also drive
## the built-in ui_* actions, so menus follow the player's layout.
##
## A binding code is an int: a physical keycode (> 0) optionally OR-ed with
## Godot's modifier masks (KEY_MASK_CTRL / SHIFT / ALT, so CTRL+S is one
## code), or the negated mouse button index for mouse buttons (< 0);
## 0 = empty slot (unassigned). Gameplay never checks keys: it asks for
## actions, and InputContext decides which actions a moment accepts.
##
## Critical actions (pause/back, continue, contextual action) always keep at
## least one binding. Presets are named sets of overrides; any other set of
## bindings is CUSTOM.

signal bindings_changed

const SLOTS := 2

## Categories in display order; context decides which actions can clash
## (global ones clash with everything).
const CATEGORIES := {
	"Movement": "global", "Interaction": "global", "Surgery": "surgery", "Tools": "surgery", "Inventory": "global",
	"Map": "global", "Journal": "global", "Dialogue": "dialogue", "Camera": "surgery", "General": "global",
}
## Player-facing names for the categories (Settings > Controls).
const CATEGORY_LABELS := {
	"Movement": "NAVIGATION", "Interaction": "GENERAL · INTERACT", "Surgery": "SURGERY", "Tools": "SURGERY · TOOL SLOTS",
	"Inventory": "CLINIC", "Map": "WORLD", "Journal": "WORLD · JOURNAL", "Dialogue": "DIALOGUE", "Camera": "CAMERA",
	"General": "GENERAL",
}
## Actions that must always keep at least one binding.
const CRITICAL := ["pause", "dialogue_next", "context"]

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
	"clinic": {"label": "Open clinic", "group": "Inventory", "keys": [KEY_H]},
	"inventory": {"label": "Inventory", "group": "Inventory", "keys": [KEY_I]},
	"database": {"label": "Cyberware database", "group": "Inventory", "keys": [KEY_B]},
	"supply": {"label": "Supply shop", "group": "Inventory", "keys": [KEY_U]},
	"map": {"label": "City map", "group": "Map", "keys": [KEY_M]},
	"facility": {"label": "Facility and property", "group": "Map", "keys": [KEY_K]},
	"business": {"label": "Business ledger", "group": "Map", "keys": [KEY_L]},
	"staff": {"label": "Staff", "group": "Map", "keys": [KEY_T]},
	"journal": {"label": "Journal", "group": "Journal", "keys": [KEY_J]},
	"comms": {"label": "Comms inbox", "group": "Journal", "keys": [KEY_N]},
	"changes": {"label": "Recent changes", "group": "Journal", "keys": [KEY_G]},
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
	"help": {"label": "Field guide (help)", "group": "General", "keys": [KEY_F1]},
}
## Named presets: overrides on top of the defaults (id -> slots).
const PRESETS := {
	"default": {},
	# Movement on WASD only, so the arrow keys stay free (menus still use them).
	"wasd": {"move_up": [KEY_W, 0], "move_down": [KEY_S, 0], "move_left": [KEY_A, 0], "move_right": [KEY_D, 0]},
	# Mouse in the left hand: arrows to move, the number pad for everything else.
	"left_handed": {
		"move_up": [KEY_UP, 0], "move_down": [KEY_DOWN, 0], "move_left": [KEY_LEFT, 0], "move_right": [KEY_RIGHT, 0],
		"interact": [KEY_KP_0, 0], "context": [KEY_KP_ENTER, 0], "inspect": [KEY_KP_PERIOD, -MOUSE_BUTTON_MIDDLE],
		"customer_info": [KEY_KP_5, 0], "tool_prev": [KEY_KP_7, -MOUSE_BUTTON_XBUTTON1], "tool_next": [KEY_KP_9, -MOUSE_BUTTON_XBUTTON2],
		"quick_coag": [KEY_KP_1, 0], "quick_sedate": [KEY_KP_2, 0], "quick_stabilize": [KEY_KP_3, 0],
		"rotate_left": [KEY_KP_4, 0], "rotate_right": [KEY_KP_6, 0], "zoom_in": [KEY_KP_ADD, 0], "zoom_out": [KEY_KP_SUBTRACT, 0],
		"dialogue_next": [KEY_ENTER, 0],
	},
}
const PRESET_LABELS := {"default": "DEFAULT", "wasd": "WASD", "left_handed": "LEFT-HANDED", "custom": "CUSTOM"}
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


const MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


static func event_for(code: int) -> InputEvent:
	if is_mouse(code):
		var m := InputEventMouseButton.new()
		m.button_index = -code as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = (code & KEY_CODE_MASK) as Key
	k.ctrl_pressed = code & KEY_MASK_CTRL != 0
	k.shift_pressed = code & KEY_MASK_SHIFT != 0
	k.alt_pressed = code & KEY_MASK_ALT != 0
	k.meta_pressed = code & KEY_MASK_META != 0
	return k


## Code for a pressed key / mouse button (0 if not bindable). Held
## modifiers become part of the code (CTRL+S); a modifier pressed on its
## own is bindable as itself.
static func code_for(event: InputEvent) -> int:
	var k := event as InputEventKey
	if k:
		var base := int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		if base in MODIFIER_KEYS:
			return base
		return base | (KEY_MASK_CTRL if k.ctrl_pressed else 0) | (KEY_MASK_SHIFT if k.shift_pressed else 0) \
			| (KEY_MASK_ALT if k.alt_pressed else 0) | (KEY_MASK_META if k.meta_pressed else 0)
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
	var pre := ""
	if code & KEY_MASK_CTRL:
		pre += "CTRL+"
	if code & KEY_MASK_SHIFT:
		pre += "SHIFT+"
	if code & KEY_MASK_ALT:
		pre += "ALT+"
	if code & KEY_MASK_META:
		pre += "META+"
	return pre + keycode_name(code & KEY_CODE_MASK)


static func keycode_name(key: int) -> String:
	var n := OS.get_keycode_string(key)
	if n.begins_with("Kp "):
		n = "NUM " + n.trim_prefix("Kp ")
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


## Binds `code` to slot `slot` of `id`. mode: "replace" takes the key from
## conflicting actions (they become unassigned in that slot), "swap" gives
## them this action's old key, "keep" leaves them alone (both fire, only
## sensible across contexts). Returns the conflicting action ids found.
func rebind(id: String, code: int, slot: int = 0, mode: String = "swap") -> Array[String]:
	var hit: Array[String] = []
	if not ACTIONS.has(id) or code == 0 or slot < 0 or slot >= SLOTS:
		return hit
	hit = conflicts_for(id, code)
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	var mine := get_slots(id)
	var old := mine[slot]
	if mode == "replace":
		# The other actions lose this key (a critical action keeps its last
		# key: callers check replace_blockers first and offer SWAP instead).
		for other in hit:
			if replace_blockers(id, code).has(other):
				continue
			var os := get_slots(other)
			for i in SLOTS:
				if os[i] == code:
					os[i] = 0
			overrides[other] = os
	elif mode == "swap":
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


## Unassigns one slot. Refused (returns false) when it would leave a
## critical action without any binding.
func clear_slot(id: String, slot: int) -> bool:
	var mine := get_slots(id)
	if is_critical(id) and mine.filter(func(c: int) -> bool: return c != 0).size() <= 1 and mine[slot] != 0:
		return false
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	mine[slot] = 0
	overrides[id] = mine
	Settings.set_value("bindings", overrides)
	return true


func is_critical(id: String) -> bool:
	return CRITICAL.has(id)


## Actions that would be left with no binding if `code` were taken from
## them (used to refuse REPLACE on a critical action's last key).
func replace_blockers(id: String, code: int) -> Array[String]:
	var out: Array[String] = []
	for other in conflicts_for(id, code):
		if is_critical(other) and get_keys(other).size() <= 1:
			out.append(other)
	return out


func is_unassigned(id: String) -> bool:
	return get_keys(id).is_empty()


func reset_category(group: String) -> void:
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	for id: String in ACTIONS:
		if str(ACTIONS[id]["group"]) == group:
			overrides.erase(id)
	Settings.set_value("bindings", overrides)


func actions_in(group: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ACTIONS:
		if str(ACTIONS[id]["group"]) == group:
			out.append(id)
	return out


## Actions whose label, category or current keys match `q` ("map" finds
## Open map, zoom...; "f5" finds Quick save).
func search(q: String) -> Array[String]:
	var out: Array[String] = []
	var t := q.strip_edges().to_lower()
	for id: String in ACTIONS:
		var a: Dictionary = ACTIONS[id]
		var hay := ("%s %s %s %s" % [a["label"], a["group"], CATEGORY_LABELS.get(a["group"], ""), id]).to_lower()
		for c in get_keys(id):
			hay += " " + code_name(c).to_lower()
		if t == "" or hay.contains(t):
			out.append(id)
	return out


# --- Presets ---------------------------------------------------------------------------

func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	Settings.set_value("bindings", (PRESETS[name] as Dictionary).duplicate(true))


## The preset the current bindings match, or "custom".
func current_preset() -> String:
	for name: String in PRESETS:
		if _same_as(PRESETS[name]):
			return name
	return "custom"


func _same_as(preset: Dictionary) -> bool:
	for id: String in ACTIONS:
		var want: Array[int] = default_slots(id)
		if preset.has(id):
			want.clear()
			var src: Array = preset[id]
			for i in SLOTS:
				want.append(int(src[i]) if i < src.size() else 0)
		if get_slots(id) != want:
			return false
	return true


func reset_action(id: String) -> void:
	var overrides: Dictionary = Settings.bindings.duplicate(true)
	overrides.erase(id)
	Settings.set_value("bindings", overrides)


func reset_bindings() -> void:
	Settings.set_value("bindings", {})


func key_name(id: String) -> String:
	var keys := get_keys(id)
	return code_name(int(keys[0])) if not keys.is_empty() else "-"


## Replaces {action} tokens in a text with the player's current keys
## ("press {customer_info}" -> "press C"), so help never names a key the
## player has moved.
func fill(text: String) -> String:
	var out := text
	var rx := RegEx.new()
	rx.compile("\\{([a-z_0-9]+)\\}")
	for m in rx.search_all(text):
		var id := m.get_string(1)
		if ACTIONS.has(id):
			out = out.replace(m.get_string(0), key_name(id))
	return out


## "[E]"-style hint for UI labels.
func hint(id: String) -> String:
	return "[%s]" % key_name(id)
