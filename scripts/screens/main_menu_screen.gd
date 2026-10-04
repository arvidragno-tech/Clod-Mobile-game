extends BaseScreen
## Title screen: continue / new game / settings.

const FLICKER_MIN_SEC := 1.5
const FLICKER_MAX_SEC := 5.0

@onready var _continue_button: Button = %ContinueButton
@onready var _new_game_button: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _subtitle: Label = %Subtitle
@onready var _version: Label = %Version

var _flicker_timer: float = 2.0


func on_enter(_params: Dictionary) -> void:
	var has_save := SaveManager.has_save()
	_continue_button.visible = has_save
	_new_game_button.theme_type_variation = &"Button" if has_save else &"AccentButton"
	_new_game_button.text = "NEW GAME" if has_save else "START"
	_continue_button.pressed.connect(GameManager.continue_game)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(func() -> void: UIManager.go_to(UIManager.SCREEN_SETTINGS, {"return_to": UIManager.SCREEN_MAIN_MENU}))
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0")


func _process(delta: float) -> void:
	if Settings.reduce_motion:
		return
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(FLICKER_MIN_SEC, FLICKER_MAX_SEC)
		var t := create_tween()
		t.tween_property(_subtitle, "modulate:a", 0.25, 0.04)
		t.tween_property(_subtitle, "modulate:a", 1.0, 0.05)
		t.tween_property(_subtitle, "modulate:a", 0.5, 0.03)
		t.tween_property(_subtitle, "modulate:a", 1.0, 0.06)


func _on_new_game_pressed() -> void:
	if SaveManager.has_save():
		UIManager.confirm("WIPE CLINIC?", "Starting over deletes your saved money, gear and reputation.", "WIPE", GameManager.start_new_game, true)
	else:
		GameManager.start_new_game()
