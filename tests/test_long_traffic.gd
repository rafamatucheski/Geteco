extends SceneTree
const Flow := preload("res://world/shared/traffic/TrafficFlowModel.gd")
const Sweep := preload("res://world/shared/traffic/TrafficBodySweep.gd")
const Factory := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const Bus := preload("res://world/harbor/urban_transit/UrbanBus.gd")
const Controller := preload("res://world/shared/roads/traffic/JunctionTrafficController.gd")
class Graph:
	extends Node2D
	var junctions: Array = []
	func get_graph_data() -> Dictionary: return {"junctions": junctions}
class Clock:
	extends Node
	var is_dark := false
	var weather_state := 0
class Stop:
	extends Node2D
	var lane: Path2D
	var offset := 0.0
class Service:
	extends Node2D
	var clock: Node
	var stops: Array[Node2D] = []
	func bus_arrived(_bus: Node, _stop: Node) -> void: pass
	func cleanup_removed_bus(_reference: WeakRef, _owned: Array) -> void: pass
class Convoy:
	extends CharacterBody2D
	var parts: Array[Node2D] = []
	func get_traffic_bodies() -> Array: return [self] + parts
	func get_traffic_storage_length() -> float: return 300.0
	func occupies_junction(center: Vector2, radius: float) -> bool: return Flow.occupies_junction(self, center, radius)
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)
func shape(body: Node2D, size: Vector2) -> void:
	var hull := CollisionShape2D.new()
	hull.name = "Collision"
	hull.shape = RectangleShape2D.new()
	hull.shape.size = size
	body.add_child(hull)
func road(world: Node, points: Array) -> Path2D:
	var path := Path2D.new()
	path.curve = Curve2D.new()
	for point in points: path.curve.add_point(point)
	path.set_meta("traffic_lane_loop", false)
	world.add_child(path)
	return path
func run() -> void:
	seed(91126)
	await contracts()
	await reservation_contract()
	for archetype in ["american_tanker_truck", "american_dump_truck", "cargo_flatbed_truck", "boxrunner", "route_city"]:
		await mixed_curve(archetype)
	print("LONG_TRAFFIC failures=",failures)
	quit(0 if failures.is_empty() else 1)
func contracts() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var path := road(world, [Vector2.ZERO,Vector2(1000,0)])
	var follower := Factory.spawn_moving_vehicle(path,"Follower","taxi_yellow",0.2,80,0)
	follower.set_process(false)
	follower.set_physics_process(false)
	var head := Convoy.new()
	head.position = Vector2(480,150)
	shape(head,Vector2(130,38))
	world.add_child(head)
	head.add_to_group("vehicle")
	var tail := CharacterBody2D.new()
	tail.position = Vector2(300,0)
	shape(tail,Vector2(108,38))
	tail.collision_layer = 2
	tail.collision_mask = 7
	world.add_child(tail)
	tail.add_to_group("vehicle")
	head.parts.append(tail)
	await physics_frame
	await process_frame
	var motion := Flow.lane_motion(follower,follower.get_parent(),80,150)
	check(is_finite(motion.allowed_advance) and motion.target_speed < 80, "Follower brakes for a tail whose head is already on another lane")
	check(Flow.occupies_junction(head,Vector2(300,0),40), "Tail keeps the junction occupied after the head clears")
	check(not Flow.occupies_junction(head,Vector2.ZERO,40), "Convoy occupancy uses actual bodies, not an oversized disk")
	var obstacle := StaticBody2D.new()
	obstacle.position = Vector2(68,68)
	shape(obstacle,Vector2(8,8))
	world.add_child(obstacle)
	var rigid := CharacterBody2D.new()
	rigid.collision_layer = 2
	rigid.collision_mask = 1
	shape(rigid,Vector2(190,30))
	world.add_child(rigid)
	await physics_frame
	check(not Sweep.clear(rigid,[{"body":rigid,"pose":Transform2D(PI/2,Vector2.ZERO)}]), "Rotation sweep detects a corner collision between two clear endpoint poses")
	obstacle.position = Vector2(500,500)
	await physics_frame
	await physics_frame
	check(Sweep.clear(rigid,[{"body":rigid,"pose":Transform2D(PI/2,Vector2.ZERO)}]), "Clear rotation remains possible")
	var parked := StaticBody2D.new()
	parked.position = Vector2(364,0)
	parked.collision_layer = 2
	shape(parked,Vector2(8,30))
	world.add_child(parked)
	await physics_frame
	var before := head.global_position
	check(not Sweep.clear(head,[{"body":head,"pose":head.global_transform.translated(Vector2(14,0))},{"body":tail,"pose":tail.global_transform.translated(Vector2(14,0))}]), "Blocked rear section vetoes the whole convoy step")
	check(head.global_position == before, "Rejected convoy step leaves the head unchanged")
	world.queue_free()
	await process_frame
func reservation_contract() -> void:
	var world := Graph.new()
	root.add_child(world)
	current_scene = world
	var path := road(world,[Vector2.ZERO,Vector2(1000,0)])
	path.add_to_group("unified_traffic_lane")
	path.set_meta("traffic_road_index",0)
	path.set_meta("traffic_lane_id","long")
	var connection := {"connection_id":"continue", "junction_index":1, "from_lane_id":"long", "to_lane_id":"long", "requires_connector":false, "movement":"straight"}
	world.junctions = [{"id":"rear", "position":Vector2(300,0), "radius":40.0,"signalized":false,"roads":[0],"approaches":[],"lane_connections":[]}, {"id":"front", "position":Vector2(420,0), "radius":40.0,"signalized":false,"roads":[0],"approaches":[],"lane_connections":[connection]}]
	var controller := Controller.new()
	controller.graph_source = world
	world.add_child(controller)
	controller.set_process(false)
	var follow := PathFollow2D.new()
	follow.loop = false
	path.add_child(follow)
	follow.progress = 220
	var head := Convoy.new()
	shape(head,Vector2(130,38))
	follow.add_child(head)
	var tail := Node2D.new()
	shape(tail,Vector2(108,38))
	world.add_child(tail)
	tail.position = Vector2(100,0)
	head.parts.append(tail)
	check(controller.try_reserve_junction(0,head.get_instance_id(),0,&"long",head), "Long convoy acquires its first junction")
	controller.notify_vehicle_entered(0,head.get_instance_id())
	follow.progress = 370
	tail.position = Vector2(300,0)
	follow.set_meta("traffic_planned_connection_id","continue")
	var contract := controller.evaluate_lane_motion(head,path,follow,5,130,30,120)
	check(contract.reservation_granted and contract.junction_index == 1, "Head can acquire the adjacent junction while its tail is still in the first")
	check(controller.is_reservation_owner(0,head) and controller.is_reservation_owner(1,head), "Both junctions remain reserved for the same physical convoy")
	follow.progress = 650
	controller.evaluate_lane_motion(head,path,follow,5,130,30,120)
	check(controller.is_reservation_owner(0,head), "Cab leaving both junctions cannot release a junction still containing the tail")
	tail.position = Vector2(570,0)
	controller.evaluate_lane_motion(head,path,follow,5,130,30,120)
	check(not controller.is_reservation_owner(0,head), "First junction releases only after the final tail clears")
	world.queue_free()
	await process_frame

func mixed_curve(archetype: String) -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var path := road(world,[Vector2(-1600,0),Vector2(0,0),Vector2(180,180),Vector2(180,1600)])
	path.curve.set_point_out(1,Vector2(100,0))
	path.curve.set_point_in(2,Vector2(0,-100))
	var service := Service.new()
	service.clock = Clock.new()
	world.add_child(service)
	service.add_child(service.clock)
	var stop := Stop.new()
	stop.lane = path
	stop.offset = path.curve.get_baked_length()-80
	world.add_child(stop)
	service.stops.append(stop)
	var follow := PathFollow2D.new()
	follow.loop = false
	path.add_child(follow)
	follow.progress = 1200
	var bus := load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate() as CharacterBody2D
	bus.set_script(Bus)
	bus.system = service
	follow.add_child(bus)
	var car := Factory.spawn_moving_vehicle(path,"FollowingCar","taxi_yellow",760/path.curve.get_baked_length(),100,0)
	var truck := Factory.spawn_moving_vehicle(path,"FollowingTruck",archetype,500/path.curve.get_baked_length(),95,0)
	var barrier := StaticBody2D.new()
	barrier.position = bus.sections.back().global_position + bus.sections.back().global_transform.x * 60.0
	shape(barrier,Vector2(8,30))
	world.add_child(barrier)
	await physics_frame
	await physics_frame
	var initial := follow.progress
	bus.dwelling = false
	for frame in 60: await process_frame
	check(follow.progress < initial + 6, "Obstacle ahead of the last trailer stops the actual bus head: " + archetype)
	barrier.queue_free()
	await physics_frame
	var actors: Array = [bus]+bus.sections+[car,truck]
	var overlapping := false
	var max_angle_step := 0.0
	var previous: float = bus.sections.back().global_rotation
	for frame in 4200:
		await process_frame
		max_angle_step = maxf(max_angle_step,absf(angle_difference(previous,bus.sections.back().global_rotation)))
		previous = bus.sections.back().global_rotation
		for i in actors.size():
			for j in range(i+1,actors.size()):
				if actors[i].global_position.distance_squared_to(actors[j].global_position)>250*250: continue
				if not Geometry2D.intersect_polygons(Sweep.rectangle(actors[i],actors[i].global_transform),Sweep.rectangle(actors[j],actors[j].global_transform)).is_empty(): overlapping = true
		if truck.get_parent().progress > 2350: break
	check(truck.get_parent().progress > 2350 and car.get_parent().progress > 2350 and follow.progress > 2350, "Bus, car and " + archetype + " all clear the 90-degree curve")
	check(not overlapping, "Mixed traffic keeps every head, trailer and truck hull separated")
	check(max_angle_step < 0.15, "Trailer yaw remains continuous through the curve")
	check(not bus._accept_clearance_request(car), "Articulated vehicle refuses a car-only reverse manoeuvre")
	print("LONG_CURVE type=",archetype," bus=",follow.progress," car=",car.get_parent().progress," truck=",truck.get_parent().progress," trailer_max_yaw_step=",max_angle_step)
	world.queue_free()
	await process_frame
