extends SceneTree

var world
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func frames(count: int) -> void:
	for index in count: await physics_frame

func wait_transition(limit := 240) -> bool:
	for index in limit:
		await physics_frame
		if not world.driving.is_body_transition_active(): return true
	return false

func approach(side := -1) -> void:
	var car = world.driving.car
	world.player.teleport(car.driver_door_anchor(side) + car.global_basis.x * float(side) * .35)
	await frames(2)

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	await frames(10)
	var driving = world.driving
	var car = driving.car
	await approach()
	var start: Vector3 = world.player.global_position
	check(driving.interact(),"entry admitted at the physical driver door")
	check(driving.occupied and driving.is_body_transition_active(),"entry reserves occupancy while the body transition owns controls")
	check(world.player.visible and world.player.collision_layer==0 and not car.controlled and car.input_locked,"entry keeps Dante visible but non-colliding until seated")
	await frames(28)
	check(world.player.global_position.distance_to(start)>.05 and world.player.global_position.distance_to(car.global_position)>.15,"entry moves through the doorway instead of teleporting to vehicle centre")
	check(driving.interact(),"repeated exit request reverses an in-progress entry")
	check(await wait_transition(),"reversed entry completes")
	check(not driving.occupied and world.player.visible and world.player.collision_mask==7 and world.camera.target==world.player,"reversed entry restores walking, collision and camera")

	await approach()
	check(driving.interact(),"normal entry starts")
	check(await wait_transition(),"normal entry animation completes")
	check(driving.occupied and not world.player.visible and car.controlled and not car.input_locked,"normal entry settles hidden occupant and enables driving only at the seat")
	car.speed=0
	car.velocity=Vector3.ZERO
	check(driving.leave(),"normal stopped exit starts")
	check(driving.occupied and driving.is_body_transition_active() and car.input_locked,"exit retains occupancy and locks the vehicle during body presentation")
	check(await wait_transition(),"normal exit animation completes")
	check(not driving.occupied and world.player.visible and world.player.collision_layer==2 and world.player.is_physics_processing(),"normal exit restores body and movement")

	await approach()
	check(driving.interact(),"entry starts before death interruption")
	await frames(12)
	driving.cancel_transition("player_death")
	check(not driving.occupied and not driving.is_body_transition_active() and world.player.visible,"death cancellation releases the partial boarding pose")
	check(world.player.collision_layer==2 and world.camera.target==world.player,"death cancellation restores collision and camera ownership")

	await approach()
	check(driving.interact(),"entry starts before removal interruption")
	await frames(12)
	car.queue_free()
	await frames(3)
	check(not driving.occupied and not driving.is_body_transition_active(),"vehicle removal cancels boarding ownership")
	check(world.player.visible and world.player.collision_layer==2 and world.camera.target==world.player,"vehicle removal leaves Dante and camera released")

	for failure in failures: push_error(failure)
	print("VEHICLE_BODY_TRANSITIONS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
