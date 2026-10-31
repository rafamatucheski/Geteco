extends "res://tests/measure/measure.gd"
## Main real, controles do mapa e embarque admitido no guincho. Teleportes são preparação de diagnóstico,
## não evidência de dirigir a rota de acesso. O APPDATA precisa ser isolado pelo runner.
const OUT := "res://artifacts/navigation-review-20261022"
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks+=1
	print("NAVIGATION_REVIEW ","PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func frames(count: int) -> void:
	for frame in count: await physics_frame
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label+".png"))
func refresh() -> void:
	world.hud.minimap.refresh()
	world.hud.refresh_from_state()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240).timeout.connect(func(): push_error("NAVIGATION_REVIEW timeout"); quit(3))
	seed(22102026)
	world=load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true); root.add_child(world)
	var deadline := Time.get_ticks_msec()+100000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"real Main ready")
	if not failures.is_empty(): finish(); return
	world.session.set_process_input(false); world.driving.set_process_unhandled_input(false); world.camera.set_process_unhandled_input(false)
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	var state=world.session.state
	var intro: Dictionary=state.intro.snapshot(); intro.phase="complete"; intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	check(state.intro.restore_snapshot(intro),"validated completed intro")
	var saved := FIXTURE.prefix(1); saved.active_id="cobra_contact"; saved.step=1
	check(state.campaign.restore_snapshot(saved),"validated tow checkpoint")
	var mission=world.session.mission_world
	check(mission.begin_tow_job({"story":true,"kind":"local"}),"production tow vehicles prepared")
	await frames(20); refresh()
	var mini=world.hud.minimap
	check(mini.destination.title=="Guincho do Neco" and mini.caption.visible and "Guincho do Neco" in mini.caption.text,"named off-screen truck destination is readable")
	check(mini.objective_target.distance_to(Vector2(mission.truck.position.x,mission.truck.position.z))<.01,"minimap points to actual tow truck")
	check(mini.caption.get_global_rect().position.y>world.hud.current_objective.get_global_rect().end.y,"destination name does not overlap objective text")
	await shot("01-objective-minimap")
	world.session.show_map(); await frames(6)
	var map=world.hud.get_node("MapUI")
	check(map._markers[0].title==mini.destination.title and map._markers[0].point==mini.objective_target,"world map and minimap share title and coordinates")
	for id in ["maciota","neco","ferrugem"]:
		check(map._markers.any(func(marker): return marker.id==id and marker.kind=="workshop"),"named important place on world map: "+id)
	map._focus_objective(); await frames(20); await shot("02-truck-world-map")
	for index in map._markers.size():
		if map._markers[index].id=="neco": map.select_marker(index); map._mark_selected(); break
	world.session.close_menu(); await frames(3); refresh()
	check(mini.destination.title=="Guincho do Neco","marking Neco cannot silently replace active truck objective")
	state.campaign.restore_snapshot(FIXTURE.prefix(1)); await frames(20); refresh()
	check(mini.destination.source=="waypoint" and "Neco" in mini.caption.text,"selected place becomes named minimap destination during exploration")
	world.session.show_map(); await frames(3); map=world.hud.get_node("MapUI"); map._clear_waypoint(); world.session.close_menu()
	await frames(20); refresh()
	check(mini.destination.is_empty() and not mini.caption.visible and mini.route_points.is_empty(),"clearing destination removes name, marker and route")
	state.campaign.restore_snapshot(saved)
	# Prepara o bairro real antes de admitir o jogador e o caminhão.
	var point: Vector3=mission.truck.position+Vector3(-4,.08,0)
	world.player.set_physics_process(false); world.player.teleport(point)
	world.production.region.set_focus(point)
	deadline=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if not mission.truck.has_meta("tow_pending") and world.session.position_clear(point): break
	check(not mission.truck.has_meta("tow_pending") and world.session.position_clear(point),"truck neighborhood has real ground and collision admission")
	world.player.set_physics_process(true)
	# Begin beside a collision-admitted door, as the player does. Garage save
	# restoration additionally demands a path from a synthetic old checkpoint.
	var began := false
	for side in mission.truck.boarding_sides():
		var door: Vector3=mission.truck.driver_door_anchor(side)+mission.truck.global_basis.x*float(side)*.11+Vector3.UP*.01
		if not world.session.position_clear(door): continue
		world.player.teleport(door); await frames(3)
		var option: Dictionary=world.driving._entry_option()
		print("NAVIGATION_BOARDING ",JSON.stringify({"side":side,"point":str(door),"truck":str(mission.truck.position),"hull_clear":world.production.vehicle_position_clear(mission.truck,mission.truck.position,mission.truck.rotation.y),"locked":world.player.input_locked,"entry_matches":option.get("car")==mission.truck}))
		if option.get("car")==mission.truck:
			began=world.driving.interact()
			if began: break
	deadline=Time.get_ticks_msec()+6000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	check(began and not world.driving.is_body_transition_active(),"actual interaction and body transition board the truck")
	await frames(20); refresh()
	check(world.driving.occupied and world.driving.car==mission.truck,"Dante is seated in Neco truck")
	check(mini.destination.title=="Caminhonete da cliente" and mini.objective_target==Vector2(mission.cargo.position.x,mission.cargo.position.z),"boarding changes minimap to cargo with correct name")
	check("traseira" in world.session.hud_objective,"mission instruction changes together with destination")
	check(not mini.caption.get_global_rect().intersects(world.hud.vehicle_name.get_global_rect()),"destination name does not overlap vehicle introduction")
	check(not world.hud.current_objective.get_global_rect().intersects(world.hud.vehicle_name.get_global_rect()),"objective text does not overlap vehicle introduction")
	await shot("03-truck-neco-landmarks")
	check(mini.drawn_places.any(func(place): return place.id=="neco"),"nearby Neco landmark is rendered on minimap")
	world.driving.car.external_input=true; world.driving.car.throttle_input=0; world.driving.car.brake_input=true
	route=PackedVector3Array([world.player.position]); driving_mode=false
	started=Time.get_ticks_usec(); previous=started

func finish() -> void:
	var report := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"performance_status":"current sample only; no isolated baseline due concurrent sessions","summary":stats(samples) if not samples.is_empty() else {},"frame_intervals_ms":samples}
	var file := FileAccess.open(OUT.path_join("integration.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"))
	print("NAVIGATION_REVIEW_RESULT ",checks," checks failures=",failures)
	world.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
