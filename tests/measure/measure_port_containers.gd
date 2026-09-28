extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240,true,false,true).timeout.connect(func(): push_error("CONTAINER MEASURE TIMEOUT"); quit(3))
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var variant := "before" if baseline else "after"
	var folder := "res://evidence/port-lockpick-20260928/"+variant
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: quit(4); return
	seed(28092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.camera.set_preview_view(false)
	world.camera.set_process_unhandled_input(false)
	world.player.teleport(Vector3(271,.1,245.15625))
	world.production.region.set_focus(world.player.position)
	for i in 180: await physics_frame
	var containers := get_nodes_in_group("lootable_port_containers")
	containers.sort_custom(func(a,b): return a.cargo_id < b.cargo_id)
	if containers.size() != 18: quit(5); return
	var cargo = containers[0]
	var door: Vector3 = cargo.door_point()
	var inside: Vector3 = cargo.global_position+Vector3(4,.1,0)
	if baseline:
		world.session.port_container_loot.set_process(false)
		var baseline_root := Node3D.new()
		world.add_child(baseline_root)
		# Reconstruct the exact pre-change NativeRegion container branch using its
		# untouched original model and full-box collider; all other Main systems run.
		for container in containers:
			var old := preload("res://assets/regions/source/world/harbor/HarborPortModel3D.gd").new()
			baseline_root.add_child(old)
			old.position = container.position
			old.build("containers",container.dimensions.x,container.dimensions.y,int(container.position.x))
			var body := StaticBody3D.new()
			body.position = container.position+Vector3(0,1.4,0)
			container.get_parent().add_child(body)
			var shape := BoxShape3D.new()
			shape.size = Vector3(container.dimensions.x,2.8,container.dimensions.y)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			container.queue_free()
		var batches := {}
		var dressing := preload("res://world/city_look/CityChunkDressing.gd")
		dressing._other_roofs(baseline_root,batches)
		dressing._flush(baseline_root,batches)
	for site in ["exterior","interior"]:
		if baseline and site == "interior": continue
		if site == "interior": cargo.apply_state({"opened":true,"looted":false})
		world.player.teleport(door if site == "exterior" else inside)
		var warm: Array[float] = []
		var intervals: Array[float] = []
		var begin := Time.get_ticks_usec()
		var previous_frame := begin
		while Time.get_ticks_usec()-begin < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-begin < 8000000: warm.append((now-previous_frame)/1000.0)
			else: intervals.append((now-previous_frame)/1000.0)
			previous_frame = now
		var result := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(intervals),"warmup":stats(warm),"frames_ms":intervals,"warmup_ms":warm,"baseline_reconstructed":baseline}
		var output := FileAccess.open(folder+"/"+site+".json",FileAccess.WRITE)
		if output == null: quit(4); return
		output.store_string(JSON.stringify(result))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site+".png")
		print("CONTAINER_MEASURE ",variant," ",site," ",JSON.stringify(result.summary))
	quit()
