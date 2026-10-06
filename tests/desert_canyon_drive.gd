extends "res://tests/desert_curve_drive.gd"
## Finite real-input canyon traversal. Photos/diagnostic rays are not FPS samples.
const FIELD := preload("res://world/desert/DesertTerrainRelief.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
var car: CharacterBody3D
var source_start: Dictionary = {}
var wall_report: Dictionary = {}
var streaming_report: Dictionary = {}
var optional_return := "not_attempted"
var temporal: Node
var temporal_report: Dictionary = {}
var diagnostic_access := false

func _initialize() -> void:
	# Main startup + primary<=120s + optional return<=35s + walk/boarding/reload.
	create_timer(300).timeout.connect(func(): failures.append("300s complete-fixture watchdog"); _finish(3))
	_run.call_deferred()

func _run() -> void:
	if not _check(DisplayServer.get_name()!="headless" and "--no-save" in OS.get_cmdline_user_args() and "--no-traffic" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered isolated no-save/no-traffic .NET required"):
		_finish(2); return
	seed(6102026)
	diagnostic_access="--diagnostic-access" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-canyon-drive")
	source_start=_fingerprint()
	var entry := Vector3(-860,.1,-1540)
	# Production parks the initial coupe on the road nearest the saved pedestrian.
	# Load 40m east so the Bison's real admission at the canyon mouth is unoccupied.
	var arrival := entry+Vector3.RIGHT*40.0
	var snapshot := FIXTURE.full_snapshot(arrival,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[arrival.x,arrival.y,arrival.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not _check(not path.is_empty(),"isolated completed-campaign save validates"): _finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path and world.session.controller.no_save,"real Main uses only isolated save"):
		_finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not _check(world.dispatch.router._native!=null and world.production.requested_population==20,"native backend and requested population20 active"):
		_finish(1); return
	if world.session.modal: world.session.close_menu()
	_check(not world.gameplay.god_mode,"health checks run without invulnerability")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45; world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600; world.session.weather._update()
	prior_gamepad=bool(root.get_node("GameInput").using_gamepad)
	root.get_node("GameInput").using_gamepad=true
	var guide := _primary_guide()
	_check(guide.get_baked_length()>450,"authored continuous mouth-to-plateau guide exceeds450m")
	if diagnostic_access:
		guide=_guide_from_offset(guide,360.0)
		var initial_direction := guide.sample_baked(0).direction_to(guide.sample_baked(2))
		entry=_diagnostic_spawn_point(guide.sample_baked(0),atan2(-initial_direction.x,-initial_direction.z))
		print("DESERT_CANYON_DIAGNOSTIC_ONLY partial access begins at full-route360m; not full traversal validation")
	world.player.teleport(entry+Vector3.RIGHT*4)
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	for i in 30: await physics_frame
	var direction := guide.sample_baked(0).direction_to(guide.sample_baked(2))
	if diagnostic_access: _diagnostic_support_rays(entry,atan2(-direction.x,-direction.z))
	car=world.production.spawn_vehicle("desert_bison",entry,atan2(-direction.x,-direction.z))
	if not _check(is_instance_valid(car),"Bison admitted by real production spawn"): _finish(1); return
	car.vehicle_id="desert_canyon_validation_bison"
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.35+Vector3.UP*.08)
	if not await _board(): _finish(1); return
	if "--temporal" in OS.get_cmdline_user_args() and not _begin_temporal(): _finish(1); return
	var drive_ok := await _drive_path("diagnostic-access360-to-plateau" if diagnostic_access else "mouth-to-plateau",guide,120.0)
	if "--surface-diagnostic" in OS.get_cmdline_user_args():
		_stop_temporal()
		await _surface_diagnostic()
		_finish(0 if drive_ok and failures.is_empty() else 1); return
	if not drive_ok: _finish(1); return
	_check(car.global_position.y>20.0,"Bison physically climbs onto22m plateau")
	await _photo("plateau-arrival")
	if diagnostic_access:
		_stop_temporal()
		_finish(0 if failures.is_empty() else 1); return
	if not await _exit_car(): _finish(1); return
	var walking_start: Vector3=world.player.global_position
	var away_from_car := walking_start-car.global_position
	away_from_car.y=0
	if not await _walk_to(walking_start+away_from_car.normalized()*5.0,"plateau-five-metre-walk"): _finish(1); return
	await _photo("plateau-on-foot")
	if not await _walk_to(walking_start,"plateau-walk-back-to-car"): _finish(1); return
	# Optional natural U-turn uses the open landing; no transform write or snap.
	var returning := _return_guide(guide)
	if _reserved_guide(returning):
		optional_return="attempted"
		if not await _board(): _finish(1); return
		if not await _drive_path("natural-u-turn-and-first50m-return",returning,35.0): _finish(1); return
		optional_return="completed"
		await _photo("natural-return")
		if not await _exit_car(): _finish(1); return
	else:
		optional_return="not_covered: proposed turn leaves authored reserved passage"
	_stop_temporal()
	if "--birds-diagnostic" in OS.get_cmdline_user_args():
		var bird_diagnostic: Script=load("res://tests/capture/desert_birds_diagnostic.gd")
		reports.append(await bird_diagnostic.capture_existing(self,world,output))
	await _wall_probes()
	await _streaming_check()
	_finish(0 if failures.is_empty() else 1)

func _begin_temporal() -> bool:
	temporal=load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(temporal)
	# 240s cap bounds disk use while covering the <=120s drive, <=35s return,
	# ordinary boarding/exits and walking. The fixture watchdog remains300s.
	var started: bool=temporal.begin(world,world.session.desert.drag,output.path_join("sequence"),7200)
	if not _check(started,"continuous canyon temporal evidence opens a new isolated directory"): return false
	temporal.segment="canyon_drive_day"
	temporal._report["clock_control"]="Fixture fixes clear daytime0.45 through production weather updater"
	temporal._report["coverage"]="Continuous real Main daytime Bison mouth-to-plateau drive, ordinary exit, plateau walking and optional natural U-turn/partial return; recording stops before diagnostic repositions"
	temporal._report["not_covered"]=["night","full return traversal","wall-probe or streaming diagnostic repositions","performance","audible audio quality"]
	if diagnostic_access:
		temporal.segment="canyon_access_partial_diagnostic_day"
		temporal._report["coverage"]="PARTIAL DIAGNOSTIC ONLY: initial fixture placement at full-route360m, then real Bison input to plateau. Does not validate full traversal, walking or streaming."
	return true

func _guide_from_offset(original: Curve3D, offset: float) -> Curve3D:
	var result := Curve3D.new(); result.bake_interval=.25
	var distance := offset
	while distance<original.get_baked_length():
		_add_grounded(result,original.sample_baked(distance))
		distance+=2.0
	_add_grounded(result,original.sample_baked(original.get_baked_length()))
	return result

func _diagnostic_spawn_point(point: Vector3, yaw: float) -> Vector3:
	# The production body is horizontal at admission, so its entire footprint
	# must start above the uphill ground. It then settles through normal physics.
	var spec: Dictionary=preload("res://runtime/FleetCatalog.gd").spec("desert_bison")
	var dimensions: Array=spec.bounds_size
	var basis := Basis(Vector3.UP,yaw)
	var highest := -INF
	for ix in 9:
		for iz in 17:
			var corner := point+basis*Vector3(lerpf(-.5,.5,float(ix)/8.0)*float(dimensions[0]),0,lerpf(-.5,.5,float(iz)/16.0)*float(dimensions[2]))
			highest=maxf(highest,HM.surface_height(Vector2(corner.x,corner.z)))
	point.y=highest+.1
	return point

func _diagnostic_support_rays(point: Vector3, yaw: float) -> void:
	var dimensions: Array=preload("res://runtime/FleetCatalog.gd").spec("desert_bison").bounds_size
	var basis := Basis(Vector3.UP,yaw)
	var samples: Array[Dictionary]=[]
	# Exactly the existing production four support locations and ray range.
	for x in [-float(dimensions[0])*.4,float(dimensions[0])*.4]:
		for z in [-float(dimensions[2])*.4,float(dimensions[2])*.4]:
			var support: Vector3=point+basis*Vector3(x,0,z)
			var query := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1)
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
			samples.append({"position":_v3(support),"hit":not hit.is_empty(),"ground_y":float(hit.position.y) if not hit.is_empty() else null,"triangular_y":HM.surface_height(Vector2(support.x,support.z))})
	var report := {"id":"partial-diagnostic-spawn","position":_v3(point),"yaw":yaw,"catalogue_dimensions":dimensions,"support_rays":samples,"production_admission_unchanged":true}
	reports.append(report)
	print("DESERT_CANYON_DIAGNOSTIC_SPAWN ",JSON.stringify(report))

func _stop_temporal(reason := "") -> void:
	if not is_instance_valid(temporal) or not temporal_report.is_empty(): return
	if not reason.is_empty() and str(temporal.failure).is_empty(): temporal.failure=reason
	var recorded: Dictionary=temporal.stop()
	temporal_report={"path":str(temporal.output).path_join("sequence.json"),"duration_seconds":float(recorded.get("duration_seconds",0.0)),"frame_count":int(recorded.get("frame_count",0)),"skipped_rendered_frames":int(recorded.get("skipped_rendered_frames",0)),"failure":str(recorded.get("failure","")),"capture_fps_cap":30,"not_a_performance_benchmark":true}
	_check(str(temporal_report.failure).is_empty() and int(temporal_report.frame_count)>0,"continuous canyon temporal evidence closes without capture errors")

func _primary_guide() -> Curve3D:
	var result := Curve3D.new(); result.bake_interval=.25
	var access := FIELD.plateau_access(4.0)
	for p in FIELD.canyon_centerline(4.0):
		if p.z<access[0].z: break
		_add_grounded(result,p)
	for p in access: _add_grounded(result,p)
	return result

func _add_grounded(curve: Curve3D, point: Vector3) -> void:
	point.y=HM.surface_height(Vector2(point.x,point.z))
	if curve.point_count==0 or curve.get_point_position(curve.point_count-1).distance_to(point)>.05: curve.add_point(point)

func _return_guide(primary: Curve3D) -> Curve3D:
	var result := Curve3D.new(); result.bake_interval=.25
	var at: Vector3=car.global_position
	var forward := -car.global_basis.z; forward.y=0; forward=forward.normalized()
	var left := Vector3(-forward.z,0,forward.x)
	var center := at+left*8.0
	for i in 25:
		var angle := float(i)/24.0*PI
		_add_grounded(result,center-left*cos(angle)*8.0+forward*sin(angle)*8.0)
	# A short connector lies wholly on the landing, followed by50m of the actual
	# reversed access. The whole guide is validated against the reserved passage.
	var length := primary.get_baked_length()
	for distance in range(20,71,2): _add_grounded(result,primary.sample_baked(maxf(0,length-float(distance))))
	return result

func _reserved_guide(guide: Curve3D) -> bool:
	var distance := 0.0
	while distance<=guide.get_baked_length():
		var at := guide.sample_baked(distance)
		if not FIELD.passage_clear(Vector2(at.x,at.z),0): return false
		distance+=2.0
	return true

func _board() -> bool:
	if world.session.modal: world.session.close_menu()
	if not _check(world.driving.interact(),"ordinary driver boarding accepted"): return false
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	return _check(world.driving.occupied and world.driving.car==car and car.controlled and not car.external_input and not car.input_locked,"ordinary player handling owns Bison")

func _exit_car() -> bool:
	if not _check(world.driving.leave(),"ordinary parked exit accepted"): return false
	var deadline := Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	return _check(not world.driving.occupied,"ordinary exit completes without teleport")

func _drive_path(id: String, guide: Curve3D, bound_seconds: float) -> bool:
	var length := guide.get_baked_length()
	var start_health: float=car.health
	var began := Time.get_ticks_msec()
	var previous: Vector3=car.global_position
	var previous_speed := float(car.speed)
	var previous_health := float(car.health)
	var distance := 0.0
	var error_max := 0.0
	var floor_error_max := 0.0
	var ray_error_max := 0.0
	var acceleration_max := 0.0
	var uncommanded_acceleration_max := 0.0
	var off_floor := 0.0
	var longest_air := 0.0
	var missing_rays := 0
	var probe_at := 0.0
	var contacts: Array[String]=[]
	var trace: Array[Dictionary]=[]
	var faults: Array[Dictionary]=[]
	var camera_clearance_min := INF
	var camera_checks := 0
	var camera_missing := 0
	var camera_occluded := 0
	var camera_margin_failures := 0
	var near_plane_checks := 0
	var near_plane_invalid := 0
	var near_plane_margin_failures := 0
	var near_plane_clearance_min := INF
	var frames := 0
	var shot := 0
	var reached := false
	while Time.get_ticks_msec()-began<int(bound_seconds*1000):
		await physics_frame
		frames+=1
		var at: Vector3=car.global_position
		distance+=at.distance_to(previous); previous=at
		var offset := guide.get_closest_offset(at)
		var nearest := guide.sample_baked(offset)
		var error := Vector2(at.x,at.z).distance_to(Vector2(nearest.x,nearest.z))
		error_max=maxf(error_max,error)
		var height := HM.surface_height(Vector2(at.x,at.z))
		floor_error_max=maxf(floor_error_max,absf(at.y-height))
		var step := 1.0/float(Engine.physics_ticks_per_second)
		var acceleration := absf(float(car.speed)-previous_speed)/step
		var speed_before := previous_speed
		acceleration_max=maxf(acceleration_max,acceleration)
		# Service braking uses the existing V1 braking /16 model and can exceed
		# 45m/s². Keep raw telemetry; reject impulses not requested by that brake.
		var commanded_braking: bool = car.brake_input and float(car.speed)<previous_speed
		if not commanded_braking: uncommanded_acceleration_max=maxf(uncommanded_acceleration_max,acceleration)
		previous_speed=float(car.speed)
		var health_drop := previous_health-float(car.health)
		var fault := health_drop>0.0 or acceleration>45.0
		var health_before := previous_health
		previous_health=float(car.health)
		off_floor=0.0 if car.is_on_floor() else off_floor+step
		longest_air=maxf(longest_air,off_floor)
		var lookahead := maxf(4.0,absf(float(car.speed))*.8)
		var target := guide.sample_baked(minf(length,offset+lookahead))
		var forward := Vector2(-car.global_basis.z.x,-car.global_basis.z.z)
		var toward := Vector2(target.x-at.x,target.z-at.z).normalized()
		var angle := forward.angle_to(toward)
		var target_speed := 5.0 if absf(angle)>.22 else 8.0
		target_speed=minf(target_speed,maxf(1.0,(length-offset)*.65))
		var throttle := clampf((target_speed-float(car.speed))*.3,0,.75)
		_axis(clampf(angle*1.8,-1,1),throttle)
		Input.action_release("brake")
		if float(car.speed)>target_speed+1.0: Input.action_press("brake",clampf((float(car.speed)-target_speed)*.15,.1,.7))
		for i in car.get_slide_collision_count():
			var contact := car.get_slide_collision(i)
			if absf(contact.get_normal().y)<.65:
				var collider := str(contact.get_collider().get_path())
				if not contacts.has(collider): contacts.append(collider)
		if offset>=probe_at:
			var ground_hit := _ground_ray(at)
			if ground_hit.is_empty(): missing_rays+=1
			else: ray_error_max=maxf(ray_error_max,absf(float(ground_hit.position.y)-height))
			probe_at=offset+2.0
		if frames%6==0 or fault:
			var sample := {"ms":Time.get_ticks_msec()-began,"physics_frame":Engine.get_physics_frames(),"render_frame":Engine.get_frames_drawn(),"position":[at.x,at.y,at.z],"speed":car.speed,"progress":offset,"guide_error":error,"triangular_height":height,"floor":car.is_on_floor(),"health":car.health,"steer":clampf(angle*1.8,-1,1),"throttle":throttle}
			if frames%6==0 and Time.get_ticks_msec()-began>=500:
				var camera_line := _camera_terrain_clearance(at)
				sample["camera_terrain_line"]=camera_line
				if not bool(camera_line.valid_camera): camera_missing+=1
				elif int(camera_line.terrain_samples)>0:
					camera_checks+=1
					var clearance := float(camera_line.minimum_clearance)
					camera_clearance_min=minf(camera_clearance_min,clearance)
					if clearance<=0.0: camera_occluded+=1
					if clearance<.05: camera_margin_failures+=1
				var near_plane := _camera_near_plane_clearance(at)
				sample["camera_near_plane"]=near_plane
				if not bool(near_plane.valid_camera): near_plane_invalid+=1
				elif int(near_plane.terrain_samples)>0:
					near_plane_checks+=1
					var near_clearance := float(near_plane.minimum_clearance)
					near_plane_clearance_min=minf(near_plane_clearance_min,near_clearance)
					if near_clearance<.05: near_plane_margin_failures+=1
			if fault:
				sample["fault"]={"health_before":health_before,"health_drop":health_drop,"speed_before":speed_before,"acceleration_mps2":acceleration,"physics_step":step,"velocity":_v3(car.velocity),"real_velocity":_v3(car.get_real_velocity()),"yaw":car.global_rotation.y,"wall":car.is_on_wall(),"ceiling":car.is_on_ceiling(),"floor_normal":_v3(car.get_floor_normal()),"wall_normal":_v3(car.get_wall_normal()) if car.is_on_wall() else [],"contacts":_all_contacts()}
				faults.append(sample.duplicate(true))
				print("DESERT_CANYON_FAULT ",JSON.stringify(sample))
			trace.append(sample)
		if shot<4 and offset/length>=float(shot)*.32:
			await _photo(id+"-%02d"%shot); shot+=1
		if offset>=length-1.5: reached=true; break
		if at.y<height-.35 or error>7.0 or car.health<start_health-.01: break
	_release(); Input.action_press("handbrake")
	for i in 180:
		await physics_frame
		if absf(float(car.speed))<.08: break
	Input.action_release("handbrake")
	var row := {"id":id,"reached":reached,"seconds":float(Time.get_ticks_msec()-began)/1000.0,"guide_length":length,"travelled":distance,"guide_error_max":error_max,"floor_origin_error_max":floor_error_max,"ray_vs_triangle_error_max":ray_error_max,"missing_ground_rays":missing_rays,"longest_air_seconds":longest_air,"acceleration_max_mps2":acceleration_max,"obstacle_contacts":contacts,"health_before":start_health,"health_after":car.health,"trace":trace}
	row["uncommanded_acceleration_max_mps2"]=uncommanded_acceleration_max
	row["fault_snapshots"]=faults
	row["camera_terrain_visibility"]={"checked_lines":camera_checks,"missing_camera_frames":camera_missing,"minimum_clearance":camera_clearance_min if camera_checks>0 else null,"terrain_occluded_frames":camera_occluded,"below_05m_clearance_frames":camera_margin_failures,"warmup_excluded_ms":500,"physics_frame_stride":6,"line_t_samples":[.1,.2,.3,.4,.5,.6,.7,.8,.9,1.0],"scope":"Sampled eye-to-camera line against exact cached terrain triangles within FIELD.BOUNDS; no prop-shape or full-frustum occlusion claim"}
	row["camera_near_plane_visibility"]={"checked_planes":near_plane_checks,"invalid_camera_frames":near_plane_invalid,"minimum_clearance":near_plane_clearance_min if near_plane_checks>0 else null,"below_05m_clearance_frames":near_plane_margin_failures,"warmup_excluded_ms":500,"physics_frame_stride":6,"screen_uv_grid":[0.0,.25,.5,.75,1.0],"scope":"25 independent project_ray_origin samples on the real orthographic near-plane rectangle, against exact terrain triangles inside FIELD.BOUNDS only; not continuous frustum or prop occlusion coverage"}
	reports.append(row)
	var summary := row.duplicate(); summary.erase("trace")
	print("DESERT_CANYON_DRIVE_RESULT ",JSON.stringify(summary))
	var ok := _check(reached and distance>length*.8,"real analog input completes "+id)
	ok=_check(error_max<7 and missing_rays==0 and ray_error_max<.08 and floor_error_max<1.2 and longest_air<.6,"triangle heights and real body support agree: "+id) and ok
	ok=_check(contacts.is_empty() and is_equal_approx(float(car.health),start_health),"collision and health remain intact without god mode: "+id) and ok
	ok=_check(uncommanded_acceleration_max<45.0,"no uncommanded speed impulse during physical drive: "+id) and ok
	ok=_check(camera_checks>0 and camera_missing==0 and camera_occluded==0 and camera_margin_failures==0 and camera_clearance_min>=.05,"sampled car-to-camera line clears canyon terrain by at least0.05m: "+id) and ok
	ok=_check(near_plane_checks>0 and near_plane_invalid==0 and near_plane_margin_failures==0 and near_plane_clearance_min>=.05,"sampled orthographic near plane clears canyon terrain by at least0.05m: "+id) and ok
	return ok

func _camera_near_plane_clearance(car_point: Vector3) -> Dictionary:
	var camera: Camera3D=world.get_viewport().get_camera_3d()
	if not is_instance_valid(camera) or camera.projection!=Camera3D.PROJECTION_ORTHOGONAL:
		return {"valid_camera":false,"terrain_samples":0}
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x<=0 or viewport_size.y<=0: return {"valid_camera":false,"terrain_samples":0}
	var minimum := INF
	var samples: Array[Dictionary]=[]
	for row in 5:
		for column in 5:
			var uv := Vector2(float(column)/4.0,float(row)/4.0)
			var point := camera.project_ray_origin(uv*viewport_size)
			var horizontal := Vector2(point.x,point.z)
			var inside := FIELD.BOUNDS.has_point(horizontal)
			var sample := {"uv":[uv.x,uv.y],"position":_v3(point),"inside_terrain_bounds":inside}
			if inside:
				var terrain := HM.surface_height(horizontal)
				var clearance := point.y-terrain
				minimum=minf(minimum,clearance)
				sample["triangular_height"]=terrain
				sample["clearance"]=clearance
			samples.append(sample)
	var terrain_samples := 0
	for sample in samples:
		if bool(sample.inside_terrain_bounds): terrain_samples+=1
	var result := {"valid_camera":true,"camera_path":str(camera.get_path()),"camera_position":_v3(camera.global_position),"pitch_degrees":rad_to_deg(asin(clampf(camera.global_basis.z.normalized().y,-1.0,1.0))),"distance_to_car":camera.global_position.distance_to(car_point),"orthographic_size":camera.size,"near":camera.near,"viewport_size":[viewport_size.x,viewport_size.y],"terrain_samples":terrain_samples,"minimum_clearance":minimum if terrain_samples>0 else null,"samples":samples}
	# Optional helper telemetry explains adjustments; it never supplies the oracle.
	var helper: Variant=camera.get("_desert_terrain_camera")
	if is_instance_valid(helper) and helper.has_method("diagnostics"):
		result["helper_diagnostics"]=helper.call("diagnostics")
	return result

func _camera_terrain_clearance(car_point: Vector3) -> Dictionary:
	var camera: Camera3D=world.get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return {"valid_camera":false,"terrain_samples":0}
	var eye := car_point+Vector3.UP*1.3
	var camera_point := camera.global_position
	var minimum := INF
	var samples: Array[Dictionary]=[]
	for i in range(1,11):
		var t := float(i)*.1
		var point := eye.lerp(camera_point,t)
		var horizontal := Vector2(point.x,point.z)
		if not FIELD.BOUNDS.has_point(horizontal): continue
		var terrain := HM.surface_height(horizontal)
		var clearance := point.y-terrain
		minimum=minf(minimum,clearance)
		samples.append({"t":t,"position":_v3(point),"triangular_height":terrain,"clearance":clearance})
	return {"valid_camera":true,"camera_path":str(camera.get_path()),"eye":_v3(eye),"camera_position":_v3(camera_point),"terrain_samples":samples.size(),"minimum_clearance":minimum if not samples.is_empty() else null,"samples":samples}

func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _all_contacts() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for slide in car.get_slide_collision_count():
		var hit := car.get_slide_collision(slide)
		for index in hit.get_collision_count():
			var collider: Object=hit.get_collider(index)
			var normal := hit.get_normal(index)
			result.append({"slide":slide,"contact":index,"collider":str(collider.get_path()) if collider is Node else str(collider),"collider_id":hit.get_collider_id(index),"collider_shape":hit.get_collider_shape(index),"local_shape":hit.get_local_shape(index),"position":_v3(hit.get_position(index)),"normal":_v3(normal),"angle_from_up_degrees":rad_to_deg(normal.angle_to(Vector3.UP)),"lateral_by_existing_check":absf(normal.y)<.65,"travel":_v3(hit.get_travel()),"remainder":_v3(hit.get_remainder()),"depth":hit.get_depth()})
	return result

func _walk_to(target: Vector3, id: String) -> bool:
	var deadline := Time.get_ticks_msec()+9000
	var start_health: float=world.gameplay.health
	var reached := false
	var error_max := 0.0
	while Time.get_ticks_msec()<deadline:
		var at: Vector3=world.player.global_position
		error_max=maxf(error_max,absf(at.y-HM.surface_height(Vector2(at.x,at.z))))
		var delta := Vector3(target.x-at.x,0,target.z-at.z)
		if delta.length()<.25: reached=true; break
		world.player.automatic_direction=delta.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	reports.append({"id":id,"reached":reached,"floor_error_max":error_max,"position":str(world.player.global_position),"health_before":start_health,"health_after":world.gameplay.health})
	return _check(reached and error_max<.3 and world.player.is_on_floor() and is_equal_approx(float(world.gameplay.health),start_health),"real Actor walks supported on plateau: "+id)

func _ground_ray(point: Vector3, radius := 2.0) -> Dictionary:
	var height := HM.surface_height(Vector2(point.x,point.z))
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,height+radius,point.z),Vector3(point.x,height-4,point.z),1)
	query.exclude=[car.get_rid(),world.player.get_rid()]
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func _surface_diagnostic() -> void:
	# Explicit fixed-pose diagnostic AFTER the physical assertions. Not traversal evidence.
	car.set_physics_process(false)
	car.global_position=Vector3(-1048,HM.surface_height(Vector2(-1048,-1809))+.32,-1809)
	world.camera.initialized=false
	await create_timer(1).timeout
	var terrain := world.find_child("DesertCanyonTerrain",true,false)
	await _photo("surface-fixed-normal")
	var old_casting: Dictionary={}
	for child in terrain.get_children():
		if child is MeshInstance3D:
			old_casting[child]=child.cast_shadow
			child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await create_timer(.15).timeout
	await _photo("surface-fixed-no-canyon-shadow-diagnostic")
	for mesh in old_casting: mesh.cast_shadow=old_casting[mesh]
	var old_materials: Dictionary={}
	var plain := StandardMaterial3D.new()
	plain.albedo_color=Color("9f7d56")
	plain.roughness=1.0
	for mesh in old_casting:
		old_materials[mesh]=mesh.material_override
		mesh.material_override=plain
	await create_timer(.15).timeout
	await _photo("surface-fixed-plain-lit-diagnostic")
	plain.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	await create_timer(.15).timeout
	await _photo("surface-fixed-plain-unshaded-diagnostic")
	for mesh in old_materials: mesh.material_override=old_materials[mesh]
	reports.append({"id":"surface_shadow_diagnostic","fixed_pose_after_drive":true,"same_camera_and_light":true,"only_canyon_shadow_casting_temporarily_disabled":true,"production_shadow_setting_restored":true,"not_traversal_or_performance_evidence":true})

func _wall_probes() -> void:
	# Diagnostic placement is explicitly AFTER the physical drive/walk. It cannot
	# substitute for any travelled route or the optional return above.
	var floor_point := Vector3(-850,HM.surface_height(Vector2(-850,-1740))+.08,-1740)
	world.player.teleport(floor_point)
	world.production.region.set_focus(floor_point)
	for x in range(-850,-737,2): world.production.region.prepare_collision_at(Vector3(float(x),0,-1740))
	for i in 8: await physics_frame
	var checked := 0
	var maximum_error := 0.0
	var normal_min_y := 1.0
	var skipped_props: Array[String]=[]
	for x in range(-850,-737,2):
		var p := Vector3(float(x),0,-1740)
		var hit := _ground_ray(p)
		if hit.is_empty(): continue
		if str(hit.collider.name)!="CanyonGroundCollider": skipped_props.append(str(hit.collider.name)); continue
		checked+=1
		maximum_error=maxf(maximum_error,absf(float(hit.position.y)-HM.surface_height(Vector2(p.x,p.z))))
		normal_min_y=minf(normal_min_y,float(hit.normal.y))
	var cross := PhysicsRayQueryParameters3D.create(floor_point+Vector3.UP*8,floor_point+Vector3.RIGHT*112+Vector3.UP*8,1)
	cross.exclude=[world.player.get_rid(),car.get_rid()]
	var wall_hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(cross)
	wall_report={"samples_every_m":2,"checked_terrain_rays":checked,"height_error_max":maximum_error,"normal_min_y":normal_min_y,"skipped_prop_hits":skipped_props,"side_ray_hit":not wall_hit.is_empty(),"side_hit":str(wall_hit.position) if not wall_hit.is_empty() else "none"}
	_check(checked>=30 and maximum_error<.08 and normal_min_y<.98,"2m wall profile matches exact rendered/collision triangles including slopes")
	_check(not wall_hit.is_empty() and str(wall_hit.collider.name)=="CanyonGroundCollider","side ray is physically stopped by rising canyon terrain")
	await _photo("canyon-wall-diagnostic-after-drive")

func _chunk_snapshot(point: Vector3) -> Dictionary:
	var key := Vector2i(floori(point.x/HM.CELL),floori(point.z/HM.CELL))
	var region=world.production.region
	if not region.chunks.has(key): return {}
	var chunk: Node3D=region.chunks[key]
	var body := chunk.find_child("CanyonGroundCollider",true,false)
	if body==null or body.get_child_count()==0: return {}
	var shape: CollisionShape3D=body.get_child(0)
	var terrain_shape: ConcavePolygonShape3D=shape.shape
	if terrain_shape==null: return {}
	var faces: PackedVector3Array=terrain_shape.get_faces()
	var vertices: PackedVector3Array=HM.mesh_for(key).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(var_to_bytes(faces))
	var hit := _ground_ray(point)
	return {"key":str(key),"node_id":chunk.get_instance_id(),"vertex_hash":hash.finish().hex_encode(),"render_collision_vertices_equal":faces==vertices,"height":float(hit.position.y) if not hit.is_empty() else -999.0}

func _streaming_check() -> void:
	var point := Vector3(-850,HM.surface_height(Vector2(-850,-1740))+.08,-1740)
	world.player.teleport(point)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	for i in 8: await physics_frame
	var before := _chunk_snapshot(point)
	if not _check(not before.is_empty(),"streaming audit captures actual canyon collider chunk"): return
	var far := Vector3(-100,.08,-880)
	world.player.teleport(far)
	world.production.region.set_focus(far)
	world.production.region.prepare_collision_at(far)
	for i in 30: await physics_frame
	var old_freed := not is_instance_id_valid(int(before.node_id))
	world.player.teleport(point)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	for i in 12: await physics_frame
	var after := _chunk_snapshot(point)
	streaming_report={"before":before,"after":after,"old_chunk_freed":old_freed,"fixture_repositions_only":true,"not_a_full_return_traversal":true}
	_check(old_freed and not after.is_empty() and before.node_id!=after.node_id,"distant focus frees old collision chunk and return creates a new node")
	if not after.is_empty():
		_check(before.vertex_hash==after.vertex_hash and before.render_collision_vertices_equal and after.render_collision_vertices_equal and absf(float(before.height)-float(after.height))<.01,"streamed render/collision vertices and floor heights remain identical")

func _fingerprint(reference: Dictionary = {}) -> Dictionary:
	var result: Dictionary={}
	if not reference.is_empty():
		for path in reference: result[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
		return result
	for directory in ["res://world/desert","res://gameplay/desert_cars","res://runtime/desert"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
				var path: String=directory+"/"+filename
				result[path]=FileAccess.get_sha256(path)
	for path in ["res://scripts/CameraRig.gd","res://scripts/Vehicle.gd","res://scripts/Driving.gd","res://runtime/ProductionWorld.gd","res://runtime/FullSession.gd","res://tests/capture/DesertDragTemporalCapture.gd",get_script().resource_path]: result[path]=FileAccess.get_sha256(path)
	return result

func _finish(code: int) -> void:
	_release()
	_stop_temporal("Canyon fixture stopped with code%d"%code if code!=0 else "")
	if is_instance_valid(root.get_node_or_null("GameInput")): root.get_node("GameInput").using_gamepad=prior_gamepad
	if is_instance_valid(world) and is_instance_valid(world.get("player")): world.player.automatic_direction=Vector3.ZERO
	var source_end := _fingerprint(source_start)
	if not source_start.is_empty() and source_start!=source_end: failures.append("Source changed during canyon physical validation")
	if not failures.is_empty() and code==0: code=1
	if not output.is_empty():
		var report := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"scenarios":reports,"wall_profile":wall_report,"streaming":streaming_report,"optional_return":optional_return,"source_sha256_start":source_start,"source_sha256_end":source_end,"source_stable":source_start==source_end,"scope":"Main .NET real Bison analog input and Actor walking; no pose edits after each drive begins, no god mode. Subsequent wall/streaming diagnostic placements are explicitly not route traversal. Screenshots and ray instrumentation invalidate FPS use. No global collision certification."}
		report["temporal"]=temporal_report
		report["diagnostic_access_only"]=diagnostic_access
		report["full_traversal_validated"]=not diagnostic_access and code==0
		if diagnostic_access: report["scope"]="PARTIAL DIAGNOSTIC ONLY: fixture initially placed at full-route360m, real Bison input to plateau. No full-route, walking or streaming approval. Original physical assertions/tolerances retained."
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_CANYON_DRIVE_DONE ",output," code=",code)
	quit(code)
