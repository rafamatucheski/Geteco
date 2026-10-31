extends SceneTree
const VEHICLE:=preload("res://scripts/Vehicle.gd")
var world
var failures: Array[String]=[]
var folder:="res://evidence/auditoria-viaria/2026-10-10-fuga-transito/rendered"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func wait_seconds(seconds: float) -> void:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		world.gameplay.health=100
func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(300).timeout.connect(func():quit(124))
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var ready_deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<ready_deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if world.session==null or not world.session.ready_for_play: world.free(); quit(1); return
	check(world.dispatch.router._native_graph()!=null,"native C# routing active")
	world.player.teleport(Vector3(-324,.08,30))
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.camera.target_size=45
	world.camera.initialized=false
	world.production.region.prepare_collision_at(Vector3(-338,0,15.75))
	await wait_seconds(6)
	var cop=world.production.spawn_vehicle("police_cruiser",Vector3(-338,.08,15.75),PI*.5)
	check(is_instance_valid(cop),"stopped police obstruction created")
	if not is_instance_valid(cop): world.free(); quit(1); return
	cop.set_meta("dispatch_unit",true)
	cop.set_external_driver(true)
	cop.throttle_input=0
	cop.brake_input=true
	var cop_start: Vector3=cop.position
	# Começa a viagem mais atrás para que os três offsets de amostra existam. Uma rota que começasse
	# em -320 prenderia senão a fila inteira no primeiro ponto.
	var path: Curve3D=world.production.ambient_traffic_routes.route_near(Vector3(-270,0,8),0,Vector3.LEFT)
	check(path!=null,"rural traffic trip exists")
	if path==null: world.free(); quit(1); return
	var offset:=path.get_closest_offset(Vector3(-314,0,16))
	check(offset>24,"upstream trip has room for all three queue positions")
	var cars:=[]
	for i in 3:
		var point:=path.sample_baked(maxf(0,offset-i*10),true)
		var next:=path.sample_baked(maxf(0,offset-i*10)+.5,true)
		var heading:=next-point
		var car=world.production.spawn_vehicle("union_sedan",point+Vector3.UP*.08,atan2(-heading.x,-heading.z))
		if not is_instance_valid(car): continue
		for frame in 3: await physics_frame
		check(not car.has_meta("awaiting_ground"),"queue vehicle starts on a clear physical road")
		car.route=path
		car.route_distance=path.get_closest_offset(point)
		car.traffic=true
		car.set_meta("ambient_traffic",true)
		car.vehicle_id="escape_fixture_"+str(i)
		cars.append({"car":car,"start":point,"escaped":false,"shift":0.0})
	check(cars.size()==3,"three civilian vehicles admitted with physical clearance")
	await shot("01_fila")
	var victim
	var victim_hit:=false
	var panic_seen:=false
	var deadline:=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		world.gameplay.health=100
		for record in cars:
			var car=record.car
			if not is_instance_valid(car): continue
			if car.get_meta("traffic_escape_state","")=="escaping":
				panic_seen=true
				record.escaped=true
				record.shift=car.get_meta("traffic_escape_shift",0)
				if victim==null:
					var at: float=car.route.get_closest_offset(car.position)
					var point: Vector3=car.route.sample_baked(at+7,true)
					var ray: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1))
					if not ray.is_empty():
						victim=preload("res://scripts/Actor.gd").new()
						victim.position=ray.position+Vector3.UP*.08
						victim.identity=80102
						world.add_child(victim)
						world.people.append(victim)
						await shot("02_fuga")
		if is_instance_valid(victim): victim_hit=victim_hit or victim.has_meta("street_down") or victim.dead or victim.health<100
	var cleared:=0
	var details:=[]
	for record in cars:
		var car=record.car
		if not is_instance_valid(car):
			cleared+=1
			details.append({"removed":true,"escaped":record.escaped,"shift":record.shift})
		else:
			var movement: float=car.position.distance_to(record.start)
			if movement>20 and car.position.distance_to(cop_start)>20: cleared+=1
			details.append({"removed":false,"position":str(car.position),"escaped":record.escaped,"shift":record.shift,"state":car.get_meta("traffic_escape_state",""),"plan":car.get_meta("traffic_escape_plan_failure","")})
	check(panic_seen,"civilian panic runs in rendered Main")
	check(cleared==cars.size() and cleared==3,"queue clears independently of stationary police")
	check(cop.position.distance_to(cop_start)<1,"police obstruction stays while civilians escape")
	check(victim_hit,"panic vehicle uses actual street impact against the pedestrian")
	await shot("03_fila_liberada")
	FileAccess.open(folder+"/traffic-case.json",FileAccess.WRITE).store_string(JSON.stringify({"cars":details,"victim_hit":victim_hit,"panic":panic_seen,"failures":failures},"\t"))
	cop.queue_free()
	world.gameplay.register_crime(60,world.player.position)
	await wait_seconds(35)
	var police:=[]
	for unit in world.dispatch.units:
		if unit.is_police(): police.append(unit)
	check(not police.is_empty(),"live police response participates")
	world.gameplay.clear_wanted()
	await wait_seconds(55)
	var finished:=0
	var unfinished:=[]
	for unit in police:
		if unit.finished: finished+=1
		else: unfinished.append({"unit":unit.label(),"state":unit.state,"position":str(unit.vehicle.position),"stall":unit._departure_stall,"clock":unit._departure_clock})
	check(finished==police.size() and finished>0,"all observed police vehicles leave or retire after response")
	await shot("04_saida_viaturas")
	FileAccess.open(folder+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"cars":details,"victim_hit":victim_hit,"police":police.size(),"police_finished":finished,"unfinished":unfinished,"events":world.dispatch.events,"failures":failures,"fps":"validation delegated to user"},"\t"))
	print("TRAFFIC_ESCAPE_MAIN failures=",failures," cars=",details," unfinished=",unfinished)
	world.free()
	quit(0 if failures.is_empty() else 1)
