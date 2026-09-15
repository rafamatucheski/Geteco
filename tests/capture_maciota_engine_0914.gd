extends SceneTree
## Finite listening sample of the production engine, with a real audio driver.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	create_timer(40).timeout.connect(func(): quit(2))
	var output := "D:/geteco/artifacts/feedback-0914-teste2/350z"
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node2D.new()
	root.add_child(stage)
	var audio := AudioStreamPlayer2D.new()
	audio.bus = "SFX"
	stage.add_child(audio)
	var engine := preload("res://audio/VehicleEngineSound.gd").new()
	engine.bind(audio,"maciota_350z")
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,recorder)
	recorder.set_recording_active(true)
	var start := Time.get_ticks_usec()
	var previous := start
	var trace: Array = []
	var next_report := 0.0
	while Time.get_ticks_usec()-start < 18000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var t := float(now-start)/1000000.0
		var delta := float(now-previous)/1000000.0
		previous = now
		var speed := 0.0
		var throttle := 0.0
		if t >= 2 and t < 10: speed = (t-2)*27.5; throttle = .7
		elif t >= 10 and t < 13: speed = 220; throttle = .18
		elif t >= 13 and t < 17: speed = 220*(17-t)/4
		engine.update(audio,speed,220,throttle,delta,"maciota_350z")
		if t >= next_report:
			trace.append({"seconds":t,"speed":speed,"gear":engine.gear,"rpm":engine.engine_rpm})
			next_report += .25
	recorder.set_recording_active(false)
	recorder.get_recording().save_to_wav(output.path_join("350z-idle-acceleration-cruise-braking.wav"))
	FileAccess.open(output.path_join("drivetrain.json"),FileAccess.WRITE).store_string(JSON.stringify(trace))
	engine.stop()
	audio.stop()
	print("MACIOTA_AUDIO_CAPTURE ",output)
	quit()
