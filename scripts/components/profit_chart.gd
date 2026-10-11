class_name ProfitChart
extends Control
## Bar chart of profit per closed day (BusinessManager.history), today as
## the last, hollow bar. Pixel-snapped bars, zero line, min/max labels.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var vals: Array[int] = []
	for h in BusinessManager.history:
		vals.append(int(h["profit"]))
	vals.append(BusinessManager.profit_today())
	var lo := 0
	var hi := 1
	for v in vals:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	var r := Rect2(Vector2(0, 8), size - Vector2(0, 28))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, 0.6))
	var span := float(hi - lo)
	var zero_y := r.position.y + r.size.y * (float(hi) / span)
	draw_rect(Rect2(r.position.x, floorf(zero_y), r.size.x, 2), Palette.LINE)
	var n := vals.size()
	var bw := floorf(minf(36.0, r.size.x / maxf(1.0, n) - 4.0))
	var font := get_theme_font(&"font", &"PixelLabel")
	for i in n:
		var v := vals[i]
		var x := floorf(r.position.x + 6 + i * (bw + 4))
		var h := floorf(absf(v) / span * r.size.y)
		var y := zero_y - h if v >= 0 else zero_y + 2
		var col := Palette.OK if v >= 0 else Palette.DANGER
		if i == n - 1:
			draw_rect(Rect2(x, y, bw, maxf(h, 2)), col, false, 2.0)
		else:
			draw_rect(Rect2(x, y, bw, maxf(h, 2)), Color(col, 0.75))
		if n <= 14 or i % 2 == 0:
			var day := BusinessManager.day - (n - 1 - i)
			draw_string(font, Vector2(x, size.y - 6), str(day), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT_DIM)
	draw_string(font, Vector2(size.x - 80, 18), "%+d" % hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT_DIM)
	if lo < 0:
		draw_string(font, Vector2(size.x - 80, r.end.y), "%+d" % lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT_DIM)
