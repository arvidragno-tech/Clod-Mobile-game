extends RefCounted
## A story conversation that is open when the game saves (the window loses
## focus, is closed, the game quits) survives the reload: it is waiting
## again, picks up on the line it was on, and nothing it already did (node
## effects, choices) happens twice. Covers Voss's ultimatum, which is the
## only way out of act IV once Moor has been turned down.
## Run by tests/test_runner.gd.

const TEST_DIALOGUE := "t_resume_probe"

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	var cs_was := CutscenePlayer.enabled
	GameManager.is_running = true
	CutscenePlayer.enabled = false
	SaveManager.reset_all()
	_open_conversation_survives_reload()
	_effects_never_run_twice()
	_finished_conversation_is_not_resumed()
	_voss_ultimatum_reaches_act_five()
	_old_saves_load()
	DialogueManager.dialogues.erase(TEST_DIALOGUE)
	DialogueManager.current_id = &""
	SaveManager.reset_all()
	CutscenePlayer.enabled = cs_was
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


## What the clinic does: take the next talk off the queue and open it.
func _open_next_talk() -> StringName:
	var id := StoryManager.pop_talk()
	if id != &"" and not DialogueManager.is_active():
		DialogueManager.start(id)
	return id


## The window closes (SaveManager saves on WM_CLOSE_REQUEST), the game is
## started again and the save is loaded.
func _save_quit_and_reload() -> void:
	SaveManager.save_game(&"manual")
	DialogueManager.current_id = &""  # the process ended
	SaveManager.reset_all()
	SaveManager.load_game()


func _act_four_without_evidence() -> void:
	SaveManager.reset_all()
	BusinessManager.day = 30
	StoryManager.act = 4
	StoryManager.act_started_day = 26
	for b: Variant in StoryManager.beats:
		StoryManager.fired_beats.append(str(b["id"]))
	StoryManager.fired_beats.erase("b_act5")
	StoryManager.talk_queue.clear()


func _open_conversation_survives_reload() -> void:
	_act_four_without_evidence()
	StoryManager.queue_talk(&"d_voss_ultimatum")
	_open_next_talk()
	check(DialogueManager.is_active() and not StoryManager.has_talk(), "dialogue save: the ultimatum is open and off the queue")
	_save_quit_and_reload()
	check(StoryManager.peek_talk() == &"d_voss_ultimatum", "dialogue save: after a reload the open ultimatum is waiting again")
	check(not DialogueManager.is_active(), "dialogue save: nothing is open straight after loading")
	_open_next_talk()
	check(DialogueManager.current_id == &"d_voss_ultimatum" and DialogueManager.current_node_id == "start", "dialogue save: it opens on Voss's first line")
	check(DialogueManager.options().size() >= 2, "dialogue save: its answers are there")
	# A second save/reload while it's open again changes nothing.
	_save_quit_and_reload()
	check(StoryManager.talk_queue.count("d_voss_ultimatum") == 1, "dialogue save: a second reload queues it once, not twice")
	DialogueManager.current_id = &""


## A made-up conversation whose every step costs or pays money, so a step
## that runs twice shows up in the balance.
func _effects_never_run_twice() -> void:
	DialogueManager.dialogues[TEST_DIALOGUE] = {
		"id": TEST_DIALOGUE, "character": "", "title": "Probe", "start": "start",
		"nodes": {
			"start": {"text": "First line.", "speaker": "npc", "effects": {"money": 100, "flag": "t_resume_start"},
				"options": [{"text": "Go on.", "kind": "plain", "next": "middle", "effects": {"money": 10}}]},
			"middle": {"text": "Second line.", "speaker": "npc", "effects": {"money": 1000},
				"options": [{"text": "Done.", "kind": "plain", "next": "", "effects": {"money": 5}}]},
		},
	}
	SaveManager.reset_all()
	var base := EconomyManager.money
	StoryManager.queue_talk(StringName(TEST_DIALOGUE))
	_open_next_talk()
	check(EconomyManager.money == base + 100, "dialogue save: the first line's effect ran once (+100)")
	_save_quit_and_reload()
	check(EconomyManager.money == base + 100, "dialogue save: the reload keeps it (+100)")
	_open_next_talk()
	check(EconomyManager.money == base + 100 and DialogueManager.current_node_id == "start", "dialogue save: reopening resumes the first line without paying it again")
	DialogueManager.choose(0)
	check(EconomyManager.money == base + 1110 and DialogueManager.current_node_id == "middle", "dialogue save: the answer and the next line ran once (+1110)")
	var choices := DialogueManager.choices.size()
	var log_size := DialogueManager.log_lines.size()
	_save_quit_and_reload()
	check(EconomyManager.money == base + 1110, "dialogue save: a reload mid-conversation keeps the balance")
	_open_next_talk()
	check(DialogueManager.current_node_id == "middle", "dialogue save: it resumes on the line it was on, not from the start")
	check(EconomyManager.money == base + 1110, "dialogue save: resuming runs no effect again")
	check(DialogueManager.choices.size() == choices and DialogueManager.log_lines.size() == log_size, "dialogue save: the answer log and the conversation so far come back as they were")
	DialogueManager.choose(0)
	check(EconomyManager.money == base + 1115 and not DialogueManager.is_active(), "dialogue save: finishing pays the last answer once and ends it")


func _finished_conversation_is_not_resumed() -> void:
	SaveManager.reset_all()
	var base := EconomyManager.money
	StoryManager.queue_talk(StringName(TEST_DIALOGUE))
	_open_next_talk()
	DialogueManager.choose(0)
	DialogueManager.choose(0)
	check(not DialogueManager.is_active(), "dialogue save: the conversation ended")
	_save_quit_and_reload()
	check(not StoryManager.talk_queue.has(TEST_DIALOGUE), "dialogue save: a finished conversation is not queued again")
	# Started fresh later (a repeatable talk), it starts from the top.
	DialogueManager.start(StringName(TEST_DIALOGUE))
	check(DialogueManager.current_node_id == "start" and EconomyManager.money == base + 1215, "dialogue save: started again later, it begins at the start")
	DialogueManager.current_id = &""


func _voss_ultimatum_reaches_act_five() -> void:
	_act_four_without_evidence()
	for f in ["evidence_given", "evidence_sold", "joined_lyra", "voss_backed_down", "thread_partner", "clinic_burned"]:
		check(not StoryManager.has_flag(StringName(f)), "dialogue save: no act IV exit flag (%s) before the ultimatum" % f)
	StoryManager.queue_talk(&"d_voss_ultimatum")
	_open_next_talk()
	_save_quit_and_reload()
	StoryManager.check()
	check(StoryManager.act == 4, "dialogue save: still act IV while the ultimatum waits")
	_open_next_talk()
	# "Get out." (always shown, needs nothing).
	var get_out := -1
	for o: Dictionary in DialogueManager.options():
		if str(o["text"]) == "Get out.":
			get_out = int(o["index"])
	check(get_out >= 0, "dialogue save: GET OUT is offered")
	DialogueManager.choose(get_out)
	if DialogueManager.is_active():
		DialogueManager.advance()
	check(StoryManager.has_flag(&"clinic_burned"), "dialogue save: the answer sets clinic_burned")
	check(StoryManager.act == 5, "dialogue save: act V begins after the reloaded ultimatum (act %d)" % StoryManager.act)
	check(StoryManager.talk_queue.has("d_finale"), "dialogue save: the finale conversation is queued")
	DialogueManager.current_id = &""


## Saves written before 3.12.1 have no open-conversation entry.
func _old_saves_load() -> void:
	SaveManager.reset_all()
	DialogueManager.load_save_data({"choices": [{"dialogue": "d_ilse_intro", "node": "start", "option": "x", "kind": "plain", "success": true, "day": 1}]})
	check(DialogueManager.choices.size() == 1 and not DialogueManager.is_active(), "dialogue save: an old save's dialogue data loads with nothing to resume")
	DialogueManager.start(&"d_ilse_intro")
	check(DialogueManager.current_node_id == str(DialogueManager.get_dialogue().get("start", "start")), "dialogue save: after an old save conversations start at the top")
	DialogueManager.current_id = &""
