class_name BaseScreen
extends Control
## Base for all full-screen states managed by UIManager.

## false = arrows / WASD are gameplay keys here, not menu focus navigation.
var keyboard_nav: bool = true


## Called right after the screen is added to the tree.
func on_enter(_params: Dictionary) -> void:
	pass


## Called right before the screen is freed.
func on_exit() -> void:
	pass
