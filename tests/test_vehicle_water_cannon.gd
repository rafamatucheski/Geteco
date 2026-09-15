extends SceneTree

const VEHICLE := preload("res://cars/traffic/TrafficVehicle.tscn")
var failures := 0

class Driver extends CharacterBody2D:
	var is_control_disabled := false
	var is_in_dialogue := false
	var is_dead := false
	var is_arrested := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var truck = VEHICLE.instantiate()
	world.add_child(truck)
	truck.apply_archetype("rescue_pumper")
	truck.configure_as_parked()
	truck.position = Vector2(260, 360)
	var cannon = truck.get_node_or_null("WaterCannon")
	check(cannon != null, "Catalog fire trucks must receive a water cannon")
	if cannon == null:
		quit(1)
		return
	var driver := Driver.new()
	world.add_child(driver)
	driver.add_to_group("player")
	truck._driver = driver
	truck.is_driven_by_player = true
	var controls := root.get_node("GameInput")
	controls.touch_aim = Vector2.RIGHT
	await frames(4)
	check(cannon.can_operate(), "Occupied working truck can operate")
	check(is_instance_valid(truck.body_model.water_turret), "Animated turret survives mesh batching")
	Input.action_press("fire")
	await frames(4)
	check(cannon.firing and cannon._audio.playing, "Holding fire produces continuous water and audio")
	check(cannon._muzzle.distance_to(cannon.impact_position) <= cannon.REACH + 0.1, "Finite stream range")
	var direction: Vector2 = cannon._muzzle.direction_to(cannon.impact_position)
	var person = load("res://AnimatedPedestrian3D.gd").new()
	world.add_child(person)
	person.set_physics_process(false)
	person.global_position = cannon._muzzle + direction * 160
	var initial_health: int = person.health
	await frames(30)
	check(person.health < initial_health and person.health >= initial_health - 12, "Real pedestrian receives light, rate-limited damage")
	check(cannon.hit_target == person, "Water stops on the first pedestrian")
	Input.action_release("fire")
	await frames(3)
	check(not cannon.firing and not cannon._audio.playing and not cannon._splash.emitting, "Release immediately stops spray and audio")
	var after_release: int = person.health
	await frames(15)
	check(person.health == after_release, "No damage after release")
	person.position += Vector2(0, 200)
	var car = VEHICLE.instantiate()
	world.add_child(car)
	car.apply_archetype("sedan_classic")
	car.configure_as_parked()
	car.position = cannon._muzzle + direction * 200
	car.health = 70
	car.bloody_tires_timer = 4.0
	car._ensure_skid_line().add_point(car.position)
	car.skid_line.add_point(car.position + Vector2.RIGHT * 20)
	Input.action_press("fire")
	await frames(20)
	check(cannon.hit_target == car, "Water collides with real traffic cars")
	check(car.health == 70, "Washing neither damages nor repairs a car")
	check(car.bloody_tires_timer == 0 and car.skid_line.get_point_count() == 0, "Washing removes tire residue and stale bloody trail")
	check(car.has_node("WaterWash"), "Car gets temporary wet highlights")
	check(not car.has_node("WaterCannon"), "Ordinary cars have no cannon")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 130)
	shape.shape = rectangle
	wall.add_child(shape)
	wall.position = cannon._muzzle + direction * 90
	world.add_child(wall)
	car.bloody_tires_timer = 4.0
	await frames(20)
	check(cannon.hit_target == wall, "Walls block water before the target")
	check(car.bloody_tires_timer > 0, "No washing through walls")
	wall.queue_free()
	driver.is_in_dialogue = true
	await frames(3)
	check(not cannon.firing, "Dialogue blocks cannon controls")
	driver.is_in_dialogue = false
	truck.set_meta("vehicle_boarding", true)
	await frames(3)
	check(not cannon.firing, "Boarding blocks cannon controls")
	truck.remove_meta("vehicle_boarding")
	truck.is_broken = true
	await frames(3)
	check(not cannon.firing, "Broken truck cannot fire")
	truck.is_broken = false
	await frames(3)
	check(cannon.firing, "Cannon resumes on an operational occupied truck")
	paused = true
	check(not cannon.firing and not cannon._audio.playing, "Pause stops water audio immediately")
	paused = false
	truck.is_driven_by_player = false
	await frames(3)
	check(not cannon.firing, "Leaving the driver's seat stops water")
	Input.action_release("fire")
	controls.touch_aim = Vector2.ZERO
	truck.apply_archetype("sedan_classic")
	check(not truck.has_node("WaterCannon"), "Recycled non-fire trucks lose their cannon")
	world.queue_free()
	await process_frame
	print("VEHICLE_WATER_CANNON failures=%d" % failures)
	quit(0 if failures == 0 else 1)
