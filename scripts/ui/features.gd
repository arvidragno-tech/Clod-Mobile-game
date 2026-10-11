class_name Features
extends RefCounted
## PROGRESSIVE FEATURES: which parts of the clinic a player has been
## introduced to. A section appears in the side bar (and its hotkey and
## room prop work) once it is relevant, with a short card saying what it
## is, why it matters, how to use it and what it costs. Nothing shows as a
## padlock in the meantime.
##
## The state (which features were introduced, on which day, which intro
## cards are still to show) lives in TutorialManager, which is saved; this
## class holds the rules and the texts. The rules only read existing state
## (Difficulty.ops(), skill points, quests, staff, the black market's own
## unlock...), so a missing flag can never lock a feature: refresh()
## re-introduces anything that is relevant.
##
## Stages (Difficulty: LEARNING ops 0-2, STREET 3-7, UNDERCITY 8+):
##  1-2  first patient, first operation: CLINIC (+ SETTINGS, FIELD GUIDE)
##  3    after the first job: SKILLS, SUPPLY, INVENTORY, BUSINESS, JOURNAL
##  3+   the second job: CYBERWARE DB
##  4    three jobs in: STAFF, FACILITY
##  5    the city: CITY MAP (four jobs, or a lead that points at a place),
##       BLACK MARKET (its own rule: street rep or a contact)

## id (= side-bar id) -> {title, screen, stage, what, why, how, cost, term}
const LIST := {
	&"skills": {"title": "SKILLS", "screen": &"skills", "stage": 3, "term": "loop",
		"what": "Skill points you earn by levelling up.",
		"why": "Steadier hands, better odds and new techniques.",
		"how": "Open SKILLS and spend a point on surgery, cybernetics, medicine or the underworld.",
		"cost": "Free: points come from experience."},
	&"supply": {"title": "SUPPLY", "screen": &"shop", "stage": 3, "term": "supplies",
		"what": "Where you buy implants, tools and medical supplies.",
		"why": "Every operation uses supplies, and better tools lower your risk.",
		"how": "Open SUPPLY; each item shows what it costs and your cash after buying.",
		"cost": "Credits. Keep a night's rent in hand."},
	&"inventory": {"title": "INVENTORY", "screen": &"inventory", "stage": 3, "term": "condition",
		"what": "Everything you own: implants in stock, tools, supplies.",
		"why": "A unit in stock is one you don't have to buy for the next job.",
		"how": "Compare units, check condition and hidden traits, sell what you don't need.",
		"cost": "None."},
	&"business": {"title": "BUSINESS", "screen": &"business", "stage": 3, "term": "outlook",
		"what": "Today's money: income, bills, debts both ways and an outlook.",
		"why": "Payment isn't profit: rent, running costs and wages are paid every night.",
		"how": "Check the OUTLOOK before you spend; settle debts here.",
		"cost": "None."},
	&"dossier": {"title": "JOURNAL", "screen": &"dossier", "stage": 3, "term": "follow",
		"what": "Messages, objectives, people you've met, your standing and the story.",
		"why": "People write back, quests have deadlines, and your reputation opens doors.",
		"how": "MAIN shows what you follow and what's waiting for an answer.",
		"cost": "None."},
	&"database": {"title": "CYBERWARE DB", "screen": &"database", "stage": 3, "term": "tier",
		"what": "Every implant: what it does, its neural load, how hard it is to fit.",
		"why": "Knowing the chrome tells you which jobs you can take.",
		"how": "Search or compare models side by side.",
		"cost": "None."},
	&"staff": {"title": "STAFF", "screen": &"staff", "stage": 4, "term": "stress",
		"what": "Ripperdocs you can hire to take jobs for you.",
		"why": "More jobs a day, and a second pair of hands when you're out.",
		"how": "Hire in STAFF; hand a patient over from their file (MORE DETAILS > ASSIGN).",
		"cost": "A hiring fee and a nightly wage. Stress and loyalty need watching."},
	&"upgrades": {"title": "FACILITY", "screen": &"upgrades", "stage": 4, "term": "tier",
		"what": "Clinic upgrades and new clinics in better districts.",
		"why": "Better rooms take more jobs and richer patients.",
		"how": "Each upgrade shows its cost, your cash after and what it changes.",
		"cost": "One-off prices; better clinics also cost more rent."},
	&"map": {"title": "CITY MAP", "screen": &"map", "stage": 5, "term": "travel",
		"what": "The city: places, people, services and leads.",
		"why": "Contacts, cheaper suppliers, quests and trouble all live out there.",
		"how": "Pick a place: the panel shows travel time and cost before you go.",
		"cost": "Time (the clinic waits) and sometimes money or danger."},
	&"blackmarket": {"title": "BLACK MARKET", "screen": &"black_market", "stage": 5, "term": "black_market",
		"what": "Chrome with no paperwork: cheap, strong, sometimes cursed.",
		"why": "Rare parts at a discount.",
		"how": "Unknown traits show as ??; patients pay less for a part without paperwork.",
		"cost": "Every buy raises authority heat."},
}

## Screen -> feature, for hotkeys and links.
const BY_SCREEN := {&"skills": &"skills", &"shop": &"supply", &"inventory": &"inventory", &"business": &"business",
	&"dossier": &"dossier", &"database": &"database", &"staff": &"staff", &"upgrades": &"upgrades", &"map": &"map",
	&"black_market": &"blackmarket", &"location": &"map"}


static func progressive() -> bool:
	return Settings.progressive_features


## Is the feature available to the player right now?
static func is_on(id: StringName) -> bool:
	if not LIST.has(id):
		return true
	if id == &"blackmarket" and not BlackMarketManager.is_unlocked():
		return false  # its own rule, as before (no contact yet)
	if not progressive():
		return true
	return TutorialManager.introduced.has(String(id))


static func screen_on(screen: StringName) -> bool:
	return is_on(BY_SCREEN.get(screen, &""))


## Has it become relevant (the rule, from existing game state)?
static func relevant(id: StringName) -> bool:
	var ops := Difficulty.ops()
	match id:
		&"skills":
			return ops >= 1  # everyone starts with a point: it matters after the first job
		&"supply":
			return ops >= 1 or InventoryManager.supplies <= 2
		&"inventory":
			return ops >= 1
		&"business":
			return ops >= 1 or BusinessManager.day >= 2 or BusinessManager.debt > 0
		&"dossier":
			return ops >= 1 or CommsManager.unread_count() > 0
		&"database":
			return ops >= 2
		&"staff":
			return ops >= 3 or StaffManager.count() > 0
		&"upgrades":
			return ops >= 3 or ClinicManager.tier > 0
		&"map":
			# Also when a lead points at a place (Nav.open introduces it on the click).
			return ops >= 4 or LocationManager.is_away()
		&"blackmarket":
			return BlackMarketManager.is_unlocked()
	return true


## Introduces everything that has become relevant (queues its intro card).
## Cheap: a handful of reads; called on events, never every frame.
static func refresh() -> void:
	if not GameManager.is_running:
		return
	for id: StringName in LIST:
		if not TutorialManager.introduced.has(String(id)) and relevant(id):
			introduce(id)


## Marks a feature introduced (a contextual link to it counts: it's relevant).
static func introduce(id: StringName, with_card: bool = true) -> void:
	var key := String(id)
	if not LIST.has(id) or TutorialManager.introduced.has(key):
		return
	TutorialManager.introduced[key] = BusinessManager.day
	if with_card and progressive():
		TutorialManager.intro_pending.append(key)
	EventBus.resources_changed.emit()  # the side bar and the field guide refresh


## Features introduced in the last `days` days (NEW marks).
static func is_new(id: StringName, days: int = 1) -> bool:
	var key := String(id)
	return TutorialManager.introduced.has(key) and BusinessManager.day - int(TutorialManager.introduced[key]) <= days


## A short toast for a hotkey or prop whose section isn't open yet.
static func not_yet(id: StringName) -> void:
	var f: Dictionary = LIST.get(id, {})
	var when: String = {3: "after your first job", 4: "once the clinic is running (a few jobs in)", 5: "when the city calls"}.get(int(f.get("stage", 3)), "later")
	UIManager.show_toast("%s opens up %s." % [str(f.get("title", "That")), when], &"info")


## The intro card for the next newly introduced feature, if it's a good
## moment (on the clinic, nothing else open, not operating or talking).
static func show_next_intro() -> bool:
	if TutorialManager.intro_pending.is_empty() or TutorialManager.is_active() or not Hints.enabled:
		return false
	if UIManager.has_modal() or Glossary.is_open() or Hints.is_showing() or SurgeryManager.is_active or DialogueManager.is_active():
		return false
	var key: String = TutorialManager.intro_pending.pop_front()
	var id := StringName(key)
	if Settings.is_minimal():
		UIManager.show_toast("New in the side bar: %s" % str(LIST[id]["title"]), &"info")
		return true
	show_intro(id)
	return true


## The card itself (also used by the field guide's TUTORIALS to show it again).
static func show_intro(id: StringName) -> void:
	var f: Dictionary = LIST.get(id, {})
	if f.is_empty():
		return
	var h := Hints._host()
	if h == null:
		return
	Hints.dismiss()
	var card := UIKit.panel(&"AccentPanel")
	card.name = "FeatureCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(card)
	var v := UIKit.vbox(6)
	card.add_child(v)
	v.add_child(UIKit.label("NEW · %s" % str(f["title"]), &"SubHeaderLabel", false, Palette.ACCENT))
	for pair: Array in [["WHAT", "what"], ["WHY", "why"], ["HOW", "how"], ["COST", "cost"]]:
		var row := UIKit.hbox(8)
		v.add_child(row)
		var cap := UIKit.caption(str(pair[0]))
		cap.custom_minimum_size.x = 64
		row.add_child(cap)
		var body := UIKit.label(str(f[pair[1]]), &"", true, Palette.TEXT, 15)
		body.custom_minimum_size.x = 420
		row.add_child(body)
	var buttons := UIKit.hbox(8)
	v.add_child(buttons)
	var screen: StringName = f["screen"]
	var open := UIKit.button("OPEN %s" % str(f["title"]), &"AccentButton", func() -> void:
		Hints.dismiss()
		GameManager.navigate(id), "FeatureOpen", 34)
	open.focus_mode = Control.FOCUS_NONE
	open.disabled = screen == &"black_market" and not BlackMarketManager.is_unlocked()
	buttons.add_child(open)
	var term := str(f["term"])
	var more := UIKit.button("MORE", &"GhostButton", func() -> void:
		Hints.dismiss()
		Glossary.open_guide(str(Glossary.entry(term).get("topic", "basics")), term), "FeatureMore", 34)
	more.focus_mode = Control.FOCUS_NONE
	buttons.add_child(more)
	var ok := UIKit.button("GOT IT", &"GhostButton", Hints.dismiss, "FeatureClose", 34)
	ok.focus_mode = Control.FOCUS_NONE
	buttons.add_child(ok)
	card.reset_size()
	var vp := h.get_viewport_rect().size
	var sz := card.get_combined_minimum_size()
	# Top right, over the room: never over the status cards or a button row.
	card.position = Vector2(vp.x - sz.x - 32, 140).floor()
	AudioManager.play_sfx(&"unlock", 0.0)
