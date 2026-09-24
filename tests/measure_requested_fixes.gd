extends "res://tests/measure_city_scenarios.gd"
## Same production checkpoint and timing metrics, with an explicit foreground
## request before each sample so background throttling cannot certify FPS.
func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	DisplayServer.window_move_to_foreground()
	await create_timer(0.5).timeout
	await super._sample(output, label, seconds, car)
