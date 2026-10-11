extends BaseScreen
## Save slots (PC). mode "load": load / delete a slot. mode "new": pick a
## slot for a new clinic (overwriting asks first). Three slots side by side
## with their summary: level, credits, rep, jobs, facility, last saved.

var _mode: String = "load"
var _return_to: StringName = UIManager.SCREEN_MAIN_MENU
var _row: HBoxContainer


func on_enter(params: Dictionary) -> void:
	_mode = str(params.get("mode", "load"))
	_return_to = StringName(str(params.get("return_to", UIManager.SCREEN_MAIN_MENU)))
	var bg := CityBackdrop.new()
	add_child(UIKit.full_rect(bg))
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(dim))
	var m := UIKit.full_rect(UIKit.margin(160, 90, 160, 90))
	add_child(m)
	var col := UIKit.vbox(26)
	m.add_child(col)
	col.add_child(UIKit.header("SAVE DATA · %s" % ("NEW CLINIC" if _mode == "new" else "LOAD"), "CHOOSE A SLOT" if _mode == "new" else "LOAD GAME", _back))
	_row = UIKit.hbox(24)
	UIKit.expand(_row, true, true)
	col.add_child(_row)
	col.add_child(UIKit.label("Saves are stored in %s" % ProjectSettings.globalize_path(SaveManager.save_dir), &"SubHeaderLabel", true))
	_build()


func _back() -> void:
	UIManager.go_to(_return_to)


func _build() -> void:
	UIKit.clear(_row)
	for n in range(1, GameConfig.SAVE_SLOTS + 1):
		_row.add_child(_slot_card(n))


func _slot_card(n: int) -> Control:
	var info := SaveManager.get_slot_info(n)
	var card := UIKit.panel(&"AccentPanel" if n == SaveManager.slot and not info.is_empty() else &"CardPanel")
	card.name = "Slot_%d" % n
	UIKit.expand(card, true, true)
	var v := UIKit.vbox(10)
	card.add_child(v)
	v.add_child(UIKit.label("SLOT %d" % n, &"HeaderLabel"))
	if info.is_empty():
		v.add_child(UIKit.label("EMPTY", &"BigMonoLabel", false, Palette.TEXT_DIM))
		v.add_child(UIKit.label("No clinic here yet.", &"DimLabel"))
	else:
		v.add_child(UIKit.label(str(info.get("clinic", "Basement Hole")).to_upper(), &"SubHeaderLabel"))
		v.add_child(UIKit.label("LV %d" % int(info.get("level", 1)), &"BigMonoLabel"))
		v.add_child(UIKit.label("%s   ·   REP %d   ·   %d JOBS" % [EconomyManager.format_money(int(info.get("money", 0))), int(info.get("rep", 0)), int(info.get("ops", 0))], &"MonoLabel", true, Palette.WARN))
		var when := Time.get_datetime_string_from_unix_time(int(info["saved_at"]), true) if int(info["saved_at"]) > 0 else "unknown"
		v.add_child(UIKit.label("Saved %s" % when, &"DimLabel"))
	v.add_child(UIKit.expand(Control.new(), false, true))
	if _mode == "new":
		var b := UIKit.button("START HERE" if info.is_empty() else "OVERWRITE", &"AccentButton" if info.is_empty() else &"DangerButton", func() -> void: _new_in(n, not info.is_empty()), "NewSlot_%d" % n, 54)
		v.add_child(b)
	else:
		var load := UIKit.button("LOAD", &"AccentButton", func() -> void: GameManager.load_slot(n), "LoadSlot_%d" % n, 54)
		load.disabled = info.is_empty()
		v.add_child(load)
		var del := UIKit.button("DELETE", &"GhostButton", func() -> void: _delete(n), "DeleteSlot_%d" % n)
		del.disabled = info.is_empty()
		v.add_child(del)
	return card


func _new_in(n: int, occupied: bool) -> void:
	if occupied:
		UIManager.confirm("OVERWRITE SLOT %d?" % n, "The clinic saved in this slot will be deleted.", "OVERWRITE", func() -> void: GameManager.start_new_game_in_slot(n), true)
	else:
		GameManager.start_new_game_in_slot(n)


func _delete(n: int) -> void:
	UIManager.confirm("DELETE SLOT %d?" % n, "This cannot be undone.", "DELETE", func() -> void:
		var keep := SaveManager.slot
		SaveManager.use_slot(n)
		SaveManager.delete_save()
		SaveManager.use_slot(keep)
		_build(), true)
