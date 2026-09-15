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
	for variant in 2:
		player.combat_pose.on_attack("axe")
		var grip_error := 0.0
		var support_error := 0.0
		var blade_top := -INF
		var blade_low := INF
		var blade_left := INF
		var blade_right := -INF
		for i in 60:
			player.combat_pose.update(player, 1.0/60, true, false, 0)
			var weapon: Node3D = player.current_gun_mesh
			grip_error = maxf(grip_error, player.right_lower_arm.get_node("Palm").global_position.distance_to(weapon.to_global(player.combat_pose.GRIPS.axe)))
			support_error = maxf(support_error, player.left_lower_arm.get_node("Palm").global_position.distance_to(weapon.to_global(player.combat_pose.SUPPORT_GRIPS.axe)))
			var blade := weapon.to_global(Vector3(0.19,0,-0.44))
			blade_top = maxf(blade_top, blade.y)
			blade_low = minf(blade_low, blade.y)
			blade_left = minf(blade_left, blade.x)
			blade_right = maxf(blade_right, blade.x)
		check(grip_error < 0.001, "dominant palm stays on handle: " + str(grip_error))
		check(support_error < 0.035, "support palm stays on handle throughout chop: " + str(support_error))
		check(blade_low > 0.05, "blade never crosses floor")
		check(blade_top - blade_low > 0.5 if variant == 0 else blade_right - blade_left > 0.6, "vertical/lateral sweep follows distinct axis")
		check(player.combat_pose.axe_variant == variant, "consecutive attacks alternate vertical and lateral")
		var before_contact: Dictionary = player.combat_pose.axe_targets(0.24, true, false)
		var at_contact: Dictionary = player.combat_pose.axe_targets(0.26, true, false)
		var head_offset: Vector3 = Vector3(0,0,-0.44) - player.combat_pose.GRIPS.axe
		var travel: Vector3 = (at_contact.hand + at_contact.basis * head_offset) - (before_contact.hand + before_contact.basis * head_offset)
		check(at_contact.basis.x.dot(travel.normalized()) > 0.7, "cutting edge leads the strike, variant " + str(variant))
		if variant == 1:
			var nearest_head_z := -INF
			var outward := 1.0
			for frame in range(28, 73):
				var pose: Dictionary = player.combat_pose.axe_targets(frame / 100.0, true, false)
				outward = minf(outward, pose.basis.z.z)
				for x in [-0.055, 0.19]:
					for y in [-0.0225, 0.0225]:
						for z in [-0.525, -0.365]:
							var corner: Vector3 = pose.hand + pose.basis * (Vector3(x,y,z) - player.combat_pose.GRIPS.axe)
							nearest_head_z = maxf(nearest_head_z, corner.z)
			check(nearest_head_z < -0.27, "entire axe head stays ahead of belly through follow-through and recovery: " + str(nearest_head_z))
			check(outward > 0.65, "shaft points outward throughout lateral recovery")
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
