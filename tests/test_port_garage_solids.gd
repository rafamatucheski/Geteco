extends "res://tests/test_port_boss_garage.gd"
## Focused geometry/lifecycle fixture using the production room and actors.
func run() -> void:
	root.get_node("SaveManager")._save_dir="D:/geteco/artifacts/port-boss-0913/test-saves/"
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("CampaignState").salvage_state.clear()
	var world := Node2D.new()
	root.add_child(world)
	current_scene=world
	var p=load("res://Player.gd").new()
	p.name="Player"
	p.collision_layer=4
	p.collision_mask=7
	var collision := CollisionShape2D.new()
	collision.name="Collision"
	var capsule := CapsuleShape2D.new()
	capsule.radius=5
	capsule.height=16
	collision.shape=capsule
	p.add_child(collision)
	var camera := Camera2D.new()
	camera.name="Camera"
	p.add_child(camera)
	world.add_child(p)
	p.set_physics_process(false)
	var manager := Node.new()
	world.add_child(manager)
	var spaces := Node2D.new()
	manager.add_child(spaces)
	var garage=preload("res://world/harbor/PortBossGarage.gd").new()
	spaces.add_child(garage)
	garage.set_process(false)
	garage.build_interior()
	p.global_position=garage.spawn_point.global_position
	garage.attach_actor(p)
	garage.set_npc_rendering_active(true)
	for guard in garage.guards: guard.set_physics_process(false)
	await verify_solids(garage,p)
	p.set_physics_process(false)
	for guard in garage.guards: guard.set_physics_process(false)
	for person in [p,garage.guards[0]]: await depth_check(garage,person)
	await photo(garage,"garagem",false)
	var car: CharacterBody2D=garage.boss
	for side in [-1.0,1.0]:
		p.is_control_disabled=false
		p.global_position=car.to_global(Vector2(-8,side*43))
		car.enter_vehicle(p)
		garage.detach_actor(p)
		for guard in garage.guards: guard.set_physics_process(false)
		await create_timer(2.2).timeout
		check(car.is_driven_by_player and not car.has_meta("vehicle_boarding"),"Native boarding finishes from side "+str(side))
		if side>0: await photo(garage,"porto-rosso-dante",true)
		car.exit_vehicle()
		await create_timer(2.8).timeout
		check(not car.is_driven_by_player and p.visible and not p.is_control_disabled,"Native animated exit finishes from side "+str(side))
		garage.attach_actor(p)
	p.global_position=garage.EXTERIOR
	garage.set_npc_rendering_active(false)
	check(not p.has_meta("interior_actor_presentation") and p.model_root.get_parent()==p.viewport_3d,"Respawn restores native rig")
	print("PORT_GARAGE_SOLIDS checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)
