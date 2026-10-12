extends SceneTree
## Rendered Main, native C# routing and live directors. Automated player walking
## uses the normal capsule/streaming. Crime/fire are explicit scenario injections.
var world
var failures: Array[String] = []
var rows: Array = []
var folder := "res://evidence/auditoria-viaria/2026-10-10-populacao-bloqueios/rendered-final"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		world.gameplay.health=100
func snapshot(label: String) -> void:
	var near := 0
	var approaching := 0
	var road_counts := {}
	var traffic := 0
	var unit_rows := []
	for unit in world.dispatch.units:
		unit_rows.append({"id":unit.label(),"state":unit.state,"position":str(unit.vehicle.position),"speed":unit.vehicle.speed,"remaining":unit.driver.remaining,"blocked":unit.driver.blocked_ahead,"blocker":str(unit.driver.blocker),"overtake":unit.driver.overtake.last_reason if unit.driver.overtake!=null else "none"})
	for actor in world.people:
		if is_instance_valid(actor) and actor.global_position.distance_to(world.player.global_position)<45: near+=1
		if is_instance_valid(actor) and actor.global_position.distance_to(world.player.global_position)<70: approaching+=1
		if is_instance_valid(actor):
			var id: String=actor.get_meta("ambient_road_id","special")
			road_counts[id]=int(road_counts.get(id,0))+1
	for car in world.production.vehicles:
		if is_instance_valid(car) and car.traffic and car.global_position.distance_to(world.player.global_position)<70: traffic+=1
	var row := {"label":label,"position":str(world.player.position),"people":world.people.size(),"people_within45":near,"people_within70":approaching,"roads":road_counts,"traffic_within70":traffic,"units":world.dispatch.units.size(),"unit_details":unit_rows}
	rows.append(row)
	print("CITY_CENSUS ",JSON.stringify(row))
	if label.begins_with("fire_trace_"): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func walk(point: Vector3, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		var direction: Vector3 = point-world.player.position
		direction.y=0
		if direction.length()<1.0:
			world.player.automatic_direction=Vector3.ZERO
			return true
		world.player.automatic_direction=direction.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	return false
func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(420).timeout.connect(func(): quit(124))
	DirAccess.make_dir_recursive_absolute(folder)
	seed(10102026)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var startup := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<startup:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if world.session==null or not world.session.ready_for_play: world.free(); quit(1); return
	check(world.dispatch.router._native_graph()!=null,"dispatch uses native C# router")
	world.player.teleport(Vector3(-155,.1,26))
	world.production.region.prepare_collision_at(world.player.position)
	world.player.controlled_automatically=true
	world.player.speed=6.5
	world.camera.target_size=45
	world.camera.initialized=false
	world.session.weather.time_of_day=.4
	if "--services-only" in OS.get_cmdline_user_args():
		folder="res://evidence/auditoria-viaria/2026-10-10-populacao-bloqueios/rendered-fire-probe" if "--fire-probe" in OS.get_cmdline_user_args() else "res://evidence/auditoria-viaria/2026-10-10-populacao-bloqueios/rendered-services-final"
		DirAccess.make_dir_recursive_absolute(folder)
		world.player.teleport(Vector3(-297,.1,26))
		world.production.region.prepare_collision_at(world.player.position)
		await wait_seconds(10)
		await snapshot("00_setup")
		await service_cases()
		return
	await wait_seconds(18)
	await snapshot("01_corredor")
	check(rows[-1].people_within70>0,"rural corridor is populated ahead of the camera")
	for point in [Vector3(-200,0,26),Vector3(-250,0,3),Vector3(-290,0,3)]:
		check(await walk(point,20),"walk corridor to "+str(point))
		if point.x==-200:
			await snapshot("01b_corredor_percurso")
			check(rows[-1].people_within45>0,"pedestrians are encountered while walking the rural corridor")
	await wait_seconds(8)
	await snapshot("02_acesso")
	check(rows[-1].people_within45>0,"village approach has nearby pedestrians")
	for point in [Vector3(-297,0,26),Vector3(-294,0,48),Vector3(-286,0,66),Vector3(-290,0,82),Vector3(-304,0,95)]:
		check(await walk(point,16),"walk village access to "+str(point))
	await wait_seconds(10)
	await snapshot("03_vila")
	check(world.people.size()<=world.production.MAX_POPULATION,"shared ambient pedestrian budget preserved")
	# Return physically to the vehicle access before provoking emergency response.
	for point in [Vector3(-290,0,82),Vector3(-286,0,66),Vector3(-294,0,48),Vector3(-297,0,26)]:
		check(await walk(point,16),"return village access to "+str(point))
	await service_cases()

func service_cases() -> void:
	# Sustained incident fixture: the ordinary ground fire fades after 20 s,
	# often before a rural response can arrive. Keep its age fresh until crew
	# starts actual extinguishing, while leaving dispatch/traffic/collision live.
	var fire = world.gameplay.emergency.ignite(Vector3(-292,0,20),null,1.5)
	var deadline := Time.get_ticks_msec()+75000
	var servicing := false
	var log_at := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		world.gameplay.health=100
		for unit in world.dispatch.units:
			if unit.service=="fire" and is_instance_valid(unit.crew) and unit.crew.mode=="service": servicing=true
		if is_instance_valid(fire) and not servicing: fire.age=minf(fire.age,1.0)
		if Time.get_ticks_msec()>log_at:
			log_at+=5000
			await snapshot("fire_trace_"+str((deadline-Time.get_ticks_msec())/1000))
		if servicing and not is_instance_valid(fire): break
	await snapshot("04_bombeiro")
	var stop_events: Array = world.dispatch.events_named("stop_planned")
	var fire_worked := false
	for event in stop_events:
		if event.get("service","")=="fire": fire_worked=true
	check(fire_worked,"fire response plans a stop in rendered Main")
	check(servicing,"firefighter reaches the incident and extinguishes in rendered Main")
	var fire_unit
	var departure_origin := Vector3.INF
	for unit in world.dispatch.units:
		if unit.service=="fire":
			fire_unit=unit
			departure_origin=unit.vehicle.position
	await wait_seconds(35)
	await snapshot("04b_saida_bombeiro")
	check(fire_unit!=null and (fire_unit.finished or (is_instance_valid(fire_unit.vehicle) and fire_unit.vehicle.position.distance_to(departure_origin)>8)),"fire crew returns and truck drives away in rendered Main")
	if "--fire-probe" in OS.get_cmdline_user_args():
		finish_report()
		return
	world.gameplay.register_crime(60,world.player.global_position)
	await wait_seconds(35)
	await snapshot("05_policia")
	var police_stop := false
	for event in world.dispatch.events_named("stop_planned"):
		if event.get("service","")=="police": police_stop=true
	check(police_stop and world.dispatch.foot_officer_count()>0,"police plans a stop and deploys in rendered Main")
	world.gameplay.clear_wanted()
	await wait_seconds(20)
	await snapshot("06_recuperacao")
	finish_report()

func finish_report() -> void:
	FileAccess.open(folder+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures,"events":world.dispatch.events,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"fps_validation":"delegated to user; no benchmark"},"\t"))
	print("CITY_CIRCULATION failures=",failures)
	world.free()
	quit(0 if failures.is_empty() else 1)
