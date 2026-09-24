extends SceneTree
const Controller = preload("res://geodata/roads/traffic/JunctionTrafficController.gd")
class Graph:
	extends Node2D
	func get_graph_data() -> Dictionary:
		return {"junctions": [{"id": "budget_crossing", "position": Vector2.ZERO, "radius": 50.0, "signalized": false, "roads": [0], "approaches": [], "lane_connections": []}]}
class Actor:
	extends CharacterBody2D
	var is_driven_by_player := false
	var is_exploding := false
	var is_scared := false
	var is_flying := false
class QuietStream:
	extends "res://world/harbor/ContinuousWorld.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func actor(parent: Node, point: Vector2, pedestrian := false) -> Actor:
	var body := Actor.new()
	body.position = point
	body.collision_layer = 4 if pedestrian else 2
	body.collision_mask = 0
	body.add_to_group("authored_sidewalk_pedestrian" if pedestrian else "modern_traffic")
	if not pedestrian: body.add_to_group("vehicle")
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(10, 10)
	body.add_child(shape)
	var sensor := RayCast2D.new()
	sensor.name = "FrontRay"
	sensor.target_position = Vector2(30, 0)
	sensor.collision_mask = 6
	body.add_child(sensor)
	parent.add_child(body)
	return body
func run() -> void:
	var graph := Graph.new()
	root.add_child(graph)
	var controller := Controller.new()
	controller.graph_source = graph
	graph.add_child(controller)
	controller.set_process(false)
	var owner := actor(graph, Vector2.ZERO)
	var blocker := actor(graph, Vector2(20, 0))
	var walker := actor(graph, Vector2(40, 0), true)
	var unrelated := actor(graph, Vector2(200, 0))
	# A sensor cycle must terminate without adding unrelated actors.
	walker.get_node("FrontRay").target_position = Vector2(-45, 0)
	var life := preload("res://world/harbor/HarborLife.gd").new()
	graph.add_child(life)
	life.set_process(false)
	life.vehicles.assign([owner, blocker, unrelated])
	life.walkers.assign([walker])
	var stream := QuietStream.new()
	graph.add_child(stream)
	await physics_frame
	await physics_frame
	for budget in [life, stream]:
		for body in [owner, blocker, walker, unrelated]:
			body.set_process(true)
			body.set_physics_process(true)
		check(controller.try_reserve_junction(0, owner.get_instance_id(), 0, &"", owner), "Fixture owner reserves the crossing")
		var method := "_budget_population" if budget == life else "_budget_traffic"
		budget.call(method, Vector2(-10000, -10000))
		check(owner.can_process() and blocker.can_process() and walker.can_process(), "Both budgets keep committed owner and blocker chain awake")
		check(not unrelated.can_process(), "Unrelated distant traffic still sleeps")
		controller._clear_reservation(0)
		budget.call(method, Vector2(-10000, -10000))
		check(not owner.can_process() and not blocker.can_process() and not walker.can_process(), "Owner and chain can sleep once the crossing clears")
		check(controller.try_reserve_junction(0, owner.get_instance_id(), 0, &"", owner), "Fixture restores a reservation on sleeping traffic")
		budget.call(method, Vector2(-10000, -10000))
		check(owner.can_process() and blocker.can_process() and walker.can_process(), "Already sleeping committed traffic is restored")
		controller._clear_reservation(0)
		if budget == life: life._population_activity.restore_all()
		else: stream.population_activity.restore_all()
	await _check_sleeping_sensor_corridor()
	print("RESERVED_TRAFFIC_BUDGET failures=", failures)
	graph.queue_free()
	for frame in 4: await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_sleeping_sensor_corridor() -> void:
	var world := Graph.new()
	# Separate from the first fixture's still-live physics space. A live body
	# in that fixture must not truncate these sensors before the test truck.
	world.position = Vector2(-3000, 2000)
	world.rotation = 0.3
	root.add_child(world)
	var controller := Controller.new()
	controller.graph_source = world
	world.add_child(controller)
	controller.set_process(false)
	var owner := actor(world, Vector2.ZERO)
	owner.get_node("FrontRay").target_position = Vector2(100, 0)
	# The long vehicle's centre is beyond the old 96 px radius, but its rear
	# occupies the sensor corridor. Its own sensor reaches a second sleeper.
	var truck := actor(world, Vector2(150, 0))
	(truck.get_child(0) as CollisionShape2D).shape.size = Vector2(130, 14)
	truck.get_node("FrontRay").target_position = Vector2(190, 0)
	var walker := actor(world, Vector2(320, 0), true)
	var lateral := actor(world, Vector2(30, 45))
	var masked := actor(world, Vector2(60, 0))
	masked.collision_layer = 16
	var cars: Array = [owner, truck, lateral, masked]
	var people: Array = [walker]
	var activity := preload("res://systems/PopulationActivity.gd").new()
	for body in cars + people: activity.set_active(body, false)
	await physics_frame
	await physics_frame
	check(controller.try_reserve_junction(0, owner.get_instance_id(), 0, &"", owner), "Sleeping corridor owner reserves crossing")
	activity.update(world, Vector2(-10000, -10000), cars, people)
	check(owner.can_process() and truck.can_process() and walker.can_process(), "Sleeping chain follows sensor reach and full truck hull beyond 96 px")
	check(not lateral.can_process(), "Nearby lateral traffic outside the sensor corridor stays asleep")
	check(not masked.can_process(), "Sleeping blockers obey the sensor collision mask")
	for body in cars + people: activity.set_active(body, false)
	var rules := preload("res://cars/traffic/TrafficSimulationBudget.gd")
	var small_stats := {}
	var local_chain: Dictionary = rules.active_conflict_actors(self, Rect2(), small_stats)
	for i in 500:
		var distant := actor(world, Vector2(10000 + i * 300, 10000))
		activity.set_active(distant, false)
	var large_stats := {}
	var scaled_chain: Dictionary = rules.active_conflict_actors(self, Rect2(), large_stats)
	check(scaled_chain.size() == local_chain.size(), "500 distant sleepers do not expand the reserved dependency chain")
	check(large_stats.indexed_actors == small_stats.indexed_actors + 500, "Conflict snapshot includes every distant resident once")
	check(large_stats.shape_tests == small_stats.shape_tests, "Distant residents do not multiply local collision tests")
	print("CONFLICT_INDEX_SCALING small=", small_stats, " large=", large_stats)
	var wall := StaticBody2D.new()
	wall.position = Vector2(60, 0)
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	wall_shape.shape = RectangleShape2D.new()
	wall_shape.shape.size = Vector2(10, 40)
	wall.add_child(wall_shape)
	world.add_child(wall)
	owner.get_node("FrontRay").collision_mask |= 1
	await physics_frame
	await physics_frame
	var obstructed: Dictionary = rules.active_conflict_actors(self)
	check(not obstructed.has(truck.get_instance_id()), "Live wall truncates the sleeping-blocker corridor")
	wall.queue_free()
	await process_frame
	(truck.get_child(0) as CollisionShape2D).disabled = true
	var disabled: Dictionary = rules.active_conflict_actors(self)
	check(not disabled.has(truck.get_instance_id()), "Disabled hulls cannot wake a dependency chain")
	controller.release_vehicle(owner.get_instance_id())
	activity.restore_all()
	world.queue_free()
	await process_frame
