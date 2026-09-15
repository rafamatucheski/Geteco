extends SceneTree

var failures: Array[String] = []
var output := "D:/geteco/artifacts/weapon-realism-0913/effects"

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(960, 540)
	RenderingServer.set_default_clear_color(Color("273039"))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	camera.zoom = Vector2(3, 3)
	camera.position_smoothing_enabled = false
	player.set_physics_process(false)
	player.position = Vector2(95, 125)
	player.model_root.rotation.y = -PI/2
	for id in ["rpg", "flamethrower"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		player.weapon_ammo[id] = {"clip": 100, "reserve": 100}
		for frame in 60: player.combat_pose.update(player, 1.0/60, true, false, 0)
		var origin: Vector2 = player.get_weapon_muzzle_position()
		player._shoot_towards(player.global_position + Vector2(1000, 0))
		var spawned: Node2D
		for node in world.get_children():
			if node.get_script() == load("res://guns/Bullet.gd") or node is FlameJet: spawned = node
		check(spawned != null, id + " creates a real projectile/effect")
		check(spawned.global_position.distance_to(origin) < 0.01, id + " leaves the visible nozzle")
		if id == "rpg":
			spawned.set_physics_process(false)
			await process_frame
			var exhaust := spawned.get_node_or_null("RocketExhaust") as Polygon2D
			check(exhaust != null and exhaust.visible, "rocket motor burns on first rendered frame")
			if exhaust:
				for heading in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
					spawned.rotation = heading.angle()
					check((exhaust.global_position - spawned.global_position).dot(heading) < 0, "exhaust stays behind rocket in every direction")
			spawned.rotation = 0
			spawned.position += Vector2(60, 0)
			await capture("rocket-launch")
			spawned.queue_free()
			player.weapon_ammo[id].clip = 0
			player.combat_pose.update(player, 1.0/60, true, false, 0)
			check(not player.current_gun_mesh.get_node("LoadedRocket").visible, "fired launcher has no second loaded warhead")
		else:
			var flame := spawned as FlameJet
			check(flame.flame_body.initial_velocity_max * flame.flame_body.lifetime >= flame.flame_range - 1, "visible stream reaches its gameplay range")
			check(not flame.flame_body.local_coords, "released flame stays in the world when the operator turns")
			for tick in 12:
				await create_timer(0.05).timeout
				player.fire_cooldown = 0
				player._shoot_towards(player.global_position + Vector2(1000, 0))
				player.combat_pose.update(player, 0.05, true, false, 0)
			await capture("flamethrower-stream")
			await create_timer(0.65).timeout
			var remaining := 0
			for node in world.get_children():
				if node is FlameJet: remaining += 1
			check(remaining == 0, "flame packets finish after trigger release")
	player._flamethrower_audio.stop()
	world.queue_free()
	await process_frame
	print("WEAPON_EFFECTS_REALISM failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
