extends "res://tests/capture/capture_drag_start_camera.gd"
## Compare the same two real 800 m runs. --before-dir reloads a frozen source
## snapshot in this process only; it never replaces files in the shared checkout.
var recording := false
var stamp := 0
var samples: Array[float]=[]
var reference := ""
var source_hashes := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--before-dir="): reference=argument.trim_prefix("--before-dir=")
	for file in ["DesertDragBoard.gd","DesertDragResults.gd","DesertDragBoardController.gd","DesertDrag.gd"]:
		var path: String="res://activities/desert_drag/"+file
		var script := load(path) as GDScript
		if not reference.is_empty():
			script.source_code=FileAccess.get_file_as_string(reference.path_join(file))
			if script.reload()!=OK: push_error("Invalid reference snapshot: "+file); quit(2); return
		source_hashes[file]=script.source_code.sha256_text()
	super._initialize()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp>0: samples.append(float(now-stamp)/1000.0)
	stamp=now
	return false

func review(race) -> void:
	var car=world.driving.car
	var session=world.session
	session.weather.time_of_day=.45
	session.weather._update()
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(3).timeout
	for cycle in 2:
		if not race.perform("start"): push_error("Reference start failed: "+race.start_block_reason()); quit(1); await process_frame; return
		race._rng.seed=2247
		race._rival_wait=.32
		stamp=Time.get_ticks_usec()
		recording=true
		while race.active and race.elapsed<18:
			race._throttle_override=.54 if race.phase=="staging" else 1.0
			race._nitro_override=race.phase=="racing"
			if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
			await physics_frame
		recording=false
		race.cancel_attempt()
		var point: Vector3=race.staging_point+Vector3(0,.1,-6)
		world.production.region.prepare_collision_at(point)
		car.place(point,-PI*.5)
		world.player.global_position=point
		world.player.reset_physics_interpolation()
		world.production.region.set_focus(point)
		await create_timer(2).timeout
	var ordered := samples.duplicate()
	ordered.sort()
	if ordered.is_empty(): push_error("No rendered samples"); quit(1); await process_frame; return
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for ms in samples:
		total+=ms
		if ms>33.3: over33+=1
		if ms>66.7: over66+=1
	var metrics := {"seconds":total/1000.0,"frames":samples.size(),"fps":samples.size()*1000.0/total,"p50":ordered[int(ordered.size()*.5)],"p95":ordered[int(ordered.size()*.95)],"p99":ordered[int(ordered.size()*.99)],"max":ordered.back(),"over33":over33,"over66":over66}
	var result := {"reference":reference,"metrics":metrics,"source_hashes":source_hashes,"raw_ms":samples,"environment":{"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"time":.45,"native":world.dispatch.router._native!=null}}
	var file := FileAccess.open(output.path_join("regression-metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("RETURN_REGRESSION ",ProjectSettings.globalize_path(output)," ",JSON.stringify(metrics))
