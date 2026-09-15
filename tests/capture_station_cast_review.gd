extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var saves = root.get_node("SaveManager")
	saves.set("_save_dir", "D:/geteco/artifacts/station-npcs-review/portraits/saves/")
	saves.clear_pending_save()
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	var police = load("res://world/harbor/interiors/HarborPoliceInterior.gd").new()
	world.add_child(police)
	police.set_npc_rendering_active(true)
	police.set_process(false)
	player.active_weapon_id = "fists"
	player._update_equipped_weapon_3d_mesh()
	await process_frame
	var actors: Array = [player]
	actors.append_array(police.all_npcs)
	var sheet := Image.create(1024, 1536, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("28313b"))
	for row in actors.size():
		var actor = actors[row]
		actor.set_physics_process(false)
		actor.viewport_3d.size = Vector2i(256, 256)
		actor.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var portrait_camera: Camera3D = actor.viewport_3d.get_camera_3d()
		portrait_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		portrait_camera.fov = 30
		portrait_camera.look_at_from_position(Vector3(0, 3.2, 1.4), Vector3(0, .65, 0))
		for col in 4:
			actor.model_root.rotation.y = PI + col * PI * 0.5
			await process_frame
			await RenderingServer.frame_post_draw
			var portrait: Image = actor.viewport_3d.get_texture().get_image()
			portrait.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(portrait, Rect2i(0, 0, 256, 256), Vector2i(col * 256, row * 256))
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/station-npcs-review/portraits")
	sheet.save_png("D:/geteco/artifacts/station-npcs-review/portraits/cast.png")
	quit()
