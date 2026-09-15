extends SceneTree

const CONTROLLER_SCRIPT := preload("res://geodata/roads/traffic/JunctionTrafficController.gd")
const VEHICLE_SCENE := preload("res://cars/traffic/TrafficVehicle.tscn")

class FakeUnifiedGraph:
	extends Node2D
	var junctions: Array = []

	func get_graph_data() -> Dictionary:
		return {"junctions": junctions.duplicate(true)}


class FakeTrafficControlZone:
	extends Node2D
	var closed := true
	var road_id := "safety_road"

	func _ready() -> void:
		add_to_group("traffic_control_zone")

	func should_stop_vehicle(_vehicle: Node = null) -> bool:
		return closed

	func get_crossing_data() -> Dictionary:
		return {"id": &"test_gate", "road_id": road_id, "position": global_position}


class FakePedestrianCrossing:
	extends Node
	var junction_id: StringName = &""
	var road_index := -1
	var has_signal_state := true
	var signal_updates := 0
	var clear_updates := 0
	var signal_controller: Node = null

	func _ready() -> void:
		add_to_group("road_crossing_area")

	func get_crossing_data() -> Dictionary:
		return {
			"crossing_id": &"test_crossing",
			"junction_id": junction_id,
			"road_index": road_index,
		}

	func set_signal_state(_vehicle_permitted: bool, _pedestrian_permitted: bool) -> void:
		has_signal_state = true
		signal_updates += 1

	func clear_signal_state() -> void:
		has_signal_state = false
		clear_updates += 1

	func set_signal_controller(controller: Node) -> void:
		signal_controller = controller


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	var graph := FakeUnifiedGraph.new()
	graph.name = "FakeUnifiedRoadNetwork"
	root.add_child(graph)
	var lane_a := _make_path(graph, "lane_a", PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), 0)
	var lane_b := _make_path(graph, "lane_b", PackedVector2Array([Vector2(200, 0), Vector2(100, 0)]), 1)
	var outgoing := _make_path(graph, "lane_out", PackedVector2Array([Vector2(100, 0), Vector2(100, 120)]), 1)
	var connector := _make_connector(graph, lane_a, outgoing)
	graph.junctions = [{
		"id": "signalized_test",
		"position": Vector2(100, 0),
		"radius": 20.0,
		"signalized": true,
		"roads": [0, 1],
		"approaches": [
			{"road_index": 0, "road_width": 80.0, "direction": 1, "entry_tangent": Vector2.RIGHT},
			{"road_index": 1, "road_width": 96.0, "direction": -1, "entry_tangent": Vector2.LEFT},
		],
		"lane_connections": [{
			"connection_id": "0:lane_a>lane_out",
			"junction_index": 0,
			"from_road_index": 0,
			"from_lane_id": "lane_a",
			"to_road_index": 1,
			"to_lane_id": "lane_out",
			"movement": "right",
			"requires_connector": true,
			"path": connector,
			"entry_curve_offset": 75.0,
			"exit_curve_offset": 25.0,
		}],
	}, {
		"id": "two_approach_continuation",
		"position": Vector2(400, 0),
		"radius": 20.0,
		"signalized": false,
		"roads": [2, 3],
		"approaches": [
			{"road_index": 2, "road_width": 72.0, "direction": 1, "entry_tangent": Vector2.RIGHT},
			{"road_index": 3, "road_width": 72.0, "direction": -1, "entry_tangent": Vector2.LEFT},
		],
		"lane_connections": [],
	}]

	var unsignalized_crossing := FakePedestrianCrossing.new()
	unsignalized_crossing.junction_id = &"two_approach_continuation"
	unsignalized_crossing.road_index = 2
	root.add_child(unsignalized_crossing)
	var controller = CONTROLLER_SCRIPT.new()
	controller.minimum_green_seconds = 0.05
	controller.yellow_seconds = 0.03
	controller.all_red_seconds = 0.03
	root.add_child(controller)
	controller.configure_graph_source(graph)
	await process_frame

	_check(controller.get_junction_id(0) != &"", "junction must receive a stable id")
	_check(controller.is_junction_signalized(0), "explicitly signalized two-approach fixture must preserve its override")
	_check(not controller.is_junction_signalized(1), "two-approach continuation must remain unsignalized")
	_check(controller.get_vehicle_permission(0, 0), "first road must start green")
	_check(not controller.get_vehicle_permission(0, 1), "conflicting road must start red")
	_check(controller.get_vehicle_permission(1, 2), "first unsignalized approach must never receive an invisible red")
	_check(controller.get_vehicle_permission(1, 3), "second unsignalized approach must never receive an invisible red")
	_check(controller.get_signal_state(1, 2) == CONTROLLER_SCRIPT.SignalState.GREEN, "unsignalized state API must report green/free passage")
	_check(not controller.is_pedestrian_phase(1), "unsignalized continuation must not manufacture an all-red pedestrian phase")
	_check(controller.get_signal_visual_count() == 1, "only the explicitly signalized junction may create a signal visual")
	_check(not unsignalized_crossing.has_signal_state, "unsignalized crossing consumer must restore pedestrian-priority mode")
	_check(unsignalized_crossing.clear_updates > 0, "unsignalized crossing consumer must explicitly clear stale signal state")
	_check(unsignalized_crossing.signal_updates == 0, "unsignalized crossing consumer must not receive a fabricated traffic phase")
	_check(unsignalized_crossing.signal_controller == null, "unsignalized crossing consumer must not retain the signal controller")
	var signal_visual := controller.get_node_or_null("Signals_%s" % String(controller.get_junction_id(0)))
	_check(signal_visual != null and signal_visual.has_method("get_signal_layout"), "signalized junction must expose its derived visual layout")
	if signal_visual != null and signal_visual.has_method("get_signal_layout"):
		for layout_value in signal_visual.call("get_signal_layout"):
			var layout := layout_value as Dictionary
			_check(
				float(layout.lateral_distance) >= float(layout.road_width) * 0.5 + 9.9,
				"signal pole must sit beyond the graph-provided road edge"
			)
	_check(
		controller.get_node_or_null("Signals_%s" % String(controller.get_junction_id(1))) == null,
		"unsignalized continuation must not create a hidden/visual signal node"
	)

	var merge_vehicle_a := Node2D.new()
	merge_vehicle_a.name = "MergeVehicleA"
	root.add_child(merge_vehicle_a)
	var merge_vehicle_b := Node2D.new()
	merge_vehicle_b.name = "MergeVehicleB"
	root.add_child(merge_vehicle_b)
	_check(
		controller.try_reserve_junction(1, merge_vehicle_a.get_instance_id(), 2, &"merge_a", merge_vehicle_a),
		"unsignalized continuation must still grant an exclusive conflict reservation"
	)
	_check(
		not controller.try_reserve_junction(1, merge_vehicle_b.get_instance_id(), 3, &"merge_b", merge_vehicle_b),
		"unsignalized continuation must deny a concurrent conflicting reservation"
	)
	_check(
		controller.get_signal_state(1, 3) == CONTROLLER_SCRIPT.SignalState.GREEN,
		"reservation yielding must not masquerade as a red signal phase"
	)
	controller.release_junction(1, merge_vehicle_a.get_instance_id())
	_check(
		controller.try_reserve_junction(1, merge_vehicle_b.get_instance_id(), 3, &"merge_b", merge_vehicle_b),
		"second unsignalized approach must reserve after the owner clears"
	)
	controller.release_junction(1, merge_vehicle_b.get_instance_id())

	var follow_a := PathFollow2D.new()
	follow_a.loop = false
	lane_a.add_child(follow_a)
	follow_a.progress = 40.0
	var vehicle_a := Node2D.new()
	vehicle_a.name = "VehicleA"
	follow_a.add_child(vehicle_a)
	var granted: Dictionary = controller.evaluate_lane_motion(vehicle_a, lane_a, follow_a, 8.0, 20.0, 40.0, 120.0)
	_check(bool(granted.reservation_granted), "green vehicle must reserve the junction")

	var follow_b := PathFollow2D.new()
	follow_b.loop = false
	lane_b.add_child(follow_b)
	# lane_b runs from x=200 to x=100. At progress 56 its front bumper is on
	# the exact red stop line: no positive advancement is legal.
	follow_b.progress = 56.0
	var vehicle_b := Node2D.new()
	vehicle_b.name = "VehicleB"
	follow_b.add_child(vehicle_b)
	var red_contract: Dictionary = controller.evaluate_lane_motion(vehicle_b, lane_b, follow_b, 12.0, 20.0, 70.0, 120.0)
	_check(bool(red_contract.controlled), "red approach must be controlled")
	_check(is_zero_approx(float(red_contract.allowed_advance)), "red stop line must hard-clamp advancement to zero")

	follow_a.progress = 75.0
	var connector_entry_position := follow_a.global_position
	_check(controller.complete_lane_transition(vehicle_a, lane_a, follow_a), "reserved vehicle must enter graph connector")
	_check(follow_a.get_parent() == connector, "turn must use the graph-owned connector Path2D")
	_check(follow_a.global_position.distance_to(connector_entry_position) <= 0.5, "connector entry must preserve continuous world position")
	follow_a.progress = connector.curve.get_baked_length()
	var connector_exit_position := follow_a.global_position
	_check(controller.complete_lane_transition(vehicle_a, connector, follow_a), "connector must hand off to outgoing lane")
	_check(follow_a.get_parent() == outgoing, "connector exit must preserve the directed outgoing lane")
	_check(follow_a.global_position.distance_to(connector_exit_position) <= 0.5, "connector exit must preserve continuous world position")

	controller.release_junction(0, vehicle_a.get_instance_id())
	var saw_pedestrian_phase := false
	for _frame in 30:
		await process_frame
		if controller.is_pedestrian_phase(0):
			saw_pedestrian_phase = true
			break
	_check(saw_pedestrian_phase, "all-red clearance must expose a pedestrian phase")
	_check(controller.get_signal_state(1, 2) == CONTROLLER_SCRIPT.SignalState.GREEN, "unsignalized junction must remain free through other signal cycles")
	_check(int(controller.get_junction_snapshot(1).stage) == CONTROLLER_SCRIPT.JunctionStage.GREEN, "unsignalized junction must never enter yellow/all-red")
	var telemetry: Dictionary = controller.get_telemetry_snapshot()
	_check(int(telemetry.reservation_grants) == 3, "signalized and unsignalized reservations must share one exclusive authority")
	_check(int(telemetry.active_reservations) == 0, "released vehicle must not retain the conflict zone")
	_check(int(telemetry.signalized_junction_count) == 1, "telemetry must classify one signalized junction")
	_check(int(telemetry.unsignalized_junction_count) == 1, "telemetry must classify one unsignalized continuation")
	await _test_pathfollow_safety_zone(graph)

	if _failures.is_empty():
		print("JUNCTION_TRAFFIC_CONTRACT: PASS signalized=1 unsignalized=1 visuals=1 reservations=exclusive red_advance=0 connector_handoff=1 safety_zone_clamp=1")
		quit(0)
	else:
		for failure in _failures:
			push_error("JUNCTION_TRAFFIC_CONTRACT: %s" % failure)
		quit(1)


func _make_path(parent: Node, lane_id: String, points: PackedVector2Array, road_index: int) -> Path2D:
	var path := Path2D.new()
	path.name = lane_id
	var curve := Curve2D.new()
	for point in points:
		curve.add_point(point)
	path.curve = curve
	path.set_meta("traffic_road_index", road_index)
	path.set_meta("traffic_road_id", "road_%d" % road_index)
	path.set_meta("traffic_lane_id", lane_id)
	path.set_meta("traffic_direction", 1)
	path.set_meta("traffic_lane_loop", false)
	parent.add_child(path)
	path.add_to_group("unified_traffic_lane")
	return path


func _make_connector(parent: Node, from_lane: Path2D, to_lane: Path2D) -> Path2D:
	var connector := Path2D.new()
	connector.name = "lane_a_to_lane_out"
	var curve := Curve2D.new()
	curve.add_point(from_lane.curve.sample_baked(75.0), Vector2.ZERO, Vector2(14, 0))
	curve.add_point(to_lane.curve.sample_baked(25.0), Vector2(0, -14), Vector2.ZERO)
	connector.curve = curve
	connector.set_meta("traffic_connection_id", "0:lane_a>lane_out")
	connector.set_meta("traffic_junction_index", 0)
	connector.set_meta("traffic_lane_loop", false)
	parent.add_child(connector)
	connector.add_to_group("unified_lane_connector")
	return connector


func _test_pathfollow_safety_zone(parent: Node) -> void:
	var safety_lane := _make_path(parent, "safety_lane", PackedVector2Array([Vector2(0, 240), Vector2(200, 240)]), 9)
	safety_lane.set_meta("traffic_road_id", "safety_road")
	var follow := PathFollow2D.new()
	follow.loop = false
	safety_lane.add_child(follow)
	follow.progress = 62.0
	var vehicle := VEHICLE_SCENE.instantiate() as DemoTrafficVehicle
	vehicle.speed = 60.0
	vehicle.target_length = 40.0
	follow.add_child(vehicle)
	var zone := FakeTrafficControlZone.new()
	zone.position = Vector2(100, 240)
	parent.add_child(zone)
	var before := follow.progress
	vehicle.advance_on_lane(1.0 / 60.0)
	_check(is_equal_approx(follow.progress, before), "closed crossing must hard-clamp PathFollow advancement")
	zone.closed = false
	vehicle.advance_on_lane(1.0 / 60.0)
	_check(follow.progress > before, "open crossing must release PathFollow traffic progressively")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
