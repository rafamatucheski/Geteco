extends SceneTree
## Real Main/.NET with isolated saves. Checkpoint fixtures stage the final
## document event; they do not claim a full playthrough of the campaign.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const POLICY := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const FAR_FIXTURE := Vector3(403.125,.1,-21.875) # Authored northbank road, outside site release but inside connection retention.
var world
var checks := 0
var failures: Array[String] = []
var output := ""
var fingerprint_started: Dictionary = {}

func _initialize() -> void:
	create_timer(330).timeout.connect(func(): push_error("NORTH_GATEWAY bounded integration timeout"); quit(3))
	run.call_deferred()

func frames(count: int) -> void:
	for index in count: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	print("NORTH_GATEWAY ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or POLICY.baseline_disabled():
		push_error("Integration requires --no-save and the installed gateway (no baseline flag).")
		quit(2)
		return
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Use the compiled .NET game; the GDScript fallback does not validate integration.")
		quit(2)
		return
	seed(5102026)
	fingerprint_started = FIXTURE.source_fingerprint()
	output = FIXTURE.output_dir("north-gateway-integration")
	var initial := LAYOUT.APPROACH+Vector3(2.1,.12,0)
	var save_path := FIXTURE.write_fixture(output,"before-document.json",FIXTURE.full_snapshot(initial))
	check(not save_path.is_empty(),"valid isolated checkpoint created without touching player save")
	if save_path.is_empty(): finish(); return
	if not await boot(save_path): finish(); return
	var gateway = get_first_node_in_group("north_gateway")
	check(is_instance_valid(gateway),"WorldConnection installs the production gateway")
	if not is_instance_valid(gateway): finish(); return
	gateway.reconcile()
	await frames(4)
	check(gateway.is_mounted() and not gateway.completed,"nearby unfinished mission mounts construction")
	check(is_instance_valid(gateway.workers),"unfinished bridge has its authored workers")
	if not gateway.is_mounted(): finish(); return
	check(is_instance_valid(gateway.workers) and gateway.workers._workers.size()==4,"all four authored worker bodies are mounted")
	await check_streaming(gateway,initial,false)
	var gate: Transform3D = LAYOUT.gate_transform()
	var full_roads: Array = FIXTURE.graph_snapshot(world.production.traffic_routes)
	var ambient_roads: Array = FIXTURE.graph_snapshot(world.production.ambient_traffic_routes)
	var forbidden := Rect2(gate.origin.x-LAYOUT.GATE_WIDTH*.5,gate.origin.z-20,LAYOUT.GATE_WIDTH,22)
	check(FIXTURE.route_keeps_outside(world.production.traffic_routes,forbidden),"mission/full routes never enter construction")
	check(FIXTURE.route_keeps_outside(world.production.ambient_traffic_routes,forbidden),"ambient routes never enter construction")
	check(world.dispatch.routes==world.production.traffic_routes and world.dispatch.router.routes==world.production.traffic_routes,"dispatch reads the same protected production graph")
	var route: Dictionary = world.dispatch.router.plan(Vector3(382.5,0,-200),Vector3(440,0,-281.3),Vector3.FORWARD)
	check(route.get("ok",false),"directed dispatch route to east mountain exit remains available")
	check(world.dispatch.router._native!=null,"actual .NET road search ran; fallback cannot pass")
	var east_from := Vector3(410,.8,-281.9)
	var east_to := Vector3(444,.8,-282.85)
	check(ray(east_from,east_to).is_empty(),"east mountain exit has no north-gateway barrier")
	check(not ray(gate.origin+Vector3(0,.8,3),gate.origin+Vector3(0,.8,-3)).is_empty(),"closed gateway has real solid barrier")
	# Follow the authored access through the real shoreline opening. No actor
	# placement or progress substitution occurs during either walking attempt.
	var walked := await walk_to(gate.origin+Vector3(0,0,3),20.0,true)
	check(walked,"player physically reaches the works through the curved access")
	var blocked_from: Vector3 = world.player.global_position
	await walk_to(gate.origin+Vector3(0,0,-5),4.0,false)
	check(world.player.global_position.z>gate.origin.z+.25 and world.player.global_position.distance_to(blocked_from)>1.0,"real actor approaches barrier and cannot cross")
	world.player.automatic_direction = Vector3.ZERO
	# Independent car fixture starts before its physical attempt. The player
	# stands beside the carriageway so it cannot be the obstacle under test.
	world.player.teleport(gate.origin+Vector3(6,.1,7))
	await frames(3)
	var car = world.production.spawn_vehicle("sport_coupe",gate.origin+Vector3(0,.08,11),0.0)
	check(is_instance_valid(car),"real physical vehicle fixture spawned")
	if is_instance_valid(car):
		car.set_meta("race_owned",true)
		car.set_external_driver(true)
		var car_start: Vector3 = car.global_position
		for index in 300:
			car.throttle_input = 1.0 if car.speed<6.0 else 0.0
			car.steer_input = 0.0
			car.brake_input = false
			await physics_frame
		car.set_external_driver(false)
		check(car.global_position.distance_to(car_start)>2.0 and car.global_position.z>gate.origin.z+.5,"real vehicle moves under throttle and stops before the closed works")
		car.queue_free()
		await frames(3)
	var accepted: Dictionary = FIXTURE.final_event(world.session.state.campaign)
	check(accepted.ok,"real final document event accepted by live campaign")
	# Wait for the production poll instead of assigning completed or rebuilding
	# scenery from the test; this verifies completion while the world stays open.
	await create_timer(.6).timeout
	await frames(3)
	check(gateway.completed,"live campaign completion automatically finishes construction")
	check(not is_instance_valid(gateway.workers),"workers are released when construction finishes")
	check(ray(gate.origin+Vector3(0,.8,3),gate.origin+Vector3(0,.8,-3)).is_empty(),"completed bridge removes physical work barrier")
	check(FIXTURE.graph_snapshot(world.production.traffic_routes)==full_roads and FIXTURE.graph_snapshot(world.production.ambient_traffic_routes)==ambient_roads,"completion preserves existing traffic graphs and east access")
	check(world.session.state.region_id=="harbor","gateway does not claim to travel to an unimplemented map 2")
	check_completed_support()
	world.player.teleport(gate.origin+Vector3(0,.1,5))
	await frames(3)
	check(await walk_to(LAYOUT.TERMINAL,35.0,false),"real actor crosses completed span and reaches safe terminal")
	check(world.player.global_position.y>LAYOUT.DECK_HEIGHT-.35,"no fall or world-boundary rescue during crossing")
	var terminal_hit := ray(Vector3(LAYOUT.TERMINAL.x,LAYOUT.DECK_HEIGHT+.8,LAYOUT.END_Z+2),Vector3(LAYOUT.TERMINAL.x,LAYOUT.DECK_HEIGHT+.8,LAYOUT.END_Z-2))
	check(not terminal_hit.is_empty(),"unfinished destination has permanent solid terminal protection")
	var mounted_id: int = gateway.scenery.get_instance_id()
	for index in 10: gateway.reconcile()
	check(gateway.scenery.get_instance_id()==mounted_id and get_nodes_in_group("north_gateway").size()==1,"repeated reconcile does not duplicate scenery or controllers")
	await check_streaming(gateway,LAYOUT.TERMINAL+Vector3(0,.1,0),true)
	# Explicit save is restricted to the verified fixture path even though normal
	# gameplay autosaving is disabled. It checks the actual live completion ledger.
	check(world.production.store.save(world.session.state)==OK,"live completion can be saved into isolated fixture")
	var persisted: Dictionary = STORE.read_valid(save_path)
	check(not persisted.is_empty() and POLICY.campaign_completed(persisted.get("campaign",{})),"saved live completion retains authoritative unlock")
	world.free()
	world = null
	await frames(3)
	var old_path := FIXTURE.write_fixture(output,"legacy-completed.json",FIXTURE.full_snapshot(initial,true,true))
	check(not old_path.is_empty(),"genuine version-1 completed save fixture validated")
	if not old_path.is_empty() and await boot(old_path):
		var restored = get_first_node_in_group("north_gateway")
		check(is_instance_valid(restored),"restoring old save installs production gateway")
		if is_instance_valid(restored):
			restored.reconcile()
			await frames(3)
			check(restored.completed and restored.is_mounted(),"old legitimate completed save restores finished bridge")
			check(not is_instance_valid(restored.workers),"old completed save does not recreate construction workers")
	finish()

func boot(path: String) -> bool:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for index in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"real Main session ready")
	if world.session==null or not world.session.ready_for_play: return false
	check(world.production.no_save and world.production.loaded_save and not world.production.save_invalid and world.production.store.path==path,"actual isolated SaveStore loaded; default player save unused")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	await frames(30)
	return failures.is_empty()

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,1)
	query.exclude = [world.player.get_rid()]
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func walk_to(target: Vector3, seconds: float, follow_access: bool) -> bool:
	var offsets := PackedVector3Array()
	if follow_access:
		for index in range(1,ceili(LAYOUT.length()/2.0)):
			var point: Vector3 = LAYOUT.sample(float(index)*2.0)
			if point.z<target.z: break
			offsets.append(point)
	offsets.append(target)
	var waypoint := 0
	for index in ceili(seconds*float(Engine.physics_ticks_per_second)):
		var delta: Vector3 = offsets[waypoint]-world.player.global_position
		delta.y = 0
		if delta.length()<.65:
			waypoint += 1
			if waypoint==offsets.size():
				world.player.automatic_direction = Vector3.ZERO
				return true
			continue
		world.player.automatic_direction = delta.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false

func check_completed_support() -> void:
	var unsupported := []
	for index in ceili(LAYOUT.length()/2.0)+1:
		var distance := minf(float(index)*2.0,LAYOUT.length()-.8)
		var point: Vector3 = LAYOUT.sample(distance)
		var forward: Vector3 = (LAYOUT.sample(minf(distance+.5,LAYOUT.length()))-LAYOUT.sample(maxf(distance-.5,0.0))).normalized()
		var side: Vector3 = forward.cross(Vector3.UP).normalized()
		for offset in [-LAYOUT.deck_half_width_at(distance)+1.0,0.0,LAYOUT.deck_half_width_at(distance)-1.0]:
			var position: Vector3 = point+side*offset
			var hit := ray(position+Vector3.UP*1.2,position-Vector3.UP*.7)
			if hit.is_empty() or hit.normal.y<.8: unsupported.append(position)
	check(unsupported.is_empty(),"finished bridge supports center and usable deck edges at 2m intervals: "+str(unsupported))

func check_streaming(gateway, return_point: Vector3, with_parked_car: bool) -> void:
	# Fixture relocation exercises residency in the real world, separately from
	# the walking/driving attempts. This road is within WorldConnection's 320m
	# retention; only the gateway's own 210m release should unload scenery.
	var old_scenery = gateway.scenery
	var old_workers = gateway.workers
	var parked
	if with_parked_car:
		parked = world.production.spawn_vehicle("sport_coupe",LAYOUT.TERMINAL+Vector3(4,.08,0),0.0)
		check(is_instance_valid(parked),"persistent parked-car fixture spawned on bridge")
		if is_instance_valid(parked):
			parked.set_meta("garage_reward",true)
			parked.input_locked = true
	world.production.region.prepare_collision_at(FAR_FIXTURE)
	world.player.teleport(FAR_FIXTURE)
	gateway.reconcile()
	await frames(6)
	if is_instance_valid(parked):
		check(gateway.is_mounted() and parked.is_physics_processing(),"active persistent parked car retains distant bridge support")
		check(parked.global_position.y>LAYOUT.DECK_HEIGHT-.35,"parked car stays on deck while player is distant")
		parked.queue_free()
		await frames(3)
		gateway.reconcile()
		await frames(3)
	check(not gateway.is_mounted() and not is_instance_valid(old_scenery) and not is_instance_valid(old_workers),"distant empty gateway releases its scenery and workers")
	if with_parked_car:
		# Spawn through production while the distant bridge is unloaded. This
		# normally enters awaiting_ground; no test callback manufactures support.
		var suspended = world.production.spawn_vehicle("sport_coupe",LAYOUT.TERMINAL+Vector3(4,.08,0),0.0)
		check(is_instance_valid(suspended),"distant production spawn creates a streaming-suspended car")
		if is_instance_valid(suspended):
			suspended.set_meta("garage_reward",true)
			suspended.input_locked = true
			check(suspended.has_meta("awaiting_ground") and not suspended.is_physics_processing(),"missing deck suspends real car physics pending ground")
			gateway.reconcile()
			check(gateway.is_mounted(),"awaiting_ground car remounts bridge even with distant player")
			await frames(60)
			check(suspended.is_physics_processing() and not suspended.has_meta("awaiting_ground") and suspended.global_position.y>LAYOUT.DECK_HEIGHT-.35,"production resumes suspended car over restored bridge floor")
			suspended.queue_free()
			await frames(3)
			gateway.reconcile()
			await frames(3)
			check(not gateway.is_mounted(),"removing restored parked car permits cleanup again")
	world.production.region.prepare_collision_at(return_point)
	world.player.teleport(return_point)
	gateway.reconcile()
	await frames(6)
	check(gateway.is_mounted() and gateway.completed==with_parked_car,"reapproach remounts the authoritative construction state")
	check(get_nodes_in_group("north_gateway").size()==1,"streaming does not duplicate gateway controllers")
	check(is_instance_valid(gateway.workers)!=with_parked_car,"streaming restores workers only before completion")

func finish() -> void:
	if is_instance_valid(world): world.player.automatic_direction = Vector3.ZERO
	var fingerprint_ended := FIXTURE.source_fingerprint()
	check(fingerprint_started==fingerprint_ended,"source files remained unchanged during integration")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"source_sha256_start":fingerprint_started,"source_sha256_end":fingerprint_ended,"args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args(),"cpu":OS.get_processor_name(),"os":OS.get_name(),"os_version":OS.get_version(),"engine":Engine.get_version_info().string,"scope":"Real Main/.NET with explicit checkpoint and streaming-position fixtures. Physical actor/car attempts use real movement. No full-campaign playthrough, rendered visual or FPS claim."},"\t"))
			file.close()
	print("NORTH_GATEWAY_INTEGRATION checks=%d failures=%d evidence=%s"%[checks,failures.size(),output])
	quit(0 if failures.is_empty() else 1)
