extends Node
## Sound hooks. Gameplay code only ever calls play_sfx(id) / play_ambient(id);
## swapping placeholder sounds for final audio means replacing the files below.
## Missing files are skipped silently so audio can never break gameplay.

const SFX_PATHS := {
	&"click": "res://audio/sfx/click.wav",
	&"tool": "res://audio/sfx/tool_select.wav",
	&"cut": "res://audio/sfx/cut.wav",
	&"burn": "res://audio/sfx/burn.wav",
	&"clamp": "res://audio/sfx/clamp.wav",
	&"zap": "res://audio/sfx/zap.wav",
	&"stitch": "res://audio/sfx/stitch.wav",
	&"implant": "res://audio/sfx/implant_install.wav",
	&"stage": "res://audio/sfx/stage_complete.wav",
	&"mistake": "res://audio/sfx/mistake.wav",
	&"warning": "res://audio/sfx/warning.wav",
	&"success": "res://audio/sfx/surgery_success.wav",
	&"failure": "res://audio/sfx/surgery_failure.wav",
	&"customer": "res://audio/sfx/customer_arrival.wav",
	&"cash": "res://audio/sfx/cash.wav",
	&"levelup": "res://audio/sfx/level_up.wav",
}

const AMBIENT_PATHS := {
	&"clinic": "res://audio/ambient/clinic_hum.wav",
}

const SFX_POOL_SIZE := 8
const SFX_VOLUME_DB := -6.0
const AMBIENT_VOLUME_DB := -14.0

var sfx_enabled: bool = true
var ambient_enabled: bool = true

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _ambient_player: AudioStreamPlayer
var _ambient_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_VOLUME_DB
		add_child(p)
		_pool.append(p)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.volume_db = AMBIENT_VOLUME_DB
	_ambient_player.finished.connect(_on_ambient_finished)
	add_child(_ambient_player)


func play_sfx(id: StringName, pitch_variance: float = 0.05) -> void:
	if not sfx_enabled:
		return
	var stream := _get_stream(SFX_PATHS.get(id, ""))
	if stream == null:
		return
	var player := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()


func play_ambient(id: StringName) -> void:
	_ambient_id = id
	if not ambient_enabled:
		return
	var stream := _get_stream(AMBIENT_PATHS.get(id, ""))
	if stream == null or (_ambient_player.playing and _ambient_player.stream == stream):
		return
	_ambient_player.stream = stream
	_ambient_player.play()


func stop_ambient() -> void:
	_ambient_id = &""
	_ambient_player.stop()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled


func set_ambient_enabled(enabled: bool) -> void:
	ambient_enabled = enabled
	if enabled and _ambient_id != &"":
		play_ambient(_ambient_id)
	else:
		_ambient_player.stop()


func _on_ambient_finished() -> void:
	if ambient_enabled and _ambient_id != &"":
		_ambient_player.play()


func _get_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[path]


func get_save_data() -> Dictionary:
	return {"sfx_enabled": sfx_enabled, "ambient_enabled": ambient_enabled}


func load_save_data(data: Dictionary) -> void:
	sfx_enabled = bool(data.get("sfx_enabled", true))
	set_ambient_enabled(bool(data.get("ambient_enabled", true)))


func reset_state() -> void:
	sfx_enabled = true
	ambient_enabled = true
