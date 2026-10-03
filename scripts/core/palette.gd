class_name Palette
extends RefCounted
## The game's limited colour palette. Very dark base, one primary neon (cyan),
## one brand accent (magenta, used sparingly) and status colours.
## tools/generate_placeholder_art.py mirrors these values.

const BG_0 := Color("07080c")
const BG_1 := Color("0d1017")
const PANEL := Color("121821")
const PANEL_HI := Color("1a2230")
const LINE := Color("2a3646")
const LINE_HI := Color("3b4b60")

const TEXT := Color("c9d6df")
const TEXT_DIM := Color("6b7c8c")
const TEXT_DARK := Color("07080c")

const ACCENT := Color("2ee6c8")
const ACCENT_DIM := Color("1a7d70")
const BRAND := Color("ff3d81")
const BRAND_DIM := Color("7a1f42")

const OK := Color("6dff8a")
const WARN := Color("ffb43d")
const DANGER := Color("ff4d4d")
const DANGER_DIM := Color("6e1c1c")

const BLOOD := Color("b3122e")
const BLOOD_DARK := Color("5c0a18")
const TISSUE := Color("8a3a48")
const TISSUE_DARK := Color("4d1d27")
const NECROTIC := Color("2b1630")
const NERVE := Color("f2d16b")
const METAL := Color("8e9aa8")
const METAL_DARK := Color("3d4652")

## Wire / pin colours for the neural splice stage. Each is also paired with a
## distinct shape (triangle / diamond / square) so the puzzle never relies on
## colour alone.
const SPLICE_COLORS: Array[Color] = [Color("2ee6c8"), Color("ffb43d"), Color("ff3d81")]

const VITAL_COLORS := {
	&"health": Color("6dff8a"),
	&"blood_loss": Color("ff4d4d"),
	&"pain": Color("ffb43d"),
	&"neural": Color("2ee6c8"),
}
