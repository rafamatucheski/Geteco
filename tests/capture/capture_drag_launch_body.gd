extends "res://tests/test_desert_drag_runtime.gd"
var measuring := false
var samples: Array[float] = []
var tick := 0
var peaks := [0.0,0.0]
var captured := false
var body_output := ""

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if measuring and tick>0: samples.append(float(now-tick)/1000.0)
	tick = now
	if measuring and is_instance_valid(world) and world.session.desert.drag.active:
		var race = world.session.desert.drag
		for i in race.racers.size():
			var entry: Dictionary = race.racers[i]
			if entry.has("launch_body"): peaks[i] = maxf(peaks[i],rad_to_deg(entry.launch_body.pitch))
		if race.phase=="racing" and race.elapsed>.7 and not captured:
			captured = true
			_save_launch.call_deferred()
	return false

func _save_launch() -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(body_output.path_join("launch.png"))

func drive_race(race,car,result_action: String = "stay") -> void:
	body_output = "res://evidence/drag-body-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(body_output))
	var rest: Transform3D = car.visual.transform
	measuring = true
	var began := Time.get_ticks_msec()
	await super.drive_race(race,car,result_action)
	while Time.get_ticks_msec()-began<30000: await process_frame
	measuring = false
	check(car.visual.transform.is_equal_approx(rest),"launch suspension restores original body pose after race")
	if preload("res://activities/desert_drag/DragLaunchBody.gd").enabled:
		check(peaks.all(func(value): return value>.4 and value<=2.401),"both cars lift subtly under acceleration")
	var sorted := samples.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in samples: sum += value
	var report := {"fps":samples.size()*1000.0/sum,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":samples.filter(func(x): return x>33.3).size(),"over66":samples.filter(func(x): return x>66.7).size(),"raw_ms":samples,"peaks_degrees":peaks,"seconds":sum/1000.0,"size":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps}
	FileAccess.open(body_output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("DRAG_BODY ",body_output," fps=",report.fps," p95=",report.p95," p99=",report.p99," peaks=",peaks)
