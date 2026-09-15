extends "res://tests/test_harbor_alleys.gd"
## The production officer must find both turns from the final destination,
## using physical motion, rather than being fed the alley's waypoints by a test.

func _run() -> void:
	create_timer(150.0).timeout.connect(func(): printerr("POLICE_ALLEYS TIMEOUT"); quit(2))
	var scene := load(PREVIEW_PATH).instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	for frame in 4: await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	_disable_dynamic_collisions(scene, player)
	player.set_physics_process(false)
	player.collision_layer = 0
	var provider := scene.get_node("Alleys") as Node2D
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	officer.set_meta("quiet_patrol", true)
	officer.set_meta("response_tier_level", 1)
	scene.add_child(officer)
	officer.set_physics_process(false)
	officer.collision_mask = 1
	for definition: Dictionary in provider.get_alley_definitions():
		for reverse in [false, true]:
			var points: PackedVector2Array = definition.points.duplicate()
			if reverse: points.reverse()
			var entry := provider.to_global(points[0])
			var goal := provider.to_global(points[-1])
			officer.global_position = entry - points[0].direction_to(points[1]) * 40.0
			officer.movement_navigation = load("res://police/PoliceFootNavigation.gd").new()
			await physics_frame
			var max_step := 0.0
			for frame in 1500:
				var before: Vector2 = officer.global_position
				officer.velocity = officer._navigate_towards(goal, officer.speed, 1.0 / 60.0)
				officer.move_and_slide()
				max_step = maxf(max_step, before.distance_to(officer.global_position))
				if officer.global_position.distance_to(goal) < 5.0: break
				await physics_frame
			_check(officer.global_position.distance_to(goal) < 5.0, "%s reverse=%s reaches final alley exit; position=%s goal=%s" % [definition.id, reverse, officer.global_position, goal])
			_check(max_step <= officer.speed / 60.0 + .25, "No teleport or speed burst through passage")
	print("POLICE_ALLEYS_RESULT failures=", _failures.size())
	_finish(scene)
