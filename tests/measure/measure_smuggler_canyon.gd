extends "res://tests/measure/measure_desert.gd"
## As medições no Main seguem a aproximação, a ponte e o portão atuais do cânion.
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
var failures: Array[String] = []
var capture_only := false

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Rendered isolated Main required"); quit(2); return
	seed(8102026)
	capture_only="--capture-only" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("smuggler-canyon-measure")
	var at: Vector3 = L.APPROACH+Vector3.UP*.1
	var snapshot := FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint=source_fingerprint()
	for folder in ["res://world/desert/canyon","res://runtime/desert/canyon"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd") or file.ends_with(".gdshader"): fingerprint[folder.path_join(file)]=FileAccess.get_sha256(folder.path_join(file))
	fingerprint["res://scripts/CameraRig.gd"]=FileAccess.get_sha256("res://scripts/CameraRig.gd")
	fingerprint[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path:
		push_error("Main startup/isolation failed"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("Native backend absent"); quit(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var points := [
		{"id":"approach","point":L.APPROACH+Vector3.UP*.2},
		{"id":"bridge","point":L.BRIDGE_START.lerp(L.BRIDGE_END,.5)+Vector3.UP*.2},
		{"id":"defended-gate","point":Vector3(L.CENTER.x,.2,L.GATE_Z-17.0)},
	]
	if "--bridge-only" in OS.get_cmdline_user_args(): points=points.filter(func(row): return row.id=="bridge")
	for setup: Dictionary in points:
		var point: Vector3=setup.point
		var id: String=setup.id
		world.player.teleport(point)
		world.production.region.set_focus(point)
		world.production.region.prepare_collision_at(point)
		world.camera.heading=0
		world.camera.initialized=false
		world.camera.target_size=40.0
		samples.clear(); cpu.clear(); physics.clear(); previous=Time.get_ticks_usec(); sampling=true
		await create_timer(5 if capture_only else 10).timeout
		sampling=false
		var warm := {"summary":stats(samples),"intervals_ms":samples.duplicate()}
		if world.player.global_position.y<-.5: failures.append("No support: "+id)
		if capture_only:
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(id+".png"))
			if "--shadow-diagnostic" in OS.get_cmdline_user_args():
				var shadows: bool=world.production.sun.shadow_enabled
				world.production.sun.shadow_enabled=false
				for frame in 6: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(id+"-diagnostic-no-shadows.png"))
				world.production.sun.shadow_enabled=shadows
			reports.append({"id":id,"summary":{},"capture_only":true})
			if "--capture-temporal" in OS.get_cmdline_user_args():
				await capture_motion(id)
		else: await measure(id)
		reports[-1]["warmup"]=warm
		reports[-1]["player_position"]=str(world.player.global_position)
		reports[-1]["health"]=world.gameplay.health
		reports[-1]["guards"]=world.session.desert.canyon.snapshot()
		var projected: Array[Dictionary]=[]
		for p: Vector2 in preload("res://world/desert/canyon/ScavengerRemains.gd").BODY_POINTS:
			var at_body := Vector3(p.x,preload("res://world/desert/canyon/DesertSmugglerTerrain.gd").surface_height(p)+.2,p.y)
			var screen: Vector2=world.camera.unproject_position(at_body)
			var ray_from: Vector3=world.camera.project_ray_origin(screen)
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from,at_body,1))
			projected.append({"body":str(at_body),"screen":str(screen),"visible_in_frame":Rect2(Vector2.ZERO,Vector2(root.size)).has_point(screen),"first_ground":str(hit.get("position",Vector3.INF)),"occlusion_distance":hit.position.distance_to(at_body) if not hit.is_empty() else 0})
		reports[-1]["body_projection"]=projected
		reports[-1]["camera_transform"]=str(world.camera.global_transform)
	var stable := fingerprint==source_fingerprint(fingerprint)
	if not stable: failures.append("Concurrent source changes during sampling")
	var report := {"valid":failures.is_empty(),"failures":failures,"baseline":not preload("res://world/desert/canyon/DesertSmugglerLayout.gd").enabled(),"scenarios":reports,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"source_stable":stable,"fingerprint":fingerprint,"notes":"Real Main native .NET with live population, camera40/day .45 at current approach/bridge/gate anchors. Fixture placements do not prove access. 10s warmup/30s per point. A comparative local baseline is not implied by this current-state report. External process overlap separately recorded. Target60fps, >5% p95/p99 increase requires bounded confirmation against equivalent evidence."}
	report["capture_only"]=capture_only
	if capture_only: report["notes"]="Main native .NET screenshots only; no performance sampling. Five seconds to settle each pose. Fixed40m camera."
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SMUGGLER_MEASURE ",output," ",JSON.stringify(reports.map(func(row): return {"id":row.id,"summary":row.summary})))
	quit(0 if failures.is_empty() else 1)

func capture_motion(id: String) -> void:
	# O MovieWriter grava todo quadro renderizado a --fixed-fps 30. O tempo de parede
	# e o FPS do HUD dele são custo de gravação, nunca evidência de desempenho.
	var first_frame := Engine.get_process_frames()
	var elapsed := 0.0
	var timeline: Array[Dictionary] = []
	while elapsed < 30.0:
		world.player.automatic_direction=Vector3(0,0,1 if elapsed>=5 and elapsed<15 else (-1 if elapsed>=15 and elapsed<25 else 0))
		world.camera.heading=sin((elapsed-5.0)/20.0*TAU)*.6 if elapsed>=5 and elapsed<25 else 0.0
		await process_frame
		elapsed+=root.get_process_delta_time()
		timeline.append({"frame":Engine.get_process_frames(),"t":elapsed,"position":str(world.player.global_position),"heading":world.camera.heading})
	world.player.automatic_direction=Vector3.ZERO
	FileAccess.open(output.path_join(id+"-temporal.json"),FileAccess.WRITE).store_string(JSON.stringify({"first_frame":first_frame,"last_frame":Engine.get_process_frames(),"seconds":elapsed,"sun_shadows":world.production.sun.shadow_enabled,"timeline":timeline},"\t"))
