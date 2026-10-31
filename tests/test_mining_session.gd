extends SceneTree
## Real Main admission, physical interior walk, discovery, disk save and vehicle boarding.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const COAL := preload("res://world/mining/coal/CoalMinePlace.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
var world
var output := ""
var failures: Array[String]=[]
var checks:=0

func _initialize() -> void:
	create_timer(260).timeout.connect(func(): push_error("MINING_SESSION timeout"); finish(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks+=1
	print("MINING_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func frames(count: int) -> void:
	for i in count: await physics_frame

func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func walk(point: Vector3) -> bool:
	var until:=Time.get_ticks_msec()+18000
	while Time.get_ticks_msec()<until:
		var offset: Vector3=point-world.player.global_position
		offset.y=0
		if offset.length()<.24:
			world.player.automatic_direction=Vector3.ZERO
			return true
		world.player.automatic_direction=offset.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	print("MINING_WALK_BLOCKED target=",point," actual=",world.player.global_position)
	return false

func run() -> void:
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-session")
	var at:=LAYOUT.SECRET_ENTRY+Vector3.UP*.08
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"isolated completed-campaign checkpoint"): finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and not world.production.save_invalid,"real Main ready with valid fixture"): finish(1); return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# routing active")
	check(world.production.store.path==path,"SaveStore uses temporary evidence file")
	# Liga as gravações reais só depois de provar que o caminho selecionado é a nossa fixture isolada.
	world.production.no_save=false
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	if "--machines-only" in OS.get_cmdline_user_args() or "--escape-vehicle-only" in OS.get_cmdline_user_args():
		await machines()
		finish(0 if failures.is_empty() else 1)
		return
	await frames(30)
	check(world.production.region.mining_life.debug_snapshot().workers==6,"six exterior miners admitted without duplicate stations")
	check(world.session.nearest().get("place","")==COAL.PLACE_ID,"exterior entry is a normal place action")
	await photo("secret-entrance-day")
	world.session.weather.time_of_day=.9
	world.session.weather._update()
	await world.session.interact()
	for i in 240:
		await physics_frame
		if world.session.state.place_id==COAL.PLACE_ID and not world.session.is_transition_blocked(): break
	if not check(world.session.state.place_id==COAL.PLACE_ID,"ordinary interaction enters coal gallery"): finish(1); return
	var room=world.session.room
	check(world.production.region.mining_life.debug_snapshot().workers==0,"exterior workers released during interior visit")
	check(world.session.position_clear(world.player.global_position),"spawn has full capsule clearance and physical support")
	check(room.reward_points.is_empty(),"hidden reward cannot collect before discovery")
	await photo("coal-before")
	for p in [Vector3(9,0,-4),Vector3(0,0,-4),COAL.LEVER_POINT]:
		if not check(await walk(room.to_global(p)),"physical tunnel walk to "+str(p)): finish(1); return
	check(world.session.nearest().get("target","")=="coal_lever","lever action is reachable")
	check(await world.session.interact(),"normal session interaction reveals easter egg")
	check(room.secret_revealed and world.session.state.world_state.get("remote_coal_secret_revealed",false),"discovery persisted in world state")
	await frames(100)
	await photo("coal-secret")
	for p in [Vector3(-4.7,0,-4.05),Vector3(-5.15,0,-7.9)]:
		if not check(await walk(room.to_global(p)),"physical approach to reward "+str(p)): finish(1); return
	await frames(30)
	check(world.session.state.world_state.rewards.has(COAL.CACHE_ID),"cache collected through production pickup")
	check(world.session.save_game(),"checkpoint writes through full session")
	var saved:=preload("res://runtime/SaveStore.gd").read_valid(path)
	check(not saved.is_empty() and saved.world.get("remote_coal_secret_revealed",false),"disk reload validates discovery state")
	check(not saved.is_empty() and saved.world.rewards.has(COAL.CACHE_ID),"disk reload validates nonrepeatable reward")
	var paid=world.session.state.economy.snapshot()
	for p in [Vector3(-4.7,0,-4.05),Vector3(0,0,-4),Vector3(9,0,-4),Vector3(9,0,10.5)]:
		if not check(await walk(room.to_global(p)),"physical return through tunnel "+str(p)): finish(1); return
	check(await world.session.interact(),"ordinary exit interaction succeeds")
	check(world.session.state.place_id.is_empty() and not world.player.input_locked,"exit restores exterior controls")
	check(world.player.global_position.distance_to(LAYOUT.SECRET_RETURN)<.6,"return uses the hidden entrance")
	check(world.gameplay.health>0 and world.player.global_position.y<-27,"deep pit return does not trigger out-of-world death")
	check(await world.session.enter_place(COAL.PLACE_ID,false),"reentry accepted")
	check(world.session.room.secret_revealed,"discovery restored on reentry")
	check(world.session.state.economy.snapshot()==paid,"reentry gives no duplicate cash")
	check(await world.session.leave_place(),"second exit restores control")
	await machines()
	finish(0 if failures.is_empty() else 1)

func machines() -> void:
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	var point: Vector3=LAYOUT.machine_spawns()[0].point+Vector3(5,.08,0)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.camera.initialized=false
	await create_timer(4).timeout
	await photo("machine-yard")
	var ids: Array = ["desert_bison"] if "--escape-vehicle-only" in OS.get_cmdline_user_args() else ["mining_backhoe","mining_tractor","mining_haul_truck","desert_bison"]
	for id in ids:
		var selected: CharacterBody3D
		for car in world.production.vehicles:
			if not is_instance_valid(car) or car.archetype!=id: continue
			if id=="desert_bison" and car.vehicle_id!="mineradora_escape": continue
			selected=car
			break
		if not check(is_instance_valid(selected),"site spawned "+id): continue
		if not check(await prepare_machine_access(selected),"streamed floor and door ready "+id): continue
		if not check(world.driving.interact(),"ordinary boarding accepted "+id): continue
		var deadline:=Time.get_ticks_msec()+10000
		while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
		if not check(world.driving.occupied and world.driving.car==selected,"driver seated in "+id): continue
		if id.begins_with("mining_"): check(selected.has_node("MiningMachine"),"machine controls attached "+id)
		else: check(selected.vehicle_id=="mineradora_escape","escape pickup is the authored persistent vehicle")
		await photo(id+"-seated")
		if id=="mining_backhoe" and "--lift-input" in OS.get_cmdline_user_args(): await lift_inputs(selected)
		var start: Vector3=selected.global_position
		Input.action_press("accelerate",.3)
		await create_timer(1.5).timeout
		Input.action_release("accelerate")
		Input.action_press("handbrake")
		await create_timer(1).timeout
		Input.action_release("handbrake")
		var floor_y: float=preload("res://world/mining/MiningExterior.gd").surface_height(Vector2(selected.global_position.x,selected.global_position.z))
		check(selected.global_position.distance_to(start)>1 and selected.global_position.y>=floor_y-.2,"drives with ordinary physics "+id)
		check(world.driving.leave(),"ordinary disembark starts "+id)
		deadline=Time.get_ticks_msec()+10000
		while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
		check(not world.driving.occupied and not world.player.input_locked,"disembark restores actor "+id)
	check(world.session.save_game(),"equipment checkpoint saved")
	check(preload("res://gameplay/mining/MiningOperation.gd").validate_snapshot(world.session.state.world_state.get("mining_equipment",null)),"parked equipment has valid persistent snapshots")

func prepare_machine_access(selected: CharacterBody3D) -> bool:
	# Esta fixture salta entre o pátio de cima e a cava. Espera a mesma
	# admissão de residência/chão que a aproximação real a pé já carregaria.
	var at: Vector3 = selected.driver_door_anchor(1)+selected.global_basis.x*.45+Vector3.UP*.08
	world.production.region.set_focus(at)
	world.production.region.prepare_collision_at(at)
	world.production.region.prepare_collision_at(selected.global_position)
	world.player.teleport(at)
	var deadline := Time.get_ticks_msec()+8000
	var ready := false
	while is_instance_valid(selected) and Time.get_ticks_msec()<deadline:
		await physics_frame
		var floor_query := PhysicsRayQueryParameters3D.create(selected.global_position+Vector3.UP*.5,selected.global_position-Vector3.UP*1.5,1,[selected.get_rid()])
		var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(floor_query)
		ready = not selected.has_meta("awaiting_ground") and selected.collision_layer!=0 and selected.is_visible_in_tree() and not floor_hit.is_empty()
		if ready: break
	if not is_instance_valid(selected): return false
	await frames(2)
	var option: Dictionary = world.driving._entry_option()
	var candidate: CharacterBody3D = option.get("car")
	print("MINING_BOARDING_DIAGNOSTIC ",JSON.stringify({"id":selected.vehicle_id,"point":str(selected.global_position),"player":str(world.player.global_position),"door":str(selected.driver_door_anchor(1)),"awaiting_ground":selected.has_meta("awaiting_ground"),"visible":selected.is_visible_in_tree(),"layer":selected.collision_layer,"speed":selected.speed,"health":selected.health,"option":candidate.vehicle_id if is_instance_valid(candidate) else "","gap":option.get("gap",-1)}))
	return ready

func key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)

func lift_inputs(car: CharacterBody3D) -> void:
	var machine=car.get_node("MiningMachine")
	# Fixture inicial controlada no avental de trabalho livre; cada
	# subir/soltar/dar ré seguinte usa os controles e a física reais do jogador.
	var point:=LAYOUT.CENTER+Vector3(7,-27.92,-22)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	car.place(point,0)
	await frames(30)
	var cargo_kinds: Array = ["rock"] if "--rock-only" in OS.get_cmdline_user_args() else ["rock","sedan_classic","bike_urban"]
	for kind in cargo_kinds:
		key(KEY_PAGEDOWN,true)
		await create_timer(3).timeout
		key(KEY_PAGEDOWN,false)
		var cargo: PhysicsBody3D
		if kind=="rock":
			cargo=preload("res://gameplay/mining/MiningOperation.gd").create_rock(20)
			cargo.position=machine.cargo_anchor()+Vector3(0,.65,-1.0)
			world.add_child(cargo)
		else:
			var position_value: Vector3=machine.cargo_anchor()+Vector3(0,0,-3.4 if kind=="sedan_classic" else -2.4)
			position_value.y=preload("res://world/mining/MiningExterior.gd").surface_height(Vector2(position_value.x,position_value.z))+.08
			cargo=world.production.spawn_vehicle(kind,position_value,0)
		if not check(is_instance_valid(cargo),"load fixture admitted without overlapping solids "+kind): continue
		await frames(15)
		if kind!="rock":
			Input.action_press("accelerate",.15)
			var approach_deadline:=Time.get_ticks_msec()+2500
			while machine.cargo_anchor().distance_to(cargo.global_position)>2.86 and Time.get_ticks_msec()<approach_deadline: await physics_frame
			Input.action_release("accelerate")
			Input.action_press("handbrake")
			await create_timer(.7).timeout
			Input.action_release("handbrake")
			print("MINING_LIFT_APPROACH ",kind," gap=",machine.cargo_anchor().distance_to(cargo.global_position)," speed=",car.speed)
		print("MINING_LIFT_CANDIDATE ",kind," active=",machine.active()," eligible=",machine.eligible(cargo)," anchor=",machine.cargo_anchor()," cargo=",cargo.global_position," gap=",machine.cargo_anchor().distance_to(cargo.global_position)," speed=",car.speed)
		key(KEY_B,true)
		await frames(2)
		key(KEY_B,false)
		if not check(machine.cargo==cargo,"B attaches nearby "+kind+" through real input"):
			cargo.queue_free(); continue
		check(not world.session.save_block_reason().is_empty(),"saving suspended cargo blocked "+kind)
		var initial: float=cargo.global_position.y
		key(KEY_PAGEUP,true)
		await create_timer(1.25).timeout
		key(KEY_PAGEUP,false)
		check(cargo.global_position.y>initial+.7,"PgUp physically lifts "+kind)
		await photo("lifting-"+kind)
		key(KEY_B,true)
		await frames(2)
		key(KEY_B,false)
		check(not is_instance_valid(machine.cargo) and not cargo.has_meta("mining_carried_by"),"B releases ownership "+kind)
		var withdrawal_start: Vector3=car.global_position
		mining_lift_trace(kind+" before_reverse",car,machine,cargo)
		Input.action_press("brake",.55)
		for reverse_frame in 108:
			await physics_frame
			if reverse_frame in [0,5,30,60,107]: mining_lift_trace(kind+" reverse_"+str(reverse_frame),car,machine,cargo)
		Input.action_release("brake")
		Input.action_press("handbrake")
		await create_timer(1.5).timeout
		Input.action_release("handbrake")
		check(car.global_position.distance_to(withdrawal_start)>2.0,"reverse control physically withdraws scoop from "+kind)
		var floor_y: float=preload("res://world/mining/MiningExterior.gd").surface_height(Vector2(cargo.global_position.x,cargo.global_position.z))
		print("MINING_RELEASE ",kind," point=",cargo.global_position," floor_y=",floor_y," carrier=",car.global_position," speed=",car.speed)
		check(cargo.global_position.y<floor_y+1.3 and cargo.global_position.y>floor_y-.2,"released load settles after driver reverses "+kind)
		cargo.queue_free()
		await frames(2)

func mining_lift_trace(label: String, car: CharacterBody3D, machine: Node, cargo: PhysicsBody3D) -> void:
	var controls:=root.get_node_or_null("GameInput")
	var contacts:=[]
	for index in car.get_slide_collision_count():
		var contact:=car.get_slide_collision(index)
		for part in contact.get_collision_count():
			var collider: Object=contact.get_collider(part)
			var local_shape: Object=contact.get_local_shape(part)
			var provider: Variant=collider.get_meta("desert_ground_height",null)
			contacts.append({"slide":index,"part":part,"body":str(collider.get_path()),"point":str(contact.get_position(part)),"normal":str(contact.get_normal(part)),"local_shape":str(local_shape.get_path()) if local_shape is Node else str(local_shape),"ground_tag":collider.get_meta("desert_continuous_ground",false),"provider_valid":provider is Callable and provider.is_valid(),"depth":contact.get_depth()})
	var attachment_hits:=[]
	var attachments: Array=[machine._bucket_shape]
	attachments.append_array(machine._rear_shapes)
	for attachment in attachments:
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=attachment.shape
		query.transform=attachment.global_transform
		query.collision_mask=7
		query.exclude=[car.get_rid()]
		for hit in world.get_world_3d().direct_space_state.intersect_shape(query,6):
			var collider: CollisionObject3D=hit.collider
			var owner_id: int=collider.shape_find_owner(int(hit.shape))
			var shape_owner:=collider.shape_owner_get_owner(owner_id) as Node
			attachment_hits.append({"attachment":str(attachment.name),"body":str(collider.get_path()),"solid":str(shape_owner.get_meta("mining_solid",shape_owner.name)) if shape_owner!=null else ""})
	var height_provider:=preload("res://gameplay/desert_cars/DesertVehicleGround.gd").terrain_height_provider(car)
	print("MINING_LIFT_TRACE ",label," ",JSON.stringify({"car":str(car.global_position),"cargo":str(cargo.global_position),"anchor":str(machine.cargo_anchor()),"speed":car.speed,"velocity":str(car.velocity),"horizontal_velocity":str(car.horizontal_velocity),"throttle":car.throttle_input,"input":str(controls.vehicle_input()) if controls!=null else "none","controlled":car.controlled,"locked":car.input_locked,"external":car.external_input,"bucket_clear":machine._bucket_motion_clear(machine._bucket_shape.global_transform),"attachments":attachment_hits,"contacts":contacts,"floor":car.is_on_floor(),"provider_valid":height_provider.is_valid(),"provider_height":height_provider.call(Vector2(car.global_position.x,car.global_position.z)) if height_provider.is_valid() else null,"support_y":preload("res://gameplay/desert_cars/DesertVehicleGround.gd").vertical_velocity(car,car.horizontal_velocity,1.0/60.0)}))

func finish(code: int) -> void:
	Input.action_release("accelerate"); Input.action_release("handbrake")
	if not output.is_empty(): FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rendered":DisplayServer.get_name()!="headless","engine":Engine.get_version_info().string,"note":"Main native session. Exterior starting fixtures are relocations; interior routes and vehicle movements are physical. No global traversal/performance approval."},"\t"))
	print("MINING_SESSION checks=",checks," failures=",failures.size()," evidence=",output)
	quit(code)
