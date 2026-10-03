extends Node
## Customer archetypes, the customer currently waiting in the clinic, and
## arrival scheduling.

var templates: Dictionary = {}  # StringName -> CustomerData
var current_customer: CustomerData = null

var _last_customer_id: StringName = &""
var _arrival_timer: Timer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_templates()
	_arrival_timer = Timer.new()
	_arrival_timer.one_shot = true
	_arrival_timer.timeout.connect(_on_arrival_timer_timeout)
	add_child(_arrival_timer)


func _load_templates() -> void:
	templates.clear()
	for entry: Variant in DataLoader.load_entries(GameConfig.DATA_CUSTOMERS, "customers"):
		var c := CustomerData.from_dict(entry)
		templates[c.id] = c


func reset_state() -> void:
	_arrival_timer.stop()
	current_customer = null
	_last_customer_id = &""


func has_customer() -> bool:
	return current_customer != null


func is_customer_pending() -> bool:
	return not _arrival_timer.is_stopped()


func get_customer(id: StringName) -> CustomerData:
	return templates.get(id) as CustomerData


## Schedules the next customer if nobody is waiting and nobody is on the way.
func request_next_customer(delay: float = GameConfig.CUSTOMER_ARRIVAL_DELAY_SEC) -> void:
	if has_customer() or is_customer_pending():
		return
	if delay <= 0.0:
		_on_arrival_timer_timeout()
	else:
		_arrival_timer.start(delay)


## The customer walks out (declined, or finished their operation).
func dismiss_current() -> void:
	if current_customer == null:
		return
	var leaving := current_customer
	_last_customer_id = leaving.id
	current_customer = null
	EventBus.customer_left.emit(leaving)


func _on_arrival_timer_timeout() -> void:
	var next := _pick_next_template()
	if next == null:
		push_warning("CustomerManager: no eligible customer templates")
		return
	current_customer = next
	EventBus.customer_arrived.emit(current_customer)


func _pick_next_template() -> CustomerData:
	var pool: Array[CustomerData] = []
	for c: CustomerData in templates.values():
		if c.min_reputation <= ReputationManager.reputation and c.id != _last_customer_id:
			pool.append(c)
	if pool.is_empty():
		for c: CustomerData in templates.values():
			pool.append(c)
	if pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]


func get_save_data() -> Dictionary:
	return {
		"current_customer": String(current_customer.id) if current_customer else "",
		"last_customer": String(_last_customer_id),
	}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	_last_customer_id = StringName(str(data.get("last_customer", "")))
	var id := StringName(str(data.get("current_customer", "")))
	if templates.has(id):
		current_customer = templates[id]
