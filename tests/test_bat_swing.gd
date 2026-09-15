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
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.weapon_inventory.bat = true
	player.equip_weapon("bat")
	for i in 60: player.combat_pose.update(player, 1.0/60, true, false, 0)
	player.combat_pose.on_attack("bat")
	var grip_error := 0.0
	var leftmost := INF
	var rightmost := -INF
	for i in 40:
		player.combat_pose.update(player, 1.0/60, true, false, 0)
		var weapon: Node3D = player.current_gun_mesh
		grip_error = maxf(grip_error, player.left_lower_arm.get_node("Palm").global_position.distance_to(weapon.to_global(player.combat_pose.SUPPORT_GRIPS.bat)))
		var tip := weapon.to_global(Vector3(0,0,-0.5))
		leftmost = minf(leftmost, tip.x)
		rightmost = maxf(rightmost, tip.x)
	check(grip_error < 0.035, "support hand stays on handle")
	check(rightmost-leftmost > 0.45, "bat sweeps visibly across the front")
	var sound = preload("res://audio/combat/BatAudio.gd").swing()
	check(sound.get_length() > 0.3 and sound == preload("res://audio/combat/BatAudio.gd").swing(), "bat air sound is cached")
	var target := Target.new()
	target.position = Vector2(35,0)
	scene.add_child(target)
	target.add_to_group("damageable")
	# Finish rig initialization before measuring the contact window.
	await create_timer(0.3).timeout
	var data := WeaponCatalog.get_weapon("bat")
	player._perform_melee_attack(Vector2.RIGHT, data)
	check(target.health == 100, "windup does not deal instant damage")
	await create_timer(0.15).timeout
	check(target.health == 100, "target remains intact before bat contact")
	await create_timer(0.18).timeout
	check(target.health == 65, "contact deals one catalog hit")
	check(scene.has_node("CombatImpactAudio") and scene.get_node("CombatImpactAudio").events_played == 1, "contact plays one material impact sound")
	await create_timer(0.4).timeout
	check(target.health == 65, "recovery cannot deal duplicate damage")
	target.health = 100
	player._perform_melee_attack(Vector2.RIGHT, data)
	player.equip_weapon("fists")
	await create_timer(0.35).timeout
	check(target.health == 100, "switching cancels pending bat hit")
	player.equip_weapon("bat")
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
	print("BAT_SWING failures=", failures)
	quit(0 if failures == 0 else 1)
