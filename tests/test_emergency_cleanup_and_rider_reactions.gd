extends SceneTree

var failures := 0
class PlayerTarget extends Node2D:
	var damage := 0
	func take_damage(amount: int) -> void: damage += amount
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	await process_frame
	var car = load("res://cars/traffic/TrafficVehicle.gd").new()
	world.add_child(car)
	car.set_physics_process(false)
	car.toggle_siren()
	check(car.siren_audio.playing and car.siren_audio.attenuation > 2.0 and car.siren_audio.bus == &"SFX", "siren uses steep distance attenuation and SFX volume")
	car.is_exploded = true
	car.toggle_siren()
	check(not car.siren_audio.playing and not car.is_siren_on, "exploded vehicle cannot enable siren")
	car.is_broken = true
	car.siren_audio.play()
	car.is_siren_on = true
	car._physics_process(0.016)
	check(not car.siren_audio.playing, "broken vehicle silences stale saved siren state")
	var truck = root.get_node("EmergencyPool").get_vehicle("fire")
	truck.set_physics_process(false)
	var firefighter = load("res://emergency/Firefighter.tscn").instantiate()
	world.add_child(firefighter)
	firefighter.set_physics_process(false)
	firefighter.fire_truck = truck
	firefighter.state = firefighter.State.EXTINGUISH
	firefighter._update_hose()
	var expected: Vector2 = (firefighter.hose_camera.unproject_position(firefighter.hose_muzzle.global_position) - Vector2(firefighter.viewport_3d.size) * 0.5) * firefighter.sprite_3d_display.scale
	check(firefighter.hose_line.visible and firefighter.water_hose.position.is_equal_approx(expected), "hose connects truck to projected hand nozzle")
	truck._response_crew.clear()
	truck._response_crew.append(firefighter)
	truck.deployed_firefighters = 2 # One member was lost before boarding.
	truck.returned_firefighters = 0
	truck.is_acting = true
	truck.on_firefighter_embarked(firefighter)
	truck.on_firefighter_embarked(firefighter)
	await create_timer(1.1).timeout
	check(truck.returned_firefighters == 1 and truck.is_returning_to_base and not truck.is_acting, "surviving crew returns without waiting forever for lost member; boarding idempotent")
	for reaction in [1, 2]:
		var rider = load("res://characters/CarjackedDriver.gd").new()
		world.add_child(rider)
		rider.set_physics_process(false)
		rider.stolen_vehicle = car
		rider.motorcycle_reaction = reaction
		rider._finish_motorcycle_recovery()
		check(not rider.motorcycle_returning and rider.personality == (rider.Personality.SUBMISSIVE if reaction == 1 else rider.Personality.FIGHTER), "recovery selects requested flee/fight branch " + str(reaction))
		rider.position = Vector2(1000, 0)
		if reaction == 1:
			rider.exit_reaction_timer = 0.0
			rider._physics_process(0.016)
			check(rider.velocity.dot(car.global_position.direction_to(rider.global_position)) > 0.0, "frightened rider runs away from motorcycle")
		else:
			var player := PlayerTarget.new()
			world.add_child(player)
			player.add_to_group("player")
			player.position = Vector2(1020, 0)
			rider.state_timer = 2.0
			rider._update_motorcycle_confrontation(0.016)
			check(player.damage == 4, "confronting rider punches nearby player instead of own motorcycle")
			var wall := StaticBody2D.new()
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(4, 40)
			shape.shape = rectangle
			wall.add_child(shape)
			world.add_child(wall)
			wall.position = Vector2(1010, 0)
			await physics_frame
			rider.state_timer = 2.0
			rider._update_motorcycle_confrontation(0.016)
			check(player.damage == 4, "motorcyclist cannot punch through a solid wall")
			player.queue_free()
			wall.queue_free()
		rider.queue_free()
	truck._deactivate()
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
