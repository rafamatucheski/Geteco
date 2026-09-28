extends SceneTree
## Visual review only, inside Main with real streamed geometry. Does not benchmark.
## Run rendered with -- --no-save --skip-arrival --output=D:/.../air-k9
var world: Node3D
var folder := "res://evidence/police-response-20260928/air-k9"

func _initialize() -> void: run.call_deferred()

func wait_until(predicate: Callable, limit: int) -> bool:
	for index in limit:
		if predicate.call(): return true
		await physics_frame
	return false

func capture(label: String) -> void:
	# Let camera transforms reach RenderingServer before reading the next image.
	# A post_draw signal alone can still describe the camera from this frame.
	await process_frame
	await process_frame
	if not label.begins_with("rappel-sequence"):
		await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	print("AIR_K9_CAPTURE ", label, " result=", result)

func fail(reason: String) -> void:
	push_error(reason)
	if is_instance_valid(world): world.queue_free()
	quit(1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or "--skip-arrival" not in args or DisplayServer.get_name() == "headless":
		fail("Capture requires rendered Godot, --no-save and --skip-arrival")
		return
	for arg in args:
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play and world.production.ready_for_play, 2400):
		fail("Main did not become ready")
		return
	if not world.session.state.place_id.is_empty(): world.session.leave_place()
	if not await wait_until(func(): return world.session.state.place_id.is_empty(), 240):
		fail("Could not exit initial interior through normal session transition")
		return
	var gameplay: Node3D = world.gameplay
	# skip_dispatch removes vehicles; suppress the legacy foot-only fallback as
	# well so this visual fixture observes exactly the transported squad.
	gameplay.dispatch_owned = true
	var director: Node3D = gameplay.police_air
	director.set_physics_process(false)
	gameplay.clear_wanted()
	# Public street near the original harbor start; keep the live map/traffic.
	var anchor: Vector3 = world.player.global_position
	world.production.region.set_focus(anchor)
	for index in 90: await physics_frame
	var zone: Dictionary = {}
	for index in 6:
		zone = director.find_landing_zone(anchor)
		if not zone.is_empty(): break
	if zone.is_empty():
		fail("No physically clear four-person landing zone near the actual player")
		return
	gameplay.crime_points = 60
	gameplay._update_stars()
	gameplay.report_contact(anchor)
	if not director.launch_helicopter(zone):
		fail("Aerial response could not launch")
		return
	var heli: CharacterBody3D = director.helicopter
	if not await wait_until(func(): return is_instance_valid(heli) and heli.mode == "rappel" and heli.deployed_count == 4, 2700):
		fail("Helicopter never reached four-person rappel; inspect collision/landing admission")
		return
	heli.set_physics_process(false)
	print("AIR_K9_CAPTURE zone=", zone.center, " officers=", heli.rappellers.size())
	await capture("rappel-gameplay-camera")
	# Explicit inspection camera: the normal screenshot above remains evidence
	# of play framing; this second view verifies depth and the four moving ropes.
	var review := Camera3D.new()
	review.projection = Camera3D.PROJECTION_ORTHOGONAL
	review.size = 30.0
	review.far = 250.0
	world.add_child(review)
	review.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	review.global_position = zone.center + Vector3(20, 20, 27)
	review.look_at(zone.center + Vector3.UP * 6.0)
	review.make_current()
	await capture("rappel-four-ropes-overview")
	var daytime: float = world.session.weather.time_of_day
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .9
	world.session.weather._update()
	heli._sense()
	await capture("rappel-night-spotlight")
	world.session.weather.time_of_day = daytime
	world.session.weather._update()
	heli._sense()
	world.session.weather.set_process(true)
	review.size = 15.5
	review.global_position = heli.global_position + Vector3(10, 6, -13)
	review.look_at(heli.global_position + Vector3.UP * .6)
	await capture("helicopter-airframe-close")
	if not heli.rappellers.is_empty():
		var first: CharacterBody3D = heli.rappellers[0].officer
		var body_focus := first.global_position + Vector3.UP * 1.0
		review.size = 4.5
		review.global_position = body_focus + Vector3(3.0, 1.6, -3.8)
		review.look_at(body_focus)
		await capture("rappel-gloves-harness-close")
	review.size = 30.0
	review.global_position = zone.center + Vector3(20, 20, 27)
	review.look_at(zone.center + Vector3.UP * 6.0)
	heli.set_physics_process(true)
	for frame in 18:
		for step in 12: await physics_frame
		await capture("rappel-sequence-%02d" % frame)
	if not await wait_until(func(): return gameplay.police.size() >= 4, 900):
		fail("Four real officers did not reach the ground")
		return
	if is_instance_valid(heli) and await wait_until(func(): return not is_instance_valid(heli) or (heli.mode == "depart" and heli._mode_time >= 1.4), 300):
		if is_instance_valid(heli): await capture("departure-climb")
	if is_instance_valid(heli) and await wait_until(func(): return not is_instance_valid(heli) or (heli.mode == "depart" and heli._mode_time >= 4.4), 300):
		if is_instance_valid(heli):
			heli.set_physics_process(false)
			review.size = 21.0
			review.global_position = heli.global_position + Vector3(17, 10, 20)
			review.look_at(heli.global_position)
			await capture("departure-banking-turn")
			heli.set_physics_process(true)
	for index in 10: await physics_frame
	# Deployment uses the same offscreen+capsule+handler checks as gameplay.
	review.global_position += Vector3(100, 0, 100)
	review.look_at(zone.center + Vector3(100, 0, 100))
	director._try_deploy_dog()
	if director.dogs.is_empty():
		fail("No eligible grounded handler and free offscreen K9 position")
		return
	var dog: CharacterBody3D = director.dogs[0]
	var center := dog.global_position + Vector3.UP * 0.55
	review.size = 7.5
	review.global_position = center + Vector3(6, 4.5, 7)
	review.look_at(center)
	for index in 3: await physics_frame
	await capture("k9-with-live-handler")
	print("AIR_K9_CAPTURE completed; visual review needed; performance not measured")
	world.queue_free()
	await process_frame
	quit(0)
