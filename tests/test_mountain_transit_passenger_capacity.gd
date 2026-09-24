extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures += 1

func _run() -> void:
	var mountain := Node2D.new()
	root.add_child(mountain)
	current_scene = mountain
	var village := Node2D.new()
	mountain.add_child(village)
	var passengers := preload("res://world/mountain_pass/transit/MountainTransitPassengers.gd").new()
	village.add_child(passengers)
	passengers.set_physics_process(false)
	var player := Node2D.new()
	player.add_to_group("player")
	mountain.add_child(player)
	player.global_position = passengers.mountain_point(preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd").BUS_DOOR)
	var coach := Node2D.new()
	mountain.add_child(coach)
	_check(passengers.receive_coach(coach) and passengers.history.back().expected == 5, "First coach creates five travelers")
	passengers.cancel_exchange(coach)
	for traveler in passengers.travelers:
		traveler.is_dead = true
	_check(passengers.receive_coach(coach) and passengers.history.back().expected == 2, "Visible corpses remain, but do not consume live passenger capacity")
	_check(passengers.travelers.size() == 7, "Visible corpses stay in the scene")
	passengers.cancel_exchange(coach)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * 0.25
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	mountain.add_child(camera)
	camera.global_position = passengers.travelers[0].global_position
	camera.make_current()
	player.global_position += Vector2(1200, 0)
	await physics_frame
	await physics_frame
	_check(not passengers._corpse_out_of_view(passengers.travelers[0], player), "Wide camera keeps a visible corpse even beyond the proximity radius")
	player.global_position += Vector2(4000, 0)
	camera.global_position = player.global_position
	await physics_frame
	await physics_frame
	_check(passengers.receive_coach(coach) and passengers.history.back().expected == 4, "Later coach still fills available live slots")
	_check(passengers.travelers.size() == 6, "Corpses outside player range are retired")
	mountain.queue_free()
	await process_frame
	quit(1 if failures else 0)
