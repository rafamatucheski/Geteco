extends "res://tests/desert_curve_drive.gd"
## Esterço real do jogador descendo a espiral de transporte inteira e subindo de volta. Nenhuma
## correção de transformação do corpo depois da única fixture inicial.
const MINE := preload("res://world/mining/MiningLayout.gd")
const SURFACE := preload("res://world/mining/MiningExterior.gd")

func _initialize() -> void:
	create_timer(480).timeout.connect(func(): push_error("MINING_HAUL timeout"); _finish(3))
	_run.call_deferred()

func _run() -> void:
	if not _check("--no-save" in OS.get_cmdline_user_args() and "--no-traffic" in OS.get_cmdline_user_args(),"isolated haul drive required"): _finish(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-haul-drive")
	var guide:=Curve3D.new(); guide.bake_interval=.2
	for point in MINE.haul_points(): guide.add_point(point)
	var start:=guide.sample_baked(0)+Vector3.UP*.12
	var snapshot:=FIXTURE.full_snapshot(start,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[start.x,start.y,start.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(world.session!=null and world.session.ready_for_play and world.production.store.path==path,"real Main native checkpoint ready"): _finish(1); return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(start)
	_check(world.dispatch.router._native!=null,"compiled C# routes loaded")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45; world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600; world.session.weather._update()
	prior_gamepad=bool(root.get_node("GameInput").using_gamepad)
	root.get_node("GameInput").using_gamepad=true
	world.production.region.prepare_collision_at(start)
	world.player.teleport(start+Vector3.RIGHT*5)
	await create_timer(1).timeout
	var direction:=start.direction_to(guide.sample_baked(1)+Vector3.UP*.12)
	var car: CharacterBody3D=world.production.spawn_vehicle("mining_haul_truck",start,atan2(-direction.x,-direction.z))
	if not _check(is_instance_valid(car),"giant truck admitted at gate"): _finish(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.45+Vector3.UP*.08)
	if not _check(world.driving.interact(),"ordinary boarding"): _finish(1); return
	while world.driving.is_body_transition_active(): await physics_frame
	if not _check(world.driving.occupied and world.driving.car==car,"player controls haul truck"): _finish(1); return
	if not await _haul(car,guide,"descent"): _finish(1); return
	# Usa a marcha à ré existente para a subida. Isto exercita a mesma rota
	# dirigida e a colisão carregada sem rotação da fixture no fundo.
	var return_guide:=Curve3D.new(); return_guide.bake_interval=.2
	var points:=MINE.haul_points(); points.reverse()
	for point in points: return_guide.add_point(point)
	await _haul(car,return_guide,"ascent",true)
	_check(world.gameplay.health>0 and world.session.state.place_id.is_empty(),"deep pit preserves living player and desert session")
	_check(world.driving.leave(),"ordinary exit after haul route")
	while world.driving.is_body_transition_active(): await physics_frame
	_check(not world.driving.occupied and not world.player.input_locked,"exit restores player control")
	_finish(0 if failures.is_empty() else 1)

func _haul(car: CharacterBody3D,guide: Curve3D,id: String,reverse:=false) -> bool:
	var length:=guide.get_baked_length()
	var began:=Time.get_ticks_msec()
	var initial_health: float=car.health
	var trace: Array[Dictionary]=[]
	var contacts: Array[String]=[]
	var max_error:=0.0
	var min_y:=INF
	var unsupported:=0
	var reached:=false
	var next_photo:=0.0
	var tick:=0
	var maximum_ms:=int((length/(4.0 if reverse else 7.0)+30.0)*1000)
	while Time.get_ticks_msec()-began<maximum_ms:
		await physics_frame
		tick+=1
		var at: Vector3=car.global_position
		var offset:=guide.get_closest_offset(at)
		var on_road:=guide.sample_baked(offset)
		var error:=Vector2(at.x,at.z).distance_to(Vector2(on_road.x,on_road.z))
		max_error=maxf(max_error,error); min_y=minf(min_y,at.y)
		var lookahead:=maxf(5,absf(float(car.speed))*.85)
		var target:=guide.sample_baked(minf(length,offset+lookahead))
		var forward:=Vector2(-car.global_basis.z.x,-car.global_basis.z.z)*(-1.0 if reverse else 1.0)
		var toward:=Vector2(target.x-at.x,target.z-at.z).normalized()
		var steer:=clampf(forward.angle_to(toward)*1.8,-1,1)*(-1.0 if reverse else 1.0)
		var target_speed:=minf(9.0,maxf(1.6,(length-offset)*.65))
		var throttle:=clampf((target_speed-absf(float(car.speed)))*.3,0,.65)
		_axis(steer,0 if reverse else throttle)
		if reverse and throttle>0: Input.action_press("brake",throttle)
		else: Input.action_release("brake")
		for i in car.get_slide_collision_count():
			var hit:=car.get_slide_collision(i)
			if absf(hit.get_normal().y)<.65:
				var label:=str(hit.get_collider().get_path())
				if not contacts.has(label): contacts.append(label)
		if tick%6==0:
			var ground:=SURFACE.surface_height(Vector2(at.x,at.z))
			if at.y<ground-.25 or at.y>ground+1.2: unsupported+=1
			trace.append({"ms":Time.get_ticks_msec()-began,"position":str(at),"speed":car.speed,"offset":offset,"error":error,"floor":car.is_on_floor(),"ground":ground,"health":car.health})
		if DisplayServer.get_name()!="headless" and offset/length>=next_photo:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(id+"-%02d.png"%int(next_photo*100)))
			next_photo+=.25
		if offset>=length-2: reached=true; break
		if at.y<on_road.y-2 or error>5 or world.gameplay.health<=0: break
	_release(); Input.action_press("handbrake")
	await create_timer(1).timeout
	Input.action_release("handbrake")
	var report:={"id":id,"length":length,"reached":reached,"min_y":min_y,"max_error":max_error,"unsupported_samples":unsupported,"contacts":contacts,"health_before":initial_health,"health_after":car.health,"trace":trace}
	reports.append(report)
	var brief:=report.duplicate(); brief.erase("trace")
	print("MINING_HAUL_RESULT ",JSON.stringify(brief))
	var ok:=_check(reached,"giant truck completes physical "+id)
	ok=_check(unsupported==0 and contacts.is_empty() and is_equal_approx(car.health,initial_health),"truck stays supported and undamaged on "+id) and ok
	return ok
