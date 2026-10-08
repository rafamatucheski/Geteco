extends "res://tests/test_desert_drag_runtime.gd"
## Paired rendered Main benchmark for this weather delta only; no frame capture.
## Requires a preserved pre-change sky shader via --baseline-sky=absolute/path.
func begin_temporal(race) -> bool:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-sky="): source=arg.trim_prefix("--baseline-sky=")
	if source.is_empty() or not FileAccess.file_exists(source):
		check(false,"preserved pre-change shader supplied")
		return false
	var baseline := Shader.new()
	baseline.code=FileAccess.get_file_as_string(source)
	var weather=world.session.weather
	weather.set_process(false)
	weather.storm.set_process(false)
	weather.weather_state=2
	weather.weather_timer=10000
	weather.time_of_day=.9
	weather._update()
	var original_shader: Shader=weather.drag_sky.material.shader
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
	var results := {"scope":"Stationary Main desert strip, night heavy storm; weather delta only, not whole drag redesign", "engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":[1280,720],"vsync":0,"fps_cap":0,"time_of_day":.9,"baseline_shader":source}
	for phase in ["before","after"]:
		weather.drag_sky.material.shader=baseline if phase=="before" else original_shader
		camera.set_meta("drag_precipitation",phase=="after")
		weather.drag_rain._clock=0.0
		weather.storm.cancel()
		weather.storm._rng.seed=8102026
		# Shader/cache warm-up remains outside the 32-second sample.
		var warm := Time.get_ticks_usec()
		var stamp := warm
		while Time.get_ticks_usec()-warm<6000000:
			await process_frame
			var now := Time.get_ticks_usec()
			advance(weather,float(now-stamp)/1000000.0,phase=="before")
			stamp=now
		weather.storm.cancel()
		weather.storm.lightning_timer=4.0
		var began := Time.get_ticks_usec()
		stamp=began
		var samples: Array[float]=[]
		while Time.get_ticks_usec()-began<32000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-stamp)/1000.0)
			advance(weather,float(now-stamp)/1000000.0,phase=="before")
			stamp=now
		results[phase]=summarize(samples)
		print("DRAG_WEATHER_METRICS ",phase," ",JSON.stringify(results[phase].duplicate().merged({"raw_ms":[]})))
	var folder := "res://evidence/drag-weather-perf-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("DRAG_WEATHER_METRICS_PATH ",ProjectSettings.globalize_path(folder))
	weather.drag_sky.material.shader=original_shader
	camera.queue_free()
	if is_instance_valid(original_camera): original_camera.make_current()
	weather.storm.cancel()
	weather.set_process(true)
	weather.storm.set_process(true)
	return false

func advance(weather, dt: float, before: bool) -> void:
	weather._process(dt)
	weather.storm._process(dt)
	if before: weather.controller.environment.environment.fog_sky_affect=.92

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
