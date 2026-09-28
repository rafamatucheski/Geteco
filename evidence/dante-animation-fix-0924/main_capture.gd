extends SceneTree
const OUT := "res://evidence/dante-animation-fix-0924/"
var world
var player
var label := ""
var previous: Array = []
var measurements := {}
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for tick in n: await physics_frame
func face(direction: Vector3) -> void:
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0; down.y = 0
	root.get_node("GameInput").touch_aim = Vector2(direction.dot(right.normalized()), direction.dot(down.normalized()))
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
func observe() -> void:
	if label.is_empty(): return
	var now: Array = player._capture_pose()
	var worst := 0.0
	var bone := ""
	if not previous.is_empty():
		for i in now.size():
			var angle := rad_to_deg((previous[i][1] as Quaternion).angle_to(now[i][1]))
			if angle > worst: worst = angle; bone = player.skeleton.get_bone_name(i)
	previous = now
	if not measurements.has(label) or worst > measurements[label].degrees:
		measurements[label] = {"degrees": worst, "bone": bone, "clip": player.animation.current_animation, "run": player._run_weight}
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(150).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for tick in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(4); return
	player = world.player
	player.controlled_automatically = true
	world.gameplay.health = 1000000
	world.gameplay.state.economy.activate_arsenal_cheat()
	world.camera.target_size = 6.0
	world.session.weather.time_of_day = 0.36
	await frames(60)
	var anchor: Vector3 = player.global_position
	var direction: Vector3 = Vector3.RIGHT
	physics_frame.connect(observe)
	for scenario in ["idle", "walk", "run", "turn", "backfire", "sidefire", "fists", "axe"]:
		player.teleport(anchor)
		player.automatic_direction = Vector3.ZERO
		world.gameplay.state.equip_weapon("smg" if scenario.ends_with("fire") else ("axe" if scenario == "axe" else "fists"))
		face(direction)
		Input.action_release("aim")
		if scenario in ["turn", "backfire", "sidefire", "fists", "axe"]: Input.action_press("aim")
		await frames(60)
		label = scenario
		previous = player._capture_pose()
		player.speed = 6.5 if scenario in ["run", "backfire"] else 3.5
		if scenario in ["walk", "run"]: player.automatic_direction = direction
		if scenario == "backfire": player.automatic_direction = -direction
		if scenario == "sidefire": player.automatic_direction = direction.rotated(Vector3.UP, PI * .5)
		for tick in 90:
			if scenario == "turn": face(direction.rotated(Vector3.UP, TAU * tick / 90.0))
			if scenario in ["backfire", "sidefire", "fists", "axe"] and tick % 30 == 0:
				world.gameplay.fire_at(player.global_position + direction * 15)
			await physics_frame
			if tick % 5 == 0: await capture("main_%s_%02d" % [scenario, tick])
		label = ""
	Input.action_release("aim")
	root.get_node("GameInput").touch_aim = Vector2.ZERO
	player.automatic_direction = Vector3.ZERO
	world.gameplay.clear_wanted()
	var car = world.driving.car
	world.camera.target_size = 7.0
	player.teleport(car.driver_door_anchor(-1) + car.global_basis.x * -0.42)
	await frames(10)
	if world.driving.interact():
		for tick in 120:
			await physics_frame
			if tick % 12 == 0: await capture("main_board_%02d" % tick)
		if world.driving.leave():
			for tick in 135:
				await physics_frame
				if tick % 15 == 0: await capture("main_exit_%02d" % tick)
	FileAccess.open(OUT.path_join("main-review.json"), FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t"))
	print("MAIN_REVIEW ", JSON.stringify(measurements))
	quit()
