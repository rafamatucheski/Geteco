extends SceneTree
var failures: Array[String] = []
var world: Node2D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in 3: await physics_frame
	await process_frame
func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	player.name = "Player"
	player.collision_layer = 4
	player.collision_mask = 7
	var shape := CollisionShape2D.new()
	shape.name = "Collision"
	shape.shape = CapsuleShape2D.new()
	shape.shape.radius = 5
	shape.shape.height = 16
	player.add_child(shape)
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	var npc = load("res://world/harbor/urban_transit/UrbanPassenger.gd").new()
	world.add_child(npc)
	for actor in [player,npc]: actor.set_physics_process(false)
	var review_camera := Camera2D.new()
	world.add_child(review_camera)
	for angle in [0.0,PI,PI/2,-PI/2]:
		var station = load("res://world/harbor/urban_transit/UrbanTubeStop.gd").new()
		station.position = Vector2(1000,1000)
		station.rotation = angle
		world.add_child(station)
		review_camera.global_position = station.global_position
		review_camera.zoom = Vector2.ONE*2
		review_camera.make_current()
		await settle()
		for slot in 4:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = npc.get_node("CollisionShape2D").shape
			query.collision_mask = 1
			for spawn in [station.sidewalk_position(slot),station.queue_position(slot)]:
				query.transform = Transform2D(0,spawn)
				check(world.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),"authored NPC spawn/queue is clear")
			for other in range(slot): check(station.sidewalk_position(slot).distance_to(station.sidewalk_position(other))>=22,"NPC spawns never overlap")
		for actor in [player,npc]:
			var original: Node = actor.model_root.get_parent()
			actor.global_position = station.ramp_approach()
			await settle()
			check(actor.has_meta("interior_actor_presentation"),"automatic admission %s %s"%[actor.name,angle])
			var helper: Node = actor.get_meta("interior_actor_presentation")
			check(actor.model_root.get_viewport()==station.view.viewport_3d and not actor.sprite_3d_display.visible,"shared depth %s"%actor.name)
			for segment in [[Vector2(0,-65),Vector2(0,80)],[Vector2(0,65),Vector2(0,-100)],[Vector2(-185,7),Vector2(100,0)],[Vector2(175,-40),Vector2(0,90)],[Vector2(175,55),Vector2(0,-90)],[Vector2(123,60),Vector2(0,-100)]]:
				actor.global_position = station.to_global(segment[0])
				var hit: KinematicCollision2D = actor.move_and_collide(segment[1].rotated(angle))
				check(hit != null,"wall/ramp side/closed gate blocks sweep %s %s %s"%[actor.name,angle,segment])
			actor.global_position = station.ramp_approach()
			for point in [Vector2(185,8),Vector2(165,8),Vector2(151,8),Vector2(100,8),Vector2(25,8),Vector2(100,8),Vector2(151,8),Vector2(185,8),Vector2(207,8)]:
				var target: Vector2 = station.to_global(point)
				var hit: KinematicCollision2D = actor.move_and_collide(target-actor.global_position)
				check(hit==null and actor.global_position.distance_to(target)<0.01,"ramp/corridor/exit open %s %s %s"%[actor.name,angle,point])
				helper._update_scale()
				check(absf(helper.anchor.position.y-station.floor_height(point))<0.001,"feet follow ramp")
			for bench_x in [-101,-53,-5]:
				actor.global_position = station.to_global(Vector2(bench_x,8))
				check(actor.move_and_collide(Vector2(0,-50).rotated(angle))!=null,"bench blocks %s"%actor.name)
			actor.global_position = station.to_global(Vector2(100,8))
			helper._update_scale()
			if actor==player: check(player.get_weapon_muzzle_position().distance_to(helper.project_world(player.muzzle_flash_3d.global_position))<0.01,"muzzle projection")
			if DisplayServer.get_name() != "headless":
				await check_depth_occlusion(actor,helper,station)
			actor.global_position = Vector2.ZERO
			await settle()
			check(actor.model_root.get_parent()==original and actor.sprite_3d_display.visible,"exit restores rig %s"%actor.name)
		# Two simultaneous occupants, removal and viewport cleanup.
		player.global_position = station.to_global(Vector2(60,8))
		npc.global_position = station.to_global(Vector2(100,8))
		await settle()
		check(station.presentations.size()==2,"two actors share station depth")
		station.gate_open = true
		station.gate_shape.disabled = true
		npc.global_position = station.to_global(Vector2(123,19))
		station._physics_process(0.016)
		check(station.gate_open,"closing gate waits for complete NPC body")
		npc.global_position = station.to_global(Vector2(100,8))
		station._physics_process(0.016)
		check(not station.gate_open,"gate closes after aperture clears")
		station._actor_exited(npc)
		npc.global_position = Vector2.ZERO
		await settle()
		check(station.presentations.size()==1,"one exit preserves other actor")
		player.global_position = Vector2.ZERO
		await settle()
		check(station.view.animated_people==0 and station.view.viewport_3d.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,"empty station stops continuous rendering")
		# Invalid old position must recover before accepting control.
		player.global_position = station.to_global(Vector2(-101,-18))
		await settle()
		check(player.global_position.distance_to(station.spawn_point.global_position)<0.01,"invalid save recovered")
		station.queue_free()
		await settle()
		check(is_instance_valid(player.model_root) and player.sprite_3d_display.visible,"unload restores player")
		player.global_position = Vector2.ZERO
	print("TUBE_ACCESS failures=",failures)
	quit(0 if failures.is_empty() else 1)

func check_depth_occlusion(actor: Node2D, helper: Node, station: Node2D) -> void:
	# An opaque object between camera and actor must hide the rig completely.
	# Compare the same rendered crop with/without the rig behind that object.
	actor.global_position = station.to_global(Vector2(60,8))
	helper._update_scale()
	helper.set_process(false)
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 4, .2)
	panel.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	station.view.viewport_3d.add_child(panel)
	panel.position = helper.anchor.position + Vector3(0, 1, 0) + (station.view.camera_3d.position - helper.anchor.position).normalized() * 1.5
	panel.look_at(station.view.camera_3d.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = station.view.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = station.view.viewport_3d.get_texture().get_image()
	var pixel: Vector2 = station.view.camera_3d.unproject_position(helper.anchor.position + Vector3.UP * .9)
	var changed := 0
	for y in range(int(pixel.y)-25, int(pixel.y)+25):
		for x in range(int(pixel.x)-20, int(pixel.x)+20):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y): changed += 1
	check(changed == 0, "Opaque room geometry hides the actor in the real depth buffer")
	print("DEPTH_OCCLUSION actor=", actor.name, " changed_pixels=", changed)
	# Positive control prevents an invisible or misplaced rig from passing.
	panel.hide()
	helper.anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	with_actor = station.view.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	without_actor = station.view.viewport_3d.get_texture().get_image()
	changed = 0
	for y in range(int(pixel.y)-25, int(pixel.y)+25):
		for x in range(int(pixel.x)-20, int(pixel.x)+20):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y): changed += 1
	check(changed > 100, "Unobstructed actor is visible at the same ground position")
	print("DEPTH_VISIBLE_CONTROL actor=", actor.name, " changed_pixels=", changed)
	panel.queue_free()
	helper.anchor.show()

	helper.set_process(true)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/tube-access/depth")
	station.view.viewport_3d.get_texture().get_image().save_png("D:/geteco/artifacts/tube-access/depth/%s-%s.png"%[actor.name,station.rotation])
