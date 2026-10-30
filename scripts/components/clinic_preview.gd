class_name ClinicPreview
extends Control
## Static window into a clinic room (background + its installed upgrade
## overlays) at the HD world-art density (GameConfig.ART_SCALE), for the facility and property
## screens.

var clinic_index: int = -1  # -1 = active clinic
var region: Rect2i = Rect2i(0, 0, 600, 336)
var scale_override: int = 0
var _bg: Texture2D
var _overlays: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load()
	custom_minimum_size = Vector2(region.size) * _s()


func _s() -> float:
	return float(scale_override if scale_override > 0 else GameConfig.ART_SCALE)


func _load() -> void:
	var t := clinic_index if clinic_index >= 0 else ClinicManager.tier
	_bg = PixelArt.tex(str(ClinicManager.get_tier_data(t).get("background", "")))
	_overlays.clear()
	for o: Dictionary in ClinicManager.get_overlays(t):
		var tex := PixelArt.tex(str(o["path"]))
		if tex:
			_overlays.append([tex, Vector2(float(o["x"]), float(o["y"]))])


func _draw() -> void:
	if _bg == null:
		return
	var s := _s()
	var src := Rect2(region)
	var k := float(GameConfig.SCENE_RES)
	draw_texture_rect_region(_bg, Rect2(Vector2.ZERO, src.size * s), Rect2(src.position * k, src.size * k))
	for o: Array in _overlays:
		var tex: Texture2D = o[0]
		var r := Rect2(o[1] as Vector2, PixelArt.scene_size(tex))
		var clip := r.intersection(src)
		if clip.has_area():
			draw_texture_rect_region(tex, Rect2((clip.position - src.position) * s, clip.size * s), Rect2((clip.position - r.position) * k, clip.size * k))
	draw_rect(Rect2(Vector2.ZERO, src.size * s), Palette.LINE, false, 2.0)
