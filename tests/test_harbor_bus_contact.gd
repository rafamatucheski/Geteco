extends SceneTree

var failures: Array[String] = []
const SCENE := preload("res://world/shared/traffic/TrafficVehicle.tscn")

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(0, 250))
	lane.curve.add_point(Vector2(2000, 250))
	world.add_child(lane)
	var follow := PathFollow2D.new()
	follow.loop = false
	lane.add_child(follow)
	follow.progress = 500
	var bus = SCENE.instantiate()
	bus.set_script(preload("res://world/harbor/HarborTransitBus.gd"))
	follow.add_child(bus)
	bus.set_process(false)
	bus.set_physics_process(false)
	var car = SCENE.instantiate()
	world.add_child(car)
	car.set_process(false)
	car.set_physics_process(false)
	await physics_frame
	check(bus.is_3d_vehicle and bus.visual.visible and bus.body_model != null, "Bus must render a native 3D model")
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		car.global_position = bus.global_position + direction * 240
		var hit: KinematicCollision2D = car.move_and_collide(-direction * 480)
		check(hit != null and hit.get_collider() == bus, "Car sweep must contact bus from %s" % direction)
		check((car.global_position - bus.global_position).dot(direction) > 20, "Car must stay on its approach side")
	car.global_position = Vector2(900, 250)
	await physics_frame
	for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
		bus.get_node(ray_name).enabled = false
	bus.depart()
	for i in 500:
		await physics_frame
		bus.advance_on_lane(1.0 / 60.0)
	check(bus.global_position.x > 550 and bus.global_position.x <= car.global_position.x - (bus.collision.shape.size.x + car.collision.shape.size.x) * 0.5, "Moving bus must stop against a car")
	car.global_position = Vector2(300, 250)
	var tail := PathFollow2D.new()
	tail.loop = false
	lane.add_child(tail)
	tail.progress = 300
	car.reparent(tail)
	car.position = Vector2.ZERO
	bus.dwelling = true
	for i in 600:
		await physics_frame
		bus.advance_on_lane(1.0 / 60.0)
		car.advance_on_lane(1.0 / 60.0)
	check(bus.global_position.x - car.global_position.x >= (bus.target_length + car.target_length) * 0.5 + 14, "Traffic must queue behind a dwelling bus")
	check(bus.doors == 1.0 and bus.body_model.platform_leaves[0].position.z < -3.7, "Platform doors must open in 3D")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(1000, 600)
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.position = bus.global_position
		camera.zoom = Vector2.ONE * 4
		bus._update_3d_orientation(1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/harbor-bus-3d.png")
	print("HARBOR_BUS_CONTACT failures=%d" % failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)










