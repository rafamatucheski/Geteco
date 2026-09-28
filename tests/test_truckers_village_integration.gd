extends "res://tests/test_urban_operations.gd"
const Quest := preload("res://gameplay/urban_v1/TruckersVillageQuest.gd")
const State := preload("res://runtime/GameState.gd")

func _visit(point: Vector3, target: String) -> void:
	world.player.teleport(point + Vector3(0,.04,1.2))
	world.production.region.set_focus(world.player.position)
	for i in 180:
		world.production.region.prepare_collision_at(world.player.position)
		await physics_frame
		if session.position_clear(world.player.position): break
	check(session.position_clear(world.player.position),"Physical standing space and floor at " + target)
	var action: Dictionary = session.nearest()
	check(action.get("id") == "urban_v1" and action.get("target") == "truckers_village_" + target,"Real nearest dispatch reaches " + target)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180,true,false,true).timeout.connect(func(): push_error("VILLAGE INTEGRATION TIMEOUT"); quit(3))
	check(await _initialize_world(),"Main starts with urban operations")
	if not failures.is_empty(): quit(1); return
	world.player.controlled_automatically = true
	world.player.set_physics_process(false)
	world.gameplay.health = 100
	var quest = urban.village_quest
	check(is_instance_valid(quest),"Quest is installed in real session")
	if not is_instance_valid(quest): quit(1); return
	await _visit(Quest.TONICO_POINT,"tonico")
	check(session.interact() and quest.data.started,"Normal interaction accepts Tonico quest")
	await _visit(Quest.CRANK_POINT,"crank")
	check(session.interact() and quest.data.crank,"Normal interaction collects first physical hidden part")
	# Concurrent checkpoint policy intentionally blocks saving during any quest.
	# Exercise partial snapshot compatibility without bypassing that gameplay rule.
	check(not session.save_game(),"Checkpoint policy rejects halfway save")
	var halfway: Dictionary = session.state.snapshot()
	halfway.world.urban_operations = urban.snapshot()
	var restored := State.new()
	check(restored.restore_snapshot(halfway),"GameState accepts complete halfway world/economy snapshot")
	check(restored.world_state.get("urban_operations",{}).get("truckers_village",{}).get("crank",false),"Quest part persisted through GameState")
	await _visit(Quest.BELT_POINT,"belt")
	check(session.interact() and quest.data.belt,"Normal interaction collects remaining part")
	var before: int = session.state.economy.balance
	await _visit(Quest.PUMP_POINT,"repair")
	check(session.interact() and quest.data.completed,"Normal interaction repairs village pump")
	check(session.state.economy.balance == before + 450,"Real wallet receives one reward")
	check(session.save_game(),"Real session captures completion")
	var completed: Dictionary = session.state.snapshot()
	check(restored.restore_snapshot(completed),"GameState restores complete quest and wallet atomically")
	check(restored.world_state.get("urban_operations",{}).get("truckers_village",{}).get("completed",false),"Completion persisted")
	check(urban.restore_snapshot(completed.world.urban_operations),"Real UrbanOperations restores quest visuals/state")
	check(not quest.perform("truckers_village_repair") and session.state.economy.balance == before + 450,"Reload does not permit duplicate reward")
	var car = world.driving.car
	check(is_instance_valid(car),"Real persistent player car is available")
	if is_instance_valid(car):
		car.set_physics_process(false)
		var parking := Quest.PARKING_POINT + Vector3(2,.04,0)
		world.production.region.prepare_collision_at(parking)
		car.place(parking,0)
		car.health = car.max_health * .5
		# Teleporting the existing car across streamed chunks leaves its old
		# awaiting_ground marker; let the production admission clear it normally.
		for i in 240:
			await physics_frame
			if not car.has_meta("awaiting_ground"): break
		check(not car.has_meta("awaiting_ground"),"Production admits parked vehicle on physical village ground")
		await _visit(Quest.PUMP_POINT,"service")
		check(session.interact() and car.health == car.max_health,"Normal interaction repairs real parked player car")
		check(session.state.economy.balance == before + 450,"Real local benefit never charges money")
		check(session.save_game(),"Vehicle repair can be saved")
		var service_save: Dictionary = session.state.snapshot()
		check(restored.restore_snapshot(service_save),"GameState accepts repaired real vehicle")
		check(not restored.world_state.vehicles.is_empty() and restored.world_state.vehicles[0].health == car.max_health,"Saved player vehicle preserves repaired health")
	var broken: Dictionary = completed.duplicate(true)
	broken.world.urban_operations.truckers_village.belt = false
	check(not restored.restore_snapshot(broken),"Real GameState rejects inconsistent quest snapshot")
	await _visit(Quest.COOLER_POINT,"counter")
	world.gameplay.health = 50
	var shop_balance: int = session.state.economy.balance
	check(session.interact() and session.modal,"Real counter opens native choice menu")
	for menu_frame in 45: await process_frame
	check(session.panel.size.x<=360 and session.panel.size.y<=220,"Counter uses compact HUD rather than generic large menu")
	print("COUNTER_ACTUAL_BOUNDS_AFTER_45_FRAMES ",session.panel.get_global_rect())
	var buy: Button
	var rob: Button
	for child in session.column.get_children():
		if child is Button:
			var viewport_rect: Rect2 = session.column.get_parent().get_global_rect()
			check(viewport_rect.encloses(child.get_global_rect()),"Compact counter keeps every button fully visible without scrolling")
		if child is Button and child.text.begins_with("Bebida"): buy=child
		if child is Button and child.text == "Assaltar caixa": rob=child
	check(is_instance_valid(buy) and is_instance_valid(rob),"Native menu exposes separate purchase and robbery choices")
	if is_instance_valid(buy): buy.pressed.emit()
	check(not session.modal and world.gameplay.health==75 and session.state.economy.balance==shop_balance-20,"Real menu purchase heals and charges once")
	check(session.panel.custom_minimum_size==Vector2(620,440),"Counter closure restores unrelated menu sizing")
	check(session.save_game(),"Peaceful completed-quest purchase can checkpoint")
	check(restored.restore_snapshot(session.state.snapshot()),"GameState accepts commerce purchase state")
	session.state.economy.grant_weapon("pistol")
	session.state.equip_weapon("pistol")
	check(session.interact() and session.modal,"Counter can reopen for explicit robbery")
	rob=null
	for child in session.column.get_children():
		if child is Button and child.text == "Assaltar caixa": rob=child
	if is_instance_valid(rob): rob.pressed.emit()
	check(session.state.economy.balance==shop_balance-20+180,"Real menu robbery grants one register")
	check(urban.village_residents.hostile and world.gameplay.stars>0,"Robbery arms actual residents and reports crime")
	check(not session.save_game(),"Crime still blocks checkpoint")
	var conflict_save: Dictionary = session.state.snapshot()
	conflict_save.world.urban_operations=urban.snapshot()
	check(restored.restore_snapshot(conflict_save),"GameState validates hostile cooldown snapshot")
	check(urban.restore_snapshot(conflict_save.world.urban_operations) and urban.village_residents.hostile,"Actual resident manager restores hostile state")
	# Shoot through an open authored pedestrian path using the actual resident,
	# muzzle ray and Gameplay.damage_player; wall/vehicle cases live in its test.
	for resident in urban.village_residents.residents: resident.set_physics_process(false)
	var shooter = urban.village_residents.residents[0]
	shooter.global_position=Vector3(-365,.04,111)
	world.player.teleport(Vector3(-371,.04,111))
	shooter.model.rotation.y=-PI*.5
	shooter._shot_left=0
	world.gameplay.armor=0
	await physics_frame
	await physics_frame
	var health_before: float = world.gameplay.health
	shooter._try_shoot()
	if world.gameplay.health!=health_before-6:
		var debug_ray:=PhysicsRayQueryParameters3D.create(shooter.model.muzzle_position(),world.player.global_position+Vector3.UP,7,[shooter.get_rid()])
		var debug_hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(debug_ray)
		print("SHOT_DIAGNOSTIC active=",shooter.active," hostile=",shooter.hostile," cooldown=",shooter._shot_left," health=",health_before,"->",world.gameplay.health," hit=",debug_hit.get("collider")," point=",debug_hit.get("position")," player_layer=",world.player.collision_layer," target=",shooter.target," model_forward=",shooter.model.global_basis.z)
	check(world.gameplay.health==health_before-6,"Actual hostile resident shot applies damage through real Gameplay")
	var homes = urban.village.homes
	check(is_instance_valid(urban.village_residents.house_guards) and homes.homes.size()==6,"Six real houses are bound to resident system")
	for index in homes.homes.size():
		var room: Dictionary = homes.homes[index]
		quest.commerce.data.hostility=0
		urban.village_residents.set_hostile(false)
		world.player.teleport(room.root.to_global(Vector3(0,.04,6)))
		world.production.region.set_focus(world.player.position)
		for frame in 55: await physics_frame
		var inside: Vector3 = room.root.to_global(Vector3(0,.04,2))
		var motion: Vector3 = inside-world.player.global_position
		check(not world.player.test_move(world.player.global_transform,motion),"Real house %d opens a walkable physical doorway"%index)
		world.player.move_and_collide(motion)
		for frame in 12: await physics_frame
		check(homes.house_at(world.player.global_position)==index and homes.current_home==index,"Walking enters real house %d without interaction key"%index)
		var guards = urban.village_residents.house_guards
		check(guards.active_house==index and guards.pairs.get(index,[]).size()==2,"Two physical occupants admitted in home %d"%index)
		check(urban.village_residents.hostile,"House %d entry calls the outside group"%index)
		for actor in guards.pairs.get(index,[]):
			actor.set_physics_process(false)
			check(actor.weapon_id=="shotgun" and actor.model.weapon.visible,"Real home occupant draws doze")
			var query := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius=.3
			capsule.height=1.75
			query.shape=capsule
			query.collision_mask=1
			# CharacterBody may rest a few millimetres into the streamed ground's
			# collision margin. Check furniture/body clearance above that contact,
			# and verify support independently instead of counting floor as a wall.
			query.transform.origin=actor.global_position+Vector3.UP*.905
			var contacts: Array = world.get_world_3d().direct_space_state.intersect_shape(query)
			if not contacts.is_empty(): print("HOME_COLLISION_DIAGNOSTIC home=",index," actor=",actor.name," point=",actor.global_position," path=",contacts[0].collider.get_path())
			check(contacts.is_empty(),"Resident admitted outside furniture and walls")
			var support:=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.3,actor.global_position-Vector3.UP*.2,1)
			check(not world.get_world_3d().direct_space_state.intersect_ray(support).is_empty(),"Resident feet have physical ground support")
		for resident in urban.village_residents.residents: resident.set_physics_process(false)
	world.free()
	await process_frame
	print("TRUCKERS_VILLAGE_INTEGRATION failures=",failures)
	quit(0 if failures.is_empty() else 1)
