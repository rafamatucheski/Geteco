extends SceneTree
var failures := 0
class FakeCar:
	extends CharacterBody2D
	var health := 100
	func take_damage(amount: int) -> void: health -= amount
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var car := FakeCar.new()
	world.add_child(car)
	car.position = Vector2(300,300)
	var driver := preload("res://CarjackedDriver.tscn").instantiate()
	world.add_child(driver)
	driver.set_physics_process(false)
	driver.stolen_vehicle = car
	driver.personality = CarjackedDriver.Personality.FIGHTER
	driver.global_position = car.to_global(Vector2(-8,-34))
	check(driver.platform_floor_layers == 0 and driver.platform_wall_layers == 0, "driver cannot inherit vehicle platform motion")
	driver.state_timer = 1.2
	driver._update_defense(0.016)
	check(car.health == 96 and driver.punch_timer > 0.0, "defender attacks from reachable door")
	driver._update_defense(0.016)
	check(car.health == 96, "punch cooldown prevents repeated frame damage")
	driver.global_position -= Vector2(40,0)
	driver._update_defense(0.1)
	check(driver.velocity.length() <= 42.1, "defense approach accelerates without launching")
	car.velocity = Vector2(300,0)
	driver._update_defense(0.1)
	check(driver.civilian_routine and driver.velocity.is_zero_approx(), "driver gives up chasing a speeding car")
	driver.civilian_routine = false
	driver.personality = CarjackedDriver.Personality.CALL_POLICE
	driver.phone_call_progress = 0.01
	driver.has_called_police = false
	driver._physics_process(0.02)
	check(driver.has_called_police, "phone report still completes without its status panel")
	check(driver.phone_indicator == null, "phone call has no text status panel")
	world.queue_free()
	await process_frame
	print("CARJACKING DEFENSE: %d failures" % failures)
	quit(1 if failures else 0)
