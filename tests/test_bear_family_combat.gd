extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures.append(label)
func _run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var region := Node2D.new()
	region.position = Vector2(4300,-4960)
	scene.add_child(region)
	var effects = load("res://world/shared/combat/WeaponEffects.gd").new()
	scene.add_child(effects)
	var player = load("res://Player.gd").new()
	player.name = "Player"
	player.collision_layer = 4
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 7
	player.add_child(shape)
	scene.add_child(player)
	player.set_physics_process(false)
	var bear = load("res://world/mountain_pass/MountainBear.gd").new()
	bear.position = Vector2(500,300)
	region.add_child(bear)
	bear.set_physics_process(false)
	var cubs: Array[Node2D] = []
	for offset in [Vector2(-45,40),Vector2(45,40)]:
		var cub = load("res://world/mountain_pass/MountainBear.gd").new()
		cub.is_cub = true
		cub.family_guardian = bear
		cub.family_offset = offset
		cub.position = bear.position+offset
		region.add_child(cub)
		cub.set_physics_process(false)
		cubs.append(cub)
	check(bear.home == region.to_global(Vector2(500,300)),"home remains global in translated region")
	check(cubs[0].model.scale.x < bear.model.scale.x and cubs[0].health<bear.health,"cub silhouette and health differ from adult")
	check(bear.model.find_children("*","MeshInstance3D",true,false).size()>60,"anatomical detail paws eyes jaw fur")
	player.global_position = bear.home+Vector2(140,0)
	bear.charge_cooldown = 0
	bear._physics_process(0.016)
	check(bear.state == bear.State.WARNING and bear.velocity == Vector2.ZERO,"charge telegraphs before acceleration")
	bear._physics_process(0.75)
	check(bear.state == bear.State.CHARGE,"warning transitions to charge")
	var fixed_heading: Vector2 = bear.charge_direction
	player.global_position += Vector2(0,40)
	bear._physics_process(0.016)
	check(bear.charge_direction == fixed_heading and bear.velocity.length()>200,"charge commits to direction and is dodgeable")
	player.global_position = bear.global_position+fixed_heading*20
	var health_before: int = player.health
	bear._physics_process(0.016)
	check(player.health == health_before-24,"charge hits real exposed player once")
	bear._physics_process(0.016)
	check(player.health == health_before-24,"continuous overlap cannot cause damage every frame")
	player.set_meta("mountain_interior",true)
	bear._physics_process(0.1)
	check(bear.state == bear.State.WANDER and bear.velocity.length()<=32,"entering interior cancels hunting")
	player.remove_meta("mountain_interior")
	player.hide()
	bear._physics_process(0.1)
	check(player.health == health_before-24,"hidden vehicle occupant not bitten")
	player.show()
	player.global_position = cubs[0].global_position+Vector2(30,0)
	var cub_health_before: int = player.health
	cubs[0]._physics_process(0.1)
	check(cubs[0].velocity.length()>60 and player.health == cub_health_before,"cub flees without attacking")
	check(bear.threat_time>0,"nearby cub alerts guardian")
	player.global_position = bear.home+Vector2(500,0)
	bear._physics_process(0.1)
	check(bear.velocity.length()<=32,"adult stays in forest territory")
	check(bear.audio_bank != null and bear.audio_voice.stream != null,"existing external bear audio connected")
	# Real render of a family at a den, before testing projectile death.
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-300,-200),Vector2(300,-200),Vector2(300,200),Vector2(-300,200)])
	ground.position = bear.home
	ground.color = Color("3e4e48")
	ground.z_index = -2
	scene.add_child(ground)
	player.global_position = bear.home+Vector2(0,130)
	camera.set_script(null)
	camera.zoom = Vector2.ONE*3.0
	camera.position = Vector2(0,-85)
	for i in 3: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/bear-family-review.png")
	var bullet = load("res://Bullet.gd").new()
	bullet.damage = 200
	bullet.set_physics_process(false)
	scene.add_child(bullet)
	bullet._hit(bear,bear.global_position,Vector2.UP)
	check(bear.is_dead and bear.collision_layer == 0,"projectile kills and disables physical actor")
	check(bear.get_parent().find_child("WildlifeBlood",false,false) != null,"blood visible on world floor")
	await create_timer(0.55).timeout
	check(absf(bear.model.rotation.z)>1 and bear.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS,"fallen body stops perpetual rendering")
	print("BEAR_FAMILY_COMBAT failures=",failures.size())
	scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
