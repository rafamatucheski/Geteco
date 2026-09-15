extends SceneTree

## Reproduces the reported southbound Quay Boulevard response: an ambulance
## catches the route 510 bi-articulated bus before the only south-port access.

class TestClock extends Node:
	var time_of_day := 8.0 / 24.0
	var is_dark := false
	var weather_state := 0


class TestWorld extends Node2D:
	var weather: Node


class TestLife extends "res://world/harbor/HarborLife.gd":
	func _spawn_traffic(_network: Node2D) -> void:
		pass
	func _spawn_walkers() -> void:
		pass


var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures.append(label)


func _run() -> void:
	seed(510)
	Engine.time_scale = 3.0
	var world := TestWorld.new()
	root.add_child(world)
	current_scene = world
	var clock := TestClock.new()
	world.add_child(clock)
	world.weather = clock

	var layout := preload("res://world/harbor/HarborRoadLayout.gd").new()
	layout.name = "RoadLayout"
	world.add_child(layout)
	var district := preload("res://world/harbor/HarborDistrict.gd").new()
	district.name = "District"
	world.add_child(district)
	var network := preload("res://world/harbor/HarborRoadNetwork.gd").new()
	network.name = "RoadNetwork"
	network.provider_paths.assign([NodePath("../RoadLayout")])
	world.add_child(network)
	var rail := Node2D.new()
	rail.name = "FreightRail"
	world.add_child(rail)
	var life := TestLife.new()
	life.name = "Life"
	world.add_child(life)
	life.setup(network)
	life.set_process(false)
	var transit := preload("res://world/harbor/urban_transit/UrbanTransit.gd").new()
	transit.name = "UrbanTransit"
	world.add_child(transit)

	for frame in 240:
		if transit.ready_for_service:
			break
		await process_frame
	_check(transit.ready_for_service and transit.buses.size() == 2, "Production urban fleet starts")
	if not transit.ready_for_service or transit.buses.is_empty():
		await _finish(world)
		return

	var bus: CharacterBody2D = transit.buses[0]
	var controller: Node
	for frame in 240:
		controller = bus._get_junction_traffic_controller()
		if controller != null and not controller._junctions.is_empty():
			break
		await process_frame
	_check(controller != null and not controller._junctions.is_empty(), "Junction controller is ready")
	if controller == null or controller._junctions.is_empty():
		await _finish(world)
		return

	transit.set_physics_process(false)
	transit._exchanges.erase(bus)
	for stop in transit.stops:
		if stop.service_bus == bus:
			stop.service_bus = null
	for other in transit.buses:
		if other == bus:
			continue
		other.suspended = true
		other.collision_layer = 0
		for section in other.sections:
			section.collision_layer = 0

	var quay_lane: Path2D = transit.stops[5].lane
	var follow := bus.get_parent() as PathFollow2D
	follow.reparent(quay_lane, false)
	follow.loop = false
	follow.progress = quay_lane.curve.get_closest_offset(quay_lane.to_local(Vector2(3000, 1720)))
	follow.remove_meta("traffic_planned_connection_id")
	follow.remove_meta("traffic_planned_junction_index")
	bus.position = Vector2.ZERO
	bus.rotation = 0.0
	bus.current_stop = 5
	bus.next_stop = 0
	bus.dwelling = false
	bus.doors = 0.0
	bus.suspended = false
	bus.is_broken = false
	bus._lane_motion_speed = 45.0
	bus._last_lane_motion_contract = {}
	controller.release_vehicle(bus.get_instance_id())
	bus._history_head = 0
	bus._history_count = 240
	for index in bus._history_count:
		bus.history[index] = bus.global_position - bus.global_transform.x * float(index) * 2.0
	bus._update_sections(0.0)

	var target := Node2D.new()
	target.name = "SouthPortMedicalIncident"
	target.position = Vector2(3310, 2780)
	target.set_meta("medical_pending", true)
	world.add_child(target)
	var ambulance := preload("res://EmergencyVehicle.tscn").instantiate() as CharacterBody2D
	ambulance.type = 1
	ambulance.target = target
	ambulance.position = Vector2(3030, 1280)
	ambulance.rotation = PI * 0.5
	world.add_child(ambulance)
	await physics_frame
	await physics_frame

	var siren_seen := false
	var reached_access := false
	var acted := false
	var minimum_gap := INF
	var maximum_joint_angle := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		await physics_frame
		siren_seen = siren_seen or ambulance.has_emergency_priority()
		minimum_gap = minf(minimum_gap, ambulance.global_position.distance_to(bus.global_position))
		var ahead: Node2D = bus
		for section in bus.sections:
			maximum_joint_angle = maxf(maximum_joint_angle, absf(angle_difference(ahead.global_rotation, section.global_rotation)))
			ahead = section
		reached_access = reached_access or ambulance.global_position.y > 2250.0
		acted = ambulance.is_acting
		if acted:
			break

	print("AMBULANCE_ARTICULATED_TRAFFIC ambulance=", ambulance.global_position,
		" bus=", bus.global_position, " reached_access=", reached_access,
		" acted=", acted, " router_plans=", ambulance._lane_router.plans,
		" min_gap=", minimum_gap, " bus_block_wait=", bus.block_wait_timer,
		" max_joint_degrees=", rad_to_deg(maximum_joint_angle))
	if bus.block_wait_timer > 1.0:
		_diagnose_bus_step(bus, 1.0)
	_check(siren_seen, "Dispatched ambulance advertises emergency priority")
	_check(maximum_joint_angle <= bus.MAX_ARTICULATION_ANGLE + deg_to_rad(0.1), "Every articulated hinge remains within its physical steering limit")
	_check(reached_access, "Ambulance gets through the shared quay/dock junction")
	_check(acted, "Ambulance reaches the south-port occurrence despite the articulated bus")
	await _finish(world)


func _diagnose_bus_step(bus: CharacterBody2D, advance: float) -> void:
	var follow := bus.get_parent() as PathFollow2D
	var path := follow.get_parent() as Path2D if follow else null
	if path == null:
		return
	var poses: Array[Dictionary] = [{"body": bus, "pose": bus._lane_proposed_pose(path, follow, advance)}]
	var section_poses: Array[Transform2D] = bus._constrained_section_poses(poses[0].pose)
	for index in bus.sections.size():
		poses.append({"body": bus.sections[index], "pose": section_poses[index]})
	var excluded: Array[RID] = []
	for item in poses:
		excluded.append((item.body as CollisionObject2D).get_rid())
	var polygons: Array[PackedVector2Array] = []
	var polygon_bodies: Array[Node2D] = []
	print("BUS_STEP_STATE path=", path.get_path(), " progress=", follow.progress,
		" head=", bus.global_transform, " proposed=", poses[0].pose)
	for item in poses:
		var body := item.body as CharacterBody2D
		var pose := item.pose as Transform2D
		var polygon := preload("res://world/shared/traffic/TrafficBodySweep.gd").rectangle(body, pose)
		for previous_index in polygons.size():
			var previous := polygons[previous_index]
			if not Geometry2D.intersect_polygons(polygon, previous).is_empty():
				print("BUS_STEP_BLOCKER own_body_overlap body=", body.name,
					" previous=", polygon_bodies[previous_index].name,
					" pose=", pose, " previous_pose=", poses[previous_index].pose)
		polygons.append(polygon)
		polygon_bodies.append(body)
		var hull := body.get_node("Collision") as CollisionShape2D
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = hull.shape
		query.transform = pose * hull.transform
		query.margin = 2.0
		query.collision_mask = body.collision_mask
		query.exclude = excluded
		for hit in body.get_world_2d().direct_space_state.intersect_shape(query, 32):
			var collider := hit.collider as Node2D
			print("BUS_STEP_BLOCKER body=", body.name, " collider=", collider.get_path() if collider else hit.collider,
				" position=", collider.global_position if collider else Vector2.INF)


func _finish(world: Node) -> void:
	Engine.time_scale = 1.0
	world.queue_free()
	await process_frame
	print("AMBULANCE_ARTICULATED_TRAFFIC failures=", failures)
	quit(0 if failures.is_empty() else 1)
