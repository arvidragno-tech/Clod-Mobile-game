extends Node
## One ticker for every animated character (portraits and in-room bodies).
## Views register with a personality profile; each frame the manager
## advances cheap timers (blink, gaze, breathing, idle actions, tremor,
## cyberware flicker) and asks a view to redraw only when its state changed.
## No per-character _process, no per-frame allocation.
##
## State keys a view reads: blink (bool), gaze ("center"/"left"/"right"),
## breath (0/1 px), jitter (Vector2i art px), lean (int px), action
## (StringName: "", "smoke", "check", "adjust", "glance"), action_t (0..1),
## glow (0..1 cyberware brightness).

const PROFILES := {
	# blink interval, gaze interval, breath period, tremor chance/s, idle actions
	"calm": {"blink": [2.5, 6.0], "gaze": [3.0, 8.0], "breath": 3.6, "tremor": 0.0, "actions": {"adjust": [9.0, 18.0]}},
	"still": {"blink": [4.0, 8.0], "gaze": [7.0, 14.0], "breath": 4.6, "tremor": 0.0, "actions": {}},
	"smoker": {"blink": [2.5, 6.0], "gaze": [3.0, 7.0], "breath": 3.8, "tremor": 0.0, "actions": {"smoke": [3.5, 8.0]}},
	"tremor": {"blink": [2.0, 5.0], "gaze": [3.0, 7.0], "breath": 3.2, "tremor": 6.0, "actions": {"smoke": [5.0, 10.0]}},
	"nervous": {"blink": [0.8, 2.4], "gaze": [0.6, 2.0], "breath": 2.2, "tremor": 2.0, "actions": {"glance": [2.0, 4.0]}},
	"aggressive": {"blink": [4.0, 9.0], "gaze": [4.0, 9.0], "breath": 3.0, "tremor": 0.0, "actions": {"lean": [4.0, 8.0]}},
	"fidget": {"blink": [1.8, 4.5], "gaze": [1.2, 3.0], "breath": 3.0, "tremor": 0.0, "actions": {"adjust": [2.5, 5.0], "check": [6.0, 12.0]}},
	"typing": {"blink": [2.0, 5.0], "gaze": [1.5, 3.5], "breath": 3.4, "tremor": 0.0, "actions": {"check": [3.0, 6.0]}},
	"withdrawal": {"blink": [0.6, 1.8], "gaze": [0.8, 2.0], "breath": 1.8, "tremor": 9.0, "actions": {"check": [3.0, 6.0]}},
}
const BLINK_SEC := 0.12
const ACTION_SEC := {"smoke": 1.6, "check": 1.2, "adjust": 0.5, "glance": 0.7, "lean": 1.8}

var _actors: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	process_priority = -10


## Registers a view (must implement queue_redraw). Returns its state dict
## (read it in _draw). Call unregister() from the view's _exit_tree.
func register(view: CanvasItem, profile: StringName = &"calm", has_cyber: bool = false) -> Dictionary:
	var p: Dictionary = PROFILES.get(String(profile), PROFILES["calm"])
	var st := {
		"view": view, "profile": p, "cyber": has_cyber,
		"blink": false, "gaze": "center", "breath": 0, "jitter": Vector2i.ZERO, "lean": 0,
		"action": &"", "action_t": 0.0, "glow": 1.0,
		"_blink_t": _rng.randf_range(0.5, 3.0), "_blink_left": 0.0,
		"_gaze_t": _rng.randf_range(1.0, 4.0), "_phase": _rng.randf() * TAU,
		"_action_timers": {}, "_action_left": 0.0, "_glow_t": _rng.randf_range(2.0, 6.0),
	}
	for a: String in p.get("actions", {}):
		var r: Array = p["actions"][a]
		st["_action_timers"][a] = _rng.randf_range(float(r[0]) * 0.3, float(r[1]))
	_actors.append(st)
	return st


func unregister(view: CanvasItem) -> void:
	for i in range(_actors.size() - 1, -1, -1):
		if _actors[i]["view"] == view:
			_actors.remove_at(i)


func actor_count() -> int:
	return _actors.size()


func _process(delta: float) -> void:
	var calm := Settings.reduce_motion
	for i in range(_actors.size() - 1, -1, -1):
		var st: Dictionary = _actors[i]
		var view: Variant = st["view"]
		if not is_instance_valid(view):
			_actors.remove_at(i)
			continue
		if not (view as CanvasItem).is_visible_in_tree():
			continue
		if _step(st, delta, calm):
			(view as CanvasItem).queue_redraw()


func _step(st: Dictionary, delta: float, calm: bool) -> bool:
	var p: Dictionary = st["profile"]
	var changed := false
	# Blink
	if st["_blink_left"] > 0.0:
		st["_blink_left"] -= delta
		if st["_blink_left"] <= 0.0:
			st["blink"] = false
			changed = true
	else:
		st["_blink_t"] -= delta
		if st["_blink_t"] <= 0.0:
			var r: Array = p["blink"]
			st["_blink_t"] = _rng.randf_range(float(r[0]), float(r[1]))
			st["_blink_left"] = BLINK_SEC
			st["blink"] = true
			changed = true
	if calm:
		return changed
	# Gaze
	st["_gaze_t"] -= delta
	if st["_gaze_t"] <= 0.0:
		var r: Array = p["gaze"]
		st["_gaze_t"] = _rng.randf_range(float(r[0]), float(r[1]))
		var g: String = ["center", "center", "left", "right"][_rng.randi() % 4]
		if g != st["gaze"]:
			st["gaze"] = g
			changed = true
	# Breathing: 1 art pixel rise on the inhale.
	st["_phase"] += delta * TAU / float(p["breath"])
	var b := 1 if sin(st["_phase"]) > 0.55 else 0
	if b != st["breath"]:
		st["breath"] = b
		changed = true
	# Tremor (shaking hands, withdrawal, fear)
	var tr := float(p.get("tremor", 0.0))
	if tr > 0.0:
		var j := Vector2i.ZERO
		if _rng.randf() < tr * delta:
			j = Vector2i(_rng.randi_range(-1, 1), 0)
		if j != st["jitter"]:
			st["jitter"] = j
			changed = true
	# Idle actions (one at a time)
	if st["_action_left"] > 0.0:
		st["_action_left"] -= delta
		var total: float = ACTION_SEC.get(String(st["action"]), 1.0)
		st["action_t"] = clampf(1.0 - st["_action_left"] / total, 0.0, 1.0)
		st["lean"] = 1 if st["action"] == &"lean" else 0
		changed = true
		if st["_action_left"] <= 0.0:
			st["action"] = &""
			st["action_t"] = 0.0
			st["lean"] = 0
	else:
		for a: String in st["_action_timers"]:
			st["_action_timers"][a] -= delta
			if st["_action_timers"][a] <= 0.0:
				var r: Array = p["actions"][a]
				st["_action_timers"][a] = _rng.randf_range(float(r[0]), float(r[1]))
				st["action"] = StringName(a)
				st["_action_left"] = float(ACTION_SEC.get(a, 1.0))
				if a == "glance":
					st["gaze"] = ["left", "right"][_rng.randi() % 2]
				changed = true
				break
	# Cyberware flicker: a brief dip in emissive brightness now and then.
	if st["cyber"] and Settings.flashing_allowed():
		st["_glow_t"] -= delta
		var g := 1.0
		if st["_glow_t"] <= 0.0:
			g = 0.35 if _rng.randf() < 0.5 else 0.6
			if st["_glow_t"] < -0.08:
				st["_glow_t"] = _rng.randf_range(1.5, 7.0)
		if not is_equal_approx(g, st["glow"]):
			st["glow"] = g
			changed = true
	return changed
