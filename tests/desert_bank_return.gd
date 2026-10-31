extends SceneTree
## Reproduz a rota medida no Main e inspeciona todos os bloqueios reais da volta sem removê-los.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world
var output := ""
var observations: Array[Dictionary]=[]
var desired := Vector3.ZERO
var blocked_return := false
var blocker: CharacterBody3D
var blocker_parked_at := Vector3.ZERO
var blocked_setup_valid := false

func _initialize() -> void:
	blocked_return="--blocked-return" in OS.get_cmdline_user_args()
	create_timer(210).timeout.connect(func(): _finish(false,"timeout"))
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with --benchmark --no-save required")
		quit(2)
		return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-bank-return")
	var snapshot := FIXTURE.full_snapshot(Vector3(300,.08,-742),true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[300,.08,-742]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): _finish(false,"fixture_invalid"); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid:
		_finish(false,"main_startup_failed"); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: _finish(false,"native_backend_missing"); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	# O modo de diagnóstico preserva o benchmark; a obstrução controlada pula o preâmbulo.
	var preamble: Array=[] if blocked_return else [{"point":Vector3(300,.08,-742),"hour":.45},{"point":Vector3(-185,.08,-890),"hour":.9}]
	for setup in preamble:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		await physics_frame
		world.player.teleport(setup.point)
		world.session.weather.time_of_day=setup.hour
		world.session.weather._update()
		await create_timer(40).timeout
	var definition := PLACES.get_definition("desert_bank")
	desired=definition.return_position
	world.production.region.set_focus(definition.entry_position)
	world.production.region.prepare_collision_at(definition.entry_position)
	if blocked_return:
		# Mantém o streaming vivo no destino enquanto admite um carro comum estacionado.
		world.player.teleport(Vector3(-215,.08,-905))
		for i in 240:
			await physics_frame
			if world.production.region.is_streaming_idle(): break
		await physics_frame
		blocker=world.production.spawn_vehicle("desert_coyote",Vector3(-210,.12,-909.85),0.0)
		if not is_instance_valid(blocker): _finish(false,"legal_blocker_spawn_rejected"); return
		blocker.input_locked=true
		blocker.speed=0.0
		await create_timer(2).timeout
		blocker_parked_at=blocker.global_position
		_observe("parked_car_admitted")
		var covered := 0
		for candidate in observations.back().candidates:
			for hit in candidate.blockers:
				if int(hit.instance_id)==blocker.get_instance_id(): covered+=1; break
		blocked_setup_valid=covered==5 and blocker.is_on_floor() and blocker.is_physics_processing() and not blocker.get_meta("awaiting_ground",false)
		if not blocked_setup_valid: _finish(false,"parked_car_does_not_block_all_five_candidates"); return
	await physics_frame
	var entry: Vector3=definition.entry_position+Vector3.UP*.08
	if blocked_return:
		# Admite o Dante perto da porta real, nunca dentro do carro posto na frente dela.
		entry=Vector3.INF
		for offset: Vector3 in [Vector3(0,0,-.9),Vector3(1.2,0,-.6),Vector3(-1.2,0,-.6),Vector3(1.4,0,0),Vector3(-1.4,0,0)]:
			var candidate: Vector3=definition.entry_position+offset+Vector3.UP*.08
			if world.session.position_clear(candidate) and candidate.distance_to(definition.entry_position)<1.5:
				entry=candidate
				break
		if not entry.is_finite(): _finish(false,"no_legal_player_admission_near_doorway"); return
	world.player.teleport(entry)
	_observe("before_entry")
	if not await world.session.enter_place("desert_bank",false):
		_observe("entry_failed")
		_finish(false,"entry_failed"); return
	desired=world.session.return_point
	_observe("interior_0s")
	for seconds in range(5,6 if blocked_return else 41,5):
		await create_timer(5).timeout
		_observe("interior_%ds"%seconds)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("before-return.png"))
	var left: bool=await world.session.leave_place()
	_observe("after_leave_attempt")
	await physics_frame
	var safe_return: bool=left and world.session.state.place_id.is_empty() and world.session.position_clear(world.player.global_position)
	if blocked_return:
		safe_return=safe_return and is_instance_valid(blocker) and Vector2(blocker.global_position.x,blocker.global_position.z).distance_to(Vector2(blocker_parked_at.x,blocker_parked_at.z))<.12
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("after-return.png"))
	_finish(safe_return,"returned_clear_of_parked_car" if safe_return and blocked_return else ("returned" if safe_return else ("unsafe_return" if left else "leave_place_false")))

func _observe(label: String) -> void:
	var session=world.session
	var offsets := [Vector3.ZERO,Vector3(0,0,.75),Vector3(0,0,1.5),Vector3(-.8,0,.75),Vector3(.8,0,.75)]
	var candidates: Array[Dictionary]=[]
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	for offset: Vector3 in offsets:
		var point := desired+offset+Vector3.UP*.08
		var capsule := CapsuleShape3D.new()
		capsule.radius=.32
		capsule.height=1.7
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.collision_mask=7
		query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.9)
		query.exclude=[world.player.get_rid()]
		var blockers: Array[Dictionary]=[]
		for hit in space.intersect_shape(query,32): blockers.append(_body(hit.collider))
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.5,1))
		var floor_info: Dictionary={}
		if not floor_hit.is_empty():
			floor_info=_body(floor_hit.collider)
			floor_info.hit_position=str(floor_hit.position)
		candidates.append({"point":str(point),"position_clear":session.position_clear(point),"blockers":blockers,"floor":floor_info})
	var vehicles: Array[Dictionary]=[]
	for car in world.production.vehicles:
		if not is_instance_valid(car) or car.global_position.distance_to(desired)>12: continue
		var detail := _body(car)
		detail.velocity=str(car.velocity)
		detail.vehicle_id=str(car.vehicle_id)
		vehicles.append(detail)
	var region=world.production.region
	observations.append({"label":label,"ticks_msec":Time.get_ticks_msec(),"place":session.state.place_id,"player":str(world.player.global_position),"desired":str(desired),"return_point":str(session.return_point),"room_valid":is_instance_valid(session.room),"health":world.gameplay.health,"is_transition_blocked":session.is_transition_blocked(),"transition_kind":session.transition_kind,"vehicle_transition_busy":session.vehicle_transition_busy,"travel_busy":world.production.travel_busy,"rescue_pending":session.rescue_pending,"arrest_pending":session.arrest_pending,"respawn_busy":session.respawn_busy,"region_focus":str(region.focus),"return_chunk_resident":region.chunks.has(region._cell(desired)),"stream_idle":region.is_streaming_idle(),"candidates":candidates,"nearby_vehicles":vehicles})
	_write(false,"observing")

func _body(body: Object) -> Dictionary:
	if not is_instance_valid(body): return {"valid":false}
	var node := body as Node3D
	var data := {"class":body.get_class(),"instance_id":body.get_instance_id()}
	if node!=null:
		data.path=str(node.get_path())
		data.position=str(node.global_position)
		data.yaw=node.global_rotation.y
		var script: Script=node.get_script()
		data.script=script.resource_path if script!=null else ""
		if node is CollisionObject3D: data.collision_layer=node.collision_layer
		var owner_node: Node=node
		var ancestors: Array[String]=[]
		for i in 4:
			if owner_node==null: break
			ancestors.append(str(owner_node.name))
			owner_node=owner_node.get_parent()
		data.ancestors=ancestors
	return data

func _write(success: bool,reason: String) -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output.path_join("return-diagnostic.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"success":success,"reason":reason,"blocked_return":blocked_return,"blocked_setup_valid":blocked_setup_valid,"scope":"Main native; legal real parked Coyote plus 5s inside" if blocked_return else "Main native live traffic; exact benchmark preamble and 40s inside bank","exit_policy":"one unforced leave attempt; all five legacy candidates diagnosed; returned player must have free capsule and floor; parked blocker must stay in place","observations":observations},"\t"))

func _finish(success: bool,reason: String) -> void:
	_write(success,reason)
	print("DESERT_BANK_RETURN success=",success," reason=",reason," output=",output)
	quit(0 if success else 1)
