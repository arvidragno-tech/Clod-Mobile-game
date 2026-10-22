extends RefCounted
## A cost you can't refuse (a fine, a crew's cut, the rent, severance) is
## paid the same way wherever it comes from: the cash covers what it can and
## the rest becomes debt, and the whole amount shows in the day's ledger.
## Events, conversations, firing and the night's bills agree. (A cost you
## choose to pay is never taken on credit: resource_cost_tests.)
## Run by tests/test_runner.gd.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var was := GameManager.is_running
	GameManager.is_running = true
	SaveManager.reset_all()
	_every_path_agrees()
	_exact_and_zero()
	_firing_with_no_cash()
	_debt_survives_save()
	SaveManager.reset_all()
	GameManager.is_running = was


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _setup(cash: int) -> void:
	SaveManager.reset_all()
	EconomyManager.money = cash
	BusinessManager.debt = 0
	BusinessManager.today.clear()


## A 400 cr fine with 50 cr in the drawer: 0 cash, 350 owed, -400 on the books.
func _every_path_agrees() -> void:
	var paths := {
		"event outcome": func() -> void: EventManager.apply_outcomes({"money": -400}),
		"event story effect": func() -> void: EventManager.apply_outcomes({"effects": {"money": -400}}),
		"conversation effect": func() -> void: StoryManager.apply_effects({"money": -400}),
		"night bill": func() -> void: BusinessManager.charge(&"rent", 400),
	}
	for k: String in paths:
		_setup(50)
		(paths[k] as Callable).call()
		var cat := &"rent" if k == "night bill" else &"events"
		check(EconomyManager.money == 0 and BusinessManager.debt == 350, "%s: a 400 fine with 50 cash leaves 0 cash and 350 owed (cash %d, debt %d)" % [k, EconomyManager.money, BusinessManager.debt])
		check(int(BusinessManager.today.get(cat, 0)) == -400, "%s: the ledger shows the whole 400 (%d)" % [k, int(BusinessManager.today.get(cat, 0))])


func _exact_and_zero() -> void:
	_setup(400)
	EventManager.apply_outcomes({"money": -400})
	check(EconomyManager.money == 0 and BusinessManager.debt == 0, "exactly enough cash: paid in full, nothing owed")
	_setup(0)
	StoryManager.apply_effects({"money": -400})
	check(EconomyManager.money == 0 and BusinessManager.debt == 400 and int(BusinessManager.today.get(&"events", 0)) == -400, "no cash at all: the whole fine is owed and booked")
	_setup(1000)
	check(BusinessManager.charge(&"events", 400) == 400 and EconomyManager.money == 600 and BusinessManager.debt == 0, "plenty of cash: paid, nothing owed")


func _firing_with_no_cash() -> void:
	_setup(0)
	var e := StaffManager.generate_candidate()
	StaffManager.employees.append(e)
	StaffManager.fire(StringName(str(e["id"])))
	check(BusinessManager.debt == int(e["salary"]) and int(BusinessManager.today.get(&"salaries", 0)) == -int(e["salary"]),
		"severance you can't pay is owed, not forgotten (%d of %d)" % [BusinessManager.debt, int(e["salary"])])


func _debt_survives_save() -> void:
	_setup(50)
	EventManager.apply_outcomes({"money": -400})
	SaveManager.save_game(&"manual")
	SaveManager.reset_all()
	check(SaveManager.load_game() and BusinessManager.debt == 350 and EconomyManager.money == 0, "what a fine left owing is still owed after a reload")
