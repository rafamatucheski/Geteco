extends SceneTree
const SOURCES = preload("res://runtime/cold/OriginalHeatSources.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_cold",true)
	root.add_child(world)
	for i in 900:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.session.weather!=null: break
	if not world.production.travel("mountain"): quit(1); return
	var cold = load("res://runtime/ColdSurvival.gd").new()
	cold.configure(world.session)
	world.add_child(cold)
	world.session.cold = cold
	world.player.set_physics_process(false)
	world.camera.set_process(false)
	world.session.weather.time_of_day = .32
	world.session.weather.weather_state = 1
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	var report: Array = []
	for source in SOURCES.SOURCES:
		if "--conflicts" in OS.get_cmdline_user_args() and source.id not in ["logging_camp","summit_camp","smuggler_camp"]: continue
		var at := SOURCES.to_world(source.point)
		world.player.teleport(at+Vector3(0,.08,4))
		world.production.region.set_focus(at)
		for i in 30: await physics_frame
		cold.presentation.elapsed = 1
		cold.presentation.update_sources(1,at,true)
		await physics_frame
		var free := false
		for offset in [Vector3(0,.08,4),Vector3(4,.08,0),Vector3(-4,.08,0),Vector3(0,.08,-4),Vector3(0,.08,7)]:
			if world.session.position_clear(at+offset):
				world.player.teleport(at+offset)
				free = true
				break
		world.camera.size = 22
		world.camera.position = at+Vector3(0,18,15)
		world.camera.look_at(at)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://tests/cold/evidence/heat-"+source.id+".png"
		root.get_texture().get_image().save_png(path)
		report.append({"id":source.id,"approach_clear":free,"image":ProjectSettings.globalize_path(path),"heat":cold.sample_context().heat_id})
		print("HEAT_CAPTURE ",report[-1])
	var file := FileAccess.open("res://tests/cold/evidence/sources.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	world.queue_free()
	await create_timer(.15).timeout
	quit(0 if report.all(func(item): return item.approach_clear) else 1)
