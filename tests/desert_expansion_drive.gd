extends "res://tests/desert_curve_drive.gd"
## Main .NET com entrada analógica comum do jogador e física de veículo inalterada.
## Só os inícios da fixture são posicionados; nenhuma pose/velocidade de carro é escrita durante a direção.
const LAND := preload("res://world/desert/expansion/DesertLandforms.gd")
var car: CharacterBody3D
var source_start: Dictionary = {}
var finishing := false

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): failures.append("300s complete-fixture watchdog"); _finish(3))
	_run.call_deferred()

func _run() -> void:
	if not _check(DisplayServer.get_name()!="headless" and "--no-save" in OS.get_cmdline_user_args() and "--no-traffic" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered isolated no-save/no-traffic .NET required"):
		_finish(2); return
	seed(6102026)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-expansion-drive")
	source_start=_fingerprint()
	var arrival := Vector3(-60,.1,-660)
	var snapshot := FIXTURE.full_snapshot(arrival,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[arrival.x,arrival.y,arrival.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not _check(not path.is_empty(),"isolated completed-campaign checkpoint validates"): _finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path and world.production.no_save,"Main uses isolated checkpoint without writing saves"):
		_finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not _check(world.dispatch.router._native!=null and world.production.requested_population==20,"compiled route backend and requested population20 are active"):
		_finish(1); return
	if world.session.modal: world.session.close_menu()
	if not _check(not world.gameplay.god_mode,"damage checks use ordinary vulnerability"): _finish(1); return
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45; world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600; world.session.weather._update()
	prior_gamepad=bool(root.get_node("GameInput").using_gamepad)
	root.get_node("GameInput").using_gamepad=true
	var dune := _line(Vector2(-54,-622),Vector2(4,-622))
	var wash := Curve3D.new(); wash.bake_interval=.2
	for i in 51: _add_point(wash,LAND.wash_point(.20+float(i)*.50/50.0))
	var rail := _line(Vector2(-1000,-566),Vector2(-1000,-535))
	var selected_case := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="): selected_case=argument.trim_prefix("--case=")
	if not _check(selected_case in ["","dune-up-and-down","dry-wash-centre","abandoned-rail-crossing"],"case filter names an authored drive scenario"):
		_finish(2); return
	for setup in [
		{"id":"dune-up-and-down","guide":dune,"speed":4.5,"minimum_peak":1.3,"require_chunk_crossing":true},
		{"id":"dry-wash-centre","guide":wash,"speed":5.5,"minimum_peak":0.0,"require_chunk_crossing":true},
		{"id":"abandoned-rail-crossing","guide":rail,"speed":3.5,"minimum_peak":0.0,"require_chunk_crossing":false},
	]:
		if not selected_case.is_empty() and selected_case!=str(setup.id): continue
		if not await _admit(setup): _finish(1); return
		if not await _drive_path(setup): _finish(1); return
		if not _check(world.driving.leave(),"ordinary parked exit accepted: "+str(setup.id)): _finish(1); return
		deadline=Time.get_ticks_msec()+10000
		while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
		if not _check(not world.driving.occupied,"ordinary exit finishes: "+str(setup.id)): _finish(1); return
	_finish(0 if failures.is_empty() else 1)

func _line(start: Vector2,end: Vector2) -> Curve3D:
	var guide := Curve3D.new(); guide.bake_interval=.2
	var count := maxi(1,ceili(start.distance_to(end)))
	for i in count+1: _add_point(guide,start.lerp(end,float(i)/float(count)))
	return guide

func _add_point(guide: Curve3D, point: Vector2) -> void:
	guide.add_point(Vector3(point.x,LAND.surface_height(point,L.surface_height),point.y))

func _admit(setup: Dictionary) -> bool:
	_release()
	var guide: Curve3D=setup.guide
	var point := guide.sample_baked(0)+Vector3.UP*.12
	world.production.region.set_focus(point); world.production.region.prepare_collision_at(point)
	world.player.teleport(point+Vector3.RIGHT*5.0)
	world.camera.initialized=false
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	if not _check(world.production.region.is_streaming_idle(),"start neighbourhood settles: "+str(setup.id)): return false
	for i in 6: await physics_frame
	var direction := point.direction_to(guide.sample_baked(1)+Vector3.UP*.12)
	car=world.production.spawn_vehicle("desert_bison",point,atan2(-direction.x,-direction.z))
	if not _check(is_instance_valid(car),"ordinary Bison spawn admitted: "+str(setup.id)): return false
	car.vehicle_id="desert_expansion_validation_"+str(setup.id)
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.35+Vector3.UP*.08)
	if world.session.modal: world.session.close_menu()
	if not _check(world.driving.interact(),"ordinary boarding accepted: "+str(setup.id)): return false
	deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	return _check(world.driving.occupied and world.driving.car==car and car.controlled and not car.external_input and not car.input_locked,"normal analog handling owns Bison: "+str(setup.id))

func _drive_path(setup: Dictionary) -> bool:
	var guide: Curve3D=setup.guide
	var length := guide.get_baked_length()
	var cruise: float=setup.speed
	# O orçamento permite velocidade média de só40% da de cruzeiro mais aceleração/frenagem.
	var bound_seconds := 20.0+length/maxf(1.0,cruise*.4)
	var began := Time.get_ticks_msec()
	var last_progress_ms := began
	var progress_mark := 0.0
	var start_health := float(car.health)
	var previous: Vector3=car.global_position
	var travelled := 0.0
	var error_max := 0.0
	var floor_error_max := 0.0
	var ray_error_max := 0.0
	var minimum_y := INF
	var maximum_y := -INF
	var off_floor := 0.0
	var longest_air := 0.0
	var missing_rays := 0
	var sample_count := 0
	var frames := 0
	var photo_index := 0
	var reached := false
	var reason := "deadline"
	var cells: Dictionary={}
	var contacts: Array[Dictionary]=[]
	var trace: Array[Dictionary]=[]
	while Time.get_ticks_msec()-began<int(bound_seconds*1000.0):
		await physics_frame
		frames+=1
		var at: Vector3=car.global_position
		travelled+=at.distance_to(previous); previous=at
		minimum_y=minf(minimum_y,at.y); maximum_y=maxf(maximum_y,at.y)
		var offset := guide.get_closest_offset(at)
		var nearest := guide.sample_baked(offset)
		var error := Vector2(at.x,at.z).distance_to(Vector2(nearest.x,nearest.z))
		error_max=maxf(error_max,error)
		var height := LAND.surface_height(Vector2(at.x,at.z),L.surface_height)
		floor_error_max=maxf(floor_error_max,absf(at.y-height))
		off_floor=0.0 if car.is_on_floor() else off_floor+1.0/float(Engine.physics_ticks_per_second)
		longest_air=maxf(longest_air,off_floor)
		var cell := Vector2i(floori(at.x/96.0),floori(at.z/96.0))
		if not cells.has(str(cell)): cells[str(cell)]={"ms":Time.get_ticks_msec()-began,"resident":world.production.region.chunks.has(cell)}
		if offset>progress_mark+.35: progress_mark=offset; last_progress_ms=Time.get_ticks_msec()
		var lookahead := maxf(3.5,absf(float(car.speed))*.8)
		var target := guide.sample_baked(minf(length,offset+lookahead))
		var forward := Vector2(-car.global_basis.z.x,-car.global_basis.z.z)
		var toward := Vector2(target.x-at.x,target.z-at.z).normalized()
		var angle := forward.angle_to(toward)
		var target_speed := minf(cruise,maxf(1.0,(length-offset)*.65))
		if absf(angle)>.22: target_speed=minf(target_speed,3.0)
		var steer := clampf(angle*1.8,-1,1)
		var throttle := clampf((target_speed-float(car.speed))*.3,0,.75)
		_axis(steer,throttle)
		Input.action_release("brake")
		if float(car.speed)>target_speed+1.0: Input.action_press("brake",clampf((float(car.speed)-target_speed)*.15,.1,.7))
		var current_contacts := _contacts()
		for contact in current_contacts:
			if absf(float(contact.normal[1]))<.65 and not contacts.any(func(other): return other.collider==contact.collider): contacts.append(contact)
		if frames%6==0:
			var sample := {"ms":Time.get_ticks_msec()-began,"physics_frame":Engine.get_physics_frames(),"position":_v3(at),"speed":car.speed,"progress":offset,"guide_error":error,"ground_height":height,"floor":car.is_on_floor(),"health":car.health,"steer":steer,"throttle":throttle,"wall":car.is_on_wall(),"cell":str(cell),"footprint":[]}
			for x in [-.85,.85]:
				for z in [-.85,.85]:
					var corner: Vector3=car.to_global(Vector3(x*float(car.half_width),0,z*float(car.half_length)))
					var expected := LAND.surface_height(Vector2(corner.x,corner.z),L.surface_height)
					var hit := _ground_ray(corner)
					sample_count+=1
					if hit.is_empty(): missing_rays+=1
					else: ray_error_max=maxf(ray_error_max,absf(float(hit.position.y)-expected))
					sample.footprint.append({"position":_v3(corner),"hit":not hit.is_empty(),"height":float(hit.position.y) if not hit.is_empty() else null,"expected":expected,"collider":str(hit.collider.get_path()) if not hit.is_empty() else ""})
			trace.append(sample)
		if photo_index<3 and offset/length>=float(photo_index)*.49:
			await _photo(str(setup.id)+"-%02d"%photo_index); photo_index+=1
		if offset>=length-1.0: reached=true; reason="reached"; break
		if at.y<height-.35: reason="below_ground"; break
		if error>3.0: reason="guide_error"; break
		if float(car.health)<start_health-.01: reason="damage"; break
		if Time.get_ticks_msec()-last_progress_ms>12000: reason="stalled_12s"; break
	_release(); Input.action_press("handbrake")
	for i in 180:
		await physics_frame
		if absf(float(car.speed))<.08: break
	Input.action_release("handbrake")
	var row := {"id":setup.id,"car":"desert_bison","reached":reached,"stop_reason":reason,"seconds":float(Time.get_ticks_msec()-began)/1000.0,"bound_seconds":bound_seconds,"guide_length":length,"distance":travelled,"guide_error_max":error_max,"floor_origin_error_max":floor_error_max,"ray_vs_ground_error_max":ray_error_max,"missing_ground_rays":missing_rays,"ground_ray_count":sample_count,"min_height":minimum_y,"max_height":maximum_y,"longest_air_seconds":longest_air,"health_before":start_health,"health_after":car.health,"cells":cells,"obstacle_contacts":contacts,"last_position":_v3(car.global_position),"last_speed":car.speed,"last_velocity":_v3(car.velocity),"last_contacts":_contacts(),"trace":trace}
	reports.append(row)
	var summary := row.duplicate(); summary.erase("trace")
	print("DESERT_EXPANSION_DRIVE_RESULT ",JSON.stringify(summary))
	var ok := _check(reached and travelled>length*.8,"ordinary input completes "+str(setup.id)+" ("+reason+")")
	var ray_tolerance := .15 if str(setup.id)=="abandoned-rail-crossing" else .04
	ok=_check(missing_rays==0 and sample_count>20 and ray_error_max<ray_tolerance and floor_error_max<1.2 and longest_air<.6,"car remains supported without a ground drop: "+str(setup.id)) and ok
	ok=_check(contacts.is_empty() and is_equal_approx(float(car.health),start_health),"no lateral obstacle contact or vehicle damage: "+str(setup.id)) and ok
	if float(setup.minimum_peak)>0: ok=_check(maximum_y>float(setup.minimum_peak),"Bison physically climbs the dune crest") and ok
	if bool(setup.require_chunk_crossing): ok=_check(cells.size()>=2 and cells.values().all(func(record): return bool(record.resident)),"actual driving crosses resident chunk boundaries: "+str(setup.id)) and ok
	return ok

func _ground_ray(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2.0,point-Vector3.UP*4.0,1)
	query.exclude=[car.get_rid(),world.player.get_rid()]
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _contacts() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for i in car.get_slide_collision_count():
		var contact := car.get_slide_collision(i)
		for j in contact.get_collision_count():
			var object := contact.get_collider(j)
			result.append({"collider":str(object.get_path()) if object is Node else str(object),"normal":_v3(contact.get_normal(j)),"position":_v3(contact.get_position(j)),"depth":contact.get_depth(),"travel":_v3(contact.get_travel()),"remainder":_v3(contact.get_remainder())})
	return result

func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func _fingerprint(reference: Dictionary = {}) -> Dictionary:
	var result: Dictionary={}
	if not reference.is_empty():
		for path in reference: result[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
		return result
	for directory in ["res://world/desert/expansion","res://gameplay/desert_cars"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
				var path: String=directory+"/"+filename
				result[path]=FileAccess.get_sha256(path)
	for path in ["res://scripts/Vehicle.gd","res://scripts/Driving.gd","res://runtime/ProductionWorld.gd","res://world/desert/DesertRegion.gd",get_script().resource_path]: result[path]=FileAccess.get_sha256(path)
	return result

func _finish(code: int) -> void:
	if finishing: return
	finishing=true
	_release()
	if is_instance_valid(root.get_node_or_null("GameInput")): root.get_node("GameInput").using_gamepad=prior_gamepad
	if is_instance_valid(world) and is_instance_valid(world.get("player")): world.player.automatic_direction=Vector3.ZERO
	var source_end := _fingerprint(source_start)
	if not source_start.is_empty() and source_start!=source_end: failures.append("Source changed during physical expansion validation")
	if not failures.is_empty() and code==0: code=1
	if not output.is_empty():
		var report := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"scenarios":reports,"source_sha256_start":source_start,"source_sha256_end":source_end,"source_stable":source_start==source_end,"scope":"Rendered Main .NET Bison driving with ordinary analog actions, no pose/velocity writes after admission, no god mode. Isolated no-save/no-traffic population20 fixture. Dune, dry-wash and rail samples only; screenshots and diagnostic rays are not a performance benchmark."}
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_EXPANSION_DRIVE_DONE ",output," code=",code)
	quit(code)
