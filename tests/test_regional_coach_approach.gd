extends SceneTree
## Local reproduction of the last 57 m into the ice station. Staging is explicit;
## after admission, the real regional controller owns every movement and actor.
const F := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ROUTES := preload("res://runtime/regional/RegionalCoachRoute.gd")
const COACH := preload("res://runtime/regional/RegionalCoach.gd")
var world
var folder := ""
var staged := 1170.0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240).timeout.connect(func(): push_error("COACH_APPROACH timeout"); quit(3))
	seed(28092026)
	folder=F.output_dir("regional-coach-approach")
	# Begin in Harbor so the player's parked car stays at the genuine origin.
	# Starting the checkpoint beside the approach would park it on this route.
	var snapshot := F.full_snapshot(Vector3(135,.12,72),true)
	snapshot.campaign.aftermath={"call_complete":true}
	var save_path := F.write_fixture(folder,"save.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",save_path)
	root.add_child(world); current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	var plan := ROUTES.plan(world.production,"harbor","mountain")
	if not plan.get("ok",false): push_error(str(plan)); quit(1); return
	var road: Curve3D=plan.curve
	var point := road.sample_baked(staged,true)
	var direction := road.sample_baked(staged+1,true)-point
	world.production._mount_region("mountain",point)
	world.player.teleport(point+Vector3.UP*.12)
	world.production._update_physical_residency(point)
	for region in world.production.regions.values(): region.prepare_collision_at(point)
	for frame in 6: await physics_frame
	var service=world.session.regional_coach
	service._snapshot_passenger()
	service.origin_id="harbor"; service.destination_id="mountain"
	service._road=road; service.route_length=road.get_baked_length()
	world.player.input_locked=true; world.player.collision_layer=0; world.player.collision_mask=0
	world.player.set_physics_process(false)
	service.train=COACH.new()
	service.train.position=point+Vector3.UP*.12
	service.train.rotation.y=atan2(-direction.x,-direction.z)
	world.add_child(service.train)
	service.train.set_service_route(road)
	service.train.route_distance=staged
	service.train.seat_player(world.player)
	world.camera.set_process(false); world.camera.locked=true
	service._set_passenger_depth(true)
	service.camera_mode=1
	service.riding=true
	service._update_train_pose()
	Engine.time_scale=4; Engine.physics_ticks_per_second=240
	var began := Time.get_ticks_msec()
	var next_report := began
	while service.riding and Time.get_ticks_msec()-began<65000:
		await process_frame
		if is_instance_valid(service.train) and Time.get_ticks_msec()>next_report:
			next_report=Time.get_ticks_msec()+5000
			_dump(service.train)
		if service._stalled_seconds>60:
			_dump(service.train)
			await photo("blocked")
			break
	var passed: bool=not service.riding and world.session.state.region_id=="mountain"
	print("COACH_APPROACH_RESULT reached_station=",passed," folder=",folder)
	if not passed: await photo("final")
	world.free(); await process_frame
	quit(0 if passed else 1)
func _dump(car) -> void:
	var record := _body(car)
	record.blocker=_body(car.blocker) if is_instance_valid(car.blocker) else {}
	record.contacts=[]
	for index in car.get_slide_collision_count():
		var hit=car.get_slide_collision(index)
		record.contacts.append({"body":str(hit.get_collider()),"normal":str(hit.get_normal()),"point":str(hit.get_position())})
	record.junctions=[]
	for junction in car._junction_list:
		if absf(float(junction.offset)-car.route_distance)<30: record.junctions.append(junction)
	record.neighbors=[]
	for other in world.production.vehicles:
		if is_instance_valid(other) and other.global_position.distance_to(car.global_position)<25: record.neighbors.append(_body(other))
	print("COACH_APPROACH_TRACE ",JSON.stringify(record))
func _body(body) -> Dictionary:
	if not is_instance_valid(body): return {}
	var result := {"path":str(body.get_path()),"script":str(body.get_script().resource_path) if body.get_script()!=null else "","point":str(body.global_position),"heading":str(-body.global_basis.z)}
	for key in ["archetype","traffic","speed","blocked","blocked_time","stall_time","route_distance","junction_wait","backoff_time","bypass_side","bypass_blend","_merging_back","health","automatic_direction","controlled_automatically"]:
		if key in body: result[key]=body.get(key)
	return result
func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
