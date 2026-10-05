extends "res://tests/measure/measure_motocross.gd"
func _process(_delta: float) -> bool: return false
func run() -> void:
	paddock_focus = true
	await super.run()
	started = 0
	var folder := "res://evidence/digo/yard-" + label
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19
	world.add_child(camera)
	camera.position = Vector3(-214,18,-18)
	camera.look_at(Vector3(-231,0,-34))
	camera.make_current()
	await create_timer(3).timeout
	var values: Array[float] = []
	var begin := Time.get_ticks_usec()
	var previous_frame := begin
	while Time.get_ticks_usec()-begin < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		values.append((now-previous_frame)/1000.0)
		previous_frame = now
	var report := {"summary":stats(values),"frames_ms":values,"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}
	FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	# Separate continuous temporal evidence from performance sampling.
	Engine.max_fps = 30
	var times: Array = []
	begin = Time.get_ticks_usec()
	while Time.get_ticks_usec()-begin < 30000000:
		var elapsed := (Time.get_ticks_usec()-begin)/1000000.0
		var angle := sin(elapsed*.25)*.5
		camera.position = Vector3(-231,0,-34)+Vector3(17,18,16).rotated(Vector3.UP,angle)
		camera.look_at(Vector3(-231,0,-34))
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		frame.resize(960,540)
		frame.save_jpg(folder+"/%04d.jpg"%times.size(),.9)
		times.append(Time.get_ticks_usec()-begin)
	FileAccess.open(folder+"/timestamps.json",FileAccess.WRITE).store_string(JSON.stringify(times))
	print("DIGO_YARD_DONE ",label," ",JSON.stringify(report.summary)," captured_frames=",times.size())
	quit()
