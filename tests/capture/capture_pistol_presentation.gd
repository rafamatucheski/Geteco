extends SceneTree
## Close diagnostic atlas for the production V2 rig. Same camera/layout as the
## V1 reference script at tests/visual/capture_pistol_reference.gd.
const SIZE := Vector2i(512, 512)
const LABELS := ["idle", "aim", "fire", "reload", "move_aim"]

func _initialize() -> void: _run.call_deferred()

func _step(actor, pose, gun: Node3D, mode: String, frame: int) -> void:
	var moving := mode == "move_aim"
	var aiming := mode in ["aim", "fire", "reload", "move_aim"]
	var reloading := mode == "reload"
	if moving:
		actor._pose_locomotion(Vector3.BACK, 3.5, Vector3(0, 0, 3.5 / 60.0), 3.5)
	else:
		actor.animation.play("Walking")
		actor.animation.seek(0.067, true)
	if mode == "fire" and frame == 43: pose.attack("pistol")
	var reload_progress := 0.32 if reloading else 0.0
	var result: Dictionary = pose.update("pistol", 1.0 / 60.0, aiming, reloading, reload_progress, moving, false, float(frame % 30) / 30.0)
	actor.combat_facing = 0.0 if aiming else NAN
	actor.set_combat_weapon_pose("pistol", result)
	actor._apply_combat_weapon_pose()
	gun.global_transform = actor.combat_weapon_transform(Vector3(0, -0.04, 0.035))

func _run() -> void:
	var output := "res://evidence/combat/pistol-v2-close.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.trim_prefix("output=")
	var view := SubViewport.new()
	view.size = SIZE
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273039")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cad4df")
	environment.environment.ambient_light_energy = 0.72
	view.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -28, 0)
	key.light_energy = 1.35
	view.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(24, 145, 0)
	fill.light_energy = 0.65
	view.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.95
	camera.position = Vector3(2.1, 1.18, -3.0)
	view.add_child(camera)
	camera.look_at(Vector3(0, 0.88, 0))
	var actor := preload("res://scripts/Actor.gd").new()
	actor.is_player = true
	view.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	var gun := Node3D.new()
	view.add_child(gun)
	preload("res://gameplay/ArsenalWeapon3D.gd").build(gun, "pistol")
	var pose := preload("res://gameplay/WeaponRigPose.gd").new()
	var atlas := Image.create(SIZE.x * LABELS.size(), SIZE.y, false, Image.FORMAT_RGBA8)
	for column in LABELS.size():
		pose.reset()
		for frame in 50:
			_step(actor, pose, gun, LABELS[column], frame)
			await process_frame
		await RenderingServer.frame_post_draw
		var frame_image := view.get_texture().get_image()
		frame_image.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(frame_image, Rect2i(Vector2i.ZERO, SIZE), Vector2i(column * SIZE.x, 0))
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := atlas.save_png(absolute)
	print("PISTOL_V2_CAPTURE ", absolute, " error=", error)
	quit(0 if error == OK else 1)
