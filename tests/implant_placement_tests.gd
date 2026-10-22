class_name ImplantPlacementTests
extends RefCounted
## Install-implant geometry: the socket, its key slot, the implant's notch,
## its art footprint and the stage's hit tests all come from one set of rules
## in SurgicalSiteView, so what the player sees lines up with what counts.
## Covers field <-> local conversion at several view sizes, the key / notch
## mapping at every rotation, drift over many turns, odd / even / non-square
## art footprints, drop and seat (preview vs confirmed), and how a seated
## implant is composited into the wound and under closed skin.
## Run by tests/test_runner.gd.

const VIEW_SIZES: Array[Vector2] = [Vector2(160, 160), Vector2(300, 220), Vector2(201, 167), Vector2(140, 120)]

var t: Node


func run(runner: Node) -> void:
	t = runner
	print("== IMPLANT PLACEMENT TESTS ==")
	var site := _make_site(Vector2(300, 220))
	_conversions(site)
	_key_and_notch(site)
	_footprints(site)
	_stage_flow(site, &"install_basic_neural_implant")
	_stage_flow(site, &"install_optic")
	_drift(site)
	_integration(site)
	site.queue_free()


func check(c: bool, msg: String) -> void:
	t.check(c, msg)


func _make_site(view: Vector2) -> SurgicalSiteView:
	var site := SurgicalSiteView.new()
	site.set_process(false)
	t.add_child(site)
	site.size = view
	site._layout()
	site.set_implant_icon("res://assets/sprites/cyberware/neural_t1.png")
	return site


func _resize(site: SurgicalSiteView, view: Vector2, focus: Vector2 = Vector2(0.5, 0.5)) -> void:
	site.size = view
	site.set_focus(focus)


# --- Coordinates --------------------------------------------------------------

func _conversions(site: SurgicalSiteView) -> void:
	for view in VIEW_SIZES:
		_resize(site, view, Vector2(0.5, 0.56))
		var field := site.get_field_rect()
		check(field.position == field.position.floor(), "field origin is a whole pixel at %s" % view)
		check(field.size == Vector2.ONE * SurgicalSiteView.FIELD_SIZE, "field is FIELD_SIZE at %s" % view)
		var ok := true
		for norm: Vector2 in [Vector2.ZERO, Vector2.ONE, Vector2(0.5, 0.5), Vector2(0.52, 0.6), Vector2(0.13, 0.91)]:
			var local := site.to_local_pos(norm)
			ok = ok and site.to_norm(local).is_equal_approx(norm)
			ok = ok and local.is_equal_approx(field.position + norm * SurgicalSiteView.FIELD_SIZE)
		check(ok, "field <-> local round trip at %s" % view)
		site.socket_pos = Vector2(0.52, 0.6)
		var c := site.socket_center()
		check(c == c.floor() and c.distance_to(site.to_local_pos(site.socket_pos)) < 1.0,
				"socket anchor is the whole pixel under the socket at %s" % view)
		site.implant_pos = site.socket_pos
		check(site.implant_center() == c, "an implant at the socket shares its anchor at %s" % view)
	_resize(site, Vector2(300, 220))


func _key_and_notch(site: SurgicalSiteView) -> void:
	site.socket_pos = Vector2(0.5, 0.56)
	site.implant_pos = site.socket_pos
	var r := site.key_radius()
	check(r == roundf(SurgicalSiteView.SOCKET_RADIUS * site.art_px()), "key radius is the socket rim (%.0f px)" % r)
	check(site.socket_key_pos() == site.socket_center() + Vector2(0, -r), "key slot sits straight above the socket anchor")
	# Every 90 degrees, both ways: the notch lands on the exact pixel.
	var c := site.implant_center()
	var expect := {0: Vector2(0, -r), 90: Vector2(r, 0), 180: Vector2(0, r), 270: Vector2(-r, 0),
		-90: Vector2(-r, 0), -180: Vector2(0, r), -270: Vector2(r, 0), 360: Vector2(0, -r)}
	for deg: int in expect:
		site.implant_angle = deg_to_rad(deg)
		check(site.implant_notch_pos() == c + expect[deg], "notch at %d deg is %s from the pivot" % [deg, expect[deg]])
	site.implant_angle = 0.0
	check(site.implant_notch_pos() == site.socket_key_pos(), "aligned notch is exactly on the key slot")
	# The notch always rides the key circle around the pivot.
	var ok := true
	for k in 72:
		site.implant_angle = deg_to_rad(k * 5.0)
		ok = ok and absf(site.implant_notch_pos().distance_to(c) - r) <= 0.75
	check(ok, "notch stays on the key radius at every 5 deg step")
	site.implant_angle = 0.0


# --- Art footprint ------------------------------------------------------------

func _footprints(site: SurgicalSiteView) -> void:
	var real := site.implant_texture
	for dims: Vector2i in [Vector2i(32, 32), Vector2i(5, 3), Vector2i(4, 7), Vector2i(9, 9), Vector2i(6, 2)]:
		var img := Image.create(dims.x, dims.y, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		site.implant_texture = ImageTexture.create_from_image(img)
		var anchor := Vector2(80, 80)
		var n := dims.x * dims.y
		var cover0 := site.implant_coverage(anchor, 0.0)
		check(cover0.size() == n, "%s art covers %d px unrotated" % [dims, n])
		# Unrotated, the art's corner is a whole pixel: texel (u, v) lands on
		# field pixel anchor - floor(size / 2) + (u, v).
		var top_left := anchor - (Vector2(dims) / 2.0).floor()
		var mapped := true
		for idx: int in cover0:
			var src: Vector2i = cover0[idx]
			mapped = mapped and Vector2(idx % SurgicalSiteView.FIELD_SIZE, idx / SurgicalSiteView.FIELD_SIZE) == top_left + Vector2(src)
		check(mapped, "%s art maps texel to pixel one to one" % dims)
		for deg: int in [90, 180, 270, -90]:
			var cover := site.implant_coverage(anchor, deg_to_rad(deg))
			var lo := Vector2i(999, 999)
			var hi := Vector2i(-999, -999)
			for idx: int in cover:
				var p := Vector2i(idx % SurgicalSiteView.FIELD_SIZE, idx / SurgicalSiteView.FIELD_SIZE)
				lo = lo.min(p)
				hi = hi.max(p)
			var box := hi - lo + Vector2i.ONE
			var want := dims if absi(deg) == 180 else Vector2i(dims.y, dims.x)
			check(cover.size() == n and box == want, "%s art at %d deg: %d px in a %s box (want %d in %s)" % [dims, deg, cover.size(), box, n, want])
			var centre := (Vector2(lo) + Vector2(hi) + Vector2.ONE) / 2.0
			var pivot := anchor + SurgicalSiteView._pivot_offset(Vector2(dims))
			check(absf(centre.x - pivot.x) <= 0.5 and absf(centre.y - pivot.y) <= 0.5, "%s art at %d deg stays centred on its pivot (%s)" % [dims, deg, centre])
	site.implant_texture = real
	check(site.implant_reach() >= site.implant_size().length() / 2.0, "grab reach encloses the art at any angle")


# --- Drop, rotate, seat -------------------------------------------------------

func _make_stage(site: SurgicalSiteView, surgery_id: StringName) -> InstallImplantStage:
	var data: SurgeryStageData = null
	for st in SurgeryManager.get_surgery(surgery_id).stages:
		if st.type == &"install_implant":
			data = st
	var stage := SurgeryStageRegistry.create(&"install_implant") as InstallImplantStage
	stage.setup(data, site, null, 1.0, 1.0, {})
	stage.view_scale = 4.0
	t.add_child(stage)
	stage.size = site.size
	stage.begin()
	stage.set_selected_tool(data.tool_category)
	return stage


func _stage_flow(site: SurgicalSiteView, surgery_id: StringName) -> void:
	for view: Vector2 in [Vector2(300, 220), Vector2(160, 160)]:
		_resize(site, view)
		site.implant_state = SurgicalSiteView.ImplantState.NONE
		var stage := _make_stage(site, surgery_id)
		var tag := "%s at %s" % [surgery_id, view]
		check(site.implant_state == SurgicalSiteView.ImplantState.IN_TRAY, "implant starts on the tray (%s)" % tag)
		# Grabbing a corner of the art picks it up, at any angle.
		var corner := site.implant_center() + Vector2(15, 15).rotated(site.implant_angle)
		check(stage._implant_hit(corner), "a corner of the art grabs the implant (%s)" % tag)
		# A drop just outside the snap ring goes back to the tray.
		var socket := site.socket_center()
		var snap := stage._snap_art * stage._px() + stage._ui(GameConfig.CLICK_SLOP) * 0.5
		stage._pointer_down(site.implant_center())
		check(site.implant_state == SurgicalSiteView.ImplantState.HELD, "pressing the implant lifts it (%s)" % tag)
		stage._pointer_move(socket + Vector2(snap + 3.0, 0))
		stage._pointer_up(socket + Vector2(snap + 3.0, 0))
		check(site.implant_state == SurgicalSiteView.ImplantState.IN_TRAY and stage.phase == InstallImplantStage.Phase.PLACE,
				"a drop outside the snap radius returns it (%s)" % tag)
		# A drop inside snaps exactly onto the socket's anchor.
		stage._return_tween.kill()
		site.implant_pos = stage.tray_pos()
		stage._pointer_down(site.implant_center())
		stage._pointer_move(socket + Vector2(snap - 2.0, 1))
		stage._pointer_up(socket + Vector2(snap - 2.0, 1))
		check(site.implant_state == SurgicalSiteView.ImplantState.PLACED and site.implant_pos == site.socket_pos
				and site.implant_center() == socket, "a drop inside the snap radius seats on the socket anchor (%s)" % tag)
		# Rotate with the step keys until aligned, both directions.
		var start := site.implant_angle
		var dir := -1.0 if stage._angle_error() > 0.0 else 1.0
		var steps := 0
		while not site.implant_aligned and steps < 200:
			stage._rotate_step(dir)
			steps += 1
		check(site.implant_aligned, "stepping %s aligns the notch in %d steps (%s)" % ["CCW" if dir < 0 else "CW", steps, tag])
		var tol: float = stage._tolerance_deg
		check(absf(rad_to_deg(stage._angle_error())) <= tol, "aligned means within %.1f deg (%s)" % [tol, tag])
		var chord := 2.0 * site.key_radius() * sin(deg_to_rad(tol) / 2.0) + 1.0
		check(site.implant_notch_pos().distance_to(site.socket_key_pos()) <= chord,
				"the aligned notch is drawn within the tolerance arc of the slot (%s)" % tag)
		check(absf(site.implant_angle) <= PI, "the angle stays wrapped (%s)" % tag)
		# Turning back the same number of steps returns to the start exactly.
		var back := site.implant_angle
		for s in steps:
			stage._rotate_step(-dir)
		check(is_equal_approx(wrapf(site.implant_angle - start, -PI, PI), 0.0), "turning back %d steps returns to the start (%s)" % [steps, tag])
		for s in steps:
			stage._rotate_step(dir)
		check(is_equal_approx(site.implant_angle, back), "and forward again lands aligned (%s)" % tag)
		# Seat: the installed implant is where the preview showed it.
		var placed_center := site.implant_center()
		var result := {}
		stage.stage_finished.connect(func(q: float, d: Dictionary) -> void: result.merge({"q": q, "d": d}))
		stage._seat()
		check(site.implant_state == SurgicalSiteView.ImplantState.SEATED and site.implant_center() == placed_center
				and site.implant_angle == 0.0, "seating keeps the previewed position, square to the slot (%s)" % tag)
		check(not result.is_empty() and float(result["d"].get("alignment", 0.0)) >= 0.85, "an aligned seat scores as aligned (%s)" % tag)
		stage.queue_free()
	# A misaligned seat stays as it was shown.
	_resize(site, Vector2(300, 220))
	var stage := _make_stage(site, surgery_id)
	site.implant_pos = site.socket_pos
	site.implant_state = SurgicalSiteView.ImplantState.PLACED
	stage.phase = InstallImplantStage.Phase.ROTATE
	site.implant_angle = deg_to_rad(70.0)
	stage._update_alignment()
	stage._seat()
	check(is_equal_approx(site.implant_angle, deg_to_rad(70.0)), "a misaligned seat keeps the angle it was shown at (%s)" % surgery_id)
	stage.queue_free()


func _drift(site: SurgicalSiteView) -> void:
	_resize(site, Vector2(300, 220))
	var stage := _make_stage(site, &"install_basic_neural_implant")
	site.implant_pos = site.socket_pos
	stage.phase = InstallImplantStage.Phase.ROTATE
	site.implant_angle = 0.3
	var center := site.implant_center()
	var bounded := true
	for i in 5000:
		stage._rotate_step(1.0)
		bounded = bounded and absf(site.implant_angle) <= PI + 0.0001
	for i in 5000:
		stage._rotate_step(-1.0)
	check(bounded, "the angle stays in -180..180 over 5000 steps")
	check(absf(wrapf(site.implant_angle - 0.3, -PI, PI)) < 0.0001, "5000 steps each way come back to the start angle")
	check(site.implant_center() == center, "rotating never moves the pivot")
	# A full drag circle around the implant turns it exactly once.
	site.implant_angle = 0.0
	stage._rotating = true
	stage._last_angle = 0.0
	for k in range(1, 361):
		stage._pointer_move(center + Vector2.RIGHT.rotated(deg_to_rad(k)) * 30.0)
	check(absf(wrapf(site.implant_angle, -PI, PI)) < 0.0001, "a full drag circle ends where it started")
	stage._rotating = false
	stage.queue_free()


# --- Integration into the body -------------------------------------------------

func _integration(site: SurgicalSiteView) -> void:
	_resize(site, Vector2(300, 220))
	var path: Array[Vector2] = [Vector2(0.5, 0.25), Vector2(0.5, 0.5), Vector2(0.5, 0.75)]
	site.set_incision_path(path)
	site.closed = false
	site.opening = 1.0
	site.socket_pos = Vector2(0.5, 0.5)
	site.implant_pos = site.socket_pos
	site.implant_angle = 0.0
	site.implant_exposed_radius = 0.0
	site.implant_state = SurgicalSiteView.ImplantState.SEATED
	site._rebuild_wound()
	site._rebuild_implant_layer()
	var anchor := site.implant_center() - site.get_field_rect().position
	var cover := site.implant_coverage(anchor, 0.0)
	var inside := 0
	var outside := 0
	var shown_inside := true
	var art_outside := false
	for idx: int in cover:
		var x := idx % SurgicalSiteView.FIELD_SIZE
		var y := idx / SurgicalSiteView.FIELD_SIZE
		var px := site._implant_layer.get_pixel(x, y)
		var texel := site._implant_image.get_pixelv(cover[idx])
		if site._open_depth[idx] <= 1.0:
			inside += 1
			shown_inside = shown_inside and px.a > 0.99
		else:
			outside += 1
			art_outside = art_outside or (px.a > 0.0 and px.is_equal_approx(texel))
	check(inside > 0 and shown_inside, "seated art inside the open wound is drawn (%d px)" % inside)
	check(not art_outside, "seated art under intact skin is not drawn over it (%d px covered)" % outside)
	# Narrow the wound: the skin edges now lap over the implant's sides.
	site.opening = 0.3
	site._rebuild_wound()
	site._rebuild_implant_layer()
	var inside_narrow := 0
	var covered := 0
	var leaked_narrow := 0
	for idx: int in cover:
		var px := site._implant_layer.get_pixel(idx % SurgicalSiteView.FIELD_SIZE, idx / SurgicalSiteView.FIELD_SIZE)
		if site._open_depth[idx] <= 1.0:
			inside_narrow += 1
		else:
			covered += 1
			if px.a > 0.0 and px.is_equal_approx(site._implant_image.get_pixelv(cover[idx])):
				leaked_narrow += 1
	check(inside_narrow < inside and covered > 0, "a narrower wound shows less of the implant (%d < %d px)" % [inside_narrow, inside])
	check(leaked_narrow == 0, "the skin edges hide the %d px they cover" % covered)
	# Closed: nothing of the art shows unless it is an exposed part.
	site.closed = true
	site._rebuild_wound()
	site._rebuild_implant_layer()
	var leaked := 0
	for idx: int in cover:
		var px := site._implant_layer.get_pixel(idx % SurgicalSiteView.FIELD_SIZE, idx / SurgicalSiteView.FIELD_SIZE)
		if px.a > 0.0 and px.is_equal_approx(site._implant_image.get_pixelv(cover[idx])):
			leaked += 1
	check(leaked == 0, "closed skin hides a subdermal implant (%d art px showing)" % leaked)
	site.implant_exposed_radius = 5.0
	site._implant_dirty = true
	site._rebuild_implant_layer()
	var exposed_ok := true
	var exposed := 0
	for idx: int in cover:
		var x := idx % SurgicalSiteView.FIELD_SIZE
		var y := idx / SurgicalSiteView.FIELD_SIZE
		var px := site._implant_layer.get_pixel(x, y)
		var is_art := px.a > 0.0 and px.is_equal_approx(site._implant_image.get_pixelv(cover[idx]))
		var within := (Vector2(x + 0.5, y + 0.5) - anchor - SurgicalSiteView._pivot_offset(site.implant_size())).length() <= 5.0
		if is_art:
			exposed += 1
		exposed_ok = exposed_ok and (is_art == within)
	check(exposed > 0 and exposed_ok, "closed skin leaves exactly the exposed part showing (%d px)" % exposed)
	# The surgery data names its exposed parts, and configure() reads them.
	check(float(SurgeryManager.get_surgery(&"install_basic_neural_implant").site.get("implant", {}).get("exposed_radius", 0.0)) > 0.0,
			"the neural jack is marked as exposed in the surgery data")
	check(float(SurgeryManager.get_surgery(&"install_dermal").site.get("implant", {}).get("exposed_radius", 0.0)) == 0.0,
			"dermal plating is fully subdermal")
	site.closed = false
	site.implant_state = SurgicalSiteView.ImplantState.NONE
