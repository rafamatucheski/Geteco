extends SceneTree
const CONTROLLER := preload("res://geodata/roads/traffic/JunctionTrafficController.gd")
class Graph:
	extends Node2D
	var junctions: Array = []
	func get_graph_data() -> Dictionary:
		return {"junctions": junctions.duplicate(true)}
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)
		push_error(description)
func run() -> void:
	var graph := Graph.new()
	root.add_child(graph)
	current_scene = graph
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2.ZERO)
	lane.curve.add_point(Vector2(240, 0))
	lane.add_to_group("unified_traffic_lane")
	lane.set_meta("traffic_lane_id", "short_link")
	lane.set_meta("traffic_road_index", 0)
	lane.set_meta("traffic_lane_loop", false)
	lane.set_meta("compound_junction_reservations", true)
	graph.add_child(lane)
	var connector := Path2D.new()
	connector.curve = Curve2D.new()
	connector.curve.add_point(Vector2(126, 0))
	connector.curve.add_point(Vector2(240, 100))
	connector.add_to_group("unified_lane_connector")
	connector.set_meta("traffic_connection_id", "next_turn")
	connector.set_meta("traffic_junction_index", 1)
	graph.add_child(connector)
	var connection := {"connection_id": "next_turn", "junction_index": 1, "from_lane_id": "short_link", "to_lane_id": "exit_lane", "from_road_index": 0, "to_road_index": 1, "requires_connector": true, "entry_curve_offset": 126.0, "exit_curve_offset": 0.0, "path": connector}
	graph.junctions = [{"id": "previous", "position": Vector2.ZERO, "radius": 79.0, "signalized": false, "roads": [0], "approaches": [], "lane_connections": []}, {"id": "next", "position": Vector2(240,0), "radius": 79.0, "signalized": true, "roads": [0,1], "approaches": [], "lane_connections": [connection]}]
	var controller := CONTROLLER.new()
	controller.graph_source = graph
	graph.add_child(controller)
	controller.set_process(false)
	var follow := PathFollow2D.new()
	follow.loop = false
	lane.add_child(follow)
	follow.progress = 126.0
	follow.set_meta("traffic_planned_connection_id", "next_turn")
	var bus := CharacterBody2D.new()
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(120,34)
	bus.add_child(collision)
	follow.add_child(bus)
	check(controller.try_reserve_junction(0,bus.get_instance_id(),0,"short_link",bus), "Bus initially reserves the previous junction")
	controller.notify_vehicle_entered(0,bus.get_instance_id())
	controller._states[1].stage = controller.JunctionStage.ALL_RED
	var red: Dictionary = controller.evaluate_lane_motion(bus,lane,follow,1.0,120.0,10.0,90.0)
	check(float(red.allowed_advance) == 0.0 and not red.reservation_granted, "Next red light stops the long bus even while it owns the previous zone")
	check(controller._states[0].reservation_owner == bus.get_instance_id(), "Red light never releases the still-occupied previous zone")
	controller._states[1].stage = controller.JunctionStage.GREEN
	controller._states[1].phase_index = 0
	var other := Node2D.new()
	graph.add_child(other)
	check(controller.try_reserve_junction(1,other.get_instance_id(),0,"other",other), "Another vehicle can own the next junction")
	var occupied: Dictionary = controller.evaluate_lane_motion(bus,lane,follow,1.0,120.0,10.0,90.0)
	check(float(occupied.allowed_advance) == 0.0 and controller._states[1].reservation_owner == other.get_instance_id(), "Bus cannot steal an occupied adjacent reservation")
	controller.release_vehicle(other.get_instance_id())
	var clear: Dictionary = controller.evaluate_lane_motion(bus,lane,follow,1.0,120.0,10.0,90.0)
	check(clear.reservation_granted, "Green and free next junction is reserved before the connector")
	check(controller._states[0].reservation_owner == bus.get_instance_id() and controller._states[1].reservation_owner == bus.get_instance_id(), "Both zones remain protected while the coach spans them")
	follow.progress = 185.0
	controller._release_if_vehicle_cleared(bus,120.0)
	check(controller._states[0].reservation_owner == 0, "Previous reservation releases only after the entire hull clears")
	check(controller._states[1].reservation_owner == bus.get_instance_id(), "Clearing previous reservation preserves the next reservation and reverse index")
	controller.release_vehicle(bus.get_instance_id())
	check(controller._retained_junctions.is_empty(), "Vehicle teardown clears retained junction ownership")
	print("ADJACENT_JUNCTION_RESERVATIONS failures=",failures.size())
	graph.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
