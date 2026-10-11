class_name DataLoader
extends RefCounted
## Loads JSON content files from res://data. JSON files are loaded through
## ResourceLoader (Godot 4 treats .json as a JSON resource), which also makes
## sure they are packed into exported builds.


static func load_entries(path: String, key: String) -> Array:
	var parsed: Variant = _load_json(path)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has(key):
		push_error("DataLoader: '%s' is missing top-level key '%s'" % [path, key])
		return []
	var entries: Variant = parsed[key]
	if typeof(entries) != TYPE_ARRAY:
		push_error("DataLoader: '%s'.%s must be an array" % [path, key])
		return []
	return entries


## Loads a whole JSON file (Dictionary or Array), or null on failure.
static func load_json(path: String) -> Variant:
	return _load_json(path)


static func _load_json(path: String) -> Variant:
	if ResourceLoader.exists(path):
		var res := load(path) as JSON
		if res != null:
			return res.data
	# Fallback for environments where .json is not handled as a resource.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: cannot open '%s'" % path)
		return null
	return JSON.parse_string(file.get_as_text())


## Helpers for reading typed values out of loosely-typed JSON dictionaries.
static func get_str(d: Dictionary, key: String, fallback: String = "") -> String:
	return str(d.get(key, fallback))


static func get_float(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	return float(d.get(key, fallback))


static func get_int(d: Dictionary, key: String, fallback: int = 0) -> int:
	return int(d.get(key, fallback))


static func get_dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func get_array(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key, [])
	return v if typeof(v) == TYPE_ARRAY else []
