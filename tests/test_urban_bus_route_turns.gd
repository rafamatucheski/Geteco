extends SceneTree

## Regression for every corner of route 510. An articulated bus must move its
## complete two-body convoy beyond each junction, not only hand its lead body
## to the destination lane.

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
	var road_lighting := preload("res://geodata/roads/RoadLighting.gd").new()
	road_lighting.name = "RoadLighting"
	world.add_child(road_lighting)

	for frame in 240:
		if transit.ready_for_service and road_lighting.ready_for_audit:
			break
		await process_frame
	_check(transit.ready_for_service and transit.buses.size() == 2, "Production urban fleet starts")
	_check(road_lighting.ready_for_audit, "Production road-lighting infill is present")
	var unsafe_lamps: Array[Node] = []
	for lamp in get_nodes_in_group("street_lamp"):
		for clearance in road_lighting.ARTICULATED_TURN_CLEARANCES:
			if clearance.has_point(lamp.global_position):
				unsafe_lamps.append(lamp)
				break
	_check(unsafe_lamps.is_empty(), "Authored and generated lamp bases stay outside articulated tail envelopes")
	if not transit.ready_for_service or transit.buses.is_empty():
		await _finish(world)
		return

	var bus: CharacterBody2D = transit.buses[0]
	_check(bus.get_traffic_bodies().size() == 2, "Bus has exactly two physical bodies")
	_check(is_equal_approx(bus.get_traffic_storage_length(), 266.0), "Traffic reserves the shorter convoy length")
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

	var scenarios: Array[Dictionary] = [
		{
			"label": "Dock to Westgate",
			"lane": transit.stops[0].lane,
			"start": Vector2(720, 2200),
			"current_stop": 0,
			"next_stop": 1,
			"destination": "westgate_drive",
			# The scheduled stop is at y=1730. Reaching it leaves the 320 px
			# convoy entirely beyond the y=2200 junction.
			"cleared": func(point: Vector2) -> bool: return point.y < 1780.0,
		},
		{
			"label": "Westgate to Foundry",
			"lane": transit.stops[2].lane,
			"start": Vector2(400, 720),
			"current_stop": 2,
			"next_stop": 3,
			"destination": "foundry_avenue",
			"cleared": func(point: Vector2) -> bool: return point.x > 880.0,
		},
		{
			"label": "Foundry to Quay",
			"lane": transit.stops[3].lane,
			"start": Vector2(2680, 400),
			"current_stop": 3,
			"next_stop": 4,
			"destination": "quay_boulevard",
			"cleared": func(point: Vector2) -> bool: return point.y > 880.0,
		},
		{
			"label": "Quay to Dock",
			"lane": transit.stops[5].lane,
			"start": Vector2(3000, 1880),
			"current_stop": 5,
			"next_stop": 0,
			"destination": "dock_street",
			"cleared": func(point: Vector2) -> bool: return point.x < 2520.0,
		},
	]
	for scenario in scenarios:
		var cleared := await _run_turn(bus, controller, scenario)
		_check(cleared, "%s clears its complete convoy" % scenario.label)

	await _finish(world)


func _run_turn(bus: CharacterBody2D, controller: Node, scenario: Dictionary) -> bool:
	controller.release_vehicle(bus.get_instance_id())
	var lane := scenario.lane as Path2D
	var follow := bus.get_parent() as PathFollow2D
	follow.reparent(lane, false)
	follow.loop = false
	follow.progress = lane.curve.get_closest_offset(lane.to_local(scenario.start))
	for key in [
		"traffic_planned_connection_id",
		"traffic_planned_junction_index",
		"traffic_connector_source_lane_id",
		"traffic_connector_destination_lane_id",
	]:
		follow.remove_meta(key)
	bus.position = Vector2.ZERO
	bus.rotation = 0.0
	bus.current_stop = int(scenario.current_stop)
	bus.next_stop = int(scenario.next_stop)
	bus.dwelling = false
	bus.doors = 0.0
	bus.suspended = false
	bus.is_broken = false
	bus.speed = 118.0
	bus._lane_motion_speed = 70.0
	bus._last_lane_motion_contract = {}
	bus.block_wait_timer = 0.0
	bus._pending_section_poses.clear()
	bus._history_head = 0
	bus._history_count = 240
	for index in bus._history_count:
		bus.history[index] = bus.global_position - bus.global_transform.x * float(index) * 2.0
	bus._update_sections(0.0)
	await physics_frame
	await physics_frame

	var entered_destination := false
	var maximum_joint_angle := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 8000:
		await physics_frame
		var active_follow := bus.get_parent() as PathFollow2D
		var active_lane := active_follow.get_parent() as Path2D if active_follow else null
		var road := String(active_lane.get_meta("traffic_road_id", "")).get_file() if active_lane else ""
		entered_destination = entered_destination or road == String(scenario.destination)
		var ahead: Node2D = bus
		for section in bus.sections:
			maximum_joint_angle = maxf(maximum_joint_angle, absf(angle_difference(ahead.global_rotation, section.global_rotation)))
			ahead = section
		if entered_destination and scenario.cleared.call(bus.global_position):
			print("URBAN_BUS_TURN label=", scenario.label, " result=cleared position=", bus.global_position,
				" lane=", road, " wait=", bus.block_wait_timer,
				" max_joint_degrees=", rad_to_deg(maximum_joint_angle))
			return true

	var final_follow := bus.get_parent() as PathFollow2D
	var final_lane := final_follow.get_parent() as Path2D if final_follow else null
	print("URBAN_BUS_TURN label=", scenario.label, " result=blocked position=", bus.global_position,
		" lane=", String(final_lane.get_meta("traffic_road_id", "")) if final_lane else "none",
		" progress=", final_follow.progress if final_follow else -1.0,
		" wait=", bus.block_wait_timer, " contract=", bus._last_lane_motion_contract,
		" max_joint_degrees=", rad_to_deg(maximum_joint_angle))
	_diagnose_bus_step(bus, 1.0)
	return false


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
		print("BUS_STEP_BODY name=", body.name, " current=", body.global_transform,
			" proposed=", pose, " degrees=", rad_to_deg(pose.get_rotation()))
		var polygon := preload("res://cars/traffic/TrafficBodySweep.gd").rectangle(body, pose)
		for previous_index in polygons.size():
			if not Geometry2D.intersect_polygons(polygon, polygons[previous_index]).is_empty():
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
			print("BUS_STEP_BLOCKER body=", body.name,
				" collider=", collider.get_path() if collider else hit.collider,
				" position=", collider.global_position if collider else Vector2.INF)


func _finish(world: Node) -> void:
	Engine.time_scale = 1.0
	world.queue_free()
	await process_frame
	print("URBAN_BUS_ROUTE_TURNS failures=", failures)
	quit(0 if failures.is_empty() else 1)
