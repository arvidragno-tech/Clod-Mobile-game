class_name ChangesPanel
extends RefCounted
## The RECENT CHANGES panel (key G, or the status bar's CHANGES button): the
## ChangeLog newest first, grouped by day, each line marked by priority
## (■ critical, ▲ important, · info), clickable when it links somewhere.
## Opening it marks everything read.


static func is_open() -> bool:
	var h := Glossary.host()
	return h != null and h.get_node_or_null("ChangesPanel") != null


static func toggle() -> void:
	if is_open():
		Glossary.close()
	else:
		open()


static func open() -> void:
	var h := Glossary.host()
	if h == null:
		return
	Glossary.close()
	Glossary.catcher(h, 0.35)
	var vp := h.get_viewport_rect().size
	var sz := Vector2(minf(760, vp.x - 80), minf(820, vp.y - 140))
	var pop := UIKit.panel(&"AccentPanel")
	pop.name = "ChangesPanel"
	pop.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(pop)
	pop.position = Vector2(vp.x - sz.x - 40, 100).floor()
	pop.size = sz
	pop.custom_minimum_size = sz
	var col := UIKit.vbox(10)
	pop.add_child(col)
	var head := UIKit.hbox(10)
	col.add_child(head)
	var t := UIKit.label("RECENT CHANGES", &"HeaderLabel")
	UIKit.expand(t)
	head.add_child(t)
	head.add_child(UIKit.button("CLOSE %s" % Controls.hint("pause"), &"GhostButton", func() -> void: (func() -> void: Glossary.close()).call_deferred(), "ChangesClose", 40))
	col.add_child(UIKit.label("What changed while you were busy. ■ critical  ▲ important  · info. Click a line to go there.", &"DimLabel", true))
	var sc := UIKit.scroll()
	UIKit.expand(sc, true, true)
	col.add_child(sc)
	var list := UIKit.vbox(4)
	list.name = "ChangesList"
	UIKit.expand(list)
	sc.add_child(list)
	var rows := ChangeLog.recent(60)
	if rows.is_empty():
		list.add_child(UIKit.label("Nothing yet. Changes to money, standing, heat, supplies, staff, people and places show up here.", &"DimLabel", true))
	var day := -1
	for e in rows:
		if int(e["day"]) != day:
			day = int(e["day"])
			list.add_child(UIKit.label("DAY %d" % day, &"SubHeaderLabel", false, Palette.ACCENT))
		list.add_child(_row(e))
	ChangeLog.mark_all_read()
	AudioManager.play_sfx(&"click", 0.0)


static func _row(e: Dictionary) -> Control:
	var level := StringName(str(e["level"]))
	var col := Palette.DANGER if level == ChangeLog.CRITICAL else (Palette.WARN if level == ChangeLog.IMPORTANT else Palette.TEXT_DIM)
	var link: Dictionary = e.get("link", {})
	var text := "%s %s  ·  %s   %s%s" % [ChangeLog.LEVEL_MARKS.get(level, "·"), str(e["subject"]), str(e["text"]),
		TimeManager.clock_text(int(e["minute"])), "  ›" if Nav.can_open(link) else ""]
	if Nav.can_open(link):
		var b := UIKit.button(text, &"GhostButton", func() -> void: (func() -> void: Nav.open(link)).call_deferred(), "Change_%d" % int(e["seq"]), 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_color_override(&"font_color", col)
		if ChangeLog.is_unread(e):
			b.text = "NEW  " + b.text
		return b
	var l := UIKit.label(("NEW  " if ChangeLog.is_unread(e) else "") + text, &"", true, col)
	return l
