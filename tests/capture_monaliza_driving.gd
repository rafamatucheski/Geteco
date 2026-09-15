extends SceneTree
const CAR := preload("res://world/harbor/monaliza/MonalizaCar.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	var city := root.get_node("CityAudioManager")
	city.set_process(false)
	for child in city.get_children():
		if child is AudioStreamPlayer: child.stop()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var car := CAR.new()
	world.add_child(car)
	car.unlocked = true
	car.is_driven_by_player = true
	car._drive_input_armed = true
	car.get_node("Camera").enabled = true
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index(&"SFX")
	var slot := AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, recorder)
	recorder.set_recording_active(true)
	car.ignition.play()
	await create_timer(1.5).timeout
	Input.action_press("move_up")
	await create_timer(8.0).timeout
	print("MONALIZA_CAPTURE full_throttle_speed=", car.velocity.length(), " gear=", car._engine_sound.gear, " rpm=", car._engine_sound.engine_rpm)
	Input.action_release("move_up")
	await create_timer(1.0).timeout
	Input.action_press("move_up")
	await create_timer(2.0).timeout
	Input.action_release("move_up")
	await create_timer(3.8).timeout
	await create_timer(0.5).timeout
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	# The record effect is before bus gain. Fade PCM, not the bus, to avoid
	# introducing a click at the end of this standalone audition file.
	var data := wav.data
	var peak := 1
	for i in data.size() / 2: peak = maxi(peak, absi(data.decode_s16(i * 2)))
	var channels := 2 if wav.stereo else 1
	var frames := data.size() / (2 * channels)
	for frame in frames:
		var gain := 0.72 * 32767.0 / float(peak)
		gain *= smoothstep(0.0, 0.015, float(frame) / wav.mix_rate)
		gain *= smoothstep(0.0, 0.25, float(frames - 1 - frame) / wav.mix_rate)
		for channel in channels:
			var index := (frame * channels + channel) * 2
			data.encode_s16(index, int(data.decode_s16(index) * gain))
	wav.data = data
	var path := ProjectSettings.globalize_path("res://../artifacts/monaliza-rb26-review/monaliza-rb26-shift-flutter.wav")
	var error := wav.save_to_wav(path)
	AudioServer.remove_bus_effect(bus, slot)
	world.queue_free()
	await process_frame
	print("MONALIZA_CAPTURE error=", error, " duration=", wav.get_length(), " path=", path)
	quit(0 if error == OK and wav.get_length() > 14.0 else 1)
