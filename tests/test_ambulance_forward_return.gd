extends SceneTree
const ROUTER = preload("res://world/shared/roads/EmergencyLaneRouter.gd")
class Ambulance extends CharacterBody2D:
	var type := 1
	var is_returning_to_base := true
class Graph extends Node2D:
	var lanes: Array = []
	var connections: Array = []
	func get_routing_revision() -> int: return 1
	func get_graph_data() -> Dictionary: return {"lanes": lanes, "lane_connections": connections}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var graph := Graph.new()
	root.add_child(graph)
	var container := Node2D.new()
	graph.add_child(container)
	var points := [Vector2(0,0), Vector2(500,0), Vector2(500,400), Vector2(0,400), Vector2(0,0)]
	for i in 5:
		var lane := Path2D.new()
		lane.curve = Curve2D.new()
		lane.curve.add_point(points[i] if i < 4 else Vector2(500,-24))
		lane.curve.add_point(points[i+1] if i < 4 else Vector2(0,-24))
		container.add_child(lane)
		lane.add_to_group("unified_traffic_lane")
		graph.lanes.append({"lane_id": str(i), "path": lane})
		if i < 4:
			graph.connections.append({"from_lane_id": str(i), "to_lane_id": str((i+1)%4), "entry_lane_progress": 1.0, "exit_lane_progress": 0.0, "requires_connector": false, "path": null, "connection_id": str(i)})
	var car := Ambulance.new()
	car.position = Vector2(180,0)
	root.add_child(car)
	await physics_frame
	var router := ROUTER.new()
	var waypoint: Vector2 = router.guidance(car, Vector2(20,0))
	var ok: bool = router.legs.size() == 5 and waypoint.x > car.position.x
	if ok:
		ok = router.legs[0].path == graph.lanes[0].path and router.legs.back().path == graph.lanes[0].path
	# Switching destinations must discard a retained legacy lane immediately.
	router.linked_lane = graph.lanes[4].path
	router.guidance(car, Vector2(450,400))
	ok = ok and router.linked_lane == null and router.destination == Vector2(450,400)
	print("AMBULANCE_FORWARD_RETURN failures=", 0 if ok else 1)
	graph.queue_free()
	car.queue_free()
	await process_frame
	quit(0 if ok else 1)
