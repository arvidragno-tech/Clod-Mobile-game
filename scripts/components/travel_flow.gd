class_name TravelFlow
extends RefCounted
## Going somewhere from the UI: travel (LocationManager), then whatever
## happens on the way (an encounter modal), then the destination screen.


static func go(to: StringName, mode: String = "") -> bool:
	var r := LocationManager.travel(to, mode)
	if not bool(r.get("ok", false)):
		AudioManager.play_sfx(&"denied")
		UIManager.show_toast(str(r.get("reason", "You can't go there now")), &"warn")
		return false
	AudioManager.play_sfx(&"stage", 0.0)
	UIManager.show_toast("%s · %s · %s%s" % [LocationManager.location_name(to), str(LocationManager.mode_def(str(r["mode"])).get("label", "")),
		TimeManager.duration_text(int(r["minutes"])), (" · %s" % EconomyManager.format_money(int(r["cost"]))) if int(r["cost"]) > 0 else ""], &"info")
	SaveManager.save_game()
	if WorldSimulationManager.has_encounter():
		show_encounter(func() -> void: _arrive(to))
	else:
		_arrive(to)
	return true


static func _arrive(to: StringName) -> void:
	UIManager.go_to(UIManager.SCREEN_CLINIC if to == LocationManager.CLINIC else UIManager.SCREEN_LOCATION)


## The encounter waiting for a decision, as a modal. then: after it closes.
static func show_encounter(then: Callable = Callable()) -> void:
	if not WorldSimulationManager.has_encounter() or UIManager.has_modal():
		return
	var e := WorldSimulationManager.encounter
	var panel := ChoicePanel.new()
	panel.name = "EncounterPanel"
	panel.kicker = "ON THE WAY · %s" % TimeManager.stamp()
	panel.title = "ON THE STREET"
	panel.text = str(e.get("text", ""))
	panel.choices = e.get("choices", [])
	panel.resolver = func(i: int) -> String:
		var t := WorldSimulationManager.resolve_encounter(i)
		SaveManager.save_game()
		return t
	AudioManager.play_sfx(&"event", 0.0)
	UIManager.show_modal(panel)
	if then.is_valid():
		panel.closed.connect(then)
