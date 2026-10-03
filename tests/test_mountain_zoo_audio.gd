extends SceneTree
const ZOO=preload("res://world/mountain_detail/zoo/MountainZoo.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var stage:=Node3D.new(); root.add_child(stage)
	root.audio_listener_enable_3d=true
	var camera:=Camera3D.new(); stage.add_child(camera); camera.make_current()
	var zoo:=ZOO.new(); stage.add_child(zoo); zoo.set_process(false)
	var listener:=AudioListener3D.new(); stage.add_child(listener); listener.make_current()
	AudioServer.add_bus()
	var bus:=AudioServer.bus_count-1; AudioServer.set_bus_name(bus,"ZooAudioProbe")
	# Capture before bus output gain, quietly; actual source gain and distance remain untouched.
	AudioServer.set_bus_volume_db(bus,-20)
	var capture:=AudioEffectCapture.new(); capture.buffer_length=2
	AudioServer.add_bus_effect(bus,capture)
	var reports: Array[Dictionary]=[]
	if zoo.sounds.size()!=4: failures.append("Four field recordings must load")
	for sound in zoo.sounds:
		sound.bus="ZooAudioProbe"; listener.global_position=sound.global_position+Vector3(0,1,2)
		capture.clear_buffer(); sound.play()
		var peak:=0.0
		var frames:=0
		var began:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-began<2500000:
			await process_frame
			var values:=capture.get_buffer(capture.get_frames_available())
			frames+=values.size()
			for value in values: peak=maxf(peak,maxf(absf(value.x),absf(value.y)))
		if peak<.00001 or frames<1000: failures.append(str(sound.name)+" produced no mixed audio")
		listener.global_position=sound.global_position+Vector3(150,0,0)
		await create_timer(.3).timeout
		capture.clear_buffer()
		await create_timer(.3).timeout
		var far_peak:=0.0
		for value in capture.get_buffer(capture.get_frames_available()): far_peak=maxf(far_peak,maxf(absf(value.x),absf(value.y)))
		if far_peak>.000001: failures.append(str(sound.name)+" audible outside maximum distance")
		reports.append({"source":str(sound.name),"seconds":sound.stream.get_length(),"near_peak":peak,"mixed_frames":frames,"far_peak":far_peak})
		sound.stop()
	FileAccess.open("res://artifacts/mountain-zoo/audio.json",FileAccess.WRITE).store_string(JSON.stringify({"reports":reports,"failures":failures},"\t"))
	stage.queue_free()
	for i in 3: await process_frame
	AudioServer.remove_bus(bus)
	print("ZOO_AUDIO ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
