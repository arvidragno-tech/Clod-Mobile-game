class_name ItemSlot
extends Control
## One square inventory cell (PC grid inventory). Draws a pixel frame, the
## item icon at exact pixel density, a stack count and a condition bar.
## Mouse: hover = highlight + details, click = select, double-click =
## inspect, right-click = set as comparison, drag = move / drop on a
## compare slot. Also used (empty, `drop_zone`) as the COMPARE targets.

signal hovered(slot: ItemSlot)
signal clicked(slot: ItemSlot)
signal double_clicked(slot: ItemSlot)
signal right_clicked(slot: ItemSlot)
signal dropped(slot: ItemSlot, data: Dictionary)

const SIZE := Vector2(112, 112)

var kind: StringName = &""  # implant / tool / supplies / parts / tokens
var key: String = ""        # instance uid, tool id, ...
var icon: Texture2D
var count: int = 0
var condition: float = -1.0
var accent: Color = Palette.LINE_HI
var selected: bool = false
var drop_zone: bool = false
var placeholder: String = ""
var _hover: bool = false
var _drop_hover: bool = false


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func setup(p_kind: StringName, p_key: String, p_icon: Texture2D, p_count: int = 0, p_condition: float = -1.0, p_accent: Color = Palette.LINE_HI) -> ItemSlot:
	kind = p_kind
	key = p_key
	icon = p_icon
	count = p_count
	condition = p_condition
	accent = p_accent
	name = "Slot_%s_%s" % [kind, key]
	queue_redraw()
	return self


func is_empty() -> bool:
	return kind == &""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			if not is_empty():
				hovered.emit(self)
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_drop_hover = false
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER:
			if not is_empty():
				hovered.emit(self)
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT, NOTIFICATION_DRAG_END:
			_drop_hover = false
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				double_clicked.emit(self)
			else:
				clicked.emit(self)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)
			accept_event()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		clicked.emit(self)
		accept_event()
	elif event.is_action_pressed("inspect"):
		double_clicked.emit(self)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if is_empty() or drop_zone:
		return null
	var preview := TextureRect.new()
	preview.texture = icon
	preview.modulate.a = 0.85
	preview.position = -Vector2(icon.get_size()) / 2.0 if icon else Vector2.ZERO
	var holder := Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	AudioManager.play_sfx(&"tool", 0.05)
	return {"slot_kind": kind, "key": key, "source": self}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.has("slot_kind") and (data["source"] != self) \
			and (drop_zone or StringName(data["slot_kind"]) == kind)
	if ok != _drop_hover:
		_drop_hover = ok
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_drop_hover = false
	queue_redraw()
	dropped.emit(self, data)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Palette.BG_1 if not drop_zone else Color(Palette.BG_0, 0.8))
	var border := accent
	var width := 3.0
	if _drop_hover:
		border = Palette.OK
	elif selected:
		border = Palette.ACCENT
	elif _hover or has_focus():
		border = Palette.ACCENT_DIM.lerp(Palette.ACCENT, 0.5)
	else:
		width = 2.0
	draw_rect(r.grow(-width / 2.0), border, false, width)
	if drop_zone and is_empty():
		var f := get_theme_font(&"font", &"SubHeaderLabel")
		var fs := get_theme_font_size(&"font_size", &"SubHeaderLabel")
		draw_string(f, Vector2(0, size.y / 2.0 + fs / 3.0), placeholder, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Palette.TEXT_DIM)
		return
	if icon:
		var ts := Vector2(icon.get_size())
		draw_texture(icon, ((size - ts) / 2.0 - Vector2(0, 6)).floor())
	if count > 1:
		var f := get_theme_font(&"font", &"MonoLabel")
		var fs := get_theme_font_size(&"font_size", &"MonoLabel")
		draw_string(f, Vector2(0, size.y - 12), "x%d" % count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, fs, Palette.TEXT)
	if condition >= 0.0:
		var c := Palette.OK if condition >= 60.0 else (Palette.WARN if condition >= 25.0 else Palette.DANGER)
		var bar := Rect2(8, size.y - 10, size.x - 16, 4)
		draw_rect(bar, Palette.BG_0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * condition / 100.0, bar.size.y)), c)
