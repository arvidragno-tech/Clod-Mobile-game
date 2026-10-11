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
## Unknown or stale links do nothing (never a dead click into an error).


static func can_open(link: Dictionary) -> bool:
	if link.is_empty():
		return false
	if link.has("customer"):
		return CustomerManager.has_customer()
	if link.has("location"):
		return LocationManager.get_location(StringName(str(link["location"]))).size() > 0
	return link.has("screen") or link.has("term") or link.has("panel") or link.has("doors")


static func open(link: Dictionary) -> void:
	if not can_open(link):
		return
	Glossary.close()
	if link.has("customer"):
		GameManager.open_customer()
	elif link.has("location"):
		UIManager.go_to(UIManager.SCREEN_MAP, {"location": StringName(str(link["location"]))})
	elif link.has("term"):
		Glossary.show(str(link["term"]))
	elif link.has("doors"):
		BusinessManager.set_doors_open(str(link["doors"]) == "open")
	elif link.has("panel"):
		if str(link["panel"]) == "changes":
			ChangesPanel.open()
	else:
		var id := StringName(str(link["screen"]))
		if id == UIManager.SCREEN_CLINIC:
			GameManager.go_to_clinic()
		else:
			UIManager.go_to(id, link.get("params", {}))
