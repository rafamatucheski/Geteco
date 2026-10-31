extends "res://tests/measure/measure_desert.gd"
## Serial rendered Main/.NET baseline and candidate; isolated completed campaign.
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(11102026)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-entrance")
	var at:=Vector3(345,.1,-475)
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	snapshot.world.desert_story=preload("res://runtime/desert/DesertStoryState.gd").defaults()
	snapshot.world.desert_story.arrived=true
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint=source_fingerprint()
	for source in ["res://runtime/desert/entrance/DesertToll.gd","res://world/desert/entrance/DesertTollPlaza.gd","res://world/desert/entrance/DesertBoundaryCamera.gd","res://world/regions/ScenarioBoundary3D.gd"]:
		fingerprint[source]=FileAccess.get_sha256(source)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 7200:
		await physics_frame
		if is_instance_valid(world.driving): world.driving.set_process_unhandled_input(false)
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: push_error("Missing .NET routing"); quit(1); return
	if world.session.modal: world.session.close_menu()
	for i in 600:
		if not world.player.controlled_automatically: break
		await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	world.production.region.set_focus(at)
	world.production.region.prepare_collision_at(at)
	world.player.teleport(at)
	await create_timer(10).timeout
	if world.driving.occupied:
		push_error("Unexpected driver during stationary fixture; measurement invalid")
		quit(1)
		return
	if "--validation-only" in OS.get_cmdline_user_args():
		await drive_toll()
		return
	if "--entrance-baseline" in OS.get_cmdline_user_args():
		install_baseline()
		await create_timer(3).timeout
	await measure("entrance-day")
	print("ENTRANCE_POSE ",world.player.global_position)
	for pose in [{"id":"bridge","at":Vector3(342.5,2.5,-360)},{"id":"east-range","at":Vector3(385,.1,-590)}]:
		world.production.region.set_focus(pose.at)
		world.production.region.prepare_collision_at(pose.at)
		world.player.teleport(pose.at)
		await create_timer(3).timeout
		if pose.id=="east-range" and "--border-measure" in OS.get_cmdline_user_args():
			await create_timer(10).timeout
			await measure("border-day")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(pose.id+".png"))
	# Só vista larga de diagnóstico; a cronometragem acima usa a câmera de jogo comum.
	world.camera.set_process(false)
	world.camera.position=Vector3(390,105,-298)
	world.camera.look_at(Vector3(342.5,0,-453))
	world.camera.size=116
	world.camera.far=600
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("overview.png"))
	var result:={"scenarios":reports,"source_stable":fingerprint==source_fingerprint(fingerprint),"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"args":OS.get_cmdline_user_args()}
	result.baseline="--entrance-baseline" in OS.get_cmdline_user_args()
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ENTRANCE_MEASURE ",output," ",JSON.stringify(reports[0].summary))
	if "--drive-toll" in OS.get_cmdline_user_args():
		await drive_toll()
	else: quit()

func install_baseline() -> void:
	# Os recursos originais são copiados para a evidência; os arquivos de produção ficam intocados.
	# O SHA256 da cópia da serra bate com o arquivo de antes da edição registrado nesta revisão.
	world.session.desert.entrance_toll.set_process(false)
	world.camera._desert_terrain_camera._boundary_camera.enabled=false
	for plaza in get_nodes_in_group("desert_toll_plaza"): plaza.free()
	var gateway=get_first_node_in_group("north_gateway")
	if is_instance_valid(gateway) and is_instance_valid(gateway.scenery):
		gateway.scenery.free()
		gateway.scenery=load("res://evidence/desert-entrance-baseline-source/NorthGatewayScenery.gd").new()
		gateway.add_child(gateway.scenery)
		gateway.scenery.build(true)
	var region=world.production.region
	var old_boundary=load("res://evidence/desert-entrance-baseline-source/ScenarioBoundary3D.gd")
	for key in region.chunks:
		var chunk: Node3D=region.chunks[key]
		for child in chunk.get_children():
			if not child is MeshInstance3D: continue
			if child.find_children("*","StaticBody3D",true,false).any(func(body): return body.is_in_group("scenario_boundary")): child.free()
		old_boundary.build_desert(chunk,Rect2(Vector2(key)*96,Vector2(96,96)).intersection(preload("res://world/desert/DesertLayout.gd").BOUNDS),region._ground_height)

func drive_toll() -> void:
	world.camera.set_process(true)
	world.camera.far=180
	if world.session.dialogue_open: world.session.interrupt_dialogue()
	if world.session.modal: world.session.close_menu()
	world.session.state.economy.grant_reward("toll_test",100)
	var start:=Vector3(345,2.48,-353)
	world.production.region.set_focus(start)
	world.production.region.prepare_collision_at(start)
	# Reaproveita o carro inicial da fixture. Criar um segundo carro deixaria o primeiro
	# parado na janela de pagamento, bloqueando artificialmente a própria rota do teste.
	var car=world.driving.car
	car.global_position=start
	car.rotation.y=0
	car.speed=0
	car.velocity=Vector3.ZERO
	car.reset_physics_interpolation()
	world.player.teleport(car.driver_door_anchor(1)+Vector3(.4,.08,0))
	await create_timer(1).timeout
	if not world.driving.interact(): push_error("TOLL DRIVE boarding rejected"); quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	if not world.driving.occupied: push_error("TOLL DRIVE boarding timed out"); quit(1); return
	var start_time:=Time.get_ticks_msec()
	var capture=load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(capture)
	capture.segment="bridge_toll_drive"
	capture.begin(world,null,output.path_join("temporal"),2700)
	capture._report.coverage="Physical bridge approach, toll payment and passage; production traffic stays active."
	capture._report.not_covered=["night","rain","full desert","audible sound quality"]
	while Time.get_ticks_msec()-start_time<45000 and car.global_position.z> -471:
		var target_speed:=2.0 if car.global_position.z< -455 else 6.0
		if car.speed<target_speed: Input.action_press("accelerate")
		else: Input.action_release("accelerate")
		if car.speed>target_speed+.5: Input.action_press("handbrake")
		else: Input.action_release("handbrake")
		await physics_frame
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	await create_timer(2).timeout
	var action: Dictionary=world.session.nearest()
	print("TOLL_APPROACH ",car.global_position," speed=",car.speed," action=",action)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("car-at-toll.png"))
	if action.get("target","")!="entrance_toll":
		for vehicle in get_nodes_in_group("drivable"):
			if vehicle.global_position.distance_to(car.global_position)<35: print("TOLL_NEARBY ",vehicle.name," ",vehicle.global_position," traffic=",vehicle.traffic," external=",vehicle.external_input," speed=",vehicle.speed)
		capture.stop()
		push_error("TOLL DRIVE payment unavailable after physical bridge approach"); quit(1); return
	var before: int=world.session.state.economy.balance
	if not await world.session.interact(): push_error("TOLL DRIVE payment rejected"); quit(1); return
	await create_timer(2).timeout
	Input.action_release("handbrake")
	start_time=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start_time<16000 and car.global_position.z> -504:
		if car.speed<6: Input.action_press("accelerate")
		else: Input.action_release("accelerate")
		await physics_frame
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	await create_timer(1).timeout
	var passed: bool=car.global_position.z< -504 and car.global_position.y>-.2 and world.session.state.economy.balance==before-10
	print("TOLL_PHYSICAL_CROSSING ",passed," at=",car.global_position," debit=",before-world.session.state.economy.balance)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("car-after-toll.png"))
	if passed:
		if world.driving.interact():
			for i in 600:
				await physics_frame
				if not world.driving.is_body_transition_active(): break
		var edge:=Vector3(385,.1,-590)
		world.production.region.set_focus(edge)
		world.production.region.prepare_collision_at(edge)
		world.player.teleport(edge)
		capture.segment="border_camera_orbit"
		capture._report.coverage+=" Camera orbit at the east rock edge after a documented fixture relocation."
		for i in 300:
			world.camera.heading+=.0035
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("border-camera-after.png"))
	capture.stop()
	FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE).store_string(JSON.stringify({"physical_crossing":passed,"debit":before-world.session.state.economy.balance,"source_stable":fingerprint==source_fingerprint(fingerprint),"output":output},"\t"))
	quit(0 if passed else 1)
