extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1100,700)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2.ZERO,Vector2(1100,0),Vector2(1100,700),Vector2(0,700)])
	ground.color = Color("626e60")
	world.add_child(ground)
	var grave := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	world.add_child(grave)
	grave.position = Vector2(800,350)
	grave.build_view(preload("res://world/harbor/cemetery/CemeteryGrave3D.gd"),5.8,80.0,Vector3(0,.6,0),Vector3(0,24,20),Vector2i(512,512))
	grave.add_solid(Rect2(-1.05,-1.75,2.1,3.5),"TombCollision")
	var guest := preload("res://world/harbor/events/WorldEventResident.gd").new()
	world.add_child(guest)
	guest.position = Vector2(220,350)
	guest.scale = Vector2.ONE*4
	guest.set_physics_process(false)
	var keeper := preload("res://world/harbor/cemetery/CemeteryKeeper.gd").new()
	world.add_child(keeper)
	keeper.position = Vector2(480,350)
	keeper.set_visual_scale(100)
	keeper.set_physics_process(false)
	keeper.model.rotation.y = PI
	keeper.model.shovel.hide()
	keeper.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in 3: await physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.position = grave.to_global(grave.project_floor(Vector2.ZERO))
	check(not world.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"Tomb footprint blocks physical actors")
	query.position = grave.to_global(grave.project_floor(Vector2(1.5,0)))
	check(world.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"Side aisle stays walkable")
	var walker := CharacterBody2D.new()
	walker.collision_mask = 1
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	collision.shape.radius = 6
	walker.add_child(collision)
	world.add_child(walker)
	walker.position = grave.position + Vector2(-180,0)
	await physics_frame
	check(walker.test_move(walker.transform,Vector2(220,0)),"Swept movement cannot cross the tomb")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/cemetery-standing-0912.png")
	guest.get_run_over(Vector2(400,0))
	keeper.get_run_over(Vector2(0,400))
	var origin := guest.position
	for i in 20:
		guest._physics_process(1.0/60.0)
		keeper._physics_process(1.0/60.0)
	check(guest.fall_presentation.rig.rotation.x > .1,"Funeral guest advances through the fall instead of freezing upright")
	check(guest.position.x > origin.x,"Impact throws guest in the incoming direction")
	check(keeper.fall.joints.size() == 8,"Keeper fall articulates elbows and knees")
	for i in 55:
		guest._physics_process(1.0/60.0)
		keeper._physics_process(1.0/60.0)
	check(absf(guest.model.rotation.x-PI/2)<.01 and not guest.fall_presentation.active,"Funeral guest settles lying down")
	check(absf(keeper.model.rotation.x-PI/2)<.01 and not keeper.fall.active,"Keeper settles lying down")
	check(not keeper.weapon.visible and not keeper.model.shovel.visible,"Dead keeper does not hold tools upright")
	var rest := guest.model.transform
	guest._physics_process(.2)
	check(guest.model.transform.is_equal_approx(rest),"Corpse stays settled after animation ends")
	var gunshot := preload("res://world/harbor/events/WorldEventResident.gd").new()
	world.add_child(gunshot)
	gunshot.position = Vector2(180,540)
	gunshot.set_physics_process(false)
	gunshot.take_damage(100)
	for i in 70: gunshot._physics_process(1.0/60.0)
	check(absf(gunshot.model.rotation.x-PI/2)<.01,"Non-vehicle death also reaches the ground")
	if DisplayServer.get_name() != "headless":
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/cemetery-fallen-0912.png")
	world.queue_free()
	await process_frame
	print("CEMETERY_PHYSICAL_PRESENTATION failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
