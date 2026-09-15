extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var hospital := preload("res://world/harbor/hospital/HarborHospital.gd").new()
	world.add_child(hospital)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE * 2.4
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	hospital.overhead_viewport.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/overhead-shadows.png")
	for light in hospital.hospital_view.viewport_3d.get_children():
		if light is DirectionalLight3D:
			print("OVERHEAD light=",light.light_cull_mask," energy=",light.light_energy, " shadow=",light.shadow_enabled)
			light.shadow_enabled = false
	hospital.overhead_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	hospital.hospital_view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	hospital.overhead_viewport.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/overhead-no-shadows.png")
	world.queue_free()
	await process_frame
	quit()
