extends "res://tests/test_urban_operations.gd"

func run() -> void:
	check(await _initialize_world(), "World starts")
	if not failures.is_empty(): quit(1); return
	check(world.production.no_save, "Fixture never accesses personal saves")
	var cemetery = urban.cemetery
	world.player.controlled_automatically = true
	world.player.teleport(CEMETERY_CENTER + Vector3(5,0,13))
	world.production.region.set_focus(CEMETERY_CENTER)
	urban.refresh_context()
	await settle(10)
	cemetery.set_process(false)
	# Physical funeral: do not advance route indexes or teleport participants.
	check(cemetery.register_synthetic_case("test:peaceful", "Visitante"), "Funeral queued")
	world.camera.set_process(false)
	world.camera.position = cemetery.GATE + Vector3(0,20,20)
	world.camera.look_at(cemetery.GATE)
	check(cemetery._arrival_visible(), "Positive control: gate is on camera")
	cemetery._try_start_trip()
	check(cemetery.trip_identity.is_empty(), "Funeral does not pop into the visible gate")
	world.camera.position += Vector3(0,0,100)
	check(not cemetery._arrival_visible(), "Gate outside camera for admission")
	cemetery._try_start_trip()
	check(cemetery.trip_identity == "test:peaceful", "Unseen arrival starts once")
	var origin: Vector3 = cemetery.mortician.global_position
	for frame in 3000:
		await physics_frame
		cemetery._tick_trip(1.0/60.0)
		if cemetery.trip_phase == "working": break
	check(cemetery.mortician.global_position.distance_to(origin) > 15.0, "Worker walks from hearse through gate")
	check(cemetery.trip_phase == "working", "Whole procession physically reaches the ceremony")
	if cemetery.trip_phase != "working":
		print("ROUTE_DEBUG worker=", cemetery.mortician.global_position, " index=",cemetery.mortician.route_index)
		for guest in cemetery.mourners: print("ROUTE_DEBUG guest=",guest.global_position," index=",guest.route_index," target=",guest.route[-1])
	check(not cemetery.mortician.dead, "Living worker performs ceremony")
	if DisplayServer.get_name() != "headless":
		world.camera.position = CEMETERY_CENTER + Vector3(0,22,22)
		world.camera.look_at(CEMETERY_CENTER)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/cemetery-npcs-ceremony-0928.png")
	# Funeral waits for every visitor, not just the worker, before removing actors.
	cemetery._tick_trip(5.1)
	check(cemetery.cases["test:peaceful"].phase == "buried", "Peaceful ceremony buries the original identity")
	world.camera.position = cemetery.GATE + Vector3(0,20,20)
	world.camera.look_at(cemetery.GATE)
	for frame in 3000:
		await physics_frame
		cemetery._tick_trip(1.0/60.0)
		if cemetery.mortician.finished() and cemetery._guests_finished(): break
	check(cemetery.mortician.finished() and cemetery._guests_finished(), "Every participant physically leaves through the gate")
	if not cemetery._guests_finished():
		for visitor in cemetery.mourners: print("EXIT_DEBUG ",visitor.global_position," index=",visitor.route_index," target=",visitor.route[-1])
	check(not cemetery.trip_identity.is_empty(), "Departing actors remain while visible")
	world.camera.position += Vector3(0,0,100)
	cemetery._tick_trip(.1)
	check(cemetery.trip_identity.is_empty(), "Unseen completed procession releases actors")
	check(cemetery.register_synthetic_case("test:physical", "Visitante"), "Second funeral queued independently")
	cemetery._try_start_trip()
	for frame in 3000:
		await physics_frame
		cemetery._tick_trip(1.0/60.0)
		if cemetery.trip_phase == "working": break
	check(cemetery.trip_phase == "working", "Second plot also keeps the aisle free for the procession")
	var guest = cemetery.mourners[0]
	var guest_health: float = guest.health
	guest.receive_damage(-10)
	guest.receive_damage(NAN)
	check(guest.health == guest_health, "Invalid damage is ignored")
	var ray := PhysicsRayQueryParameters3D.create(guest.global_position + Vector3(0,1,-.9), guest.global_position + Vector3.UP, 3)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider") == guest, "Physical bullet ray hits the visitor capsule")
	if hit.get("collider") == guest: world.gameplay._damage(hit.collider, 30.0, world.player)
	check(guest.health == 70.0 and guest.frightened, "Combat damage injures visitor and triggers flight")
	check(cemetery.trip_phase == "returning" and cemetery.cases["test:physical"].phase == "morgue", "Violence interrupts burial without losing deceased")
	check(cemetery.keeper.frightened and cemetery.storyteller.frightened, "Residents react to assault")
	world.gameplay._damage(guest, 100.0, world.player)
	check(guest.dead and guest.health == 0 and guest.collision_layer == 0, "Visitor can die through gameplay damage")
	check(guest.is_in_group("v2_damageable"), "Visitor participates in physical damage discovery")
	var dead_position: Vector3 = guest.global_position
	await settle(12)
	check(guest.global_position.is_equal_approx(dead_position), "Dead visitor stops moving")
	check(cemetery.deaths.has("test:physical:cemetery_mourner_00"), "Visitor death has stable funeral identity")
	if DisplayServer.get_name() != "headless":
		await settle(75)
		world.camera.position = cemetery.GATE + Vector3(0,16,16)
		world.camera.look_at(cemetery.GATE)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/cemetery-npcs-interrupted-0928.png")
	var worker = cemetery.mortician
	world.gameplay._damage(worker, 200.0, world.player)
	check(worker.dead, "Funeral worker is mortal")
	var keeper = cemetery.keeper
	world.gameplay._damage(keeper, 200.0, world.player)
	check(keeper.dead and cemetery.nearest_action().is_empty(), "Dead keeper cannot offer dialogue")
	world.gameplay.weapon_fired.emit("pistol", cemetery.storyteller.global_position)
	check(cemetery.storyteller.frightened, "Gunfire is connected to civilian response")
	world.gameplay.explode(cemetery.storyteller.global_position + Vector3(0,1,.3), 2.0, 400.0, world.player, false)
	check(cemetery.storyteller.dead, "Real explosion kills a cemetery resident")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(cemetery.snapshot()))
	check(cemetery.validate_snapshot(snapshot), "Death ledger validates")
	check(cemetery.restore_snapshot(snapshot), "Deaths restore with case ledger")
	await settle()
	check(not is_instance_valid(cemetery.keeper) and cemetery.trip_identity.is_empty(), "Restore does not resurrect keeper or murdered worker")
	check(actor_prefix_count("cemetery_mourner_") == 0, "Aborted funeral has no duplicate visitors")
	var invalid := snapshot.duplicate(true)
	invalid.deaths.append("unknown:cemetery_mortician")
	check(not cemetery.validate_snapshot(invalid), "Unknown death identity rejected atomically")
	var legacy := snapshot.duplicate(true)
	legacy.erase("deaths")
	check(cemetery.validate_snapshot(legacy), "Old saves remain compatible")
	world.player.teleport(Vector3(0,.04,0))
	urban.refresh_context()
	world.player.teleport(CEMETERY_CENTER)
	urban.refresh_context()
	await settle()
	check(not is_instance_valid(cemetery.keeper), "Streaming does not resurrect named resident")
	world.free()
	await process_frame
	print("CEMETERY_NPCS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
