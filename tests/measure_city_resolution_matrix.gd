extends "res://tests/measure_city_scenarios.gd"
## A fresh process per resolution: daytime calm, then night/rain/police/fires.
## Keep --police/--chaos/--night/--rain OFF: this runner owns stage transitions.
func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	await super._sample(output, label, seconds, car)
	if _sample_failed: return
	if label != "driving": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("calm.png"))
	# Screenshot encoding is intentionally outside the next runtime sample. A
	# blocking save here can accumulate physics ticks and falsely attribute its
	# I/O stall to the weather/police transition frame.
	await process_frame
	_scenario_hour = 0.90
	_hold_scenario_clock()
	_scenario_world.weather.set_weather(1)
	_scenario_world.weather.weather_timer = 1000000.0
	root.get_node("WantedManager").report_crime(240)
	await process_frame
	await super._sample(output, "chaos", 30.0, car)
	if _sample_failed: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("chaos.png"))
