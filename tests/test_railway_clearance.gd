extends SceneTree
## Geometria real do Main em streaming. O posicionamento da fixture é só para as varreduras e o
## início de cada caminhada de acesso; depois o ator sobe e desce sob a física.
## Isto não certifica oclusão visual, iluminação temporal nem tempo de quadro.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const TRAIN := preload("res://world/railway/TrainModel.gd")
var world
var checks := 0
var failures: Array[String] = []
var collision_findings: Array[Dictionary] = []
var shape_queries := 0
var evidence := ""
var access_capture := 0


func _initialize() -> void:
	create_timer(450).timeout.connect(func(): push_error("RAILWAY_CLEARANCE bounded timeout"); quit(3))
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("RAILWAY_CLEARANCE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func frames(count: int) -> void:
	for index in count: await physics_frame


func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires --no-save and the compiled .NET project.")
		quit(2)
		return
	evidence = FIXTURE.output_dir("railway-clearance")
	var initial: Vector3 = NETWORK.get_station("harbor_central").entry
	var saved_point := Vector3(149.4,12.95,67) if "--legacy-station-save" in OS.get_cmdline_user_args() else initial
	var snapshot := FIXTURE.full_snapshot(saved_point, true)
	snapshot.campaign.aftermath = {"call_complete": true}
	var path := FIXTURE.write_fixture(evidence, "fixture.json", snapshot)
	check(not path.is_empty(), "isolated completed-campaign fixture is valid")
	if path.is_empty(): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	for index in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play, "actual Main ready")
	if world.session == null or not world.session.ready_for_play: finish(); return
	check(world.production.no_save and world.production.store.path == path, "fixture cannot write personal saves")
	if "--legacy-station-save" in OS.get_cmdline_user_args():
		check(world.player.global_position.distance_to(initial)<2.0,"legacy elevated station save restored at new station entrance")
	var railway_world: Node = world.production.get("railway_world")
	if railway_world == null:
		for candidate in world.find_children("RailwayWorld", "", true, false): railway_world = candidate; break
	check(is_instance_valid(railway_world), "actual RailwayWorld installed")
	if not is_instance_valid(railway_world): finish(); return
	# Para só a orquestração que brigaria com o foco da varredura; montadores de região, física,
	# colisão das estações e o Actor nativo continuam rodando normalmente.
	world.production.set_process(false)
	world.session.set_process(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.set_physics_process(false)
	railway_world.set_campaign_completed(true)
	for region_id in ["harbor", "mountain", "desert"]:
		world.production._mount_region(region_id, initial)
	if "--access-only" not in OS.get_cmdline_user_args():
		# Estes cobrem as duas aproximações da cidade, os dois ramais e a corda montanha/deserto.
		# Viagens inteiras mantêm a pose real da locomotiva pelos entroncamentos.
		for pair in [["harbor_central", "harbor_north"], ["harbor_central", "mountain_pines"], ["harbor_central", "desert_copper"], ["mountain_pines", "desert_copper"]]:
			if argument("--route-pair=") == "harbor" and pair != ["harbor_central", "harbor_north"]: continue
			for reverse in [false, true]:
				var points := NETWORK.get_route(pair[1], pair[0]) if reverse else NETWORK.get_route(pair[0], pair[1])
				await scan_edge(str(pair[0]) + "-" + str(pair[1]) + ("-return" if reverse else ""), points, railway_world)
		check(collision_findings.is_empty(), "coach and locomotive envelopes clear existing solids on every line, both directions")
	if "--scan-only" not in OS.get_cmdline_user_args():
		for station in NETWORK.stations():
			var selected_station := argument("--station=")
			if selected_station == "harbor" and station.region != "harbor": continue
			if not selected_station.is_empty() and selected_station != "harbor" and station.id != selected_station: continue
			await check_station_access(station, railway_world)
	finish()


func argument(prefix: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(prefix): return value.trim_prefix(prefix)
	return ""


func prepare(point: Vector3, railway_world: Node) -> void:
	world.player.teleport(point + Vector3.UP * 1.0)
	railway_world.set_focus(point)
	for region in world.production.regions.values():
		region.set_focus(point)
		region.prepare_collision_at(point)
	for index in 300:
		await physics_frame
		var pending := false
		for region in world.production.regions.values():
			if not region.pending.is_empty() or not region.build_jobs.is_empty(): pending = true
		if not pending: break
	await frames(3)


func scan_edge(id: String, points: PackedVector3Array, railway_world: Node) -> void:
	var length := NETWORK.route_length(points)
	var coach_shape := BoxShape3D.new()
	coach_shape.size = Vector3(3.42, 2.90, 10.8)
	var engine_shape := BoxShape3D.new()
	engine_shape.size = Vector3(2.85, 2.8, 7.95)
	var samples := ceili(length / 5.0)
	var before := collision_findings.size()
	for index in samples + 1:
		var distance := minf(float(index) * 5.0, length)
		var coach_pose := rail_pose(points, distance)
		var engine_pose := rail_pose(points, distance + TRAIN.ENGINE_LEAD)
		await prepare(coach_pose.position, railway_world)
		query_envelope(id, distance, "coach", coach_shape, coach_pose, 1.72)
		query_envelope(id, distance, "locomotive", engine_shape, engine_pose, 1.75)
	print("RAILWAY_CLEARANCE_EDGE ", id, " samples=", samples + 1, " findings=", collision_findings.size() - before)


func rail_point(points: PackedVector3Array, distance: float) -> Vector3:
	var length := NETWORK.route_length(points)
	if distance < 0.0: return points[0] + (points[1] - points[0]).normalized() * distance
	if distance > length: return points[-1] + (points[-1] - points[-2]).normalized() * (distance - length)
	return NETWORK.sample(points, distance).position


func rail_pose(points: PackedVector3Array, distance: float) -> Dictionary:
	var point := rail_point(points, distance)
	var tangent := (rail_point(points, distance + 0.8) - rail_point(points, distance - 0.8)).normalized()
	return {"position": point, "basis": Basis.looking_at(tangent, Vector3.UP)}


func query_envelope(edge: String, distance: float, vehicle: String, shape: Shape3D, pose: Dictionary, center_y: float) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(pose.basis, pose.position + pose.basis * Vector3.UP * center_y)
	query.collision_mask = 1
	query.margin = 0.0
	query.exclude = [world.player.get_rid()]
	shape_queries += 1
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider: Node = hit.collider
		var cursor := collider
		var own_train := false
		while cursor != null:
			if cursor.get_meta("railway_train", false): own_train = true; break
			cursor = cursor.get_parent()
		if own_train: continue
		var finding := {"edge": edge, "distance": distance, "vehicle": vehicle, "position": str(pose.position), "collider": str(collider.get_path())}
		if collider is CollisionObject3D:
			var owner_id: int = collider.shape_find_owner(int(hit.shape))
			var owner: Object = collider.shape_owner_get_owner(owner_id)
			if owner is CollisionShape3D:
				finding.shape_position = str(owner.global_position)
				finding.shape_size = str(owner.shape.size) if owner.shape is BoxShape3D else owner.shape.get_class()
		collision_findings.append(finding)
		if collision_findings.size() <= 30: print("RAILWAY_SOLID_INTERSECTION ", JSON.stringify(finding))


func check_station_access(station: Dictionary, railway_world: Node) -> void:
	var route: PackedVector3Array = NETWORK.approach_path(station.id)
	check(route.size() >= 4, "authored ground-to-platform access: " + str(station.id))
	if route.size() < 4: return
	world.player.set_physics_process(false)
	await prepare(route[0], railway_world)
	railway_world.ensure_station(station.id)
	await frames(5)
	world.player.teleport(route[0])
	world.player.speed = 3.2
	world.player.controlled_automatically = true
	world.player.input_locked = false
	world.player.set_physics_process(true)
	await frames(20)
	check(world.player.is_on_floor(), "station entrance has native world support: " + str(station.id))
	var climbed := await walk(route)
	check(climbed and world.player.is_on_floor() and absf(world.player.global_position.y - station.arrival.y) < 0.3, "actor physically climbs all flights and reaches platform: " + str(station.id))
	if climbed:
		route.reverse()
		check(await walk(route) and world.player.is_on_floor(), "actor physically descends to street without teleport: " + str(station.id))
	world.player.automatic_direction = Vector3.ZERO
	world.player.set_physics_process(false)


func walk(route: PackedVector3Array) -> bool:
	var deadline := Time.get_ticks_msec() + 55000
	var waypoint := 1
	var last_contacts: Array[Dictionary] = []
	while waypoint < route.size() and Time.get_ticks_msec() < deadline:
		var direction: Vector3 = route[waypoint] - world.player.global_position
		direction.y = 0
		if direction.length() < 0.20:
			if "--capture-access" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(evidence.path_join("access-%03d.png"%access_capture))
				access_capture+=1
			waypoint += 1
			continue
		world.player.automatic_direction = direction.normalized()
		await physics_frame
		last_contacts.clear()
		for index in world.player.get_slide_collision_count():
			var contact: KinematicCollision3D = world.player.get_slide_collision(index)
			var collider: Object = contact.get_collider()
			var item := {"collider": str(collider.get_path()) if collider is Node else str(collider), "point": str(contact.get_position()), "normal": str(contact.get_normal())}
			if collider is CollisionObject3D:
				var owner: Object = contact.get_collider_shape()
				if owner is CollisionShape3D:
					item.shape_position = str(owner.global_position)
					item.shape_size = str(owner.shape.size) if owner.shape is BoxShape3D else owner.shape.get_class()
			last_contacts.append(item)
	world.player.automatic_direction = Vector3.ZERO
	await frames(3)
	if waypoint < route.size():
		print("RAILWAY_ACCESS_BLOCKED waypoint=", waypoint, " position=", world.player.global_position, " target=", route[waypoint])
		for item in last_contacts: print("RAILWAY_ACCESS_CONTACT ", JSON.stringify(item))
	return waypoint == route.size()


func finish() -> void:
	if not evidence.is_empty():
		var file := FileAccess.open(evidence.path_join("clearance.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"queries": shape_queries, "intersections": collision_findings, "checks": checks, "failures": failures}, "\t"))
	print("RAILWAY_CLEARANCE_RESULT checks=%d failures=%d queries=%d intersections=%d evidence=%s" % [checks, failures.size(), shape_queries, collision_findings.size(), evidence])
	quit(0 if failures.is_empty() else 1)
