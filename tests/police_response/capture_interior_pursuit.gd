extends SceneTree
## Real Main/session transition and native visitor presentation. Safe save
## flags are mandatory. Run rendered to produce room/depth review pictures.
const OFFICER := preload("res://gameplay/PoliceAgent.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world: Node3D
var failures: Array[String] = []
var folder := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("INTERIOR_PURSUIT PASS " if ok else "INTERIOR_PURSUIT FAIL ") + label)
	if not ok: failures.append(label)

func wait_until(predicate: Callable, count := 600) -> bool:
	for i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func frames(count: int) -> void:
	for i in count: await physics_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Run with -- --no-save --skip-arrival")
		quit(2)
		return
	folder = OS.get_temp_dir().path_join("geteco-police-interior-main")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): folder = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play and world.production.ready_for_play, 1800):
		check(false, "Main ready")
		quit(1)
		return
	var session = world.session
	var gameplay = world.gameplay
	var definition := PLACES.get_definition("harbor_ammunation")
	world.production.region.set_focus(definition.return_position)
	world.player.teleport(definition.return_position + Vector3.UP * .06)
	await frames(60)
	var officer := OFFICER.new()
	officer.controller = gameplay
	officer.tier = 2
	gameplay.add_child(officer)
	officer.global_position = definition.return_position + Vector3(1.6, .06, 0)
	gameplay.police.append(officer)
	gameplay.register_crime(150, world.player.global_position)
	gameplay.report_contact(world.player.global_position)
	# Capture before transfer with the real facade/approach, and preserve this
	# officer's identity throughout the session's actual transition.
	await frames(3)
	await capture("01-exterior-existing-officer")
	var identity := officer.get_instance_id()
	check(await session.enter_place("harbor_ammunation", false), "real FullSession entry")
	if session.state.place_id != "harbor_ammunation":
		world.queue_free()
		quit(1)
		return
	world.player.teleport(session.room.spawn_position + Vector3(-1.3, .06, -.8))
	var admitted := await wait_until(func(): return is_instance_valid(officer) and officer.get_meta("police_place_id", "") == "harbor_ammunation", 600)
	check(admitted and officer.get_instance_id() == identity, "same exterior officer admitted through entrance")
	if admitted:
		officer.set_physics_process(false)
		check(session.room.is_floor_clear(session.room.to_local(officer.global_position), .34), "visitor whole body outside room solids")
		check(officer.get_viewport() == world.player.get_viewport(), "player, resident and visitor share native depth buffer")
		await capture("02-interior-player-resident-visitor")
		# Stage a real visiting officer on each side of an authored display.
		# Snapshot positions stay on walkable floor; the camera and furniture
		# remain the production room's own geometry and presentation.
		var room: Node3D = session.room
		var display_bounds: AABB
		var found := false
		for body in room.solid_bodies:
			var id := str(body.get_meta("interior_solid_id", "")).to_lower()
			if "armordisplay" in id:
				display_bounds = body.get_meta("bounds")
				found = true
				break
		check(found, "production armor display located for depth review")
		if found:
			# Front stock crates occupy z=2.2..3.8; stage beyond their footprint.
			var points := [Vector3(display_bounds.get_center().x, .06, 4.22), Vector3(display_bounds.get_center().x, .06, display_bounds.position.z - .6)]
			for index in points.size():
				var point: Vector3 = room.to_global(points[index])
				if not room.is_floor_clear(points[index], .34) or not officer._tactics.point_clear(officer, point, 7):
					check(false, "display side %d has safe full-body staging point" % index)
					continue
				officer.global_position = point
				officer.velocity = Vector3.ZERO
				await frames(3)
				await capture("03-display-%s" % ("front" if index == 0 else "behind"))
	check(await session.leave_place(), "real FullSession exit")
	await frames(3)
	check(not is_instance_valid(officer), "visitor released with unloaded room")
	await capture("04-return-to-exterior")
	print("INTERIOR_PURSUIT failures=", failures, " evidence=", folder)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
