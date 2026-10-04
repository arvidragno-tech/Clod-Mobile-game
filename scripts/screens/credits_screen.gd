extends BaseScreen
## Credits.

const CREDITS := [
	["UNDERCITY: RIPPER", ""],
	["An original cyberpunk cyber-surgery game", ""],
	["DESIGN, CODE, PIXEL ART, AUDIO", "Generated and hand-tuned with reproducible tools in this repository"],
	["ENGINE", "Godot Engine 4.3 (MIT licence)"],
	["FONTS", "VT323, Silkscreen, Pixelify Sans: SIL Open Font License 1.1"],
	["SPECIAL THANKS", "Every ripper who kept the lights on below sublevel 3"],
]


func on_enter(_params: Dictionary) -> void:
	var bg := CityBackdrop.new()
	add_child(UIKit.full_rect(bg))
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(dim))
	var m := UIKit.full_rect(UIKit.margin(160, 90, 160, 90))
	add_child(m)
	var col := UIKit.vbox(22)
	m.add_child(col)
	col.add_child(UIKit.header("UNDERCITY: RIPPER", "CREDITS", func() -> void: UIManager.go_to(UIManager.SCREEN_MAIN_MENU)))
	for c: Array in CREDITS:
		var l := UIKit.label(str(c[0]), &"HeaderLabel")
		col.add_child(l)
		if str(c[1]) != "":
			col.add_child(UIKit.label(str(c[1]), &"DimLabel", true))
	col.add_child(UIKit.label("Not affiliated with any existing cyberpunk franchise.", &"SubHeaderLabel"))
