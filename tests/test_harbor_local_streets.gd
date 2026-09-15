extends SceneTree
const LOCAL := preload("res://world/harbor/HarborLocalStreets.gd")
const OUTPUT := "D:/geteco/artifacts/local-streets-0914/validation"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func run() -> void:
	create_timer(180).timeout.connect(func(): print("LOCAL_STREETS TIMEOUT"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	root.get_node("SaveManager")._save_dir = OUTPUT + "/saves/"
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("CampaignState").reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	paused = false
	if OS.get_cmdline_user_args().has("--garage-only"):
		await garage_transition(world)
		print("LOCAL_GARAGE checks=%d failures=%s" % [checks, failures])
		quit(0 if failures.is_empty() else 1)
		return
	if OS.get_cmdline_user_args().has("--police-only"):
		await police_departure(world)
		await garage_transition(world)
		print("LOCAL_POLICE checks=%d failures=%s" % [checks, failures])
		quit(0 if failures.is_empty() else 1)
		return
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector2(750, 1660)
	var district = world.get_node("District")
	check(district.get_spatial_audit().is_empty(), "Building / access audit: " + str(district.get_spatial_audit()))
	check(district.get_node("Garage").position == LOCAL.GARAGE_POSITION, "Garage moved north")
	check(district.get_node("Garage/Entrance").global_position.y < 1690, "Garage door follows building")
	var network = world.get_node("RoadNetwork")
	check(network.get_validation_errors().is_empty(), "Road graph: " + str(network.get_validation_errors()))
	var local_lanes: Array[Path2D] = []
	for lane in get_nodes_in_group("unified_traffic_lane"):
		if String(lane.get_meta("traffic_road_id", "")).get_file() in ["westgate_service_lane", "medical_garden_lane"]:
			local_lanes.append(lane)
	check(local_lanes.size() == 4, "Two streets expose four real directed lanes")
	# Freeze traffic at this point; static sweeps exclude moving actors, while
	# the actual departure below retains production vehicle collision behavior.
	var ignored: Array[RID] = []
	for actor in world.find_children("*", "CharacterBody2D", true, false):
		if not actor is DemoTrafficVehicle or actor.get_parent() is PathFollow2D:
			ignored.append(actor.get_rid())
	for i in 3: await physics_frame
	var tow: CharacterBody2D = world.get_node("ThematicFleet/WorkshopTowTruck")
	check(not tow.test_move(tow.global_transform, Vector2(0, .1)), "Tow truck bay stays clear of scenery and player's parked car")
	for lane in local_lanes:
		var length := lane.curve.get_baked_length()
		var offset := 65.0
		while offset < length - 65:
			var p: Vector2 = lane.to_global(lane.curve.sample_baked(offset))
			var next: Vector2 = lane.to_global(lane.curve.sample_baked(offset + 25))
			var shape := RectangleShape2D.new()
			shape.size = Vector2(104, 42)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform = Transform2D(p.direction_to(next).angle(), p)
			query.motion = next - p
			query.collision_mask = 3
			query.exclude = ignored
			var result: PackedFloat32Array = world.get_world_2d().direct_space_state.cast_motion(query)
			check(result[0] == 1.0, "Ambulance swept footprint on " + str(lane.name) + " at " + str(p))
			offset += 25
	# Both real actor bodies must be stopped by each individual supply object.
	var npc: CharacterBody2D = world.get_node("Life").walkers[0]
	npc.ensure_presentation()
	npc.set_physics_process(false)
	for actor in [player, npc]:
		actor.collision_mask |= 1
		for body in get_nodes_in_group("garage_supply_solid"):
			var polygon: CollisionPolygon2D = body.get_child(0)
			check(not polygon.polygon.is_empty(), "Supply mesh has projected solid")
			var center: Vector2 = body.global_position
			for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var hit := KinematicCollision2D.new()
				var blocked: bool = actor.test_move(Transform2D(0, center + dir * 36), -dir * 72, hit)
				check(blocked and hit.get_collider() == body, "Swept " + str(actor.name) + " versus " + str(body.get_parent().name) + " " + str(dir))
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(1300, 1710)
	camera.zoom = Vector2.ONE * .68
	camera.make_current()
	world.weather.time_of_day = .45
	world.weather.set_weather(0)
	for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
	while not world.get_node("RoadLighting").ready_for_audit: await process_frame
	for frame in 30: await process_frame
	await shot("streets-overview")
	if OS.get_cmdline_user_args().has("--geometry-only"):
		print("LOCAL_GEOMETRY checks=%d failures=%s" % [checks, failures])
		quit(0 if failures.is_empty() else 1)
		return
	# Confirm rendered occlusion has a positive front-side control for each actor.
	if DisplayServer.get_name() != "headless":
		var view = district.get_node("GarageSupplies/DrumsEast")
		var zone = view.get_children().filter(func(n): return n is Area2D)[0]
		camera.global_position = view.global_position
		camera.zoom = Vector2.ONE * 4.0
		for actor in [player, npc]:
			player.global_position = view.global_position + Vector2(150, 0)
			for side in [-1, 1]:
				actor.global_position = view.global_position + Vector2(0, side * 28)
				actor.reset_physics_interpolation()
				for frame in 12: await physics_frame
				zone._process(0.0)
				check(zone.overlay.visible == (side < 0), "Supply depth front/behind " + str(actor.name) + " " + str(side))
				await shot(str(actor.name) + ("-behind" if side < 0 else "-front"))
			actor.global_position = Vector2(1300, 1200)
	# Real dispatch must use the new medical exit and advance through its aisle.
	var director = world.get_node("HarborEmergencyDirector")
	var target := Node2D.new()
	world.add_child(target)
	target.position = Vector2(1300, 2100)
	var ambulance = director._dispatch_unbatched("ambulance", target, false)
	check(is_instance_valid(ambulance), "Ambulance dispatch succeeds")
	if is_instance_valid(ambulance):
		check(ambulance.has_meta("depot_departure_waypoints"), "West incident uses medical south aisle")
		var end := Time.get_ticks_msec() + 22000
		var report_at := 0
		while bool(ambulance.get_meta("depot_departure_pending", false)) and Time.get_ticks_msec() < end:
			await physics_frame
			if Time.get_ticks_msec() >= report_at:
				report_at = Time.get_ticks_msec() + 2000
				print("LOCAL_DEPARTURE position=", ambulance.global_position, " heading=", ambulance.rotation, " speed=", ambulance.current_speed, " cursor=", ambulance._depot_driveway.cursor, " reversing=", ambulance.is_reversing, " passage=", ambulance._traffic_passage.state, " returning=", ambulance.is_returning_to_base)
		check(not bool(ambulance.get_meta("depot_departure_pending", false)), "Real ambulance clears new exit: " + str(ambulance.global_position))
		if bool(ambulance.get_meta("depot_departure_pending", false)):
			var hull: CollisionShape2D = ambulance.get_node("CollisionShape2D")
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = hull.shape
			query.transform = ambulance.global_transform * hull.transform
			query.margin = 8
			query.collision_mask = ambulance.collision_mask
			query.exclude = [ambulance.get_rid()]
			for hit in world.get_world_2d().direct_space_state.intersect_shape(query): print("DEPARTURE_BLOCKER ", hit.collider.get_path())
	print("LOCAL_STREETS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))

func police_departure(world: Node2D) -> void:
	var target := Node2D.new()
	target.set_meta("ambient_crime", true)
	world.add_child(target)
	target.position = Vector2(400, 1500)
	var director = world.get_node("HarborEmergencyDirector")
	var unit = director._dispatch_unbatched("police", target, false)
	check(is_instance_valid(unit), "Police dispatch succeeds at its real bay")
	if not is_instance_valid(unit): return
	var gate: Vector2 = unit.get_meta("depot_road_gate")
	check(absf(gate.y - LOCAL.PATROL_Y) <= 36, "Police gate joins the new local street")
	var end := Time.get_ticks_msec() + 22000
	while bool(unit.get_meta("depot_departure_pending", false)) and Time.get_ticks_msec() < end:
		await physics_frame
	check(not bool(unit.get_meta("depot_departure_pending", false)), "Police clears the north aisle: " + str(unit.global_position))
	check(unit.global_position.y < 1780, "Police physically reaches the new street")
	if bool(unit.get_meta("depot_departure_pending", false)):
		print("POLICE_BLOCK pose=", unit.global_transform, " clearance=", unit._forward_clearance(), " traffic=", unit._is_vehicle_ahead(), " acting=", unit.is_acting, " return=", unit.is_returning_to_base)
		var ray := PhysicsRayQueryParameters2D.create(unit.global_position, unit.global_position + unit.transform.x * 200, 3)
		ray.exclude = [unit.get_rid()]
		var hit := world.get_world_2d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): print("POLICE_BLOCKER ", hit.collider.get_path(), " at=", hit.position)

func garage_transition(world: Node2D) -> void:
	var player = world.get_node("Player")
	var door = world.get_node("District/Garage/Entrance")
	var manager = world.get_node("Interiors")
	var garage = manager.garage_interior
	world._walk()
	player.global_position = door.to_global(Vector2(0, 42))
	player.reset_physics_interpolation()
	await create_timer(1.0).timeout
	check(door.open_amount > .95, "Relocated garage opens on actual approach")
	check(player.global_position.distance_to(door.global_position) < 100, "Approach alone stays outside")
	Input.action_press("move_up")
	await create_timer(1.1).timeout
	Input.action_release("move_up")
	# The physical threshold starts the normal fade; transfer occurs afterwards.
	# Wait on that lifecycle instead of checking coordinates midway through it.
	var fade_deadline := Time.get_ticks_msec() + 3000
	while manager._fade_busy and Time.get_ticks_msec() < fade_deadline: await process_frame
	check(player.global_position.distance_to(garage.spawn_point.global_position) < 250, "Physical walk through the relocated door enters garage")
	manager._on_exit_door_requested(garage.exit_door, player, &"", null, &"", &"harbor/District/Garage/Entrance")
	check(player.global_position.distance_to(door.get_node("OutsideReturn").global_position) < 1, "Exit returns beside the relocated door")
	check(not player.test_move(player.global_transform, Vector2(0, 2)), "Full player body fits at exterior return")
