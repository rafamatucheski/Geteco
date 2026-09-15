extends SceneTree

const WEATHER := preload("res://DayNightWeatherManager.gd")
var failures := 0

class ReactiveVisual extends Node:
	var refreshes := 0
	func queue_redraw() -> void:
		refreshes += 1

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var reactive := ReactiveVisual.new()
	reactive.add_to_group(&"weather_reactive_visuals")
	root.add_child(reactive)
	var weather := WEATHER.new()
	weather.is_dynamic_time = false
	weather.weather_timer = 1000.0
	root.add_child(weather)

	weather.set_weather(WEATHER.WeatherState.CLEAR)
	weather.time_of_day = 0.45
	weather._update_lighting()
	check(weather.color.is_equal_approx(Color.WHITE), "Clear midday remains neutral")
	reactive.refreshes = 0

	weather.time_of_day = 0.23
	weather._update_lighting()
	var dawn: Color = weather.color
	check(dawn.b > dawn.r and absf(dawn.g - dawn.b) < 0.16, "Dawn has a restrained gray-blue cast")

	weather.time_of_day = 0.77
	weather._update_lighting()
	var sunset: Color = weather.color
	check(sunset.r > sunset.g and sunset.g > sunset.b, "Sunset has a warm amber gradient")
	check(not weather.is_dark, "Golden sunset keeps daylight presentation active")
	weather.time_of_day = 0.80
	weather._update_lighting()
	check(weather.is_dark, "Street lighting takes over during twilight")

	weather.time_of_day = 0.45
	weather._update_lighting()
	reactive.refreshes = 0
	weather.set_weather(WEATHER.WeatherState.CLOUDY)
	check(reactive.refreshes == 1, "Weather state changes redraw reactive world art once")
	check(not weather.is_raining(), "Cloud cover does not manufacture rain")
	check(not weather.rain_particles.emitting and not weather.splash_particles.emitting, "Cloud cover has no rain particles")
	check(weather.color.get_luminance() < 0.9 and weather.color.b >= weather.color.r, "Cloudy daylight is cool and dimmer than clear daylight")

	weather.set_rain_intensity(0.22)
	weather.set_weather(WEATHER.WeatherState.DRIZZLE)
	check(weather.is_raining() and is_equal_approx(weather.get_rain_intensity(), 0.22), "Drizzle exposes its light intensity to gameplay")
	check(weather.rain_particles.emitting and weather.rain_particles.amount < 70, "Drizzle uses a restrained particle budget")
	check(not weather.thunder_audio.playing, "Drizzle never triggers thunder")

	for i in 160:
		weather._roll_next_city_weather()
		check(weather.weather_state in [WEATHER.WeatherState.CLEAR, WEATHER.WeatherState.CLOUDY, WEATHER.WeatherState.DRIZZLE], "Natural city cycle excludes storms")
		if weather.weather_state == WEATHER.WeatherState.DRIZZLE:
			check(weather.get_rain_intensity() >= 0.14 and weather.get_rain_intensity() <= 0.30, "Natural drizzle stays light")

	weather.set_weather(WEATHER.WeatherState.STORM)
	check(is_equal_approx(weather.get_rain_intensity(), 1.0), "Explicit legacy storm remains available")
	check(weather.rain_particles.amount <= 120 and weather.splash_particles.amount <= 36, "Even explicit storms keep a bounded particle budget")
	weather.set_biome(WEATHER.BiomeType.DESERT_BADLANDS)
	check(weather.weather_state == WEATHER.WeatherState.CLEAR and not weather.is_raining(), "Desert remains dry")

	weather.queue_free()
	reactive.queue_free()
	await process_frame
	# AudioServer retires the private weather bus on its mixing thread.
	await create_timer(0.25).timeout
	print("WEATHER_ATMOSPHERE_CYCLE failures=", failures)
	quit(0 if failures == 0 else 1)
