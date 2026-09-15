extends SceneTree
const CONTROLLER = preload("res://world/shared/roads/traffic/JunctionTrafficController.gd")
const CROSSING = preload("res://world/shared/roads/safety/RoadCrossingArea2D.gd")
class Graph:
	extends Node2D
	var junctions: Array = []
	func get_graph_data() -> Dictionary:
		return {"junctions":junctions.duplicate(true)}
var failures: Array[String] = []
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ", message)
	if not value: failures.append(message)
func run() -> void:
	var graph = Graph.new()
	root.add_child(graph)
	current_scene = graph
	graph.junctions = [{"id":"probe", "position":Vector2(500,0), "radius":95.6, "signalized":true, "roads":[0,1], "approaches":[], "lane_connections":[]}]
	var lane = Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2.ZERO)
	lane.curve.add_point(Vector2(1000,0))
	lane.add_to_group("unified_traffic_lane")
	lane.set_meta("traffic_lane_id","probe_lane")
	lane.set_meta("traffic_road_id","probe_road")
	lane.set_meta("traffic_road_index",0)
	lane.set_meta("traffic_lane_loop",false)
	graph.add_child(lane)
	var controller = CONTROLLER.new()
	controller.graph_source = graph
	graph.add_child(controller)
	controller.set_process(false)
	var crossing = CROSSING.new()
	crossing.configure({"id":"probe_crossing", "junction_id":"probe", "road_id":"probe_road", "position":Vector2(420,0)})
	# Runtime graph resolution changes the property after configuration; old
	# metadata must not prevent a resolved crossing from recognizing its road.
	crossing.road_index = 0
	graph.add_child(crossing)
	var pedestrian := CharacterBody2D.new()
	pedestrian.position = Vector2(1000,1000)
	pedestrian.collision_layer = 4
	pedestrian.collision_mask = 0
	pedestrian.add_to_group("pedestrian")
	var pedestrian_collision := CollisionShape2D.new()
	pedestrian_collision.shape = CircleShape2D.new()
	pedestrian_collision.shape.radius = 7
	pedestrian.add_child(pedestrian_collision)
	graph.add_child(pedestrian)
	crossing.set_signal_controller(controller)
	crossing.set_signal_state(true,false)
	var follow = PathFollow2D.new()
	follow.loop = false
	lane.add_child(follow)
	follow.progress = 360
	var car = load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	follow.add_child(car)
	car.target_length = 120
	car.set_process(false)
	car.set_physics_process(false)
	await physics_frame
	check(controller.try_reserve_junction(0,car.get_instance_id(),0,"probe_lane",car),"Vehicle reserves on green")
	crossing.set_signal_state(false,false)
	check(crossing.should_stop_vehicle(car),"Reservation before commitment cannot bypass a red crossing")
	controller.notify_vehicle_entered(0,car.get_instance_id())
	controller._states[0].stage = controller.JunctionStage.ALL_RED
	crossing.set_signal_state(false,false)
	check(not controller.can_clear_crossing(car,"other_junction"),"Reservation never authorizes a different junction")
	check(not controller.can_clear_crossing(graph,"probe"),"Unreserved actors cannot bypass red")
	check(crossing.should_stop_vehicle(graph) and crossing.should_stop_vehicle(),"Unreserved and global crossing queries remain stopped")
	crossing.junction_id = &"other_junction"
	check(crossing.should_stop_vehicle(car),"Another junction crossing still stops the committed owner")
	crossing.junction_id = &"probe"
	crossing.set_signal_state(false,true)
	check(crossing.should_stop_vehicle(car),"Pedestrian permission outranks committed vehicle clearance")
	crossing.set_signal_state(false,false)
	pedestrian.global_position = crossing.global_position
	crossing._pedestrians_inside[pedestrian.get_instance_id()] = weakref(pedestrian)
	check(crossing.should_stop_vehicle(car),"An actual pedestrian on the crossing retains priority")
	crossing._pedestrians_inside.clear()
	crossing.clear_signal_state()
	crossing._pedestrians_inside[pedestrian.get_instance_id()] = weakref(pedestrian)
	check(crossing.should_stop_vehicle(car),"Unsignalized pedestrian priority is unchanged")
	crossing._pedestrians_inside.clear()
	crossing.set_signal_state(false,false)
	var before = follow.progress
	var contract: Dictionary = controller.evaluate_lane_motion(car,lane,follow,1.0,120.0,0.0,302.4)
	var zone: Dictionary = car._traffic_control_zone_motion(lane,follow)
	print("OWNER_CONTRACT ",contract," CROSSING_LIMIT ",zone," SNAPSHOT ",controller.get_junction_snapshot(0))
	check(contract.reservation_granted and contract.allowed_advance > 0,"Reservation authorizes committed vehicle to clear")
	check(is_inf(zone.allowed_advance),"Same-junction red permits committed vehicle to clear an empty crossing")
	for frame in 1200:
		controller._advance_junction(0,1.0/60)
		car.advance_on_lane(1.0/60)
	check(follow.progress > before+300,"Real vehicle advances through and out of the crossing")
	check(controller._states[0].reservation_owner == 0,"Physical exit releases the occupied reservation")
	check(controller._states[0].stage != controller.JunctionStage.ALL_RED,"Signal cycle resumes after occupied vehicle clears")
	# A seeded car can already be past the junction center without owning its
	# reservation. Holding that car at an exit zebra traps the owner behind it.
	follow.progress = 550.0
	car._lane_motion_speed = 0.0
	crossing.position = Vector2(580,0)
	lane.remove_meta("traffic_control_projections")
	controller._states[0].stage = controller.JunctionStage.ALL_RED
	crossing.set_signal_state(false,false)
	var exit_limit: Dictionary = car._traffic_control_zone_motion(lane,follow)
	print("EXIT_CROSSING_LIMIT ",exit_limit," reserved=",controller._states[0].reservation_owner," position=",car.global_position)
	check(is_inf(exit_limit.allowed_advance),"Unreserved car already leaving the junction clears its empty exit zebra")
	follow.progress = 450.0
	check(crossing.should_stop_vehicle(car),"Before the junction center an unreserved approach still stops")
	follow.progress = 550.0
	crossing.set_signal_state(false,true)
	check(crossing.should_stop_vehicle(car),"Exit clearance never overrides pedestrian permission")
	crossing.set_signal_state(false,false)
	pedestrian.global_position = crossing.global_position
	crossing._pedestrians_inside[pedestrian.get_instance_id()] = weakref(pedestrian)
	check(crossing.should_stop_vehicle(car),"Exit clearance never overrides pedestrians physically on the zebra")
	crossing._pedestrians_inside.clear()
	crossing.road_index = 1
	check(crossing.should_stop_vehicle(car),"Exit clearance cannot borrow the crossing of another road")
	crossing.road_index = 0
	for frame in 120:
		car.advance_on_lane(1.0/60)
	check(follow.progress > 600.0,"Real unreserved car physically clears the exit zebra under all-red")
	follow.progress = 800.0
	crossing.position = Vector2(850,0)
	check(crossing.should_stop_vehicle(car),"A distant crossing outside the body conflict envelope still stops")
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(1000,0))
	lane.curve.add_point(Vector2.ZERO)
	controller._lane_projection_cache.clear()
	lane.remove_meta("traffic_control_projections")
	crossing.position = Vector2(420,0)
	follow.progress = 450.0
	check(crossing.should_stop_vehicle(car),"Reverse lane approaching the center still obeys red")
	follow.progress = 550.0
	check(not crossing.should_stop_vehicle(car),"Reverse lane leaving the center clears its own exit zebra")
	for signalized in [true,false]:
		for angle in [0.0,PI*0.5]:
			crossing.rotation = angle
			if signalized: crossing.set_signal_state(true,false)
			else: crossing.clear_signal_state()
			crossing._pedestrians_inside[pedestrian.get_instance_id()] = weakref(pedestrian)
			pedestrian.global_position = crossing.to_global(Vector2(0,crossing.road_width*0.5+14))
			check(not crossing.should_stop_vehicle(car),"Sidewalk waiter leaves the roadway clear signal=%s angle=%s" % [signalized,angle])
			crossing._refresh_stop_requirement()
			check(not crossing._pedestrians_inside.is_empty() and controller._pedestrian_demand.get(0,false),"Sidewalk waiter still requests pedestrian phase")
			pedestrian.global_position = crossing.to_global(Vector2(0,crossing.road_width*0.5+5))
			check(crossing.should_stop_vehicle(car),"Pedestrian hull straddling asphalt edge stops traffic")
			pedestrian.global_position = crossing.global_position
			check(crossing.should_stop_vehicle(car),"Pedestrian inside the physical zebra stops traffic")
			pedestrian.global_position = crossing.to_global(Vector2(crossing.crossing_depth*0.5+12,0))
			check(not crossing.should_stop_vehicle(car),"Pedestrian fully beyond zebra depth no longer occupies crossing")
	crossing._pedestrians_inside.clear()
	pedestrian.global_position = Vector2(1000,1000)
	print("COMMITTED_OWNER_CROSSING failures=",failures," position=",car.global_position," progress=",follow.progress)
	graph.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
