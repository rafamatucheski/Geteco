extends "res://tests/test_desert_drag_runtime.gd"
## Main render benchmark for instrument presentation. No screenshots while sampling.
## Stationary track, original pre-change HUD versus new default and premium face.
func begin_temporal(race) -> bool:
	var baseline_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-hud="): baseline_path=arg.trim_prefix("--baseline-hud=")
	if baseline_path.is_empty() or not FileAccess.file_exists(baseline_path):
		check(false,"preserved pre-change HUD supplied")
		return false
	var baseline=load(baseline_path)
	var current=load("res://activities/desert_drag/DesertDragHUD.gd")
	var weather=world.session.weather
	weather.weather_state=0
	weather.time_of_day=.9
	weather._update()
	weather.set_process(false)
	var original_camera := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov=57
	camera.far=2200
	world.add_child(camera)
	var framing: Dictionary=race.camera_frame(race.grid(0).origin,race.grid(1).origin)
	camera.global_position=framing.position
	camera.look_at(framing.target,Vector3.UP)
	camera.make_current()
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	world.hud.root_control.hide()
	var layer := CanvasLayer.new()
	layer.layer=75
	root.add_child(layer)
	var drive=preload("res://gameplay/desert_cars/DesertDrivetrain.gd").new()
	drive.configure("desert_mirage")
	var results := {"scope":"Main stationary desert strip, UI delta only. Instruments sweep synthetic display values; not a race-speed benchmark.","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"vsync":0,"fps_cap":0,"baseline":baseline_path,"samples":{}}
	for identity in ["before","classic","champion"]:
		var hud=baseline.new() if identity=="before" else current.new()
		if identity!="before": hud.set_style(identity)
		layer.add_child(hud)
		hud.racing=true
		var beginning := Time.get_ticks_usec()
		var stamp := beginning
		var samples: Array[float]=[]
		# Seis segundos de aquecimento seguidos de exatamente32segundos de intervalos de quadro de parede.
		while Time.get_ticks_usec()-beginning<38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			var elapsed := float(now-beginning)/1000000.0
			if elapsed>=6.0: samples.append(float(now-stamp)/1000.0)
			stamp=now
			drive.rpm=2000.0+4500.0*(sin(elapsed*1.4)*.5+.5)
			drive.speed_mps=20.0+30.0*(sin(elapsed*.4)*.5+.5)
			drive.gear=3
			hud.update_state(drive,400.0,12.5,2.0,"","Digo")
		results.samples[identity]=summarize(samples)
		var printable: Dictionary=results.samples[identity].duplicate()
		printable.erase("raw_ms")
		print("INSTRUMENT_PERF ",identity," ",JSON.stringify(printable))
		hud.queue_free()
		await process_frame
	var folder := "res://evidence/drag-instrument-perf-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("INSTRUMENT_PERF_PATH ",ProjectSettings.globalize_path(folder))
	layer.queue_free()
	camera.queue_free()
	if is_instance_valid(original_camera): original_camera.make_current()
	weather.set_process(true)
	return false

func summarize(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in samples:
		total+=value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	return {"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":samples}
