extends SceneTree
var player
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func step(aiming := true) -> void:
	player.meshy_rig.prepare_pose(1.0 / 60.0, false, false)
	player.combat_pose.update(player, 1.0 / 60.0, aiming, false, 0.0)
	player.meshy_rig.update_pose(1.0 / 60.0, false, false)

func palm(side: String) -> Vector3:
	return player.model_root.to_local(player.meshy_rig.palm_position(side))

func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	for id in ["knife", "grenade", "fists"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		for i in 90: step()
		var left := palm("Left")
		check(left.y < 0.76 and left.x < -0.12 and absf(left.z) < 0.12, id + " aiming leaves free hand beside thigh: " + str(left))
		if id != "knife":
			check(palm("Right").y < 0.82, id + " aiming keeps holding/idle hand low")
		player.combat_pose.on_attack(id)
		var left_strike: bool = player.combat_pose.punch_left
		for i in 9: step()
		if id == "fists":
			var active := "Left" if left_strike else "Right"
			var resting := "Right" if left_strike else "Left"
			check(palm(active).y > 0.86 and palm(active).z < -0.20, "punch raises and extends only striking hand")
			check(palm(resting).y < 0.77, "opposite fist stays lowered")
			for i in 45: step()
			player.combat_pose.on_attack(id)
			check(player.combat_pose.punch_left != left_strike, "successive punches alternate hands")
			for i in 9: step()
			check(palm(resting).y > 0.86 and palm(active).y < 0.77, "second punch raises opposite hand and lowers first")
		else:
			check(palm("Left").y < 0.76, id + " attack leaves free arm lowered")
		for i in 60: step()
		check(palm("Left").y < 0.76, id + " recovers to lowered free hand")
	# The shared Square binding must not both reload and trigger physics-polled
	# doors/pickups. A full magazine leaves the same press available to interact.
	player.weapon_inventory.pistol = true
	player.equip_weapon("pistol")
	player.weapon_ammo.pistol = {"clip": 0, "reserve": 24}
	var square := InputEventJoypadButton.new()
	square.button_index = JOY_BUTTON_X
	square.pressed = true
	Input.action_press("interact")
	player._input(square)
	check(player.is_reloading() and not Input.is_action_pressed("interact"), "Square starts reload and suppresses physics-polled interaction")
	player._cancel_reload()
	player.weapon_ammo.pistol.clip = player.get_weapon_data("pistol").magazine_size
	Input.action_press("interact")
	player._input(square)
	check(not player.is_reloading() and Input.is_action_pressed("interact"), "full magazine leaves Square available for interaction")
	Input.action_release("interact")
	scene.queue_free()
	await process_frame
	print("RELAXED_COMBAT_POSES failures=", failures)
	quit(0 if failures == 0 else 1)
