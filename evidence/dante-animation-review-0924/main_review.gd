extends SceneTree
const OUT = "res://evidence/dante-animation-review-0924/"
var world
var player
var label := ""
var previous: Array = []
var measurements := {}
var trace := []
func _initialize() -> void: run.call_deferred()
func observe() -> void:
	if label.is_empty() or player == null: return
	var now: Array = player._capture_pose()
	if not previous.is_empty():
		var worst := 0.0
		var bone := ""
		for i in now.size():
			var angle := rad_to_deg((previous[i][1] as Quaternion).angle_to(now[i][1]))
			if angle > worst:
				worst = angle
				bone = player.skeleton.get_bone_name(i)
		var entry := {"label":label,"degrees":worst,"bone":bone,"age":world.gameplay._rig_pose.action_age,"left_fist":world.gameplay._pose_frame.get("left_fist"),"left_free":world.gameplay._pose_frame.get("left_free")}
		trace.append(entry)
		if not measurements.has(label) or worst > measurements[label].degrees: measurements[label] = entry
	previous = now
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	create_timer(90).timeout.connect(func(): quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for tick in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(4)
		return
	player = world.player
	player.controlled_automatically = true
	player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 1000000
	world.gameplay.state.economy.activate_arsenal_cheat()
	world.camera.target_size = 8.0
	if world.session.weather != null: world.session.weather.time_of_day = 0.36
	var controls = root.get_node("GameInput")
	controls.touch_aim = Vector2(0,1)
	Input.action_press("aim")
	for tick in 60: await physics_frame
	physics_frame.connect(observe)
	for id in ["fists","fists","axe","smg"]:
		world.gameplay.state.equip_weapon(id)
		for tick in 60: await physics_frame
		label = id + str(measurements.size())
		previous = player._capture_pose()
		var direction: Vector3 = world.gameplay._aim_direction()
		var accepted: bool = world.gameplay.fire_at(player.global_position + direction * 15.0)
		print("MAIN_ACTION ", label," accepted=",accepted)
		for tick in 75:
			await physics_frame
			if tick in [0,4,8,12,16,18,19,20,24,35,50]:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT.path_join("main_%s_%02d.png" % [label,tick]))
		label = ""
	Input.action_release("aim")
	controls.touch_aim = Vector2.ZERO
	FileAccess.open(OUT.path_join("main-review.json"),FileAccess.WRITE).store_string(JSON.stringify({"measurements":measurements,"trace":trace},"\t"))
	print("MAIN_REVIEW ",JSON.stringify(measurements))
	quit()
