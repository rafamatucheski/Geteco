extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	scene.call("_walk")
	var player = scene.get_node("Player")
	var door = scene.get_node("District/Garage/Entrance")
	var manager = scene.get_node("Interiors")
	player.global_position = door.to_global(Vector2(0, 42))
	player.reset_physics_interpolation()
	await create_timer(0.9).timeout
	assert(door.open_amount > 0.95, "Approach opens garage")
	assert(player.global_position.distance_to(door.global_position) < 100, "Standing nearby must not enter")
	Input.action_press("move_up")
	await create_timer(1.1).timeout
	Input.action_release("move_up")
	assert(player.global_position.distance_to(manager.garage_interior.spawn_point.global_position) < 250, "Walking into open garage enters without interaction")
	print("GARAGE_WALK_IN PASS: proximity waits; walking enters actual interior")
	quit(0)
