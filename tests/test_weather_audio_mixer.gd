extends SceneTree
const WEATHER := preload("res://systems/DayNightWeatherManager.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	# Isolate this audio fixture from the autoload's timed siren/radio playback.
	var city_audio := root.get_node_or_null("CityAudioManager")
	if city_audio:
		city_audio.set_process(false)
		for player in city_audio.get_children():
			if player is AudioStreamPlayer:
				player.stop()
	var bus_count := AudioServer.bus_count
	var weather := WEATHER.new()
	weather.is_dynamic_time = false
	weather.weather_timer = 1000.0
	root.add_child(weather)
	var mixer: Node = weather.weather_audio
	var bus_index := AudioServer.get_bus_index(mixer.bus_name)
	check(AudioServer.get_bus_send(bus_index) == &"SFX", "Weather respects the SFX volume/mute control")
	check(mixer.layers.size() == 3 and mixer.get_child_count() == 4, "Bounded three rain voices and one thunder voice")
	for layer in mixer.layers:
		check(layer.stream.stereo and layer.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Stereo seamless looping asset")
	weather.set_rain_intensity(0.25)
	weather.set_weather(1)
	await wait_seconds(1.0)
	check(mixer.layers[0].playing and mixer.layers[1].playing, "Light rain is audible")
	check(not mixer.layers[2].playing, "Light rain does not merely turn down the storm texture")
	weather.set_weather(0)
	weather.set_weather(1)
	weather.set_interior_mode(true)
	weather.set_interior_mode(false)
	await wait_seconds(3.3)
	check(mixer.layers[0].playing and is_equal_approx(mixer.intensity, 0.25), "Rapid reversals leave no stale fade-stop callback")
	weather.set_rain_intensity(0.6)
	await wait_seconds(1.2)
	check(mixer.layers[2].playing, "Moderate rain introduces sheet texture")
	weather.set_weather(2)
	check(not mixer.thunder.playing, "Thunder does not precede the flash")
	await wait_seconds(3.4)
	check(mixer.thunder.playing and mixer.intensity == 1.0, "Storm plays delayed thunder and reaches strong rain")
	var outside_db: float = mixer.layers[0].volume_db
	weather.set_interior_mode(true)
	await wait_seconds(1.0)
	check(mixer.layers[0].playing, "Shelter muffles rain rather than deleting the exterior")
	check(mixer.low_pass.cutoff_hz < 900.0 and mixer.layers[0].volume_db < outside_db - 10.0, "Shelter removes treble and lowers level")
	weather.set_weather(1)
	check(not weather.rain_particles.emitting and weather.color == Color.WHITE, "Weather changes cannot emit rain or flash indoors")
	weather.set_interior_mode(false)
	await wait_seconds(1.0)
	check(mixer.low_pass.cutoff_hz > 17000.0 and weather.rain_particles.emitting, "Leaving shelter restores exterior sound and rain")
	weather.set_weather(2)
	weather.set_weather(0)
	mixer.thunder.stop()
	await wait_seconds(3.5)
	check(not mixer.thunder.playing, "Cancelled storm cannot dispatch stale thunder")
	for layer in mixer.layers:
		check(not layer.playing, "Clear weather stops all three voices after the fade")
	weather.set_weather(2)
	weather.set_biome(WEATHER.BiomeType.DESERT_BADLANDS)
	await wait_seconds(3.5)
	check(mixer.target_intensity == 0.0 and not weather.rain_particles.emitting, "Desert stays dry")
	check(mixer.get_child_count() == 4, "State changes do not accumulate players")
	weather.queue_free()
	await process_frame
	# AudioServer retires playback on its mixing thread, not on a fixed render frame.
	await wait_seconds(0.25)
	check(AudioServer.bus_count == bus_count, "Scene teardown removes its private filter bus")
	print("WEATHER_AUDIO_MIXER failures=", failures)
	quit(0 if failures == 0 else 1)
