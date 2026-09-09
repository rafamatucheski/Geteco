extends SceneTree

class MountainFixture:
	extends Node2D
	var road: Node2D
	var streamed_region := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture := MountainFixture.new()
	fixture.position = Vector2(4300, -4960)
	root.add_child(fixture)
	current_scene = fixture
	fixture.road = preload("res://world/mountain_pass/MountainPassRoad.gd").new()
	fixture.add_child(fixture.road)
	var traffic := preload("res://world/mountain_pass/MountainTraffic.gd").new()
	fixture.add_child(traffic)
	for car in traffic.vehicles: car.queue_free()
	var actor := CharacterBody2D.new()
	actor.add_to_group("player")
	fixture.add_child(actor)
	actor.global_position = fixture.to_global(Vector2(6550, 175))
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.report_crime(15)
	await physics_frame
	await physics_frame
	var spawn: Dictionary = wanted._find_lane_spawn(actor)
	assert(not spawn.is_empty(), "Mountain traffic supplies viable lane spawns at translated world origin")
	var police = root.get_node("EmergencyPool").get_vehicle("police")
	police.global_position = spawn.position
	police.rotation = spawn.rotation
	police.target = actor
	police.set_meta("police_player_pursuit", true)
	var initial_distance: float = police.global_position.distance_to(actor.global_position)
	var worst_pavement_distance := 0.0
	for index in 1000:
		await physics_frame
		if not police.visible: break
		var local: Vector2 = fixture.road.to_local(police.global_position)
		worst_pavement_distance = maxf(worst_pavement_distance, local.distance_to(fixture.road.curve.get_closest_point(local)))
		if police.is_acting: break
	print("MOUNTAIN_POLICE_METRICS|start=",initial_distance,"|end=",police.global_position.distance_to(actor.global_position),"|visible=",police.visible,"|max_axis_distance=",worst_pavement_distance)
	assert(police.visible, "Cruiser remains active during approach")
	assert(worst_pavement_distance < 65.0, "Cruiser remains on the 140px road through mountain bends")
	assert(police.global_position.distance_to(actor.global_position) < initial_distance - 150.0, "Cruiser approaches along translated lane")
	fixture.process_mode = Node.PROCESS_MODE_DISABLED
	assert(wanted._find_lane_spawn(actor).is_empty(), "Dormant region cannot spawn police")
	print("POLICE_MOUNTAIN_LANES|PASS|worst_pavement_distance=", worst_pavement_distance)
	wanted.dismiss_all_police()
	fixture.queue_free()
	await process_frame
	quit()
