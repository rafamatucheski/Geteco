extends SceneTree
var failures: Array[String] = []
var world: Node2D
var operations: Node2D
var rendering := false
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func tick(service: Node2D, frames: int) -> void:
	for frame in frames:
		operations._physics_process(1.0 / 60.0)
		service._advance(1.0 / 60.0)
		service._sync_native(0.0)
		await physics_frame
func capture(label: String) -> void:
	if not rendering: return
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/terminal-authorization-" + label + ".png")
func run() -> void:
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	rendering = DisplayServer.get_name() != "headless"
	var view: Node2D
	if rendering:
		root.size = Vector2i(1100, 750)
		var region := world
		var layout := preload("res://world/harbor/HarborRoadLayout.gd").new()
		layout.name = "RoadLayout"
		region.add_child(layout)
		world = Node2D.new()
		world.name = "ArrivalStop"
		world.position = Vector2(1700, 1060)
		region.add_child(world)
		var network := preload("res://world/harbor/HarborRoadNetwork.gd").new()
		network.provider_paths.assign([NodePath("../RoadLayout")])
		network.build_guard_rails = false
		region.add_child(network)
		view = preload("res://world/harbor/terminal/HarborTerminalView.gd").new()
		world.add_child(view)
		var camera := Camera2D.new()
		camera.position = Vector2(305, 95)
		camera.zoom = Vector2.ONE * 3.5
		world.add_child(camera)
	operations = preload("res://world/harbor/terminal/HarborTerminalOperations.gd").new()
	operations.architecture = view
	world.add_child(operations)
	operations.set_physics_process(false)
	for service in operations.fleet:
		service.set_physics_process(false)
		for person in service.passenger_service.people: person.set_physics_process(false)
		service.coach.position = Vector2(-800 - service.platform_index * 200, -800)
		service._sync_native(0.0)
	await physics_frame
	await physics_frame
	for inbound in [false, true]: await direction_case(inbound)
	print("TERMINAL_GATE_AUTHORIZATION failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func direction_case(inbound: bool) -> void:
	var service: Node2D = operations.fleet[0]
	var gate: Dictionary = operations.gates[0 if inbound else 1]
	service.state = "arriving" if inbound else "departing"
	service._merge_clear = true
	service._set_route(service._arrival_route() if inbound else service._departure_route())
	service.route_progress = service.gate_stop_progress - 35
	service.coach.position = service.route.sample_baked(service.route_progress)
	service.heading = service._route_heading(service.route_progress)
	service.coach_shape.shape = service._shape_for_heading(service.heading)
	service.current_speed = 20
	var label := "Entry" if inbound else "Exit"
	var walker := CharacterBody2D.new()
	walker.collision_layer = 4
	walker.collision_mask = 0
	walker.position = gate.point + Vector2(0, 300)
	var collider := CollisionShape2D.new()
	collider.shape = CircleShape2D.new()
	collider.shape.radius = 6
	walker.add_child(collider)
	world.add_child(walker)
	await physics_frame
	await physics_frame
	await tick(service, 20)
	check(gate.requests == 0 and gate.opening == 0, label + " mere approach does not request permission or open the gate")
	for frame in 300:
		await tick(service, 1)
		if gate.state == "checking": break
	await tick(service, 120)
	check(gate.state == "checking" and gate.authorizations == 0 and gate.opening == 0, label + " clear lane still requires a perceptible stopped authorization check")
	await capture(label.to_lower() + "-checking")
	walker.position = gate.point
	await physics_frame
	await physics_frame
	await tick(service, 180)
	check(gate.state == "checking" and gate.opening == 0 and gate.requests == 1 and service.current_speed < 1, label + " driver stops and calls once while pedestrian holds the gate")
	check(service.route_progress <= service.gate_stop_progress + .01, label + " entire coach remains behind the closed arm")
	walker.position += Vector2(0, 300)
	await physics_frame
	await physics_frame
	var held_while_opening := true
	for frame in 75:
		operations._physics_process(1.0 / 60.0)
		service._advance(1.0 / 60.0)
		service._sync_native(0.0)
		if gate.state == "opening": held_while_opening = held_while_opening and service.route_progress <= service.gate_stop_progress + .01
		await physics_frame
	check(held_while_opening and gate.authorizations == 1, label + " green authorization waits for the arm to finish rising")
	await capture(label.to_lower() + "-released")
	var retained_through_hull := true
	var saw_partial := false
	var passed := false
	for frame in 650:
		# A person reaches the threshold just after the rear clears, so there
		# must be no closing stroke across that newly occupied space.
		if gate.state == "passing" and operations._owner_cleared(gate):
			walker.position = gate.point
			await physics_frame
			await physics_frame
			passed = true
			break
		operations._physics_process(1.0 / 60.0)
		service._advance(1.0 / 60.0)
		service._sync_native(0.0)
		if gate.state == "passing" and operations._gate_occupied(gate):
			saw_partial = true
			retained_through_hull = retained_through_hull and gate.owner == service and gate.opening == 1
		await physics_frame
	check(passed and saw_partial and retained_through_hull, label + " keeps its exclusive passage until the entire long hull clears")
	await tick(service, 60)
	check(gate.opening == 1 and gate.state == "passing", label + " pedestrian on the threshold prevents closing")
	await capture(label.to_lower() + "-rear-clear")
	walker.queue_free()
	await physics_frame
	await physics_frame
	await tick(service, 100)
	check(gate.state == "closed" and gate.passages == 1 and gate.owner == null, label + " closes after the coach and pedestrian leave, releasing its reservation")
	service.coach.position = Vector2(-1000, -800)
	await physics_frame
	await physics_frame
