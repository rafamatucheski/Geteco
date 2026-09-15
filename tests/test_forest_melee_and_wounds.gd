extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	collision.shape.radius = 7
	player.add_child(collision)
	scene.add_child(player)
	player.set_physics_process(false)
	var logger = load("res://world/mountain_pass/WinterResident.gd").new()
	logger.role = "logger"
	logger.position = Vector2(35,0)
	scene.add_child(logger)
	logger.set_physics_process(false)
	for i in 3: await physics_frame
	player.active_weapon_id = "knife"
	player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("knife"))
	check(logger.health == 58, "knife damages a real winter resident")
	check(logger.has_node("BodyWound"), "knife leaves blood attached to the victim")
	check(logger.retaliation_target == player, "wounded logger identifies the attacker")
	logger._process_retaliation(0.016)
	check(logger.axe_windup > 0, "logger telegraphs axe strike")
	var hp: int = player.health
	logger._process_retaliation(0.4)
	check(player.health == hp - 28 and player.has_node("BodyWound"), "axe damages and bloodies the real player")
	logger._process_retaliation(0.016)
	check(player.health == hp - 28, "axe cooldown prevents damage every frame")
	logger.health = 80
	logger.position = Vector2(-35,0)
	player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("knife"))
	check(logger.health == 80, "knife does not hit behind the player")
	logger.position = Vector2(100,0)
	player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("knife"))
	check(logger.health == 80, "knife cannot hit beyond reach")
	logger.position = Vector2(35,0)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(17,0)
	var wall_shape := CollisionShape2D.new()
	wall_shape.shape = RectangleShape2D.new()
	wall_shape.shape.size = Vector2(5,60)
	wall.add_child(wall_shape)
	scene.add_child(wall)
	await physics_frame
	player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("knife"))
	check(logger.health == 80, "wall blocks knife damage")
	logger.axe_cooldown = 0
	logger.axe_windup = 0.1
	hp = player.health
	logger._process_retaliation(0.2)
	check(player.health == hp, "wall blocks retaliating axe")
	wall.queue_free()
	await physics_frame
	logger.set_meta("combat_attacker", player)
	logger.hear_gunfire(player.global_position, Vector2(400,0))
	check(logger.retaliation_left > 0 and logger.retaliation_target == player, "gunfire provokes logger instead of civilian escape")
	logger.work_station.model.chop()
	check(logger.work_station.model.split_count == 1, "logger splits wood at work station")
	var civilian = load("res://world/mountain_pass/WinterResident.gd").new()
	civilian.position = Vector2(200,100)
	scene.add_child(civilian)
	civilian.set_physics_process(false)
	civilian.hear_gunfire(Vector2.ZERO, Vector2(400,0))
	check(civilian.panic_timer > 0 and civilian.retaliation_left == 0, "unarmed resident seeks safety")
	check(civilian._visual_interval() <= 1.0 / 60.0, "nearby residents animate at city frame rate")
	var bullet = load("res://Bullet.gd").new()
	bullet.damage = 10
	bullet.set_physics_process(false)
	scene.add_child(bullet)
	hp = player.health
	bullet._hit(player,player.global_position,Vector2.UP)
	check(player.health == hp - 10 and player.has_node("BodyWound"), "bullet wounds player")
	var skier = load("res://world/mountain_pass/MountainSkier.gd").new()
	skier.position = Vector2(35,0)
	scene.add_child(skier)
	skier.set_physics_process(false)
	logger.position = Vector2(300,0)
	player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("knife"))
	check(skier.health == 58 and skier.model.fallen, "skiers react to injury instead of ignoring combat")
	var pickup = load("res://world/mountain_pass/MountainWeaponPickup.gd").new()
	pickup.weapon_id = "axe"
	pickup.pickup_id = "test_forest_axe"
	pickup.position = Vector2(500,500)
	scene.add_child(pickup)
	player.personal_loadout_enabled = true
	player.personal_loadout = {"curta":"", "longa":"", "corpo":"", "granada":""}
	pickup._collect(player)
	check(player.weapon_inventory.get("axe",false) and player.personal_loadout.corpo == "axe", "collected axe enters melee loadout")
	check(player.weapon_ammo.axe.clip == -1 and player.active_weapon_id == "axe", "axe equips without ammunition")
	var saved: Dictionary = player.serialize()
	player.restore(JSON.parse_string(JSON.stringify(saved)))
	check(player.weapon_inventory.get("axe",false) and player.personal_loadout.corpo == "axe" and player.world_pickups_collected.has("test_forest_axe"), "axe ownership loadout and collection survive JSON restore")
	var mesh := Node3D.new()
	load("res://scripts/player/ArsenalWeapon3D.gd").build(mesh,"axe")
	check(mesh.has_node("AshHandle") and mesh.has_node("SteelHead"), "equipped axe uses axe geometry")
	mesh.free()
	var city_person = load("res://AnimatedPedestrian3D.gd").new()
	city_person.position = Vector2(35,0)
	scene.add_child(city_person)
	city_person.set_physics_process(false)
	skier.position = Vector2(200,0)
	var city_hp: int = city_person.health
	player._perform_melee_attack(Vector2.RIGHT, WeaponCatalog.get_weapon("knife"))
	check(city_person.health == city_hp - 22 and city_person.has_node("BodyWound"), "city pedestrian takes knife damage and bleeds")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,720)
		camera.enabled = true
		camera.zoom = Vector2.ONE * 4.0
		camera.position = Vector2(65,-15)
		logger.position = Vector2(95,15)
		logger.model.activity = "work"
		logger.model._process(0.5)
		logger.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		var ground := Polygon2D.new()
		ground.polygon = PackedVector2Array([Vector2(-500,-500),Vector2(500,-500),Vector2(500,500),Vector2(-500,500)])
		ground.color = Color("4e5b42")
		ground.z_index = -10
		scene.add_child(ground)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/forest-combat-review.png")
	print("FOREST_COMBAT failures=", failures.size())
	scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
