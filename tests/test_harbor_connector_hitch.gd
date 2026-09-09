extends SceneTree

const LAYOUT := preload("res://world/harbor/HarborRoadLayout.gd")
const NETWORK := preload("res://world/harbor/HarborRoadNetwork.gd")
const LIFE := preload("res://world/harbor/HarborLife.gd")
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	var layout := LAYOUT.new()
	layout.name = "RoadLayout"
	fixture.add_child(layout)
	var network := NETWORK.new()
	network.name = "RoadNetwork"
	network.provider_paths = [NodePath("../RoadLayout")]
	fixture.add_child(network)
	var controller := LIFE.HarborController.new()
	controller.graph_source = network
	fixture.add_child(controller)
	var failures := 0
	var checked := 0
	var exit_id := -1
	var release_road := -1
	for connection in network.get_graph_data().lane_connections:
		if bool(connection.requires_connector) and String(connection.from_lane_id).ends_with("exchange_lane/forward_01"):
			exit_id = int(connection.junction_index)
			release_road = int(network.get_lane_path(String(connection.from_lane_id)).get_meta("traffic_road_index"))
		if not bool(connection.requires_connector) or not String(connection.from_lane_id).ends_with("courtyard_lane/forward_01"):
			continue
		var path: Path2D = network.get_lane_path(String(connection.from_lane_id))
		var road_index := int(path.get_meta("traffic_road_index"))
		for tick in 1000:
			if controller.get_vehicle_permission(int(connection.junction_index), road_index):
				break
			controller._process(0.1)
		var car := FACTORY.spawn_moving_vehicle(path, "ConnectorHitchProbe", "sedan_classic", 0.5, 90.0, 0)
		var follow := car.get_parent() as PathFollow2D
		# Fixture placement only. The step crossing the connector runs unchanged
		# production driving, with a long render frame and its normal 14px cap.
		follow.progress = float(connection.entry_curve_offset) - 0.25
		follow.set_meta("traffic_planned_connection_id", String(connection.connection_id))
		follow.set_meta("traffic_planned_junction_index", int(connection.junction_index))
		var reserved := controller.try_reserve_junction(int(connection.junction_index), car.get_instance_id(), road_index, StringName(connection.from_lane_id), car)
		var before := car.global_position
		car.advance_on_lane(0.5)
		var entered: bool = follow.get_parent() == connection.path
		var distance := before.distance_to(car.global_position)
		print("HARBOR_CONNECTOR_HITCH id=%s reserved=%s entered=%s distance=%.3f" % [connection.connection_id, reserved, entered, distance])
		if not reserved or not entered or distance > 14.1:
			failures += 1
		controller.release_vehicle(car.get_instance_id())
		follow.free()
		checked += 1
	# The reservation protects the complete body, not a second full car length
	# behind it. Oversized release envelopes overlap the next short-block turn.
	var release_state: Dictionary = controller.get_junction_snapshot(exit_id)
	for tick in 1000:
		if controller.get_vehicle_permission(exit_id, release_road):
			break
		controller._process(0.1)
	var body := Node2D.new()
	fixture.add_child(body)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(76.0, 34.0)
	collision.shape = rectangle
	collision.rotation = 0.4
	body.add_child(collision)
	body.global_position = release_state.position
	var reserved := controller.try_reserve_junction(exit_id, body.get_instance_id(), release_road, &"", body)
	controller._release_if_vehicle_cleared(body, 76.0)
	var radius := float(network.get_graph_data().junctions[exit_id].radius)
	var body_radius := rectangle.size.length() * 0.5
	body.global_position += Vector2(radius + body_radius + controller.stop_line_margin - 1.0, 0.0)
	controller._release_if_vehicle_cleared(body, 76.0)
	var retained := int(controller.get_junction_snapshot(exit_id).reservation_owner) == body.get_instance_id()
	body.global_position += Vector2(2.0, 0.0)
	controller._release_if_vehicle_cleared(body, 76.0)
	var released := int(controller.get_junction_snapshot(exit_id).reservation_owner) == 0
	print("HARBOR_JUNCTION_REAR_CLEAR reserved=%s retained_before_clear=%s released=%s" % [reserved, retained, released])
	if not reserved or not retained or not released:
		failures += 1
	if checked == 0:
		failures += 1
	print("HARBOR_CONNECTOR_HITCH failures=%d checked=%d" % [failures, checked])
	fixture.free()
	quit(0 if failures == 0 else 1)
