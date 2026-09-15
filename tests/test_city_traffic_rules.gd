extends SceneTree
const Controller := preload("res://world/shared/roads/traffic/JunctionTrafficController.gd")
const Flow := preload("res://cars/traffic/TrafficFlowModel.gd")
class Graph:
	extends Node2D
	func get_graph_data() -> Dictionary:
		return {"junctions": [{"id": "city", "position": Vector2(300, 0), "radius": 40.0,
			"signalized": false, "roads": [0, 1, 2], "approaches": [], "lane_connections": []}]}
class Car:
	extends Node2D
	var target_length := 40.0
	var _lane_motion_speed := 0.0
	var is_broken := false
	var block_wait_timer := 0.0
class Crossing:
	extends Node2D
	var occupied := true
	var junction_id := &"city"
	var road_index := 0
	var crossing_id := &"zebra"
	func has_pedestrian_on_roadway() -> bool: return occupied
	func set_signal_state(_cars: bool, _people: bool) -> void: pass
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)
func lane(world: Node, id: int, points: Array) -> Path2D:
	var path := Path2D.new()
	path.curve = Curve2D.new()
	for point in points: path.curve.add_point(point)
	path.set_meta("traffic_road_index", id)
	path.set_meta("traffic_lane_id", "lane%d" % id)
	path.set_meta("traffic_lane_loop", false)
	world.add_child(path)
	path.add_to_group("unified_traffic_lane")
	return path
func car(path: Path2D, progress: float) -> Car:
	var follow := PathFollow2D.new()
	follow.loop = false
	path.add_child(follow)
	follow.progress = progress
	var actor := Car.new()
	var hull := CollisionShape2D.new()
	hull.name = "Collision"
	hull.shape = RectangleShape2D.new()
	hull.shape.size = Vector2(40, 18)
	actor.add_child(hull)
	follow.add_child(actor)
	actor.add_to_group("vehicle")
	return actor
func motion(controller: Node, actor: Car) -> Dictionary:
	var follow := actor.get_parent() as PathFollow2D
	return controller.evaluate_lane_motion(actor, follow.get_parent(), follow, 10.0, 40.0, 50.0, 140.0)
func run() -> void:
	var world := Graph.new()
	root.add_child(world)
	current_scene = world
	var main := lane(world, 0, [Vector2.ZERO, Vector2(1000, 0)])
	var cross := lane(world, 1, [Vector2(300, -300), Vector2(300, 700)])
	var reverse := lane(world, 2, [Vector2(600, 40), Vector2(-400, 40)])
	var rear := car(main, 150)
	var head := car(main, 226)
	var other := car(cross, 226)
	var newcomer := car(reverse, 226)
	var obstruction := car(main, 400)
	var controller := Controller.new()
	controller.graph_source = world
	world.add_child(controller)
	controller.set_process(false)
	var first := motion(controller, rear)
	check(not first.reservation_granted and first.controlled, "Follower cannot reserve ahead of its leader in the shared controller")
	var blocked := motion(controller, head)
	check(not blocked.reservation_granted and blocked.allowed_advance == 0.0, "Green with a full receiving lane stops before the junction")
	check(controller.get_junction_snapshot(0).reservation_owner == 0, "Blocked exit does not acquire a reservation")
	check(motion(controller, other).reservation_granted, "An unusable queue does not block a free crossing approach")
	controller.release_vehicle(other.get_instance_id())
	obstruction.get_parent().progress = 650
	check(motion(controller, head).reservation_granted, "Head resumes automatically when downstream storage opens")
	check(not motion(controller, other).reservation_granted, "Conflicting vehicle waits while the junction is reserved")
	controller.release_vehicle(head.get_instance_id())
	# Head leaves the approach in this contract fixture; runtime travel is tested separately.
	head.get_parent().progress = 550
	rear.get_parent().progress = 550
	check(not motion(controller, newcomer).reservation_granted, "New arrival cannot take the junction from an older eligible request")
	check(motion(controller, other).reservation_granted, "Oldest eligible approach receives the next turn")
	controller.release_vehicle(other.get_instance_id())
	controller.release_vehicle(newcomer.get_instance_id())
	head.get_parent().progress = 226
	rear.get_parent().progress = 150
	check(motion(controller, head).reservation_granted, "Uncommitted approach receives a fresh reservation")
	obstruction.get_parent().progress = 400
	check(not motion(controller, head).reservation_granted, "Exit filling before entry revokes approach permission")
	obstruction.get_parent().progress = 650
	check(motion(controller, head).reservation_granted, "Approach can reserve again after exit clears")
	head.get_parent().progress = 260
	controller.notify_vehicle_entered(0, head.get_instance_id())
	obstruction.get_parent().progress = 400
	check(motion(controller, head).reservation_granted, "Committed crossing keeps protection even if downstream changes")
	controller.release_vehicle(head.get_instance_id())
	var crossing := Crossing.new()
	world.add_child(crossing)
	crossing.add_to_group("road_crossing_area")
	controller._states[0].signalized = true
	controller._states[0].phases = [[0], [1]]
	controller._states[0].phase_index = 0
	controller._set_stage(0, Controller.JunctionStage.ALL_RED)
	controller._synchronize_crossing_consumers()
	controller._advance_junction(0, 7.0)
	check(controller.get_junction_snapshot(0).stage == Controller.JunctionStage.ALL_RED, "Signal cannot release cars while a pedestrian still occupies the roadway")
	check(not controller.is_pedestrian_phase(0), "New walkers wait once the walk interval ends; committed walkers can finish")
	crossing.occupied = false
	controller._advance_junction(0, 0.1)
	check(controller.get_junction_snapshot(0).stage == Controller.JunctionStage.GREEN, "Next vehicle phase opens after the last pedestrian clears")
	var before_pause: int = controller._traffic_now_ms()
	paused = true
	controller._process(5.0)
	check(controller._traffic_now_ms() == before_pause, "Pausing the game freezes reservation and signal time")
	paused = false
	controller._process(0.25)
	check(controller._traffic_now_ms() == before_pause + 250, "Reservation clock follows simulated delta instead of wall time")
	controller._waiting_since.clear()
	controller._states[0].phases = [[0], [2], [1]]
	controller._states[0].phase_index = 0
	controller._track_wait(other.get_instance_id(), 0, 1, &"lane1")
	controller._set_stage(0, Controller.JunctionStage.ALL_RED)
	controller._advance_junction(0, 2.0)
	check(controller.get_vehicle_permission(0, 1), "Signals skip an empty approach to serve an actual waiting queue")
	check(Flow.following(100, 50, 0, 140).target_speed > 0, "Stopped leader permits progressive closing of excess space")
	check(Flow.following(14, 50, 0, 140).allowed_advance == 0, "Standstill bumper gap is a hard movement limit")
	check(Flow.following(35, 120, 0, 140).target_speed < Flow.following(100, 120, 0, 140).target_speed, "Closing distance reduces following speed progressively")
	# A civilian may choose another legal turn when its receiving street jams.
	controller.release_vehicle(head.get_instance_id())
	controller.release_vehicle(other.get_instance_id())
	controller.release_vehicle(newcomer.get_instance_id())
	controller._waiting_since.clear()
	controller._states[0].signalized = false
	rear.get_parent().progress = 650
	other.get_parent().progress = 650
	newcomer.get_parent().progress = 650
	head.get_parent().progress = 226
	obstruction.get_parent().progress = 400
	var alternate := lane(world, 3, [Vector2(0, 200), Vector2(1000, 200)])
	var connector := lane(world, 4, [Vector2(250, 0), Vector2(340, 200)])
	var straight := {"connection_id": "straight", "from_lane_id": "lane0", "to_lane_id": "lane0", "junction_index": 0, "requires_connector": false, "from_road_progress": 0.2, "to_road_progress": 0.4}
	var detour := {"connection_id": "detour", "from_lane_id": "lane0", "to_lane_id": "lane3", "junction_index": 0, "requires_connector": true, "entry_curve_offset": 250.0, "exit_curve_offset": 340.0, "path": connector}
	controller._connections_by_id = {"straight": straight, "detour": detour}
	controller._connections_from_lane = {"lane0": [straight, detour]}
	controller._lane_paths_by_id["lane3"] = alternate
	head.get_parent().set_meta("traffic_planned_connection_id", "straight")
	head.get_parent().set_meta("traffic_planned_junction_index", 0)
	head.block_wait_timer = 2.0
	check(not motion(controller, head).reservation_granted, "Brief queue waits instead of constantly changing route")
	head.block_wait_timer = 7.0
	check(motion(controller, head).reservation_granted, "Persistent blocked exit selects a free legal alternative")
	check(head.get_parent().get_meta("traffic_planned_connection_id") == "detour", "Detour commits to the authored alternate connector")
	controller.release_vehicle(head.get_instance_id())
	head.get_parent().set_meta("traffic_planned_connection_id", "straight")
	head.get_parent().set_meta("traffic_detour_after_ms", 0)
	var alternate_queue := car(alternate, 380)
	await process_frame
	await process_frame
	check(not motion(controller, head).reservation_granted, "Detour refuses an alternate street without storage space")
	alternate_queue.get_parent().progress = 700
	head.get_parent().set_meta("traffic_detour_after_ms", 0)
	head.set_meta("taxi_route_end", 900.0)
	check(not motion(controller, head).reservation_granted, "Civilian queue recovery preserves an assigned taxi destination")
	# Numerical queue stress: no physical server or render scheduling can hide an overlap.
	for hz in [20, 60, 120]:
		var positions := [0.0, -80.0, -160.0, -240.0, -320.0]
		var speeds := [60.0, 60.0, 60.0, 60.0, 60.0]
		var safe := true
		for frame in hz * 25:
			var delta: float = 1.0 / hz
			for i in positions.size():
				var target := 70.0 if frame < hz * 4 or frame > hz * 10 else 0.0
				var allowed := INF
				if i > 0:
					var contract := Flow.following(positions[i-1]-positions[i]-40, speeds[i], speeds[i-1], 140)
					target = minf(70, contract.target_speed)
					allowed = contract.allowed_advance
				speeds[i] = move_toward(speeds[i], target, (80 if target > speeds[i] else 140) * delta)
				positions[i] += minf(speeds[i] * delta, allowed)
				if i > 0: safe = safe and positions[i-1]-positions[i] >= 53.99
		check(safe and positions[4] > 400, "Five-car stop/restart queue stays separated and drains at %d Hz" % hz)
	print("CITY_TRAFFIC_RULES failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
