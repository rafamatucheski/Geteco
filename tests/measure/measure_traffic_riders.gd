extends "res://tests/measure/measure.gd"
## Same rendered Main scene and six occupied motorcycles before/after.
var variant := "before"
var bikes: Array = []
func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
	seed(16102026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(66,.2,129))
	world.production.region.set_focus(world.player.position)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.camera.set_process(false)
	world.camera.global_position = Vector3(73,7,138)
	world.camera.look_at(Vector3(66,1,129))
	world.camera.size = 12
	for i in 6:
		var bike = preload("res://scripts/Vehicle.gd").new()
		bike.archetype = ["bike_urban","bike_sport","bike_cruiser"][i % 3]
		bike.vehicle_id = "rider_review_%d" % i
		bike.traffic = true
		world.add_child(bike)
		bike.place(Vector3(63 + (i % 3)*3,.15,127 + (i / 3)*4), PI)
		bike.set_physics_process(false)
		bikes.append(bike)
	started = Time.get_ticks_usec()
	previous = started

func _process(_delta: float) -> bool:
	if started == 0: return false
	var now := Time.get_ticks_usec()
	var ms := float(now-previous)/1000.0
	previous = now
	var elapsed := float(now-started)/1000000.0
	if elapsed < 8: cold.append(ms)
	else: samples.append(ms)
	if elapsed >= 38:
		started = 0
		finish.call_deferred()
	return false

func finish() -> void:
	var folder := "res://evidence/traffic-riders-20261016/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"summary":stats(samples),"warmup":stats(cold),"intervals_ms":samples,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.people.size(),"vehicles":world.production.vehicles.size()}
	FileAccess.open(folder+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/riders.png")
	print("TRAFFIC_RIDERS ",variant," ",JSON.stringify(report.summary))
	quit()
