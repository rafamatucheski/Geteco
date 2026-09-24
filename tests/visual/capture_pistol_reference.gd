extends SceneTree
## V1 reference atlas matching geteco_v2/tests/capture_pistol_presentation.gd.
const SIZE := Vector2i(512, 512)
const LABELS := ["idle", "aim", "fire", "reload", "move_aim"]

func _initialize() -> void: _run.call_deferred()

func _step(player, mode: String, frame: int) -> void:
	var moving := mode == "move_aim"
	var aiming := mode in ["aim", "fire", "reload", "move_aim"]
	player.walk_clock = float(frame) * 0.18
	player._update_locomotion(1.0 / 60.0, moving, false)
	if mode == "fire" and frame == 43: player.combat_pose.on_attack("pistol")
	if mode == "reload" and frame == 0:
		player.weapon_ammo.pistol = {"clip": 0, "reserve": 60}
		player._reload_active_weapon()
	if player.is_reloading() and mode == "reload": player._reload_elapsed = player._reload_duration * 0.32
	player.combat_pose.update(player, 1.0 / 60.0, aiming, false, player._gait_arm_swing())

func _run() -> void:
	var output := "D:/geteco/game/artifacts/combat-parity/pistol-v1-close.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.trim_prefix("output=")
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = preload("res://characters/Player.gd").new()
	var camera_2d := Camera2D.new()
	camera_2d.name = "Camera"
	player.add_child(camera_2d)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.viewport_3d.size = SIZE
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = player.viewport_3d.get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.95
	camera.position = Vector3(2.1, 1.18, -3.0)
	camera.look_at(Vector3(0, 0.88, 0))
	player.weapon_inventory.pistol = true
	player.equip_weapon("pistol")
	player.weapon_ammo.pistol = {"clip": 12, "reserve": 60}
	var atlas := Image.create(SIZE.x * LABELS.size(), SIZE.y, false, Image.FORMAT_RGBA8)
	for column in LABELS.size():
		player._cancel_reload()
		player.combat_pose.weapon_id = ""
		for frame in 50:
			_step(player, LABELS[column], frame)
			await process_frame
		await RenderingServer.frame_post_draw
		atlas.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(Vector2i.ZERO, SIZE), Vector2i(column * SIZE.x, 0))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := atlas.save_png(output)
	print("PISTOL_V1_CAPTURE ", output, " error=", error)
	quit(0 if error == OK else 1)
