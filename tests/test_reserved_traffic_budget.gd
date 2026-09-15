extends SceneTree
const Controller = preload("res://world/shared/roads/traffic/JunctionTrafficController.gd")
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
	print("RESERVED_TRAFFIC_BUDGET failures=", failures)
	graph.queue_free()
	for frame in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
