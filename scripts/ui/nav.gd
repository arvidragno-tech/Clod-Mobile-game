class_name Nav
extends RefCounted
## Follows a link from guidance, recent changes, follows and results to the
## thing it points at. A link is a Dictionary with one of:
##   {"screen": id, "params": {...}}       open a screen (journal tab by tab_name)
##   {"location": id}                       the city map, centred on the place
##   {"customer": true}                     the patient at the door (their file)
##   {"term": "heat"}                       the field-guide card for a word
##   {"panel": "changes"}                   the recent-changes panel
##   {"doors": "open"}                      open (or close) the clinic doors
##   {"answer": true}                       bring back the decision or conversation that's waiting
## Unknown or stale links do nothing (never a dead click into an error).


static func can_open(link: Dictionary) -> bool:
	if link.is_empty():
		return false
	if link.has("customer"):
		return CustomerManager.has_customer()
	if link.has("location"):
		return LocationManager.get_location(StringName(str(link["location"]))).size() > 0
	if link.has("answer"):
		return EventManager.has_pending() or StoryManager.has_talk() or StoryManager.has_cutscene()
	return link.has("screen") or link.has("term") or link.has("panel") or link.has("doors")


static func open(link: Dictionary) -> void:
	if not can_open(link):
		return
	Glossary.close()
	if link.has("customer"):
		GameManager.show_patient_summary()
	elif link.has("location"):
		# A link to a place makes the city relevant (Features).
		Features.introduce(&"map")
		UIManager.go_to(UIManager.SCREEN_MAP, {"location": StringName(str(link["location"]))})
	elif link.has("term"):
		Glossary.show(str(link["term"]))
	elif link.has("answer"):
		# The clinic shows what's waiting (decision > scene > conversation).
		if UIManager.current_screen_id == UIManager.SCREEN_CLINIC and UIManager.current_screen.has_method("resume_story"):
			UIManager.current_screen.resume_story()
		else:
			GameManager.go_to_clinic()
	elif link.has("doors"):
		BusinessManager.set_doors_open(str(link["doors"]) == "open")
	elif link.has("panel"):
		if str(link["panel"]) == "changes":
			ChangesPanel.open()
	else:
		var id := StringName(str(link["screen"]))
		# Following a link to a section introduces it: it's relevant now.
		if Features.BY_SCREEN.has(id):
			Features.introduce(Features.BY_SCREEN[id])
		if id == UIManager.SCREEN_CLINIC:
			GameManager.go_to_clinic()
		else:
			UIManager.go_to(id, link.get("params", {}))
