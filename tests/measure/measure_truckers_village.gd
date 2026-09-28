extends "res://tests/measure/measure.gd"
## Real gameplay, unchanged camera/population/weather, isolated save, 30 s/site.
var _baseline_sources: Array[Resource] = []
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(28092026)
	if "--redesign-baseline" in OS.get_cmdline_user_args():
		# Exact saved pre-redesign source, reconstructed only in this process.
		# Never rewrites shared project files to obtain the control measurement.
		var folder := "res://evidence/truckers-village-20260928/redesign-baseline-source/"
		for path in ["res://gameplay/urban_v1/FreightOutskirts.gd","res://gameplay/urban_v1/TruckersVillageVisuals.gd","res://world/urban_detail/HarborRoadGeometry3D.gd"]:
			var source: GDScript = load(path)
			source.source_code = FileAccess.get_file_as_string(folder+path.get_file()+".txt")
			if source.reload(true) != OK: quit(4); return
			_baseline_sources.append(source)
		Engine.set_meta("geteco_world_edit_document",JSON.parse_string(FileAccess.get_file_as_string(folder+"world_edits.json")))
		# The original village had its stationary V1 actor and no resident manager.
		# Adapt only this benchmark process to that original integration contract.
		var operations: GDScript = load("res://gameplay/urban_v1/UrbanOperations.gd")
		var code := operations.source_code
		var start := code.find("\tvillage.tonico.gameplay = session.world.gameplay")
		var end := code.find("\tvillage_quest =",start)
		if start>=0 and end>start: code=code.substr(0,start)+code.substr(end)
		code=code.replace("\tvillage_quest.bind_residents(village_residents)\n","")
		start=code.find("\tvillage.homes.configure(session)")
		end=code.find("\nfunc refresh_context()",start)
		if start>=0 and end>start: code=code.substr(0,start)+code.substr(end)
		code=code.replace("\tif is_instance_valid(village) and is_instance_valid(village.homes): village.homes.set_region_active(session.state.region_id == \"harbor\" and session.state.place_id.is_empty())\n","")
		operations.source_code=code
		if operations.reload(true)!=OK: quit(4); return
		_baseline_sources.append(operations)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	var folder := "res://evidence/truckers-village-20260928/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"yard","point":Vector3(-330,.1,108),"time":.4,"weather":0}, {"id":"night_rain","point":Vector3(-330,.1,108),"time":.9,"weather":1}, {"id":"approach","point":Vector3(-290,.1,25),"time":.4,"weather":0}]
	if "--capture-only" in OS.get_cmdline_user_args(): sites = []
	for site in sites:
		world.session.weather.time_of_day = site.time
		world.session.weather.weather_state = site.weather
		world.session.weather._update()
		world.player.teleport(site.point)
		world.production.region.set_focus(site.point)
		world.camera.heading = 0
		world.camera.target_size = 62
		world.camera.initialized = false
		var warm: Array[float] = []
		var frames: Array[float] = []
		var begin := Time.get_ticks_usec()
		var last := begin
		while Time.get_ticks_usec()-begin < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-begin < 8000000: warm.append((now-last)/1000.0)
			else: frames.append((now-last)/1000.0)
			last = now
		var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"paused":paused,"world_processing":world.can_process(),"player_position":str(world.player.position),"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm}
		FileAccess.open(folder+"/"+site.id+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site.id+".png")
		print("VILLAGE_MEASURE ",site.id," ",JSON.stringify(report.summary))
	if "--measure-only" in OS.get_cmdline_user_args(): quit(); return
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.player.teleport(Vector3(-330,.1,108))
	world.production.region.set_focus(world.player.position)
	for i in 300: await physics_frame
	var review := Camera3D.new()
	review.projection = Camera3D.PROJECTION_ORTHOGONAL
	review.size = 175
	world.add_child(review)
	review.global_position = Vector3(-330,130,235)
	review.look_at(Vector3(-330,0,100))
	review.make_current()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/overview.png")
	world.player.teleport(Vector3(-290,.1,25))
	world.production.region.set_focus(world.player.position)
	review.size = 85
	review.global_position = Vector3(-272,75,86)
	review.look_at(Vector3(-290,0,24))
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/entrada.png")
	world.player.teleport(Vector3(-394,.1,111))
	world.production.region.set_focus(world.player.position)
	review.size = 49
	review.global_position = Vector3(-376,35,148)
	review.look_at(Vector3(-395,0,112))
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/quintais.png")
	if not is_instance_valid(world.session.urban_operations.get("village")): quit(); return
	review.size = 51
	review.global_position = Vector3(-341,32,128)
	review.look_at(Vector3(-355,0,88))
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/posto.png")
	world.player.teleport(Vector3(-353,.1,102.2))
	world.camera.target_size = 24
	world.camera.initialized = false
	world.camera.make_current()
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/tonico.png")
	var village = world.session.urban_operations.village
	var npc_home: Vector3 = village.tonico.global_position
	var pump: Vector3 = village.ORIGIN+village.STATION_TRANSFORM*Vector3(-34,0,-12)
	review.size = 12
	review.global_position = pump+Vector3(0,12,13)
	review.look_at(pump)
	review.make_current()
	for entry in [{"id":"front","z":pump.z+2,"x":pump.x},{"id":"behind","z":pump.z-2,"x":pump.x},{"id":"side","z":pump.z,"x":pump.x+2}]:
		world.production.region.set_focus(Vector3(entry.x,0,entry.z))
		world.production.region.prepare_collision_at(Vector3(entry.x,0,entry.z))
		world.production.region.prepare_collision_at(Vector3(entry.x+1.6,0,entry.z))
		await _review_pair(Vector3(entry.x,.1,entry.z),Vector3(entry.x+1.6,.1,entry.z),village.tonico)
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/depth-"+entry.id+".png")
		print("VILLAGE_DEPTH ",entry.id," player=",world.player.global_position," npc=",village.tonico.global_position," visible=",village.tonico.is_visible_in_tree())
		await _review_pair(Vector3(entry.x+1.6,.1,entry.z),Vector3(entry.x,.1,entry.z),village.tonico)
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/npc-depth-"+entry.id+".png")
	village.tonico.global_position = npc_home
	world.player.teleport(Vector3(-269,.1,105))
	world.production.region.set_focus(world.player.position)
	world.camera.target_size = 22
	world.camera.initialized = false
	world.camera.make_current()
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/borracharia.png")
	if "--interactions" in OS.get_cmdline_user_args():
		world.player.teleport(Vector3(-364,.1,86.2))
		world.production.region.set_focus(world.player.position)
		world.production.region.prepare_collision_at(world.player.position)
		world.camera.target_size=17
		world.camera.initialized=false
		world.session.state.economy.grant_reward("village_capture",200)
		world.gameplay.health=60
		for i in 90: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/balcao.png")
		var quest = world.session.urban_operations.village_quest
		quest.perform("truckers_village_counter")
		for frame in 45: await process_frame
		print("VILLAGE_COUNTER_RENDERED_BOUNDS ",world.session.panel.get_global_rect())
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/comprar-ou-assaltar.png")
		world.session.close_menu()
		quest.perform("truckers_village_buy_drink")
		world.session.state.economy.grant_weapon("pistol")
		world.session.state.equip_weapon("pistol")
		quest.perform("truckers_village_rob_register")
		world.player.teleport(Vector3(-353,.1,107))
		world.camera.target_size=25
		world.camera.initialized=false
		for i in 90: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/reacao-ao-assalto.png")
	if "--homes" in OS.get_cmdline_user_args():
		for i in village.homes.homes.size():
			var home: Node3D=village.homes.homes[i].root
			world.gameplay.health=100
			world.player.teleport(home.to_global(Vector3(0,.1,1.7)))
			world.production.region.set_focus(world.player.position)
			world.production.region.prepare_collision_at(world.player.position)
			for frame in 40: await physics_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/casa-%d.png"%(i+1))
			print("VILLAGE_HOME ",i," player=",world.player.global_position," current=",village.homes.current_home)
	if "--home-depth" in OS.get_cmdline_user_args():
		var poses: Array=preload("res://tests/probe_truckers_village_home_depth.gd").POSES
		village.tonico.set_physics_process(false)
		for i in village.homes.homes.size():
			var home: Node3D=village.homes.homes[i].root
			world.gameplay.health=100
			world.player.teleport(home.to_global(Vector3(0,.1,1)))
			world.production.region.set_focus(world.player.position)
			for frame in 15: await physics_frame
			review.size=7
			review.cull_mask=village.homes.interior_camera.cull_mask
			review.global_position=home.to_global(poses[i].furniture+Vector3(0,8,7))
			review.look_at(home.to_global(poses[i].furniture))
			review.make_current()
			for side in ["front","behind","side"]:
				for actor in ["player","npc"]:
					var point: Vector3=home.to_global(poses[i][side]+Vector3.UP*.1)
					world.gameplay.health=100
					await _review_pair(point if actor=="player" else home.to_global(Vector3(0,.1,1)),point if actor=="npc" else home.to_global(Vector3(0,.1,-2)),village.tonico)
					for frame in 8: await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(folder+"/casa-%d-%s-%s.png"%[i+1,actor,side])
					print("HOME_DEPTH_RENDER ",i," ",actor," ",side," player=",world.player.global_position," npc=",village.tonico.global_position)
	quit()

func _review_pair(player_at: Vector3,npc_at: Vector3,npc: CharacterBody3D) -> void:
	# Exchange two physical actors only after the physics server has vacated
	# their former poses. Direct swaps interpret one as a moving platform.
	var staging := Vector3(-350,.1,108)
	world.production.region.prepare_collision_at(staging)
	npc.global_position=staging
	npc.velocity=Vector3.ZERO
	npc.model.teleported()
	for i in 2: await physics_frame
	world.player.teleport(player_at)
	for i in 2: await physics_frame
	npc.global_position=npc_at
	npc.velocity=Vector3.ZERO
	npc.model.teleported()
	for i in 2: await physics_frame
