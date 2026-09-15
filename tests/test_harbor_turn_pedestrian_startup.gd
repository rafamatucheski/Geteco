extends SceneTree
var failures: Array[String] = []

class TestLife extends "res://world/harbor/HarborLife.gd":
	func _spawn_traffic(_network: Node2D) -> void:
		pass
	func _spawn_walkers() -> void:
		pass

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var layout = preload("res://world/harbor/HarborRoadLayout.gd").new()
	layout.name = "RoadLayout"
	world.add_child(layout)
	var network = preload("res://world/harbor/HarborRoadNetwork.gd").new()
	network.name = "RoadNetwork"
	network.provider_paths.assign([NodePath("../RoadLayout")])
	world.add_child(network)
	var rail := Node2D.new()
	rail.name = "FreightRail"
	world.add_child(rail)
	var life := TestLife.new()
	world.add_child(life)
	life.setup(network)
	life.set_process(false)
	var turn: Path2D
	for candidate in get_nodes_in_group("unified_lane_connector"):
		if String(candidate.get_meta("traffic_connection_id", "")) == "6:RoadLayout/foundry_avenue/forward_01>RoadLayout/warehouse_way/forward_01": turn = candidate
	check(turn != null, "Reproduce the real Harbor junction without an interregional service")
	if turn == null:
		quit(1)
		return
	var car := preload("res://emergency/ModernTrafficFactory.gd").spawn_moving_vehicle(turn, "HarborTraffic_53", "route_city", 0.0, 89.6, 53)
	car.set_process(false)
	car.set_physics_process(false)
	var follow: PathFollow2D = car.get_parent()
	follow.progress = 67.96405
	car.position = Vector2.ZERO
	car.rotation = 0.0
	var person := CharacterBody2D.new()
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11
	collision.shape = circle
	person.add_child(collision)
	world.add_child(person)
	person.global_position = Vector2(2286.582, 477.1404)
	check(not car._lane_pedestrian_blocks(follow, person, false), "A sidewalk resident cannot strand the car holding the junction")
	person.global_position = turn.to_global(turn.curve.sample_baked(follow.progress + 10, true))
	check(car._lane_pedestrian_blocks(follow, person, false), "A person in the turning corridor still stops the car")
	turn.set_meta("curved_pedestrian_corridor", false)
	person.global_position = Vector2(2286.582, 477.1404)
	check(car._lane_pedestrian_blocks(follow, person, false), "Other maps retain their existing pedestrian rule")
	var exit_turn: Path2D
	for candidate in get_nodes_in_group("unified_lane_connector"):
		if String(candidate.get_meta("traffic_connection_id", "")) == "11:RoadLayout/union_avenue/forward_01>RoadLayout/market_street/forward_01": exit_turn = candidate
	check(exit_turn != null, "The recorded queue at the terminal return junction is available")
	if exit_turn:
		follow.reparent(exit_turn, false)
		follow.progress = 58.731
		car._lane_motion_speed = 72.0
		var coach := CharacterBody2D.new()
		coach.collision_layer = 2
		coach.collision_mask = 0
		coach.add_to_group("harbor_terminal_coach")
		var coach_shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(107, 29)
		coach_shape.shape = rectangle
		coach.add_child(coach_shape)
		world.add_child(coach)
		coach.global_position = Vector2(1583.54, 1228)
		await physics_frame
		await physics_frame
		check(not car._lane_terminal_coach_blocks(follow, coach), "A distant queued coach does not retain the turning car inside the junction")
		coach.global_position = exit_turn.to_global(exit_turn.curve.sample_baked(follow.progress + 10, true))
		await physics_frame
		check(car._lane_terminal_coach_blocks(follow, coach), "A coach within the real stopping corridor remains a hard blocker")
	print("HARBOR_TURN_PEDESTRIAN_STARTUP failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
