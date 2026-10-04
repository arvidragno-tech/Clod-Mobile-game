extends Node
## Keyboard + mouse control scheme for the PC version. Registers every game
## action in the InputMap with its default keys, applies the player's remaps
## from Settings, and exposes rebinding for the Controls settings tab.
## WASD / arrows also drive the built-in ui_* focus actions, so every menu is
## fully keyboard-navigable.

signal bindings_changed

## id -> {label, group, keys: Array[Key]}. Order is the Controls tab order.
const ACTIONS := {
	"pause": {"label": "Pause / back", "group": "General", "keys": [KEY_ESCAPE]},
	"cycle_panel": {"label": "Cycle panels", "group": "General", "keys": [KEY_TAB]},
	"interact": {"label": "Interact", "group": "General", "keys": [KEY_E]},
	"context": {"label": "Contextual action", "group": "General", "keys": [KEY_SPACE]},
	"inspect": {"label": "Inspect / contextual", "group": "General", "keys": [KEY_F]},
	"quicksave": {"label": "Quick save", "group": "General", "keys": [KEY_F5]},
	"quickload": {"label": "Quick load", "group": "General", "keys": [KEY_F9]},
	"inventory": {"label": "Inventory", "group": "Screens", "keys": [KEY_I]},
	"customer_info": {"label": "Customer information", "group": "Screens", "keys": [KEY_C]},
	"map": {"label": "City map", "group": "Screens", "keys": [KEY_M]},
	"facility": {"label": "Facility and property", "group": "Screens", "keys": [KEY_K]},
	"business": {"label": "Business ledger", "group": "Screens", "keys": [KEY_L]},
	"journal": {"label": "Journal (dossier)", "group": "Screens", "keys": [KEY_J]},
	"database": {"label": "Cyberware database", "group": "Screens", "keys": [KEY_B]},
	"tool_prev": {"label": "Previous tool", "group": "Surgery", "keys": [KEY_Q]},
	"tool_next": {"label": "Next tool", "group": "Surgery", "keys": [KEY_R]},
	"quick_coag": {"label": "Emergency: COAG", "group": "Surgery", "keys": [KEY_Z]},
	"quick_sedate": {"label": "Emergency: SEDATE", "group": "Surgery", "keys": [KEY_X]},
	"quick_stabilize": {"label": "Emergency: STABIL", "group": "Surgery", "keys": [KEY_V]},
	"rotate_left": {"label": "Rotate implant left", "group": "Surgery", "keys": [KEY_COMMA]},
	"rotate_right": {"label": "Rotate implant right", "group": "Surgery", "keys": [KEY_PERIOD]},
	"zoom_in": {"label": "Zoom in", "group": "Surgery", "keys": [KEY_EQUAL]},
	"zoom_out": {"label": "Zoom out", "group": "Surgery", "keys": [KEY_MINUS]},
	"tool_1": {"label": "Tool slot 1", "group": "Tool slots", "keys": [KEY_1]},
	"tool_2": {"label": "Tool slot 2", "group": "Tool slots", "keys": [KEY_2]},
	"tool_3": {"label": "Tool slot 3", "group": "Tool slots", "keys": [KEY_3]},
	"tool_4": {"label": "Tool slot 4", "group": "Tool slots", "keys": [KEY_4]},
	"tool_5": {"label": "Tool slot 5", "group": "Tool slots", "keys": [KEY_5]},
	"tool_6": {"label": "Tool slot 6", "group": "Tool slots", "keys": [KEY_6]},
	"tool_7": {"label": "Tool slot 7", "group": "Tool slots", "keys": [KEY_7]},
	"tool_8": {"label": "Tool slot 8", "group": "Tool slots", "keys": [KEY_8]},
	"tool_9": {"label": "Tool slot 9", "group": "Tool slots", "keys": [KEY_9]},
}
## Extra keys on Godot's built-in UI actions (menu navigation).
const UI_EXTRA := {"ui_up": KEY_W, "ui_down": KEY_S, "ui_left": KEY_A, "ui_right": KEY_D}


func _ready() -> void:
	for ui_action: String in UI_EXTRA:
		if InputMap.has_action(ui_action):
			var ev := InputEventKey.new()
			ev.physical_keycode = UI_EXTRA[ui_action]
			InputMap.action_add_event(ui_action, ev)
	apply_bindings()
	Settings.changed.connect(apply_bindings)


## Rebuilds every game action from defaults + Settings.bindings overrides.
func apply_bindings() -> void:
	for id: String in ACTIONS:
		if InputMap.has_action(id):
			InputMap.action_erase_events(id)
		else:
			InputMap.add_action(id)
		for key: int in get_keys(id):
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(id, ev)
	bindings_changed.emit()


func get_keys(id: String) -> Array:
	var overrides: Dictionary = Settings.bindings
	if overrides.has(id):
		return [int(overrides[id])]
	return ACTIONS[id]["keys"]


const SHORT_NAMES := {"Escape": "ESC", "Comma": ",", "Period": ".", "Equal": "=", "Minus": "-",
	"Backspace": "BKSP", "Enter": "ENTER", "Space": "SPACE", "Tab": "TAB", "Slash": "/", "Semicolon": ";",
	"Apostrophe": "'", "BracketLeft": "[", "BracketRight": "]", "Backslash": "\\", "QuoteLeft": "`"}


func key_name(id: String) -> String:
	var keys := get_keys(id)
	return keycode_name(keys[0]) if not keys.is_empty() else "-"


static func keycode_name(key: int) -> String:
	var n := OS.get_keycode_string(key)
	return str(SHORT_NAMES.get(n, n.to_upper()))


## Rebinds an action to a key. A key already used by another action in a
## conflicting group is swapped onto that action so nothing is left unbound.
func rebind(id: String, key: int) -> String:
	if not ACTIONS.has(id) or key == KEY_NONE:
		return ""
	var swapped := ""
	var old := get_keys(id)
	var overrides: Dictionary = Settings.bindings.duplicate()
	for other: String in ACTIONS:
		if other != id and int(get_keys(other)[0]) == key:
			overrides[other] = int(old[0]) if not old.is_empty() else KEY_NONE
			swapped = other
	overrides[id] = key
	Settings.set_value("bindings", overrides)
	return swapped


func reset_bindings() -> void:
	Settings.set_value("bindings", {})


## "[E]"-style hint for UI labels.
func hint(id: String) -> String:
	return "[%s]" % key_name(id)
