extends SceneTree
const STATE := preload("res://gameplay/urban_v1/PortContainerState.gd")
var world
var service
var failures: Array[String] = []
var checks := 0
var folder := "res://evidence/port-lockpick-20260928"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func photo(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder+"/"+id+".png") == OK,"Photo "+id)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240,true,false,true).timeout.connect(func(): push_error("CONTAINER TEST TIMEOUT"); quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(28092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	service = world.session.port_container_loot
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.player.teleport(Vector3(271,.1,245.15625))
	world.production.region.set_focus(world.player.position)
	await frames(180)
	var containers := get_nodes_in_group("lootable_port_containers")
	containers.sort_custom(func(a,b): return STATE.known_ids().find(a.cargo_id) < STATE.known_ids().find(b.cargo_id))
	check(containers.size() == 18,"All and only 18 ground containers are interactive")
	if containers.is_empty(): quit(1); return
	var cargo = containers[0]
	world.player.teleport(cargo.door_point())
	await frames(3)
	check(service.available(),"Port exploration is available")
	check(world.session.nearest().get("target","") == cargo.cargo_id,"Session routes actual door interaction")
	check(not world.session.interact() and not cargo.opened,"No lockpick means no attempt")
	await photo("closed")
	var wallet = world.session.state.economy
	wallet.grant_reward("lockpick_test_budget",1000)
	var catalog := preload("res://runtime/HarborAmmunationCatalog.gd").new()
	catalog.configure(world.session)
	world.hud.add_child(catalog)
	catalog.open_catalog()
	var cash: int = wallet.balance
	catalog.purchase_lockpick()
	check(service.picks() == 1 and wallet.balance == cash-75,"Real catalog purchases one lockpick")
	catalog.purchase_lockpick()
	check(service.picks() == 2,"Real catalog count refreshes")
	await photo("ammunation-lockpick")
	catalog.dismiss()
	catalog.queue_free()
	check(world.session.interact(),"Open lockpick minigame")
	await frames(15)
	await photo("lockpick-minigame")
	service.minigame.finish("cancelled")
	await frames(2)
	check(service.pending == null and service.picks() == 2 and not cargo.opened and not world.session.modal and not world.player.input_locked,"Cancel restores controls without charging")
	check(world.session.interact(),"Retry starts")
	# Adjust through the same movement function as keyboard/gamepad, then hold torque.
	for i in 120: service.minigame.step(1.0/60.0,-1.0 if service.minigame.target_angle > 0 else 1.0,false)
	for i in 3: await process_frame
	check(service.minigame.torque_armed,"Opening interaction released before applying torque")
	Input.action_press("interact")
	await create_timer(2.65).timeout
	print("LOCK_PROBE active=",service.minigame.active," angle=",service.minigame.angle," target=",service.minigame.target_angle," turn=",service.minigame.turn," wear=",service.minigame.wear," armed=",service.minigame.torque_armed," count=",service.picks())
	Input.action_release("interact")
	await frames(3)
	check(service.picks() == 1 and not cargo.opened,"Wrong angle plus excessive torque breaks exactly one tool")
	await photo("failed")
	check(world.session.interact(),"Attempt after failure")
	for i in 120:
		var difference: float = service.minigame.target_angle-service.minigame.angle
		service.minigame.step(1.0/60.0,clampf(difference/(85.0/60.0),-1,1),false)
	for i in 3: await process_frame
	Input.action_press("interact")
	await create_timer(1.75).timeout
	Input.action_release("interact")
	await frames(3)
	check(cargo.opened and service.picks() == 1,"Correct angle opens without consuming tool")
	# Walk through the actual doorway; no teleport across the entrance.
	world.player.automatic_direction = Vector3.LEFT
	await frames(90)
	world.player.automatic_direction = Vector3.ZERO
	await frames(25)
	print("DOOR_PROBE ",world.player.global_position," door=",cargo.door_point()," local=",cargo.to_local(world.player.global_position)," speed=",world.player.speed," available=",service.available()," opened=",cargo.opened," revealed=",cargo.revealed)
	check(cargo.contains(world.player.global_position),"Player walks through opened doors")
	check(cargo.revealed and is_equal_approx(float(world.camera.get_meta("port_container_zoom",1)),.84),"Roof and gentle camera zoom activate inside")
	await create_timer(.7).timeout
	check(world.camera.global_basis.z.dot(Vector3.UP) > .99 and world.camera.focus.distance_to(cargo.global_position) < .1,"Camera looks down from above the occupied container")
	await photo("inside")
	world.player.teleport(cargo.loot_point())
	await frames(3)
	cash = wallet.balance
	check(world.session.interact(),"Session collects reachable loot")
	check(wallet.balance == cash+int(STATE.loot(cargo.cargo_id).amount),"Cash reward applied")
	check(not service.collect(cargo) and wallet.balance == cash+int(STATE.loot(cargo.cargo_id).amount),"Repeat collection cannot duplicate cash")
	var npc := preload("res://gameplay/routines_v1/V1RoutineActor.gd").new()
	npc.configure({"id":"container_physics_visitor","stationary":true,"position":cargo.global_position})
	world.add_child(npc)
	await frames(3)
	for body in [world.player,npc]:
		var original: Transform3D = body.global_transform
		var center: Vector3 = cargo.global_position+Vector3(0,.10,0)
		var probe := Transform3D(Basis.IDENTITY,center)
		# Move the other actor away so only authored cargo solids can stop the sweep.
		if body == world.player: npc.position = cargo.door_point()+Vector3(4,0,0)
		else: world.player.teleport(cargo.door_point()+Vector3(4,0,0))
		await frames(2)
		check(body.test_move(probe,Vector3(0,0,5)),"Front wall blocks "+body.name)
		check(body.test_move(probe,Vector3(0,0,-5)),"Back wall blocks "+body.name)
		check(body.test_move(probe,Vector3(-30,0,0)),"Rear end blocks large sweep "+body.name)
		check(not body.test_move(probe,Vector3(4,0,0)),"Middle corridor open "+body.name)
		var crate_probe := Transform3D(Basis.IDENTITY,cargo.to_global(Vector3(-cargo.dimensions.x*.5+2.5,.1,-cargo.dimensions.y*.25)))
		check(body.test_move(crate_probe,Vector3(-2,0,0)),"Rear crate blocks "+body.name)
		var chest_probe := Transform3D(Basis.IDENTITY,cargo.contents.global_position+Vector3(1.5,.1,0))
		check(body.test_move(chest_probe,Vector3(-2,0,0)),"Loot chest blocks "+body.name)
		var closed = containers[1]
		check(body.test_move(Transform3D(Basis.IDENTITY,closed.door_point()),Vector3(-3,0,0)),"Closed door blocks "+body.name)
		body.global_transform = original
	npc.position = cargo.global_position+Vector3(-2,.1,0)
	world.player.teleport(cargo.global_position+Vector3(2,.1,0))
	await frames(30)
	print("INSIDE_PROBE ",world.player.global_position," available=",service.available()," revealed=",cargo.revealed," occupied=",service.occupied," roof children=",cargo.roof.get_child_count())
	await photo("two-actors")
	npc.queue_free()
	# Leave via actual motion, then restore camera/roof and re-enter.
	world.player.teleport(cargo.to_global(Vector3(cargo.dimensions.x*.5-1,.1,0)))
	world.player.automatic_direction = Vector3.RIGHT
	await frames(50)
	world.player.automatic_direction = Vector3.ZERO
	await frames(25)
	check(not cargo.revealed and is_equal_approx(float(world.camera.get_meta("port_container_zoom",1)),1.0),"Exit restores roof and ordinary zoom")
	await create_timer(.7).timeout
	check(not world.camera.has_meta("port_container_focus") and is_zero_approx(world.camera._container_blend),"Exit restores exterior camera angle and follow")
	await photo("exit")
	# Save through the real disk serializer, isolated from user saves.
	var store := preload("res://runtime/SaveStore.gd").new()
	store.path = folder+"/fixture-save.json"
	check(store.save(world.session.state) == OK,"Cargo and inventory write through SaveStore")
	var restored := preload("res://runtime/GameState.gd").new()
	check(store.load_into(restored).ok,"SaveStore reload succeeds")
	check(restored.economy.inventory.lockpick == 1 and restored.world_state.port_containers[cargo.cargo_id].looted,"Save retains tools, opened door and collected loot")
	# Streamed instance reconstruction exercises the same bind used by NativeRegion.
	var rebuilt := preload("res://world/regions/LootablePortContainer.gd").new()
	world.add_child(rebuilt)
	rebuilt.build(cargo.position,cargo.dimensions)
	check(rebuilt.opened and rebuilt.looted,"Rebuilt chunk restores cargo state before physics")
	rebuilt.queue_free()
	# Ammunition and empty cargo both use the real interaction/receipt paths.
	wallet.grant_weapon("pistol")
	for index in [1,3]:
		var other = containers[index]
		service.records[other.cargo_id] = {"opened":true,"looted":false}
		other.apply_state(service.records[other.cargo_id])
		world.player.teleport(other.loot_point())
		await frames(3)
		var reserve: int = wallet.get_ammo("pistol").reserve
		check(service.collect(other),"Collect ammunition/empty cargo "+str(index))
		check(wallet.get_ammo("pistol").reserve == reserve+(24 if index == 1 else 0),"Exact ammo grant "+str(index))
		check(not service.collect(other),"No repeated loot "+str(index))
	var stacked = containers[6]
	stacked.apply_state({"opened":true,"looted":false})
	world.player.teleport(stacked.global_position+Vector3(0,stacked.height+.2,0))
	check(not stacked.contains(world.player.global_position) and service.nearest_action().is_empty(),"Upper container is inaccessible scenery")
	world.player.teleport(stacked.global_position+Vector3(0,.1,0))
	await frames(30)
	await photo("stacked-interior")
	world.player.teleport(Vector3(0,.1,0))
	world.production.region.set_focus(world.player.position)
	await frames(60)
	check(service.occupied == null and service.pending == null and float(world.camera.get_meta("port_container_zoom",1)) == 1.0,"Teleport/stream unload cleans roof and camera state")
	print("PORT_CONTAINERS: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
