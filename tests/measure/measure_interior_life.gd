extends SceneTree
## Rendered Main with normal population; isolated saves, finite 30 s samples.
var world
var label := "current"
var directory := "res://artifacts/interior-life-20261022"
var results := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(directory)
	create_timer(480).timeout.connect(func(): quit(3))
	seed(9282026)
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var startup_deadline := Time.get_ticks_msec()+120000
	while world.session == null or not world.session.ready_for_play:
		if Time.get_ticks_msec() >= startup_deadline:
			push_error("Interior measurement: session did not become ready")
			quit(3)
			return
		await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .38
	world.session.weather.weather_timer = 99999
	world.session.weather.weather_state = 0
	world.session.weather._update()
	for id in ["maciota","westgate_garden","quayside_house","canal_north"]:
		if id != "maciota":
			var definition: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition(id)
			world.production.region.set_focus(definition.entry_position)
			world.player.teleport(definition.entry_position+Vector3(0,.08,2))
			await create_timer(5).timeout
			world.session.activities.residence.data.active_home = id
		if not await world.session.enter_place(id,false):
			push_error("Interior measurement: could not enter "+id)
			quit(4)
			return
		await create_timer(4).timeout
		await _sample(id+"-interior")
		await world.session.leave_place()
	results["environment"] = {"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":"1280x720","max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"population":world.production.requested_population,"condition":"Other Godot processes present; comparison diagnostic only"}
	var output := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify(results,"\t"))
	world.queue_free()
	await process_frame
	quit()

func _sample(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/"+label+"-"+id+".png")
	var rows: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		rows.append((now-previous)/1000.0)
		previous = now
	var sorted := rows.duplicate()
	sorted.sort()
	var slow := 0
	var very_slow := 0
	for value in rows:
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	results[id] = {"samples_ms":rows,"frames":rows.size(),"seconds":(previous-start)/1000000.0,"fps":rows.size()*1000000.0/(previous-start),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over_33":slow,"over_66":very_slow}
	print("RESIDENCE_SAMPLE ",label," ",id," fps=",results[id].fps," p95=",results[id].p95)

