extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	assert(player.active_weapon_id == "fists", "New player starts unarmed")
	for id in player.weapon_inventory:
		assert(player.weapon_inventory[id] == (id == "fists"), "No starting weapons")
	assert(player.weapon_ammo.pistol.clip == 0 and player.weapon_ammo.pistol.reserve == 0, "No starting pistol ammunition")
	player.equip_weapon("pistol")
	assert(player.active_weapon_id == "fists", "Unowned pistol cannot be equipped")
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	assert(is_equal_approx(player.velocity.length(), 27.6), "Walking is 15 percent faster")
	Input.action_press("sprint")
	player._physics_process(1.0 / 60.0)
	assert(is_equal_approx(player.velocity.length(), 90.0), "Running is 25 percent faster")
	Input.action_release("sprint")
	Input.action_release("move_right")
	player.velocity = Vector2.ZERO
	var cabin = load("res://world/mountain_pass/MountainCabinInterior.gd").new()
	world.add_child(cabin)
	player.global_position = cabin.spawn_point.global_position
	var native_pixels: Array[float] = []
	for direction in [Vector2.RIGHT, Vector2.DOWN]:
		var cam: Camera3D = player.viewport_3d.get_camera_3d()
		var axis := Vector3(direction.x, 0, direction.y) * .01
		native_pixels.append(cam.unproject_position(axis).distance_to(cam.unproject_position(-axis)) * player.sprite_3d_display.scale.x / .02)
	for script in ["res://world/shared/interiors/InteriorActorPresentation.gd", "res://world/mountain_pass/MountainInteriorActorScale.gd"]:
		var helper = load(script).new()
		world.add_child(helper)
		helper.configure(player, cabin.camera_3d, cabin.sprite_3d)
		for i in 2:
			var direction := Vector2.RIGHT if i == 0 else Vector2.DOWN
			var factor: float = player._movement_projection_scale(direction)
			assert(factor > 1.0, "Enlarged rooms must not retain outdoor pixel speed")
			assert(absf(24.0 * factor / helper.pixels_per_rig_unit(direction) - 24.0 / native_pixels[i]) < .001, "Walking covers the same rig distance per second indoors")
			print("MOVEMENT_SCALE ", script.get_file(), " direction=", direction, " factor=", factor, " walk=", 24*factor, " run=", 72*factor)
		var start := Time.get_ticks_usec()
		for i in 10000: player._movement_projection_scale(Vector2.RIGHT)
		print("PROJECTION_CPU_US_PER_CALL ", (Time.get_ticks_usec()-start)/10000.0)
		var braking_scale: float = player._movement_projection_scale(Vector2.RIGHT)
		player.velocity = Vector2.RIGHT * 72.0 * braking_scale
		player._physics_process(1.0 / 60.0)
		assert(absf(player.velocity.x / braking_scale - 57.0) < .01, "Indoor braking preserves outdoor stopping time")
		player.velocity = Vector2.ZERO
		helper.restore()
		assert(is_equal_approx(player._movement_projection_scale(Vector2.RIGHT), 1.0), "Leaving restores outdoor speed")
		helper.queue_free()
	var worker = load("res://prototypes/gameplay_repair_art_0909/CemeteryWorkerModel.gd").new()
	var guest = load("res://world/harbor/cemetery/CemeteryResidentModel.gd").new()
	world.add_child(worker)
	world.add_child(guest)
	guest.set_process(false)
	guest.walking = true
	var start := Time.get_ticks_usec()
	for i in 1000:
		worker.update_animation(1.0/30.0, true, .04)
		guest.travel_metres = .04
		guest._process(1.0/30.0)
		for knee in [worker.left_knee, worker.right_knee, guest.knees[0], guest.knees[1]]:
			var foot: Node3D = knee.get_node("StrideFoot")
			assert(absf(foot.global_rotation.x) < .001, "Boot remains level")
			assert(foot.global_position.y > .07, "Boot clears floor")
	print("TWO_NPC_POSES_CPU_US ", (Time.get_ticks_usec()-start)/1000.0)
	print("MOVEMENT_PROJECTION_SCALE passed")
	quit()
