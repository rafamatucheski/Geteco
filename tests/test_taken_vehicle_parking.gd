extends SceneTree

const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	var actor := CharacterBody2D.new()
	# Production motorcycle boarding reparents Dante's rig and accesses his
	# body nodes; a bare CharacterBody2D is not a valid rider fixture.
	actor.set_script(load("res://characters/Player.gd"))
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	world.add_child(actor)
	actor.set_physics_process(false)
	var case_index := 0
	for id in ["bike_sport", "bike_cruiser", "bike_urban", "union_sedan", "boxrunner"]:
		var lane := FACTORY.create_lane(world, "ParkingTest", PackedVector2Array([Vector2.ZERO, Vector2(1000, 0)]))
		# Drivers ejected by earlier cases remain real solid NPCs. Give each
		# scenario its own street so those actors cannot block a later theft.
		lane.position = Vector2(case_index*2000,0)
		case_index += 1
		var car = FACTORY.spawn_moving_vehicle(lane, "Taken", id, 0.2, 90, 0)
		car.set_physics_process(false)
		actor.position = car.global_position + Vector2(0, 40)
		car.enter_vehicle(actor)
		check(car.is_driven_by_player,id+" is actually taken before testing parking persistence")
		while car.has_meta("vehicle_boarding"): await process_frame
		car.force_exit_vehicle()
		while car.has_meta("vehicle_boarding"): await process_frame
		car.set_physics_process(false)
		actor.set_physics_process(false)
		var parked: Vector2 = car.global_position
		var paint: Color = car.body_model.paint.albedo_color
		car.health = 73
		actor.position = Vector2(20000, 20000)
		for tick in 25: car._physics_process(1.0)
		check(not car.is_queued_for_deletion(), id + " survives a distant interior visit")
		check(car.global_position.distance_to(parked) < 0.01 and car.health == 73 and car.body_model.paint.albedo_color == paint, id + " retains parking position, damage and paint")
		actor.position = parked + Vector2(0, 40)
		# Let production visibility wake the vehicle after the distant visit.
		await process_frame
		await physics_frame
		await process_frame
		car.enter_vehicle(actor)
		if not car.is_driven_by_player:
			print("PARKING_RETURN id=",id," visible=",car.is_visible_in_tree()," broken=",car.is_broken," controls=",actor.get("is_control_disabled"))
		check(car.is_driven_by_player, id + " can be driven again on return")
		while car.has_meta("vehicle_boarding"): await process_frame
		car.force_exit_vehicle()
		while car.has_meta("vehicle_boarding"): await process_frame
		actor.set_physics_process(false)
		car.queue_free()
		lane.queue_free()
		await process_frame
	print("PARKING_FAILURES=", failures)
	quit(1 if failures else 0)
