extends "res://tests/measure_game_frame_stability.gd"

var _subject: Node2D

func _sample_kind(label: String) -> String:
	return "stationary_patrol_parking_" + label

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	if label == "warmup":
		car.global_position = current_scene.get_node("PatrolParking").global_position + Vector2(120, 160)
		car.reset_physics_interpolation()
		current_scene.call("_walk")
		var deadline := Time.get_ticks_msec() + 8000
		while car.is_driven_by_player and Time.get_ticks_msec() < deadline:
			await process_frame
		_subject = current_scene.get_node("Player")
		_subject.global_position = current_scene.get_node("PatrolParking").global_position + Vector2(60, 30)
		_subject.reset_physics_interpolation()
		_subject.get_node("Camera").reset_smoothing()
	Input.action_release("move_up")
	DisplayServer.window_move_to_foreground()
	await super._sample(output, label, seconds, _subject)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
