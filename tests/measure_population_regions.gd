extends "res://tests/measure_game_frame_stability.gd"
## Checkpoint changes deliberately include first-load stalls. Physical seam
## continuity is covered separately by test_continuous_world.gd.
func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	await super._sample(output, label, seconds, car)
	if label != "driving": return
	Input.action_release("move_up")
	await _capture(output, "city")
	var world := current_scene
	world.call("_walk")
	# Exit animation owns player position until it completes.
	var exit_deadline := Time.get_ticks_msec() + 8000
	while (car.get("is_driven_by_player") == true or (is_instance_valid(car.get("_boarding")) and car.get("_boarding").active)) and Time.get_ticks_msec() < exit_deadline:
		await process_frame
	if car.get("is_driven_by_player") == true:
		push_error("Checkpoint requires completed vehicle exit")
		quit(1)
		return
	var player: Node2D = world.get_node("Player")
	player.set_physics_process(false)
	var stream := world.get_node("ContinuousWorld")
	for checkpoint in [
		{"label": "mountain_approach", "point": Vector2(7000, -4560)},
		{"label": "mountain", "point": Vector2(8000, -4529)},
		{"label": "city_return", "point": Vector2(1620, 900)}
	]:
		player.global_position = checkpoint.point
		player.reset_physics_interpolation()
		player.get_node("Camera").reset_smoothing()
		if checkpoint.label == "mountain_approach": stream.call_deferred("ensure_mountain")
		await super._sample(output, checkpoint.label, 30.0, player)
		await _capture(output, checkpoint.label)
		if player.global_position.distance_to(checkpoint.point) > 32.0:
			push_error("Population checkpoint displaced from requested location")
			quit(1)
			return
		if player.get("is_dead") == true or paused:
			push_error("Population checkpoint interrupted by death or pause")
			quit(1)
			return

func _capture(output: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
