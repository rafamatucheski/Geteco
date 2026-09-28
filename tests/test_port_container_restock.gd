extends "res://tests/test_port_containers.gd"

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180,true,false,true).timeout.connect(func(): push_error("RESTOCK TEST TIMEOUT"); quit(3))
	root.size = Vector2i(1280,720)
	seed(28092026)
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
	check(containers.size() == 18,"Eighteen accessible ground containers")
	if containers.size() != 18: quit(1); return
	var cargo = containers[0]
	var wallet = world.session.state.economy
	# Real collection adapter: new weapons, duplicate weapons, armor capacity, empty.
	for index in [2,8,4,3]:
		var other = containers[index]
		service.records[other.cargo_id] = {"opened":true,"looted":false}
		other.apply_state(service.records[other.cargo_id])
		world.player.teleport(other.loot_point())
		await frames(3)
		if index == 4:
			world.gameplay.armor = 100
			check(not service.collect(other) and not other.looted,"Full armor leaves vest available")
			world.gameplay.armor = 15
		check(service.collect(other),"Collect real reward "+str(index))
		check(not service.collect(other),"Reward cannot duplicate "+str(index))
	check(wallet.owns_weapon("pistol") and wallet.owns_weapon("shotgun"),"Both weapons are granted")
	check(world.gameplay.armor == 100,"Vest restores armor")
	var duplicate = containers[14]
	service.records[duplicate.cargo_id] = {"opened":true,"looted":false}
	duplicate.apply_state(service.records[duplicate.cargo_id])
	world.player.teleport(duplicate.loot_point())
	await frames(3)
	var reserve: int = wallet.get_ammo("pistol").reserve
	check(service.collect(duplicate) and wallet.get_ammo("pistol").reserve == reserve+12,"Owned weapon becomes ammunition")
	var npc := preload("res://gameplay/urban_v1/PortWorker.gd").new()
	npc.configure({"id":"restock_witness","kind":"dock_worker","stationary":true,"position":cargo.global_position})
	world.add_child(npc)
	# Three layouts: matching solid sweeps, reachable chest and uninterrupted aisle.
	var layouts := []
	for cycle in 3:
		var row := {"opened":true,"looted":false,"cycle":cycle,"elapsed":0.0}
		service.records[cargo.cargo_id] = row
		cargo.apply_state(row)
		layouts.append(cargo.contents.position)
		world.player.teleport(cargo.global_position+Vector3(0,.1,0))
		npc.position = cargo.door_point()+Vector3(4,0,0)
		await frames(3)
		for body in [world.player,npc]:
			if body == npc: world.player.teleport(cargo.door_point()+Vector3(5,0,0))
			await frames(2)
			var probe := Transform3D(Basis.IDENTITY,cargo.global_position+Vector3(-7,.1,0))
			check(not body.test_move(probe,Vector3(15,0,0)),"Clear central aisle layout %d %s" % [cycle,body.name])
			probe.origin = cargo.contents.global_position+Vector3(1.5,.1,0)
			check(body.test_move(probe,Vector3(-2,0,0)),"Chest blocks body layout %d %s" % [cycle,body.name])
			for solid in cargo.cargo_props.find_children("*","StaticBody3D",true,false):
				probe.origin = solid.global_position+Vector3(1.4,-solid.position.y+.1,0)
				check(body.test_move(probe,Vector3(-2,0,0)),"Cargo crate blocks body layout %d %s" % [cycle,body.name])
		world.player.teleport(cargo.loot_point())
		await frames(45)
		check(cargo.contains(world.player.global_position) and service.nearest_action().get("target","") == cargo.cargo_id,"Loot approachable in layout "+str(cycle))
		await photo("restock-layout-"+str(cycle))
	check(layouts[0] != layouts[1] and layouts[1] != layouts[2],"Cargo changes position each delivery")
	# Restocking must never close around an occupant, even after its timer expires.
	service.advance_restock(STATE.RESTOCK_SECONDS)
	check(cargo.opened and service.records[cargo.cargo_id].cycle == 2,"No restock around player")
	world.player.teleport(cargo.global_position+Vector3(90,.1,0))
	npc.position = cargo.global_position+Vector3(0,.1,0)
	await frames(45)
	service.advance_restock(1)
	check(cargo.opened and service.records[cargo.cargo_id].cycle == 2,"No restock around NPC")
	npc.position = cargo.global_position+Vector3(40,.1,0)
	await frames(3)
	service.advance_restock(1)
	check(not cargo.opened and not cargo.looted and service.records[cargo.cargo_id].cycle == 3,"Vacant distant cargo relocks and changes delivery")
	var rebuilt := preload("res://world/regions/LootablePortContainer.gd").new()
	world.add_child(rebuilt)
	rebuilt.build(cargo.position,cargo.dimensions)
	check(not rebuilt.opened and rebuilt.layout_cycle == 3,"Streaming restores current delivery/layout")
	rebuilt.queue_free()
	await frames(2)
	var store := preload("res://runtime/SaveStore.gd").new()
	store.path = folder+"/restock-save.json"
	var save_result := store.save(world.session.state)
	if save_result != OK:
		var data: Dictionary = world.session.state.snapshot()
		print("SAVE_DIAG code=",save_result," cargo=",STATE.validate_snapshot(data.world.port_containers)," wallet=",preload("res://systems/economy/Economy.gd").validate_snapshot(data.economy))
		for key in data.world.keys():
			var probe: Dictionary = data.duplicate(true)
			probe.world.erase(key)
			if preload("res://runtime/GameState.gd").new().restore_snapshot(probe): print("SAVE_DIAG rejected world key=",key," value=",data.world[key])
		FileAccess.open(folder+"/restock-invalid-save.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	check(save_result == OK,"Save restocked state")
	var restored := preload("res://runtime/GameState.gd").new()
	check(store.load_into(restored).ok and restored.world_state.port_containers[cargo.cargo_id].cycle == 3,"Reload preserves delivery and timer")
	# Perception uses actual walls, range, facing and living witnesses.
	cargo.apply_state({"opened":true,"looted":false,"cycle":3})
	world.player.teleport(cargo.global_position+Vector3(1,.1,0))
	npc.position = cargo.global_position+Vector3(5,.1,0)
	npc.model.rotation.y = npc._facing_yaw(world.player.global_position-npc.global_position)
	await frames(3)
	check(service.witness_can_see(npc),"Living worker sees theft through clear aisle")
	npc.model.rotate_y(PI)
	check(not service.witness_can_see(npc),"Worker facing away cannot report")
	npc.position = cargo.global_position+Vector3(1,.1,3)
	npc.model.rotation.y = npc._facing_yaw(world.player.global_position-npc.global_position)
	check(not service.witness_can_see(npc),"Container wall blocks witness even when roof is cut away")
	npc.position = cargo.global_position+Vector3(30,.1,0)
	npc.model.rotation.y = npc._facing_yaw(world.player.global_position-npc.global_position)
	check(not service.witness_can_see(npc),"Distant witness cannot report")
	npc.position = cargo.global_position+Vector3(5,.1,0)
	npc.model.rotation.y = npc._facing_yaw(world.player.global_position-npc.global_position)
	npc.dead = true
	check(not service.witness_can_see(npc),"Dead worker cannot report")
	npc.dead = false
	world.gameplay.clear_wanted()
	world.player.input_locked = true
	check(service.report_witnessed_theft() and world.gameplay.stars >= 1 and world.gameplay.last_known_valid,"Witness informs real wanted/dispatch system")
	check(world.player.input_locked,"Reporting during lockpick preserves modal input lock")
	world.player.input_locked = false
	var points: int = world.gameplay.crime_points
	service.report_witnessed_theft()
	check(world.gameplay.crime_points == points,"Repeated sighting does not pile up crime points")
	await create_timer(8).timeout
	var police_count := 0
	for actor in get_nodes_in_group("v2_damageable"):
		if actor.get_meta("gameplay_role","") == "police": police_count += 1
	print("DISPATCH_DIAG ",world.dispatch.status()," events=",world.dispatch.events)
	check(police_count > 0 or world.dispatch.status().police > 0,"Police response deploys a real officer or patrol vehicle")
	print("PORT_CONTAINER_RESTOCK: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
