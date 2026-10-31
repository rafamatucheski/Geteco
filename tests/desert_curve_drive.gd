extends SceneTree
## Main real, dirigibilidade comum do jogador e CharacterBody3D.move_and_slide.
## Um controlador finito de entrada analógica esterça; nunca move/gira o corpo do carro.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const L := preload("res://world/desert/DesertLayout.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
const GEOMETRY := preload("res://world/desert/DesertRoadGeometry.gd")
var world: Node3D
var output := ""
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var checks := 0
var geometry: RefCounted
var prior_gamepad := false

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("DESERT_CURVE_DRIVE timeout"); _finish(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	checks+=1
	print("DESERT_CURVE_DRIVE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _run() -> void:
	if not _check("--no-save" in OS.get_cmdline_user_args() and "--no-traffic" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"requires isolated no-save/no-traffic .NET run"):
		_finish(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-curve-drive")
	var snapshot := FIXTURE.full_snapshot(Vector3(346,.1,-820),true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[346,.1,-820]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not _check(not path.is_empty(),"isolated checkpoint validates"): _finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path,"real Main loads only isolated checkpoint"):
		_finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not _check(world.dispatch.router._native!=null,"compiled native route backend is active"): _finish(1); return
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.gameplay.god_mode=true
	world.session.weather.time_of_day=.45; world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600; world.session.weather._update()
	# Emula o caminho existente de ação analógica, sem alterar atalhos nem física.
	prior_gamepad=bool(root.get_node("GameInput").using_gamepad)
	root.get_node("GameInput").using_gamepad=true
	geometry=GEOMETRY.new(); geometry.configure(L.roads())
	var graph := ROUTES.new(); graph.configure(L.roads().filter(func(road: Dictionary): return road.traffic))
	for setup in [
		{"id":"route66-coyote","start":Vector3(342.5,0,-850),"end":Vector3(290,0,-900),"car":"desert_coyote","speed":12.0,"lead":30.0,"incoming":Vector3.FORWARD,"outgoing":Vector3.LEFT},
		{"id":"west-bison","start":Vector3(-1005,0,-540),"end":Vector3(-1060,0,-595),"car":"desert_bison","speed":10.0,"lead":30.0,"incoming":Vector3.LEFT,"outgoing":Vector3.FORWARD},
		{"id":"digo-faisca","start":Vector3(-110,0,-610),"end":Vector3(-142,0,-640),"car":"desert_faisca","speed":6.5,"lead":15.0,"incoming":Vector3.FORWARD,"outgoing":Vector3.LEFT},
	]:
		if "--shortcut-only" in OS.get_cmdline_user_args(): continue
		var native: Curve3D = graph.route_between(setup.start,setup.end)
		if not _check(native!=null,"native guide exists: "+str(setup.id)): _finish(1); return
		var guide := _extend(native,float(setup.lead),setup.incoming,setup.outgoing)
		if not await _drive(setup,guide): _finish(1); return
	# A nova diagonal privada liga vértices reais da Main Street e do
	# acesso da arrancada. Dirige por ela com esterço normal, incluindo os dois entroncamentos.
	var private_graph := ROUTES.new()
	private_graph.configure(L.roads())
	var shortcut: Curve3D = private_graph.route_between(Vector3(-590,0,-540),Vector3(-935,0,-760))
	if not _check(shortcut!=null and shortcut.get_baked_length()<450,"town-to-meet guide takes the compact private shortcut"):
		_finish(1); return
	var shortcut_setup := {"id":"town-meet-shortcut","car":"desert_coyote","speed":12.0,"seconds":80.0}
	# A rua no sentido oeste curva para o norte logo depois deste destino. Mantém uma
	# saída curta dentro da rua real em vez de avançar pela areia.
	if not await _drive(shortcut_setup,_extend(shortcut,15.0,Vector3.LEFT,Vector3.LEFT,3.0)):
		_finish(1); return
	await _bank_walk()
	_finish(0 if failures.is_empty() else 1)

func _extend(native: Curve3D, lead: float, incoming: Vector3, outgoing: Vector3, departure: float = -1.0) -> Curve3D:
	var guide := Curve3D.new(); guide.bake_interval=.2
	var length := native.get_baked_length()
	var first := native.sample_baked(0)
	var last := native.sample_baked(length)
	guide.add_point(first-incoming*lead)
	var distance := 0.0
	while distance<length:
		guide.add_point(native.sample_baked(distance)); distance+=1
	guide.add_point(last); guide.add_point(last+outgoing*(lead if departure<0 else departure))
	return guide

func _drive(setup: Dictionary, guide: Curve3D) -> bool:
	var point := guide.sample_baked(0)+Vector3.UP*.12
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point+Vector3.RIGHT*4)
	for i in 90: await physics_frame
	var direction := point.direction_to(guide.sample_baked(1)+Vector3.UP*.12)
	var car: CharacterBody3D = world.production.spawn_vehicle(str(setup.car),point,atan2(-direction.x,-direction.z))
	if not _check(is_instance_valid(car),"ordinary spawn admitted: "+str(setup.id)): return false
	car.vehicle_id="desert_curve_validation_"+str(setup.id)
	world.player.teleport(car.driver_door_anchor(1)+Vector3(.4,.05,0))
	if not _check(world.driving.interact(),"ordinary driver boarding: "+str(setup.id)): return false
	var deadline := Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	if not _check(world.driving.occupied and world.driving.car==car and car.controlled and not car.external_input and not car.input_locked,"normal handling owns the car: "+str(setup.id)): return false
	var start_health: float = car.health
	var start_yaw: float = car.rotation.y
	var length := guide.get_baked_length()
	var began := Time.get_ticks_msec()
	var travelled := 0.0
	var previous: Vector3 = car.global_position
	var min_height := INF
	var worst_error := 0.0
	var off_pavement := 0
	var bad_corners: Array[Dictionary] = []
	var collisions: Array[String] = []
	var trace: Array[Dictionary] = []
	var frames := 0
	var shot := 0
	var reached := false
	while Time.get_ticks_msec()-began<int(float(setup.get("seconds",30.0))*1000.0):
		await physics_frame
		frames+=1
		var at: Vector3 = car.global_position
		travelled+=at.distance_to(previous); previous=at
		min_height=minf(min_height,at.y)
		var offset := guide.get_closest_offset(at)
		var error := Vector2(at.x,at.z).distance_to(Vector2(guide.sample_baked(offset).x,guide.sample_baked(offset).z))
		worst_error=maxf(worst_error,error)
		var lookahead := maxf(4.0,absf(float(car.speed))*.8)
		var target := guide.sample_baked(minf(length,offset+lookahead))
		var forward := Vector2(-car.global_basis.z.x,-car.global_basis.z.z)
		var toward := Vector2(target.x-at.x,target.z-at.z).normalized()
		var steer := clampf(forward.angle_to(toward)*1.8,-1,1)
		var target_speed := minf(float(setup.speed),maxf(2.0,(length-offset)*.65))
		# Um motorista humano freia antes de um cruzamento. A fixture precisa fazer o mesmo,
		# em vez de pedir ao carro que vire 90 graus a 12 m/s constantes.
		var ahead := guide.sample_baked(minf(length,offset+maxf(12.0,absf(float(car.speed))*1.4)))
		var future_direction := Vector2(ahead.x-target.x,ahead.z-target.z)
		if future_direction.length()>.1:
			var bend := absf(forward.angle_to(future_direction.normalized()))
			if bend>.45: target_speed=minf(target_speed,5.0)
		var throttle := clampf((target_speed-float(car.speed))*.3,0,.65)
		if float(car.speed)>target_speed+1.0: Input.action_press("brake",.5)
		else: Input.action_release("brake")
		_axis(steer,throttle)
		for i in car.get_slide_collision_count():
			var hit := car.get_slide_collision(i)
			if absf(hit.get_normal().y)<.65:
				var name := str(hit.get_collider().get_path())
				var collider = hit.get_collider()
				name += " at="+str(collider.global_position)
				if collider.get("archetype")!=null: name += " archetype="+str(collider.archetype)
				if collider.get("vehicle_id")!=null: name += " id="+str(collider.vehicle_id)
				if not collisions.has(name): collisions.append(name)
		if frames%6==0:
			for x: float in [-1.0,1.0]:
				for z: float in [-1.0,1.0]:
					var corner: Vector3 = car.to_global(Vector3(x*float(car.half_width),0,z*float(car.half_length)))
					if not _paved(Vector2(corner.x,corner.z)):
						off_pavement+=1
						if bad_corners.size()<24: bad_corners.append({"at":str(at),"corner":str(corner),"yaw":car.rotation.y,"speed":car.speed,"progress":offset})
			trace.append({"ms":Time.get_ticks_msec()-began,"position":[at.x,at.y,at.z],"speed":car.speed,"yaw":car.rotation.y,"progress":offset,"error":error,"steer":steer,"throttle":throttle,"floor":car.is_on_floor(),"health":car.health})
		if DisplayServer.get_name()!="headless" and offset/length>=float(shot)*.25:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(str(setup.id)+"-%02d.png"%shot)); shot+=1
		if offset>=length-2.0: reached=true; break
		if at.y<-.3 or error>5.0: break
	_release(); Input.action_press("handbrake")
	for i in 120:
		await physics_frame
		if absf(float(car.speed))<.08: break
	Input.action_release("handbrake")
	var result := {"id":setup.id,"car":setup.car,"reached":reached,"distance":travelled,"guide_length":length,"max_error":worst_error,"min_height":min_height,"off_pavement_corners":off_pavement,"obstacle_contacts":collisions,"health_before":start_health,"health_after":car.health,"heading_change_degrees":rad_to_deg(absf(wrapf(float(car.rotation.y)-start_yaw,-PI,PI))),"trace":trace}
	result["bad_corners"]=bad_corners
	reports.append(result)
	var summary := result.duplicate(); summary.erase("trace")
	print("DESERT_CURVE_RESULT ",JSON.stringify(summary))
	var ok := _check(reached and travelled>length*.8,"physical input traversal reaches the curved route end: "+str(setup.id))
	ok=_check(min_height>-.15 and off_pavement==0 and collisions.is_empty() and is_equal_approx(float(car.health),start_health),"whole physical car stays supported, paved and undamaged: "+str(setup.id)) and ok
	if not _check(world.driving.leave(),"ordinary parked exit: "+str(setup.id)): return false
	deadline=Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	return ok and not world.driving.occupied

func _axis(steer: float, throttle: float) -> void:
	Input.action_release("move_left"); Input.action_release("move_right")
	if steer<0: Input.action_press("move_left",-steer)
	elif steer>0: Input.action_press("move_right",steer)
	if throttle>0: Input.action_press("accelerate",throttle)
	else: Input.action_release("accelerate")

func _release() -> void:
	for action in ["move_left","move_right","accelerate","brake","handbrake"]: Input.action_release(action)

func _paved(point: Vector2) -> bool:
	for row in geometry.corridors:
		if Geometry2D.is_point_in_polygon(point,row.polygon): return true
	return false

func _bank_walk() -> void:
	var start := L.BANK+Vector3(0,.08,14)
	var end: Vector3 = L.place_definitions()[0].entry_position
	world.production.region.set_focus(start); world.production.region.prepare_collision_at(start)
	world.player.teleport(start)
	for i in 90: await physics_frame
	var trace: Array[Dictionary] = []
	var reached := false
	var deadline := Time.get_ticks_msec()+8000
	var minimum_y := INF
	while Time.get_ticks_msec()<deadline:
		var at: Vector3 = world.player.global_position
		minimum_y=minf(minimum_y,at.y)
		var delta := Vector3(end.x-at.x,0,end.z-at.z)
		if delta.length()<.22: reached=true; break
		world.player.automatic_direction=delta.normalized()
		await physics_frame
		trace.append({"position":[at.x,at.y,at.z],"floor":world.player.is_on_floor()})
	world.player.automatic_direction=Vector3.ZERO
	_check(reached and minimum_y>-.15,"real Actor walks from Cobre asphalt cap across ramp to original entry")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("cobre-walk.png"))
	reports.append({"id":"cobre-walk","reached":reached,"minimum_y":minimum_y,"trace":trace})
	if reached:
		_check(await world.session.enter_place("desert_bank",false),"original Cobre doorway transition still accepts the actor")
		_check(await world.session.leave_place(),"Cobre exit returns through the same exterior access")

func _finish(code: int) -> void:
	_release()
	if is_instance_valid(root.get_node_or_null("GameInput")): root.get_node("GameInput").using_gamepad=prior_gamepad
	if not output.is_empty():
		var report := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"scenarios":reports,"scope":"Low-demand physical player handling with logical analog actions; not ambient traffic arbitration or a performance benchmark."}
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_CURVE_DRIVE_DONE ",output," code=",code)
	quit(code)
