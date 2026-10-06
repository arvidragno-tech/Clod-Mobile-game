class_name InputContext
extends RefCounted
## Which input context the game is in right now, and what that context
## lets actions do. One place decides; UIManager routes through it.
##
## Priority (first match wins): REBIND (a key is being captured) > TEXT (a
## text field has focus) > GUIDE (field guide / help card) > DIALOGUE >
## MODAL (any other dialog, pause menu, event) > the screen's own context
## (SURGERY, MAP, INVENTORY, JOURNAL, SETTINGS, MENU, CLINIC, SCREEN).
##
## ESC is the same key everywhere and means "step back once" in the
## current context (see escape_label): stop rebinding, leave the text
## field, close the guide, close the dialog, pause the operation, go back
## to the previous screen, or open the pause menu on the clinic.

const REBIND := &"rebind"
const TEXT := &"text"
const GUIDE := &"guide"
const DIALOGUE := &"dialogue"
const MODAL := &"modal"
const SURGERY := &"surgery"
const MAP := &"map"
const INVENTORY := &"inventory"
const JOURNAL := &"journal"
const SETTINGS := &"settings"
const MENU := &"menu"
const CLINIC := &"clinic"
const SCREEN := &"screen"

## Screen -> context (anything else in-game is SCREEN).
const SCREEN_CONTEXTS := {
	&"surgery": SURGERY, &"map": MAP, &"inventory": INVENTORY, &"database": INVENTORY, &"shop": INVENTORY,
	&"dossier": JOURNAL, &"settings": SETTINGS, &"main_menu": MENU, &"load_game": MENU, &"credits": MENU,
	&"clinic": CLINIC, &"diagnosis": SURGERY,
}
## Screens that open from the global hotkeys.
const ROUTES := {
	"clinic": &"clinic", "inventory": &"inventory", "journal": &"dossier", "database": &"database", "map": &"map",
	"facility": &"upgrades", "business": &"business", "staff": &"staff", "supply": &"shop", "comms": &"dossier",
}
## Contexts where the global navigation hotkeys work.
const NAV_CONTEXTS := [CLINIC, MAP, INVENTORY, JOURNAL, SETTINGS, SCREEN]
## Screens that are not part of a running game (no hotkey navigation).
const OUT_OF_GAME := [&"main_menu", &"load_game", &"credits", &"results"]


static func current() -> StringName:
	var ui := UIManager
	var screen: Node = ui.current_screen
	if screen and screen.has_method("is_rebinding") and screen.call("is_rebinding"):
		return REBIND
	var vp := ui.get_viewport()
	var focus := vp.gui_get_focus_owner() if vp else null
	if focus is LineEdit or focus is TextEdit:
		return TEXT
	if Glossary.is_open():
		return GUIDE
	if ui.has_modal():
		var m := ui.top_modal()
		if m is DialoguePanel:
			return DIALOGUE
		return MODAL
	return SCREEN_CONTEXTS.get(ui.current_screen_id, SCREEN)


## Whether `action` may do its global job in context `ctx`.
static func allows(action: String, ctx: StringName = &"") -> bool:
	if ctx == &"":
		ctx = current()
	if ctx == REBIND or ctx == TEXT:
		return false
	match action:
		"pause":
			return true
		"help":
			return ctx != GUIDE and ctx != REBIND
		"quickload":
			return ctx in NAV_CONTEXTS or ctx == MENU
		"quicksave", "customer_info", "changes":
			return ctx in NAV_CONTEXTS and not (UIManager.current_screen_id in OUT_OF_GAME)
	if ROUTES.has(action):
		return ctx in NAV_CONTEXTS and not (UIManager.current_screen_id in OUT_OF_GAME)
	return false


## What ESC does right now, for hint strips and the field guide.
static func escape_label(ctx: StringName = &"") -> String:
	if ctx == &"":
		ctx = current()
	match ctx:
		REBIND:
			return "cancel rebinding"
		TEXT:
			return "leave the text field"
		GUIDE:
			return "close the guide"
		DIALOGUE, MODAL:
			return "close"
		SURGERY:
			return "pause the operation"
		CLINIC:
			return "pause menu"
		MENU:
			return "back"
	return "back"


## Player-facing name of a context.
static func label(ctx: StringName) -> String:
	return String(ctx).to_upper()
