extends SceneTree
var world
var results := {}
var label := "before"
var focus_home := ""
const DIRECTORY := "res://evidence/residence-immersive"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--home="): focus_home = arg.trim_prefix("--home=")
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	create_timer(420).timeout.connect(func(): quit(3))
	seed(10022026)
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	while world.session == null or not world.session.ready_for_play: await process_frame
	results.environment={"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"population":world.production.requested_population,"scenario":"Main real; normal directors; direct entry and station placement (diagnostic, not walked route)"}
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.state.economy.grant_weapon("ak47")
	world.session.weather.time_of_day = .38
	world.session.weather.weather_timer = 99999
	world.session.weather.weather_state = 0
	world.session.weather._update()
	for id in ["westgate_garden","quayside_house","canal_north"]:
		if not focus_home.is_empty() and id != focus_home: continue
		world.session.activities.residence.data.active_home = id
		await world.session.enter_place(id,false)
		await create_timer(4).timeout
		await sample(id+"-room")
		for station in ["wardrobe","arsenal","food","time"]:
			world.player.teleport(world.session.room.interaction_points[station]+Vector3.UP*.08)
			await create_timer(.2).timeout
			world.session.residence_services.perform("residence_services")
			if station == "arsenal": world.session.residence_services._customize_weapon("ak47","longa","finish")
			await create_timer(4).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(DIRECTORY+"/"+label+"-"+id+"-"+station+".png")
			if id == "westgate_garden" and station in ["wardrobe","arsenal"]: await sample(id+"-"+station)
			world.session.close_menu()
		await world.session.leave_place()
	FileAccess.open(DIRECTORY+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	world.queue_free()
	await process_frame
	quit()
func sample(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIRECTORY+"/"+label+"-"+id+".png")
	var rows: Array[float]=[]
	var start:=Time.get_ticks_usec()
	var previous:=start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		rows.append((now-previous)/1000.0)
		previous=now
	var sorted:=rows.duplicate()
	sorted.sort()
	var slow:=0
	var very_slow:=0
	for value in rows:
		if value>33.3: slow+=1
		if value>66.7: very_slow+=1
	results[id]={"samples_ms":rows,"frames":rows.size(),"seconds":(previous-start)/1000000.0,"fps":rows.size()*1000000.0/(previous-start),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over_33":slow,"over_66":very_slow}
	results[id].quality={"size":str(root.size),"msaa":root.msaa_3d,"scale":root.scaling_3d_scale}
	# Preserva toda amostra concluída se outro diagnóstico interromper a rodada.
	FileAccess.open(DIRECTORY+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("HOME_SAMPLE ",label," ",id," fps=",results[id].fps," p95=",results[id].p95)
