class_name SafeAreaUtil
extends RefCounted
## Converts the OS safe area (in physical screen pixels) into viewport-space
## insets. Returned Rect2 packs insets as position=(left, top), size=(right, bottom).


static func get_insets(viewport: Viewport) -> Rect2:
	var debug := GameConfig.DEBUG_SIMULATED_SAFE_AREA
	if debug != Rect2():
		return debug
	if not OS.has_feature("mobile"):
		return Rect2()
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if window_size.x <= 0.0 or window_size.y <= 0.0 or safe.size == Vector2.ZERO:
		return Rect2()
	var vp_size := viewport.get_visible_rect().size
	var scale := vp_size / window_size
	var left := safe.position.x * scale.x
	var top := safe.position.y * scale.y
	var right := (window_size.x - safe.end.x) * scale.x
	var bottom := (window_size.y - safe.end.y) * scale.y
	return Rect2(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))
