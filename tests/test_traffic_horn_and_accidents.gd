extends SceneTree
const FACTORY = preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []
var world: Node2D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func fixture(y: float, moving := false, archetype := "sedan_classic") -> Array:
	var lane := FACTORY.create_lane(world, "Lane" + str(y), PackedVector2Array([Vector2(0,y), Vector2(3000,y)]))
	var car := FACTORY.spawn_moving_vehicle(lane, "Driver", archetype, 0.1, 130.0, 0)
	car.set_process(false)
	car.set_physics_process(false)
	car._lane_motion_initialized = true
	car._lane_motion_speed = 130.0 if moving else 0.0
	var actor := AnimatedPedestrian3D.new()
	actor.archetype_override = 0
	world.add_child(actor)
	actor.global_position = car.global_position + Vector2(maxf(85, car.collision.shape.size.x * 0.5 + 55),0)
	actor.set_physics_process(false)
	return [car, actor]

func step(car, actor, frames: int, respond := false) -> void:
	for frame in frames:
		for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
			car.get_node(ray_name).force_raycast_update()
		car.advance_on_lane(1.0/60.0)
		if respond: actor._physics_process(1.0/60.0)
		await physics_frame

func run() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("SaveManager").set("_save_dir", "D:/geteco/artifacts/traffic-horn-0913/saves/")
	root.get_node("NPCMedicalCare").set_process(false)
	root.get_node("PresentationBudget").set_process(false)
	root.get_node("WantedManager").set_process(false)
	var pair := fixture(300)
	var car = pair[0]
	var actor = pair[1]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.size = Vector2i(1280, 720)
		var camera := Camera2D.new()
		camera.position = Vector2(370, 300)
		camera.zoom = Vector2(3,3)
		world.add_child(camera)
		car.ensure_presentation()
		actor.ensure_presentation()
	await physics_frame
	await physics_frame
	await step(car, actor, 65)
	check(not car._person_warned and actor._horn_escape_time == 0 and not actor.is_incapacitated, "driver waits before horn")
	await step(car, actor, 20)
	check(car._person_warned and actor._horn_escape_time > 0, "audible horn reaches real pedestrian")
	await capture("01-horn")
	var start: Vector2 = car.global_position
	await step(car, actor, 240, true)
	check(absf(actor.global_position.y - 300) > 40 and not actor.is_incapacitated, "pedestrian clears lane alive")
	check(car.global_position.x > start.x + 100, "driver continues after pedestrian yields")
	await capture("02-cleared-lane")
	pair = fixture(700)
	car = pair[0]; actor = pair[1]
	await physics_frame
	await physics_frame
	await step(car, actor, 230)
	check(car._person_warned and not actor.is_incapacitated, "warning grace protects person still blocking")
	await step(car, actor, 160)
	check(actor.is_incapacitated or actor.is_dead, "persistent obstruction results in actual lane impact")
	check(actor.has_meta("vehicle_feedback_ms"), "accident triggers injury feedback")
	pair = fixture(1100, true)
	car = pair[0]; actor = pair[1]
	actor.position = car.global_position + Vector2(car.collision.shape.size.x * 0.5 + 11,0)
	await physics_frame
	await physics_frame
	await step(car, actor, 6)
	check(actor.is_incapacitated or actor.is_dead, "sudden crossing is hit during braking")
	pair = fixture(1500)
	car = pair[0]; actor = pair[1]
	actor.set_meta("medical_vehicle_protected", true)
	await physics_frame
	await physics_frame
	await step(car, actor, 400)
	check(not actor.is_incapacitated and not actor.is_dead and car.global_position.x < actor.global_position.x - 30, "medical protection remains a physical blocker")
	pair = fixture(1900)
	car = pair[0]; actor = pair[1]
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(220, 12)
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = actor.global_position + Vector2(0, 32)
	await physics_frame
	await physics_frame
	car.honk_horn()
	check(actor._horn_escape_target.y < actor.global_position.y, "horn chooses free shoulder when other side is a wall")
	await step(car, actor, 180, true)
	check(actor.global_position.y < 1870 and not actor.is_incapacitated, "escape movement respects solid wall")
	pair = fixture(2300, true)
	car = pair[0]; actor = pair[1]
	actor.queue_free()
	var parked = FACTORY.spawn_parked_vehicle(world, "CrossingCar", car.global_position + Vector2(63,0), PI/2, "sedan_classic", 0, Color.BLUE)
	parked.set_process(false)
	parked.set_physics_process(false)
	parked.global_position = car.global_position + Vector2(car.collision.shape.size.x * 0.5 + parked.collision.shape.size.y * 0.5 + 0.5, 0)
	await physics_frame
	await physics_frame
	var original: Vector2 = car.global_position
	await step(car, null, 8)
	check(car.global_position.x < original.x + 12, "sudden vehicle obstruction remains solid")
	check(car._last_crash_visual_ms > 0 and parked._last_crash_visual_ms > 0, "lane accident deforms both vehicles")
	pair = fixture(2700)
	car = pair[0]; actor = pair[1]
	actor.global_position = car.global_position + Vector2(car.collision.shape.size.x * 0.5 + 10, 0)
	await physics_frame
	await physics_frame
	await step(car, actor, 400)
	check(actor.is_incapacitated and not actor.is_dead, "persistent bumper contact produces low-speed knockdown after warning")
	pair = fixture(3100, false, "route_city")
	car = pair[0]; actor = pair[1]
	actor.global_position = car.global_position + Vector2(car.collision.shape.size.x * 0.5 + 10, 0)
	await physics_frame
	await physics_frame
	await step(car, actor, 400)
	check(actor.is_incapacitated and not actor.is_dead, "long vehicle also resolves persistent bumper obstruction without lethal damage")
	print("TRAFFIC_HORN_ACCIDENTS failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/traffic-horn-0913/" + label + ".png")
