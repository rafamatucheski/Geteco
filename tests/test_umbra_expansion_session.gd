extends "res://tests/capture/capture_amusement_park_temporal.gd"
## Main/.NET journey; --umbra-before records the unchanged house before editing.
var wing_recording := false
var wing_clock := 0.0

func _process(delta: float) -> bool:
	if wing_recording and is_instance_valid(world):
		wing_clock += delta
		world.session.amusement_park.yaw = sin(wing_clock*.23)*.7
	return false

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240).timeout.connect(func(): check(false,"finite Umbra deadline"); finish(3))
	var before := "--umbra-before" in OS.get_cmdline_user_args()
	folder = FIXTURE.output_dir("umbra-before" if before else "umbra-after")
	fingerprint = _source_fingerprint()
	var snapshot := FIXTURE.full_snapshot(LAYOUT.HAUNTED_ENTRY,false)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if world.session.modal: world.session.close_menu()
	# Prevent another desktop session's keystrokes from invoking load/menu here.
	root.gui_disable_input = true
	for node in world.find_children("*","Node",true,false):
		node.set_process_input(false)
		node.set_process_unhandled_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"production C# is active")
	check(await world.session.enter_place(LAYOUT.HAUNTED_ID,false),"enter existing Umbra through session")
	await create_timer(1).timeout
	await photo("entrance")
	if before: finish(); return
	var room = world.session.room
	var park = world.session.amusement_park
	if "--umbra-wing" in OS.get_cmdline_user_args():
		for item in [["wing",Vector3(0,0,-10)],["upper",Vector3(-3.1,3.5,-23.0)],["crypt",Vector3(0,0,-22.0)]]:
			world.player.teleport(room.to_global(item[1]+Vector3.UP*.04))
			park.yaw = 0
			await create_timer(.2).timeout
			await photo(item[0]+"-detail")
			wing_clock = 0.0
			wing_recording = true
			await record(item[0],true)
			wing_recording = false
		finish()
		return
	await capture_house_depth()
	for point in [Vector3(-6.4,0,4.5),Vector3(-6.4,0,-5.2),Vector3(0,0,-5.2),Vector3(0,0,-10),Vector3(-6,0,-10),Vector3(-6,3.5,-20.5),Vector3(0,3.5,-23.5),Vector3(6,3.5,-20.5),Vector3(6,0,-10),Vector3(0,0,-10),Vector3(0,0,-5.2),Vector3(6.4,0,-5.2),Vector3(6.4,0,4.5),LAYOUT.HOUSE_SPAWN]:
		check(await walk(room.to_global(point)),"physical journey "+str(point))
		check(absf(world.player.global_position.y-room.to_global(point).y)<.22,"correct storey "+str(point))
		if point==Vector3(0,0,-10) or point==Vector3(0,3.5,-23.5):
			park.yaw = 0
			await photo("hall" if point.y<1 else "gallery")
		if point==Vector3(-6,0,-10):
			park.yaw = 0
			await photo("staircase")
	check(room.model.annex.scares.size()==4,"four distinct articulated fright stations (sem aranha desde 21/10)")
	await check_house_pause()
	await actor_depth()
	await record("house",true)
	# Desde a porta de empurrar (8537bd0c) andar até a saída já tira o jogador (WeaponShopEntrance._update_exit):
	# o "walk to exit" antigo saía no meio do caminho e depois media a distância a uma sala que não existia mais.
	# Se a saída for recusada, UMBRA_EXIT_DEBUG diz por quê (28/10: o chão do parque saía da física com o
	# jogador dentro, e a volta não achava piso).
	var exit_point: Vector3 = room.exit_position
	check(await walk_out(exit_point + Vector3(0,0,1.2)),"walking through the door leaves the house")
	check(world.session.state.place_id.is_empty(),"exit returns to park")
	await create_timer(.4).timeout
	check(not park.house_view and world.player.visual.visible,"first-person state restored")
	check(await world.session.enter_place(LAYOUT.HAUNTED_ID,false),"reentry recreates house")
	await create_timer(.4).timeout
	check(world.session.room.model.annex.scares.size()==4,"reentry has no duplicated creatures")
	finish()

func photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func walk(point: Vector3) -> bool:
	world.player.speed = 3.5
	var deadline := Time.get_ticks_msec()+14000
	while Time.get_ticks_msec()<deadline:
		var offset: Vector3 = point-world.player.global_position
		offset.y = 0
		if offset.length()<.20: break
		world.player.automatic_direction = offset.normalized()
		world.session.amusement_park.yaw = atan2(-offset.x,-offset.z)
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return Vector2(point.x-world.player.global_position.x,point.z-world.player.global_position.z).length()<.35

func walk_out(point: Vector3) -> bool:
	world.player.speed = 3.5
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline and not world.session.state.place_id.is_empty():
		var offset: Vector3 = point-world.player.global_position
		offset.y = 0
		world.player.automatic_direction = offset.normalized() if offset.length()>.05 else Vector3.ZERO
		# Em primeira pessoa o movimento segue a câmera da casa, como em walk().
		if offset.length()>.05: world.session.amusement_park.yaw = atan2(-offset.x,-offset.z)
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	# Sair recarrega o exterior do parque: a casa fecha em segundos, não no mesmo quadro.
	var leaving_deadline := Time.get_ticks_msec()+40000
	while Time.get_ticks_msec()<leaving_deadline and not world.session.state.place_id.is_empty() and bool(world.session.weapon_shop_entrance.get("_leaving")): await physics_frame
	if not world.session.state.place_id.is_empty():
		print("UMBRA_EXIT_DEBUG ",{"player":world.player.global_position,"target":point,"velocity":world.player.velocity,"exit":world.session.room.exit_position if is_instance_valid(world.session.room) else null,
			"entrance":str(world.session.get("weapon_shop_entrance")),"handles":world.session.weapon_shop_entrance.handles_place(world.session.state.place_id) if world.session.get("weapon_shop_entrance") != null else null,
			"blocked":world.session.weapon_shop_entrance._blocked() if world.session.get("weapon_shop_entrance") != null else null,
			"leaving":world.session.weapon_shop_entrance.get("_leaving") if world.session.get("weapon_shop_entrance") != null else null,
			"entering":world.session.weapon_shop_entrance.get("_entering") if world.session.get("weapon_shop_entrance") != null else null,
			"input_locked":world.player.input_locked,"modal":world.session.modal,"transition":world.session.is_transition_blocked(),"paused":paused,"place":world.session.state.place_id,
			"return_point":world.session.get("return_point"),"return_clear":world.session.position_clear(world.session.return_point+Vector3.UP*.08),
			"clear_return":world.session._clear_return_point(world.session.state.place_id,world.session.return_point),
			"return_probe":_probe_point(world.session.return_point),
			"upside_busy":world.session.upside_world.busy() if world.session.get("upside_world") != null else null})
	# A câmera volta do zoom da porta antes de liberar o jogador (CAMERA_SECONDS).
	while Time.get_ticks_msec()<leaving_deadline and world.player.input_locked: await physics_frame
	return world.session.state.place_id.is_empty()

func _probe_point(point: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.98)
	query.exclude = [world.player.get_rid()]
	var hits: Array = []
	for hit in space.intersect_shape(query,6): hits.append(str(hit.collider.get_path()) if hit.collider is Node else str(hit.collider))
	var ground: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.38,point-Vector3.UP*.42,1))
	var deep: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*6.0,point-Vector3.UP*6.0,0xFFFFFFFF))
	var deep_info := {}
	if not deep.is_empty():
		deep_info = {"y":deep.position.y,"collider":str(deep.collider.get_path()) if deep.collider is Node else str(deep.collider),"layer":deep.collider.collision_layer if deep.collider is CollisionObject3D else -1}
	return {"deep":deep_info,"overlaps":hits,"ground":str(ground.get("collider").get_path()) if not ground.is_empty() and ground.collider is Node else ground.is_empty()}

func actor_depth() -> void:
	var room = world.session.room
	var park = world.session.amusement_park
	paused = true
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.environment = park.view.environment
	camera.fov = 72
	camera.make_current()
	var torch: Node3D = park.view.get_node("UmbraVisitorLight")
	torch.reparent(camera,false)
	for player in [true,false]:
		var actor := preload("res://scripts/Actor.gd").new()
		actor.is_player = player
		actor.controlled_automatically = true
		room.add_child(actor)
		actor.set_physics_process(false)
		for at in [Vector3(1,0,-13.4),Vector3(1,0,-17.6)]:
			actor.position = at
			await depth_pair(camera,actor,"table-%s-%s"%[player,at.z],room.to_global(Vector3(1,.68,-11.5)),actor.global_position+Vector3.UP*.55,at.z>-15)
		actor.free()
	torch.reparent(park.view,false)
	park.view.make_current()
	camera.queue_free()
	paused = false

func finish(code := -1) -> void:
	super.finish(code)
	var path := folder.path_join("report.json")
	if FileAccess.file_exists(path):
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		report.notes = "Main/.NET, isolated checkpoint, daytime exterior, Umbra camera environment. Direct session admission; actual walking covers both stairs in normal mode. Wing-only capture uses directed positions. Actor depth checks concern the lower-body band behind the banquet table. No FPS claim from captured frames; external Godot sessions are concurrent."
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
