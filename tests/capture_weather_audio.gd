extends SceneTree
## Records the actual Godot bus after its indoor filter. No microphone required.
const WEATHER := preload("res://systems/DayNightWeatherManager.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--baseline-only" in OS.get_cmdline_user_args():
		var original := ProceduralAudio.get_rain_stream() as AudioStreamWAV
		var error := original.save_to_wav("D:/geteco/artifacts/weather-audio/rain-before-raw.wav")
		quit(0 if error == OK else 1)
		return
	var weather := WEATHER.new()
	weather.is_dynamic_time = false
	weather.weather_timer = 1000.0
	weather.lightning_timer = 1000.0
	root.add_child(weather)
	var mixer: Node = weather.weather_audio
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(AudioServer.get_bus_index(mixer.bus_name), recorder)
	recorder.set_recording_active(true)
	# 0–6 light; 6–12 moderate; 12–20 storm; 20–26 shelter; 26–32 outside; 32–36 clear.
	weather.set_rain_intensity(0.25)
	weather.set_weather(1)
	await create_timer(6.0).timeout
	weather.set_rain_intensity(0.60)
	await create_timer(6.0).timeout
	weather.set_weather(2)
	await create_timer(8.0).timeout
	weather.set_interior_mode(true)
	await create_timer(6.0).timeout
	weather.set_interior_mode(false)
	await create_timer(6.0).timeout
	weather.set_weather(0)
	await create_timer(4.0).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	var result := recording.save_to_wav("D:/geteco/artifacts/weather-audio/weather-in-game.wav")
	print("WEATHER_AUDIO_CAPTURE result=", result, " seconds=", recording.get_length())
	weather.queue_free()
	await process_frame
	quit(0 if result == OK and recording.get_length() > 34.0 else 1)
