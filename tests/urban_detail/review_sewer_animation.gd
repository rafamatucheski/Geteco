extends SceneTree

## Rendered review of the production V2 hatch and player transition.
## Run with -- --no-save out_dir=<workspace path> tag=<label>.
const PLACES := preload("res://world/places/PlaceCatalog.gd")

var failures: Array[String] = []
var out_dir := "res://evidence/sewer-entry-0922"
var tag := "review"
var world: Node3D
var entry_completed := false
var entry_succeeded := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(tag + "-" + label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--no-save"):
		push_error("review_sewer_animation requires --no-save")
		quit(1)
		return
	for arg in args:
		if arg.begins_with("out_dir="): out_dir = arg.trim_prefix("out_dir=")
		elif arg.begins_with("tag="): tag = arg.trim_prefix("tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 480:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "production session ready")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	check(world.production.no_save, "player save is isolated")
	var definition := PLACES.get_definition("harbor_sewer")
	var access: Vector3 = definition.entry_position
	session.controller.region.set_focus(access)
	world.player.teleport(access + Vector3(-1.0, 0.08, 0.0))
	for i in 12: await physics_frame
	var hatch: Node3D = session._find_sewer_hatch()
	check(is_instance_valid(hatch), "production hatch streamed at the street access")
	if not is_instance_valid(hatch): quit(1); return
	if args.has("--diagnose-nearby"): _diagnose_nearby(hatch.global_position)
	var access_action: Dictionary = session.nearest()
	check(access_action.get("id", "") == "enter" and access_action.get("place", "") == "harbor_sewer", "E interaction points to the sewer entrance")
	check(is_zero_approx(hatch.open_amount), "hatch is closed before interaction")
	check(world.player.animation.has_animation("Fast_Ladder_Climb"), "Dante has the ladder clip")
	var hatch_point: Vector3 = hatch.global_position
	check(session.position_clear(hatch_point + Vector3(-0.65, 0.08, 0.0)), "ladder approach has ground and no solid obstacle")
	check(session.position_clear(hatch_point + Vector3(0.0, 0.08, 0.0)), "shaft entrance has ground and no solid obstacle")
	var closed_ray := PhysicsRayQueryParameters3D.create(hatch_point + Vector3.UP * 0.25, hatch_point + Vector3.DOWN * 1.7, 1)
	closed_ray.exclude = [world.player.get_rid()]
	var closed_hit := world.get_world_3d().direct_space_state.intersect_ray(closed_ray)
	check(not closed_hit.is_empty() and closed_hit.collider.name == "ClosedCoverCollision", "closed lid physically supports the opening")
	var exterior_camera_size: float = world.camera.target_size
	await create_timer(1.0).timeout
	await capture("closed")
	_run_entry.call_deferred(session, func(ok: bool) -> void:
		entry_succeeded = ok
		entry_completed = true)
	await create_timer(0.32).timeout
	print("SEWER_REVIEW_PHASE early hatch=", hatch.open_amount, " player=", world.player.global_position)
	check(hatch.open_amount < 0.1, "Dante approaches the closed hatch before opening it")
	await capture("reach")
	await create_timer(0.48).timeout
	print("SEWER_REVIEW_PHASE opening hatch=", hatch.open_amount, " player=", world.player.global_position)
	await capture("opening")
	await create_timer(0.65).timeout
	print("SEWER_REVIEW_PHASE dragging hatch=", hatch.open_amount, " player=", world.player.global_position)
	check(hatch.open_amount > 0.8, "cover slides clear before Dante takes the ladder")
	var opened_ray := PhysicsRayQueryParameters3D.create(hatch_point + Vector3.UP * 0.25, hatch_point + Vector3.DOWN * 1.7, 1)
	opened_ray.exclude = [world.player.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_ray(opened_ray).is_empty(), "open shaft has no floor collider across the descent")
	var shaft_shape := CapsuleShape3D.new()
	shaft_shape.radius = 0.32
	shaft_shape.height = 1.7
	var shaft_query := PhysicsShapeQueryParameters3D.new()
	shaft_query.shape = shaft_shape
	shaft_query.transform = Transform3D(Basis.IDENTITY, hatch_point + Vector3.UP * 0.1)
	shaft_query.collision_mask = 1
	shaft_query.exclude = [world.player.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(shaft_query, 1).is_empty(), "player capsule fits between the shaft walls")
	await capture("dragging")
	await create_timer(0.50).timeout
	await capture("ladder")
	await create_timer(0.65).timeout
	print("SEWER_REVIEW_PHASE descent hatch=", hatch.open_amount, " player=", world.player.global_position)
	await capture("descent")
	var deadline := Time.get_ticks_msec() + 15000
	while not entry_completed and Time.get_ticks_msec() < deadline: await process_frame
	check(entry_completed and entry_succeeded and session.state.place_id == "harbor_sewer", "entry ends inside the sewer")
	check(is_zero_approx(hatch.open_amount), "hatch is closed after the descent")
	await capture("inside")
	if entry_completed and entry_succeeded:
		check(await session.leave_place(), "sewer exit returns to the street")
		await create_timer(1.0).timeout
		check(is_zero_approx(hatch.open_amount), "hatch closes after return")
		check(is_equal_approx(world.camera.target_size, exterior_camera_size), "exterior camera framing returns")
		check(not world.player.input_locked, "player controls unlock after returning to the street")
		await capture("returned")
	print("SEWER_ANIMATION_REVIEW failures=", failures)
	world.free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)

func _run_entry(session: Node, done: Callable) -> void:
	var result: bool = await session.enter_place("harbor_sewer", false)
	done.call(result)

func _diagnose_nearby(center: Vector3) -> void:
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if Vector2(mesh.global_position.x, mesh.global_position.z).distance_to(Vector2(center.x, center.z)) < 2.2:
			print("SEWER_NEAR_MESH ", mesh.get_path(), " position=", mesh.global_position, " type=", mesh.mesh.get_class() if mesh.mesh else "none")
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		if batch.multimesh == null: continue
		for index in batch.multimesh.instance_count:
			var point: Vector3 = (batch.global_transform * batch.multimesh.get_instance_transform(index)).origin
			if Vector2(point.x, point.z).distance_to(Vector2(center.x, center.z)) < 2.2:
				print("SEWER_NEAR_BATCH ", batch.get_path(), " index=", index, " position=", point)
