extends SceneTree

## Actual production rig, identical light/camera before and after the revision.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.active_weapon_id = "fists"
	player._update_equipped_weapon_3d_mesh()
	if not OS.get_cmdline_user_args().has("--before"):
		player._update_locomotion(1.0 / 60.0, false, false)
	var viewport: SubViewport = player.viewport_3d
	viewport.size = Vector2i(320, 400)
	viewport.msaa_3d = Viewport.MSAA_4X
	var cam: Camera3D = viewport.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.75
	cam.position = Vector3(0, 1.05, 3.5)
	cam.look_at(Vector3(0, 0.72, 0))
	var output := "D:/geteco/artifacts/dante-0910"
	var tag := "before" if OS.get_cmdline_user_args().has("--before") else "after"
	var atlas := Image.create(1280, 800, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("28303a"))
	for row in 2:
		if row == 1:
			cam.position = Vector3(0, 3.2, 1.4)
			cam.look_at(Vector3(0, 0.65, 0))
		for column in 4:
			for frame in 60:
				player.combat_pose.update(player, 1.0 / 60.0, false, false, 0.0)
			player.model_root.rotation.y = [PI, PI * 0.75, PI * 0.5, 0.0][column]
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			atlas.blend_rect(viewport.get_texture().get_image(), Rect2i(0, 0, 320, 400), Vector2i(column * 320, row * 400))
	atlas.save_png(output + "/" + tag + "-turnaround.png")
	if OS.get_cmdline_user_args().has("--motion"):
		cam.position = Vector3(0, 1.5, 3.5)
		cam.look_at(Vector3(0, 0.72, 0))
		DirAccess.make_dir_recursive_absolute(output + "/motion")
		for frame in 180:
			var moving := frame >= 20 and frame < 155
			var sprinting := frame >= 75 and frame < 135
			player.walk_clock += (8.8 if sprinting else 6.0) / 30.0 if moving else 0.0
			player._update_locomotion(1.0 / 30.0, moving, sprinting)
			player.combat_pose.update(player, 1.0 / 30.0, false, sprinting, cos(player.walk_clock) * lerpf(0.30, 0.55, player._sprint_weight) * player._move_weight)
			player.model_root.rotation.y = PI * 0.70
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(output + "/motion/frame_%03d.png" % frame)
	scene.queue_free()
	await process_frame
	print("DANTE_FIDELITY_CAPTURE ", tag)
	quit()
