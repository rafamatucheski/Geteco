extends SceneTree

const OUT_DIR := "D:/geteco/artifacts/weather-cycle-0912"

func _initialize() -> void:
	call_deferred("run")

func wait_frames(count: int) -> void:
	for i in count:
		await process_frame

func capture(world: Node2D, id: String, hour: float, state: int, rain: float = 0.0) -> void:
	world.weather.time_of_day = hour / 24.0
	world.weather.set_rain_intensity(rain)
	world.weather.set_weather(state)
	world.weather._update_lighting()
	await wait_frames(75 if state == DayNightWeatherManager.WeatherState.DRIZZLE else 8)
	await RenderingServer.frame_post_draw
	var path := OUT_DIR.path_join(id + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save atmosphere capture %s: %s" % [path, error_string(error)])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.size = Vector2i(1280, 720)
	var world := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	for i in 360:
		if world.world_build_ready:
			break
		await process_frame
	if world._panel:
		world._panel.hide()
	var camera := world.get_node("OverviewCamera") as Camera2D
	camera.global_position = Vector2(1650, 1050)
	camera.zoom = Vector2.ONE * 0.82
	camera.make_current()
	await wait_frames(10)

	await capture(world, "01-gray-dawn", 5.5, DayNightWeatherManager.WeatherState.CLEAR)
	await capture(world, "02-clear-day", 12.0, DayNightWeatherManager.WeatherState.CLEAR)
	await capture(world, "03-cloudy-day", 12.0, DayNightWeatherManager.WeatherState.CLOUDY)
	await capture(world, "04-light-drizzle", 12.0, DayNightWeatherManager.WeatherState.DRIZZLE, 0.22)
	await capture(world, "05-sunset", 18.5, DayNightWeatherManager.WeatherState.CLEAR)

	print("ATMOSPHERE_CAPTURE_COMPLETE dir=", OUT_DIR)
	world.queue_free()
	await wait_frames(3)
	quit()
