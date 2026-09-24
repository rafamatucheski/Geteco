extends SceneTree
var failures := 0
class Target extends Node2D:
	var health := 100
	func take_damage(amount, _melee): health -= amount
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var effects := preload("res://guns/combat/WeaponEffects.gd").new()
	scene.add_child(effects)
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.weapon_inventory.axe = true
	player.equip_weapon("axe")
	for i in 60: player.combat_pose.update(player, 1.0/60, true, false, 0)
	for id in ["axe", "bat"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		for i in 60: player.combat_pose.update(player, 1.0/60, false, false, 0)
		var weapon: Node3D = player.current_gun_mesh
		var idle_tip: Vector3 = player.model_root.to_local(weapon.to_global(Vector3(0,0,-0.44)))
		check(idle_tip.z > 0.1, id + " rests behind the shoulder")
		check(not player.combat_pose.melee_support_active, id + " idle leaves support hand free")
		player.combat_pose.on_attack(id)
		var grip_error := 0.0
		var support_error := 0.0
		var support_frames := 0
		var blade_low := INF
		var travel := 0.0
		for i in 60:
			player.combat_pose.update(player, 1.0/60, false, false, 0)
			grip_error = maxf(grip_error, player.right_lower_arm.get_node("Palm").global_position.distance_to(weapon.to_global(player.combat_pose.GRIPS[id])))
			if player.combat_pose.melee_support_active:
				support_frames += 1
				var support: Vector3 = player.combat_pose.SUPPORT_GRIPS[id]
				if id == "axe": support = player.combat_pose.GRIPS[id] + Vector3(0,0,-0.12)
				support_error = maxf(support_error, player.left_lower_arm.get_node("Palm").global_position.distance_to(weapon.to_global(support)))
			var blade := weapon.to_global(Vector3(0,0,-0.44))
			blade_low = minf(blade_low, blade.y)
			travel = maxf(travel, player.model_root.to_local(blade).distance_to(idle_tip))
		check(grip_error < 0.001, id + " dominant palm stays on handle")
		check(support_frames > 5 and support_error < 0.035, id + " support joins handle during strike")
		check(blade_low > 0.05, id + " never crosses floor")
		check(travel > 0.5, id + " makes a full swing from shoulder")
		check(not player.combat_pose.melee_support_active, id + " releases support after recovery")
	player.equip_weapon("axe")
	var trail: Node = player.current_gun_mesh.get_node("AxeSwingTrail")
	check(trail.samples.is_empty() and not trail.ribbon.visible, "short ribbon expires after swing")
	var target := Target.new()
	target.position = Vector2(35,0)
	scene.add_child(target)
	target.add_to_group("damageable")
	var data := WeaponCatalog.get_weapon("axe")
	player._perform_melee_attack(Vector2.RIGHT, data)
	check(target.health == 100, "windup does not deal instant damage")
	await create_timer(0.15).timeout
	check(target.health == 100, "target remains intact before blade contact")
	await create_timer(0.18).timeout
	check(target.health == 48, "contact deals one catalog hit")
	check(effects._live_effects > 0, "contact creates material impact effect")
	await create_timer(0.4).timeout
	check(target.health == 48, "recovery cannot deal duplicate damage")
	target.health = 100
	player._perform_melee_attack(Vector2.RIGHT, data)
	player.equip_weapon("fists")
	await create_timer(0.35).timeout
	check(target.health == 100, "switching cancels pending axe hit")
	player.equip_weapon("axe")
	var wall := StaticBody2D.new()
	var hull := CollisionShape2D.new()
	hull.shape = RectangleShape2D.new()
	hull.shape.size = Vector2(5,60)
	wall.add_child(hull)
	wall.position = Vector2(15,0)
	scene.add_child(wall)
	await physics_frame
	player._perform_melee_attack(Vector2.RIGHT, data)
	await create_timer(0.35).timeout
	check(target.health == 100, "wall receives contact instead of target behind it")
	scene.queue_free()
	await process_frame
	print("AXE_SWING failures=", failures)
	quit(0 if failures == 0 else 1)
