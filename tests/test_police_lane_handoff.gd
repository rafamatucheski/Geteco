extends SceneTree
const ROUTER = preload("res://world/shared/roads/EmergencyLaneRouter.gd")
const NETWORK = preload("res://world/shared/roads/UnifiedRoadNetwork2D.gd")
class Roads:
	extends Node2D
	func get_road_graph_definitions() -> Array[Dictionary]:
		return [{"id":"bridge", "points":PackedVector2Array([Vector2(0,0), Vector2(1000,0)]), "width":96.0, "open_start":true, "open_end":true}]
func _initialize(): call_deferred("run")
func run():
	var fixture := Node2D.new()
	root.add_child(fixture)
	var roads := Roads.new()
	roads.name = "Roads"
	fixture.add_child(roads)
	var graph := NETWORK.new()
	graph.provider_paths = [NodePath("../Roads")]
	graph.build_guard_rails = false
	fixture.add_child(graph)
	var mountain := Path2D.new()
	mountain.curve = Curve2D.new()
	mountain.curve.add_point(Vector2(1000,-24))
	mountain.curve.add_point(Vector2(1800,-24))
	mountain.curve.add_point(Vector2(1800,24))
	mountain.curve.add_point(Vector2(1000,24))
	mountain.add_to_group("unified_traffic_lane")
	fixture.add_child(mountain)
	var vehicle := CharacterBody2D.new()
	vehicle.position = Vector2(850,-24)
	fixture.add_child(vehicle)
	await physics_frame
	var router := ROUTER.new()
	var crossed := false
	var returned := false
	for i in 160:
		var waypoint: Vector2 = router.guidance(vehicle, Vector2(1500,-24))
		vehicle.global_position = vehicle.global_position.move_toward(waypoint,5)
		crossed = crossed or vehicle.global_position.x > 1100
	assert(crossed, "Canonical bridge hands off physically to its adjacent mountain lane")
	vehicle.position = Vector2(1110,24)
	router.reset()
	for i in 100:
		var waypoint: Vector2 = router.guidance(vehicle, Vector2(500,24))
		vehicle.global_position = vehicle.global_position.move_toward(waypoint,5)
		returned = returned or vehicle.global_position.x < 850
	assert(returned, "Mountain lane hands back to the canonical city graph")
	var wrong := Path2D.new()
	wrong.curve = Curve2D.new()
	wrong.curve.add_point(Vector2(1000,-24))
	wrong.curve.add_point(Vector2(900,-24))
	fixture.add_child(wrong)
	wrong.add_to_group("unified_traffic_lane")
	mountain.process_mode = Node.PROCESS_MODE_DISABLED
	var forward: Path2D
	for node in get_nodes_in_group("unified_traffic_lane"):
		if node.get_parent() == graph.get_node("GeneratedLanePaths") and node.curve.sample_baked(node.curve.get_baked_length()).x > 990: forward = node
	assert(not router._link_adjacent_lane(vehicle, forward), "Opposing direction and dormant lane are not valid handoffs")
	print("POLICE_LANE_HANDOFF|PASS")
	fixture.queue_free()
	await process_frame
	quit()
