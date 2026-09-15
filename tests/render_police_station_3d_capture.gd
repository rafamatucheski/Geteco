extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1400, 900)
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene

	for frame in 30:
		await physics_frame

	var interiors_node := scene.get_node("Interiors")
	var police: HarborPoliceInterior = interiors_node.police_interior
	police.set_npc_rendering_active(true)

	var player := scene.get_node("Player") as CharacterBody2D
	var camera := scene.get_node("OverviewCamera") as Camera2D
	camera.make_current()
	camera.global_position = police.global_position
	camera.zoom = Vector2(1.0, 1.0)
	player.global_position = police.spawn_point.global_position

	for frame in 45:
		await physics_frame

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var dir := "d:/geteco/game/docs/measurements/police-3d-0912"
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png(dir + "/police_station_3d_render.png")
		print("IMAGE_SAVED: " + dir + "/police_station_3d_render.png")

	# Salvar diretamente a textura do SubViewport 3D da delegacia
	if police.view:
		for frame in 10:
			await physics_frame
		var vp_tex := police.view.get_texture()
		if vp_tex:
			var vp_img := vp_tex.get_image()
			if vp_img:
				var dir := "d:/geteco/game/docs/measurements/police-3d-0912"
				DirAccess.make_dir_recursive_absolute(dir)
				vp_img.save_png(dir + "/police_viewport_3d_direct.png")
				print("VIEWPORT_IMAGE_SAVED: " + dir + "/police_viewport_3d_direct.png")

	quit(0)
