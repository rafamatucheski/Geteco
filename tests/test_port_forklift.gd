extends SceneTree
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
var failures := 0
var world: Node2D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func parked(id: String, at: Vector2):
	var body = FACTORY.spawn_parked_vehicle(world,id,at,0,id,0)
	body.ensure_presentation()
	return body

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var forklift = parked("port_forklift",Vector2(300,300))
	var lift = forklift.get_node("ForkliftLift")
	var actor = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	var body_shape := CollisionShape2D.new()
	body_shape.shape = CircleShape2D.new()
	actor.add_child(body_shape)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.position = forklift.position + Vector2(0,40)
	forklift.enter_vehicle(actor)
	await frames(150)
	check(forklift.is_driven_by_player and lift.can_operate(), "Real player boards and can use hydraulics after animation")
	check(forklift.body_model.carriage.get_child_count() > 0, "Moving forks survive batching")
	check(forklift.wheel_rig.pivots.size() == 4 and forklift.wheel_rig._rear_steering, "Four rolling wheels with rear steering")
	check(forklift.collision.shape.size.x == 39, "Streaming presentation preserves chassis-only hull")
	for kind in ["crate", "sedan_classic", "bike_urban", "port_forklift"]:
		forklift.position = Vector2(300,300)
		forklift.rotation = 0
		forklift.velocity = Vector2.ZERO
		var target: CharacterBody2D
		if kind == "crate":
			target = load("res://world/harbor/ForkliftCrate.gd").new()
			target.position = Vector2(335,300)
			world.add_child(target)
		else:
			target = parked(kind,Vector2(345,300))
		if kind == "port_forklift":
			target.position = Vector2(335,300)
			target.rotation = PI*0.5
		var layers := Vector2i(target.collision_layer,target.collision_mask)
		await frames(3)
		check(lift.nearby_cargo() == target, kind + " fits the forks")
		Input.action_press("fire")
		await frames(100)
		Input.action_release("fire")
		check(lift.cargo == target and lift.height > 1, kind + " picked up using left mouse action")
		check(target.has_meta("forklift_carried") and target.collision_layer == 0 and not lift.load_shape.disabled, kind + " transfers collision to carrier")
		if kind == "port_forklift":
			check(not target.get_node("ForkliftLift").can_operate(), "Suspended forklift cannot use its own hydraulics")
		if kind != "crate":
			var view: Camera3D = target.body_viewport.get_camera_3d()
			for i in target._lamp_mounts.size():
				var point: Vector2 = view.unproject_position(target.body_model.to_global(target._lamp_mounts[i]))
				var expected: Vector2 = target.visual.to_global(point-Vector2(target.body_viewport.size)*0.5)
				var light: PointLight2D = target.headlight if i == 0 else target.second_headlight
				check(light.global_position.distance_to(expected) < 0.1, kind + " suspended lamps follow raised body")
		var before: Vector2 = forklift.position
		Input.action_press("move_up")
		await frames(100)
		Input.action_release("move_up")
		check(forklift.position.distance_to(before) > 20 and forklift.velocity.length() <= 55.1, kind + " moves with heavy speed cap")
		await frames(25)
		check(target.global_position.distance_to((forklift.global_transform * lift._relative).origin) < .1, kind + " follows carrier without drift")
		if kind != "crate":
			target.enter_vehicle(actor)
			check(not target.is_driven_by_player, "Cannot board a suspended vehicle")
		Input.action_press("aim")
		await frames(160)
		Input.action_release("aim")
		check(lift.cargo == null and lift.height == 0, kind + " lowers and releases with right mouse action")
		check(not target.has_meta("forklift_carried") and Vector2i(target.collision_layer,target.collision_mask) == layers and target.process_mode != Node.PROCESS_MODE_DISABLED, kind + " restores body and controls")
		target.queue_free()
		await frames(3)
	# Unloaded top speed and real pedestrian impact at industrial speeds.
	forklift.position = Vector2(300,300)
	forklift.rotation = 0
	Input.action_press("move_up")
	await frames(160)
	check(forklift.velocity.length() > 60 and forklift.velocity.length() <= 90.1, "Unloaded machine remains very slow")
	Input.action_release("move_up")
	await frames(30)
	var person = load("res://AnimatedPedestrian3D.gd").new()
	world.add_child(person)
	person.position = forklift.position + Vector2(70,0)
	person.set_physics_process(false)
	Input.action_press("move_up")
	await frames(95)
	Input.action_release("move_up")
	check(person.is_incapacitated or person.is_dead, "Slow forklift can run over a real pedestrian")
	person.queue_free()
	await frames(30)
	# Keep a loaded hull from tunnelling through a wall or sweeping into it.
	forklift.position = Vector2(300,600)
	forklift.rotation = 0
	var car = parked("sedan_classic",Vector2(345,600))
	await frames(3)
	check(lift.attach(car), "Car reattaches for collision test")
	lift.height = 1
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10,200)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = Vector2(415,600)
	world.add_child(wall)
	Input.action_press("move_up")
	await frames(180)
	Input.action_release("move_up")
	check(car.position.x + car.collision.shape.size.x * .5 <= 410.5, "Full lifted car footprint stops at wall")
	check(forklift.position.x < 340, "Cargo, rather than forklift nose, limits travel")
	check(not is_equal_approx(lift.safe_rotation(.3), .3), "Turning cannot sweep the lifted car through the wall")
	check(lift.release(), "Cargo touching a wall can be put down without teleporting")
	car.position = Vector2(345,600)
	forklift.position = Vector2(300,600)
	lift.height = 0
	car.is_driven_by_player = true
	check(not lift.attach(car), "Occupied vehicles cannot be picked up")
	car.is_driven_by_player = false
	car.position = Vector2(345,710)
	check(not lift.attach(car), "Cargo beside the machine is out of fork reach")
	car.position = Vector2(345,600)
	wall.position = Vector2(320,600)
	await frames(3)
	check(not lift.attach(car), "A wall between the forks and cargo blocks pickup")
	wall.position = Vector2(415,600)
	await frames(3)
	check(lift.attach(car), "Unobstructed car can be picked up again")
	forklift.force_exit_vehicle()
	await frames(3)
	check(not forklift.is_driven_by_player and not actor.is_control_disabled and actor.visible, "Real driver exits forklift")
	forklift.queue_free()
	await frames(3)
	check(is_instance_valid(car) and not car.has_meta("forklift_carried") and car.collision_layer != 0, "Deleting carrier safely restores cargo")
	var recycled = parked("port_forklift",Vector2(800,800))
	recycled.apply_archetype("sedan_classic")
	check(not recycled.has_node("ForkliftLift") and recycled.collision.position == Vector2.ZERO and recycled.collision.shape.size.x > 60, "Changing archetype restores ordinary car hull and removes lifting equipment")
	print("PORT_FORKLIFT failures=",failures)
	quit(1 if failures else 0)
