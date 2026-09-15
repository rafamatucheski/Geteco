extends SceneTree
## Integration fixture: production cars and controller run through their normal
## callbacks. After spawn, this test only reads them; it never advances their AI.
const Factory := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const Controller := preload("res://geodata/roads/traffic/JunctionTrafficController.gd")
class Graph:
	extends Node2D
	func get_graph_data() -> Dictionary:
		return {"junctions": [{"id": "city_runtime", "position": Vector2(700, 0), "radius": 50.0,
			"signalized": true, "roads": [0, 1], "approaches": [], "lane_connections": []}]}
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)
func lane(world: Node, id: int, a: Vector2, b: Vector2) -> Path2D:
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(a)
	path.curve.add_point(b)
	path.set_meta("traffic_road_index", id)
	path.set_meta("traffic_lane_id", "runtime%d" % id)
	path.set_meta("traffic_lane_loop", false)
	world.add_child(path)
	path.add_to_group("unified_traffic_lane")
	return path
func run() -> void:
	seed(9112026)
	var world := Graph.new()
	root.add_child(world)
	current_scene = world
	var lanes := [lane(world, 0, Vector2.ZERO, Vector2(2500, 0)), lane(world, 1, Vector2(700,-700), Vector2(700,1800))]
	var controller := Controller.new()
	controller.graph_source = world
	world.add_child(controller)
	var cars: Array[Node2D] = []
	for road in 2:
		for index in 4:
			cars.append(Factory.spawn_moving_vehicle(lanes[road], "Queue%d_%d" % [road,index], "taxi_yellow", (90.0 + index * 125.0) / 2500.0, 85.0, 0))
	var passed := {}
	var previous := {}
	var max_jump := 0.0
	var max_overlap := 0
	var overlaps := {}
	var sample_frames := 0
	for frame in 7200:
		await process_frame
		sample_frames += 1
		for actor in cars:
			var follow := actor.get_parent() as PathFollow2D
			var old: Vector2 = previous.get(actor.get_instance_id(), actor.global_position)
			max_jump = maxf(max_jump, old.distance_to(actor.global_position))
			previous[actor.get_instance_id()] = actor.global_position
			if follow.progress > 850.0: passed[actor.get_instance_id()] = true
			var contract: Dictionary = actor._last_lane_motion_contract
			if not contract.get("reservation_granted", false) and follow.progress < 700:
				check(follow.progress + actor.target_length * 0.5 <= 636.1, "Unreserved car crossed the stop line")
		for i in cars.size():
			for j in range(i + 1, cars.size()):
				var a := cars[i]
				var b := cars[j]
				var key := "%d:%d" % [i,j]
				if a.global_position.distance_squared_to(b.global_position) > 16000:
					overlaps.erase(key)
					continue
				var polygons: Array[PackedVector2Array] = []
				for car in [a,b]:
					var hull: CollisionShape2D = car.collision
					var half: Vector2 = hull.shape.size * 0.5 - Vector2.ONE * 0.2
					var polygon := PackedVector2Array()
					for point in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]: polygon.append(hull.to_global(point))
					polygons.append(polygon)
				if not Geometry2D.intersect_polygons(polygons[0],polygons[1]).is_empty():
					overlaps[key] = int(overlaps.get(key,0)) + 1
					max_overlap = maxi(max_overlap,overlaps[key])
				else: overlaps.erase(key)
		if passed.size() == cars.size(): break
	check(passed.size() == cars.size(), "Every naturally simulated queue must drain through the intersection")
	check(max_overlap == 0, "Production hulls must never overlap")
	check(max_jump <= 14.1, "Movement must stay continuous under remote 10 Hz simulation")
	for actor in cars:
		print("CITY_ACTOR ", actor.name, " progress=", actor.get_parent().progress, " contract=", actor._last_lane_motion_contract)
	print("CITY_TRAFFIC_RUNTIME seed=9112026 frames=",sample_frames," cars=",cars.size()," passed=",passed.size()," max_overlap_frames=",max_overlap," max_jump=",max_jump," telemetry=",controller.get_telemetry_snapshot()," failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
