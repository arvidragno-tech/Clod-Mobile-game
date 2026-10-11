extends Node
## Central stat-modifier stack. Skills, clinic tier, owned tools and timed
## event effects all contribute additive deltas per key; consumers read
## `value(key)` or `mult(key)` (= 1 + value). Keys are documented in
## docs/ARCHITECTURE.md (e.g. surgery.precision, complication.chance, pay).

var _cache: Dictionary = {}
var _dirty: bool = true


func _ready() -> void:
	EventBus.modifiers_changed.connect(invalidate)


func invalidate() -> void:
	_dirty = true


func value(key: StringName) -> float:
	if _dirty:
		_rebuild()
	return float(_cache.get(key, 0.0))


func mult(key: StringName) -> float:
	return 1.0 + value(key)


func get_all() -> Dictionary:
	if _dirty:
		_rebuild()
	return _cache.duplicate()


func _rebuild() -> void:
	_cache.clear()
	for source: Dictionary in [SkillManager.get_modifiers(), ClinicManager.get_modifiers(),
			InventoryManager.get_tool_modifiers(), EventManager.get_temp_modifiers(), TimeManager.get_modifiers(), WorldEventManager.get_modifiers(), LocationManager.get_modifiers()]:
		for key: Variant in source:
			var k := StringName(str(key))
			_cache[k] = float(_cache.get(k, 0.0)) + float(source[key])
	_dirty = false
