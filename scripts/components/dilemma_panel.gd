class_name DilemmaPanel
extends Control
## The operation stops: a surgical dilemma (SurgicalDilemmas). Shows what's
## wrong and every option with its odds, its risk and what it needs; after
## choosing, what happened. The patient's clock is frozen meanwhile.

signal closed()

var _box: VBoxContainer


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0, 0, 0.72)
	add_child(UIKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var p := UIKit.panel(&"DangerPanel")
	p.custom_minimum_size.x = 860
	center.add_child(p)
	_box = UIKit.vbox(10)
	p.add_child(_box)
	_build()


func _build() -> void:
	var d := SurgeryManager.active_dilemma
	_box.add_child(UIKit.label("OPERATION HALTED · DECISION", &"SubHeaderLabel", false, Palette.DANGER))
	var t := UIKit.label(str(d.get("title", "")), &"HeaderLabel", true, Palette.WARN)
	t.name = "DilemmaTitle"
	_box.add_child(t)
	_box.add_child(UIKit.label(str(d.get("text", "")), &"MonoLabel", true))
	var choices: Array = d.get("choices", [])
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var why := SurgicalDilemmas.block_reason(ch)
		var pct := roundi(SurgicalDilemmas.odds(SurgeryManager, ch) * 100.0)
		var label := "%s  ·  %s" % [str(ch.get("label", "")), ("%d%%" % pct) if pct < 100 else "SAFE"]
		if bool(ch.get("requires", {}).get("staff", false)):
			var e := SurgicalDilemmas.helper(SurgeryManager.customer)
			if not e.is_empty():
				label += "  (%s)" % str(e["name"]).get_slice(" ", 0)
		var b := UIKit.button(label, &"AccentButton" if i == 0 else &"GhostButton", _pick.bind(i), "DilemmaChoice_%d" % i, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = why != ""
		b.tooltip_text = str(ch.get("risk", ""))
		_box.add_child(b)
		_box.add_child(UIKit.label("   " + (why if why != "" else str(ch.get("risk", ""))), &"DimLabel", true, Palette.WARN if why != "" else Palette.TEXT_DIM, 13))
		if i == 0 and why == "":
			UIManager.focus_later(b)


func _pick(i: int) -> void:
	var r := SurgeryManager.resolve_dilemma(i)
	if r.is_empty():
		AudioManager.play_sfx(&"denied", 0.0)
		return
	AudioManager.play_sfx(&"confirm" if bool(r["success"]) else &"denied", 0.0)
	UIKit.clear(_box)
	_box.add_child(UIKit.label("SUCCEEDED" if bool(r["success"]) else "WENT WRONG", &"SubHeaderLabel", false, Palette.OK if bool(r["success"]) else Palette.DANGER))
	_box.add_child(UIKit.label(str(r["text"]), &"MonoLabel", true))
	var b := UIKit.button("BACK TO THE TABLE" if not bool(r["aborted"]) else "CLOSE UP", &"AccentButton", _close, "DilemmaContinue", 48)
	_box.add_child(b)
	UIManager.focus_later(b)


func _close() -> void:
	UIManager.close_modal()


func _exit_tree() -> void:
	# Back to the table: the patient's clock runs again.
	SurgeryManager.resume()
	closed.emit()
