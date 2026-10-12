extends Node
## Closes a small popup (a field-guide term card) when the player clicks
## anywhere outside it, without eating that click: the button under the
## mouse still gets it. (A full-screen transparent catcher would swallow the
## click and feel like a dead button.)

var target: Control
var on_close: Callable


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or target == null or not is_instance_valid(target):
		return
	if target.get_global_rect().has_point(mb.position):
		return
	_close_if_current.call_deferred()


## Only if our card is still the one showing: the same click may have
## opened another card (another "?"), which must stay.
func _close_if_current() -> void:
	if is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion():
		on_close.call()
