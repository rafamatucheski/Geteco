extends SceneTree

const SCENE := preload("res://world/harbor/HarborPreview.tscn")
const SAFETY := preload("res://world/harbor/HarborSafety.gd")
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(4307)
	var scene := SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var safety := scene.get_node_or_null("RoadSafety")
	if safety == null:
		safety = SAFETY.new()
		safety.name = "RoadSafety"
		scene.add_child(safety)
	await create_timer(0.6).timeout
	var data: Dictionary = safety.get_safety_data()
	_check(data.validation_errors.is_empty(), "Safety validation: %s" % [data.validation_errors])
	_check(data.rail_level_crossings.is_empty(), "Elevated railway must not create ground-level barriers")
	_check(data.grade_separated_rail_crossings.size() >= 4, "City viaduct must cross four actual streets")
	for intersection in data.grade_separated_rail_crossings:
		var elevated := String(intersection.classification) == "rail_elevated" and float(intersection.rail_elevation) >= 48.0
		var underground := String(intersection.classification) == "rail_underground" and float(intersection.rail_elevation) <= -12.0
		_check(elevated or underground, "Rua exige separação vertical explícita: viaduto acima ou túnel abaixo")
		var at: Vector2 = intersection.position
		var ray := PhysicsRayQueryParameters2D.create(at + Vector2(0, -80), at + Vector2(0, 80), 1)
		var collision: Dictionary = scene.get_world_2d().direct_space_state.intersect_ray(ray)
		_check(collision.is_empty(), "Street below viaduct must remain physically open at %s" % at)
	var ramp_ray := PhysicsRayQueryParameters2D.create(Vector2(3114, 2320), Vector2(3114, 3310), 1)
	_check(scene.get_world_2d().direct_space_state.intersect_ray(ramp_ray).is_empty(), "Real ramp corridor must fit the sea embankment and southern fence opening")
	var rail := scene.get_node("FreightRail")
	var cranes: Array = scene.get_node("Waterfront").get_waterfront_audit_data().crane_obstacles
	var rail_points: PackedVector2Array = rail.get_rail_graph_data().points_local
	for point in rail_points:
		if point.y >= 1192.0 and point.y <= 2240.0 and point.x > 2800.0:
			for crane in cranes:
				_check(not (crane as Rect2).grow(24.0).has_point(point), "Viaduct deck must not overlap crane bases")
	_check(data.pedestrian_crossings.size() > 0, "Functional crosswalk nodes must exist")
	var crossings: Array[Node] = safety.find_children("*", "Area2D", true, false)
	var crossing: RoadCrossingArea2D
	for candidate in crossings:
		# This regression exercises synchronized SIGNAL phases and sibling-arm
		# demand. Ashbend also has valid unsignalized crossings; do not choose
		# one merely because it happens to be first in the generated node list.
		if candidate is RoadCrossingArea2D and bool(candidate.get_crossing_data().has_signal_state):
			crossing = candidate
			break
	_check(crossing != null, "Signal-phase fixture requires a controlled RoadCrossingArea2D")
	if crossing == null:
		quit(1)
		return
	var player: CharacterBody2D = scene.get_node("Player")
	_check(player.is_in_group("pedestrian"), "Preview player must participate in pedestrian crossing detection")
	# Request through the real Area2D overlap at the sidewalk waiting pad.
	player.global_position = crossing.to_global(Vector2(0, crossing.road_width * 0.5 + 20.0))
	var controller: Node = scene.get_node("Life").traffic_controller
	var requested := false
	var granted := false
	var probe: DemoTrafficVehicle
	Engine.time_scale = 4.0
	for sample in 120:
		await create_timer(0.2).timeout
		var state := crossing.get_crossing_data()
		requested = requested or int(state.pedestrians_inside) > 0
		if requested and crossing.is_pedestrian_allowed():
			granted = true
			# Synchronizing an empty sibling arm must not revoke this occupied
			# crossing's extended pedestrian clearance request.
			controller.call("_synchronize_crossing_consumers")
			for sibling in crossings:
				if sibling is RoadCrossingArea2D and sibling != crossing and sibling.junction_id == crossing.junction_id and int(sibling.get_crossing_data().pedestrians_inside) == 0:
					var sibling_state: Dictionary = sibling.get_crossing_data()
					sibling.set_signal_state(sibling_state.vehicle_permitted, sibling_state.pedestrian_permitted)
					break
			var demand: Dictionary = controller.get("_pedestrian_demand")
			_check(bool(demand.get(int(crossing.get_meta("junction_index")), false)), "Occupied arm pedestrian demand must survive synchronization of empty arms")
			_check(crossing.should_stop_vehicle(), "Pedestrian phase must stop civil vehicles")
			_check(not controller.get_vehicle_permission(crossing.junction_id, crossing.road_index), "Junction authority must deny vehicle passage during pedestrian phase")
			probe = await _assert_civil_stop(scene, crossing)
			break
	var handoffs_before := int(controller.get_telemetry_snapshot().connector_handoffs)
	var probe_before := probe.global_position if is_instance_valid(probe) else Vector2.ZERO
	player.global_position = Vector2(715, 1800)
	for sample in 40:
		await create_timer(1.0).timeout
	var telemetry: Dictionary = controller.get_telemetry_snapshot()
	_check(is_instance_valid(probe) and probe.global_position.distance_to(probe_before) > 120.0, "Stopped civil vehicle must resume real travel after the player leaves")
	_check(int(telemetry.connector_handoffs) > handoffs_before + 5, "Crosswalks must not deadlock ambient lane transfers")
	_check(int(telemetry.deadlock_limit_exceeded) == 0, "No junction deadlock reported during crossing traffic test")
	Engine.time_scale = 1.0
	_check(requested, "Real player body overlap must register crossing demand")
	_check(granted, "Controller must serve the requested pedestrian phase")
	if not granted:
		print("UNSERVED_CROSSING ", crossing.get_crossing_data(), " JUNCTION ", controller.get_junction_snapshot(crossing.junction_id))
		for car in scene.get_node("Life").vehicles:
			print("TRAFFIC_PROBE ", car.name, " ", car.global_position, " ", car.get_parent().get_parent().name)
	print("HARBOR_SAFETY_RESULT failures=%d crossings=%d player_request=%s pedestrian_granted=%s handoffs=%d" % [failures.size(), data.pedestrian_crossings.size(), requested, granted, int(telemetry.connector_handoffs)])
	scene.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)


func _assert_civil_stop(scene: Node, crossing: RoadCrossingArea2D) -> DemoTrafficVehicle:
	var network := scene.get_node("RoadNetwork")
	var path: Path2D
	for candidate in network.find_children("*", "Path2D", true, false):
		if candidate.is_in_group("unified_traffic_lane") and String(candidate.get_meta("traffic_road_id", "")) == String(crossing.road_id) and int(candidate.get_meta("traffic_direction", 0)) == 1:
			path = candidate
			break
	_check(path != null, "Requested crossing must have a canonical vehicle lane")
	if path == null:
		return null
	var car := FACTORY.spawn_moving_vehicle(path, "CrosswalkProbeCar", "sedan_classic", 0.1, 100.0, 0)
	var follow := car.get_parent() as PathFollow2D
	var crossing_offset := path.curve.get_closest_offset(path.to_local(crossing.global_position))
	follow.progress = crossing_offset - car.target_length * 0.5 - 17.0
	var motion: Dictionary = car.call("_traffic_control_zone_motion", path, follow)
	_check(float(motion.allowed_advance) <= 0.1, "Real civil traffic consumer must clamp crossing advance")
	var before := car.global_position
	await create_timer(0.5).timeout
	_check(car.global_position.distance_to(before) <= 3.0, "Real civil car must remain stopped during pedestrian permission")
	return car


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
