extends SceneTree
## Actual SFX-bus recording: quieter storm bed + public weapon audio APIs.
const WEATHER := preload("res://systems/DayNightWeatherManager.gd")
const BANK := preload("res://audio/combat/CombatAudioBank.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var city := root.get_node_or_null("CityAudioManager")
	if city:
		city.set_process(false)
		for child in city.get_children():
			if child is AudioStreamPlayer: child.stop()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var weather := WEATHER.new()
	weather.is_dynamic_time = false
	weather.weather_timer = 1000.0
	world.add_child(weather)
	weather.set_rain_intensity(1.0)
	weather.set_weather(1) # Strong rain without thunder masking the comparisons.
	var voices: Array[AudioStreamPlayer] = []
	for i in 8:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		world.add_child(voice)
		voices.append(voice)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var index := AudioServer.get_bus_index(&"SFX")
	var slot := AudioServer.get_bus_effect_count(index)
	AudioServer.add_bus_effect(index, recorder)
	await create_timer(3.2).timeout
	recorder.set_recording_active(true)
	await create_timer(2.0).timeout
	# Seven 2-second sections. Automatic weapons use a burst at real catalog cadence.
	for kind in ["pistol", "magnum", "smg", "ak47", "m4a1", "shotgun", "sawed_off"]:
		var gap := 0.5
		var shots := 3
		if kind in ["smg", "ak47", "m4a1"]:
			gap = float(WeaponCatalog.get_weapon(kind).fire_interval)
			shots = 6
		for i in shots:
			voices[i].stream = ProceduralAudio.get_gunshot_stream(kind)
			voices[i].volume_db = WeaponCatalog.get_audio_volume_db(kind)
			voices[i].play()
			await create_timer(gap).timeout
		await create_timer(maxf(0.1, 2.0 - gap * shots)).timeout
	# 16–21s: metal, concrete, flesh, wood, glass (two takes each).
	for material in ["metal", "concrete", "flesh", "wood", "glass"]:
		for i in 2:
			voices[i].stream = BANK.sound(material)
			voices[i].volume_db = -10.0 if material == "flesh" else -8.0
			voices[i].play()
			await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	var error := wav.save_to_wav("D:/geteco/artifacts/combat-audio/weapons-with-rain.wav")
	AudioServer.remove_bus_effect(index, slot)
	world.queue_free()
	await create_timer(0.3).timeout
	print("COMBAT_AUDIO_CAPTURE result=", error, " seconds=", wav.get_length())
	quit(0 if error == OK and wav.get_length() > 21.0 else 1)
