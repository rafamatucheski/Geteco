extends "res://tests/capture/capture_drag_start_camera.gd"
## Actual Main/.NET route. Temporal JPEG recording and FPS measurement are
## separate invocations; capture overhead never counts as performance evidence.
var temporal := false
var reference := ""
var recording := false
var stamp := 0
var frame_ms: Array[float]=[]
var preparation_ms: Array[float]=[]
var frames: Array[Dictionary]=[]
var timeline: Array[Dictionary]=[]
var next_probe := 0.0
var marks := {}
var source_hashes := {}
var failures: Array[String]=[]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--temporal": temporal=true
		if arg.begins_with("--scenery-before="): reference=arg.trim_prefix("--scenery-before=")
	for path in ["world/desert/DesertHorizonRelief.gd","world/desert/DesertAmbientLife.gd","world/desert/DesertSurfaceDetail.gd","world/desert/DesertRegion.gd","activities/desert_drag/DesertDrag.gd"]:
		var script := load("res://"+path) as GDScript
		if not reference.is_empty():
			script.source_code=FileAccess.get_file_as_string(reference.path_join(path.get_file()))
			if script.reload()!=OK: push_error("Invalid scenery reference: "+path); quit(2); return
		source_hashes[path]=script.source_code.sha256_text()
	var grass := load("res://world/desert/desert_dry_grass.gdshader") as Shader
	if not reference.is_empty(): grass.code=FileAccess.get_file_as_string(reference.path_join("desert_dry_grass.gdshader"))
	source_hashes["world/desert/desert_dry_grass.gdshader"]=grass.code.sha256_text()
	create_timer(420).timeout.connect(func(): push_error("SCENERY watchdog"); quit(3))
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp>0:
		if world.session.desert.drag.phase in ["racing","braking"]: frame_ms.append(float(now-stamp)/1000.0)
		else: preparation_ms.append(float(now-stamp)/1000.0)
	stamp=now
	return false

func _capture_frame() -> void:
	if not recording or not temporal: return
	var name := "%05d.jpg"%frames.size()
	root.get_texture().get_image().save_jpg(output.path_join(name),.85)
	frames.append({"frame":Engine.get_frames_drawn(),"usec":Time.get_ticks_usec(),"file":name,"phase":world.session.desert.drag.phase,"elapsed":world.session.desert.drag.elapsed})

func shot(label: String) -> void:
	var was_recording := recording
	recording=false
	await capture(label)
	stamp=Time.get_ticks_usec()
	recording=was_recording

func review(race) -> void:
	output=FIXTURE.output_dir("drag-scenery-"+("before" if not reference.is_empty() else "after")+("-temporal" if temporal else "-perf"))
	Engine.max_fps=30 if temporal else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	if temporal: RenderingServer.frame_post_draw.connect(_capture_frame)
	await create_timer(2).timeout
	if not race.start_return_pass("digo"): push_error("Scenery race failed: "+race.start_block_reason()); quit(1); await process_frame; return
	if reference.is_empty() and temporal and race.phase=="preparing":
		var pose: Transform3D=race.player_car.global_transform
		world.session._menu("Pausa")
		await create_timer(.2).timeout
		if not race.player_car.global_transform.is_equal_approx(pose) or not is_zero_approx(race.elapsed): failures.append("pause moved car during preparation")
		world.session.close_menu()
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.physical_keycode=KEY_Q
			event.keycode=KEY_Q
			event.pressed=pressed
			Input.parse_input_event(event)
			Input.flush_buffered_events()
		for i in 3: await physics_frame
		if race.active or world.production.regions.desert._drag_preparing or race.player_car.input_locked: failures.append("cancel did not release preparation owners")
		if not race.start_return_pass("digo"): failures.append("restart after preparation cancellation failed"); quit(1); await process_frame; return
	race._rng.seed=2247
	race._rival_wait=.32
	var region=world.production.regions.desert
	await shot("start")
	recording=true
	while race.active:
		race._throttle_override=.54 if race.phase in ["staging","preparing"] else 1.0
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		var entry: Dictionary=race.racers[0]
		if race.phase=="racing" and race.elapsed>=next_probe:
			next_probe=race.elapsed+.25
			var outcrops := []
			for node in region.find_children("ErodedSandstoneOutcrop*","Node3D",true,false):
				outcrops.append(str(node.get_path()))
			var retained_jobs := 0
			for job in region.build_jobs:
				if region.drag_view_cells.has(job.key): retained_jobs+=1
			if reference.is_empty() and (retained_jobs>0 or not region.drag_view_pending.is_empty()):
				if failures.is_empty(): push_error("Visible course still building after green")
				failures.append("visible course was still building at %.3f"%race.elapsed)
			timeline.append({"time":race.elapsed,"progress":entry.return_progress,"gate":entry.return_gate,"chunks":region.chunks.keys().map(func(k): return str(k)),"jobs":region.build_jobs.size(),"retained_jobs":retained_jobs,"pending":region.drag_view_pending.size(),"outcrops":outcrops})
		for distance in [100,250,450,650,765,950,1200,1450]:
			if entry.return_progress>=distance and not marks.has(distance):
				marks[distance]=true
				await shot("route-%04d"%distance)
		await physics_frame
	recording=false
	if temporal: RenderingServer.frame_post_draw.disconnect(_capture_frame)
	await shot("result")
	var data := {"source_hashes":source_hashes,"reference":reference,"temporal":temporal,"failures":failures,"result":race.last_result,"timeline":timeline,"frames":frames,"raw_ms":frame_ms,"preparation_raw_ms":preparation_ms,"environment":{"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"time":.45,"native":world.dispatch.router._native!=null}}
	if not frame_ms.is_empty():
		var ordered := frame_ms.duplicate()
		ordered.sort()
		var total := 0.0
		var over33 := 0
		var over66 := 0
		for ms in frame_ms:
			total+=ms
			if ms>33.3: over33+=1
			if ms>66.7: over66+=1
		data.metrics={"frames":frame_ms.size(),"seconds":total/1000,"fps":frame_ms.size()*1000/total,"p50":ordered[int(ordered.size()*.5)],"p95":ordered[int(ordered.size()*.95)],"p99":ordered[int(ordered.size()*.99)],"max":ordered.back(),"over33":over33,"over66":over66,"valid_for_performance":not temporal}
	var file := FileAccess.open(output.path_join("scenery.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	print("SCENERY_DONE ",ProjectSettings.globalize_path(output)," ",JSON.stringify(data.get("metrics",{})))
	if not failures.is_empty(): quit(1); await process_frame
