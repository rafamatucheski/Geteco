extends SceneTree

var changes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ViewportTexture residency probe requires a renderer")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 3.0)
	viewport.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	viewport.add_child(mesh)
	var texture := viewport.get_texture()
	texture.changed.connect(func(): changes += 1)
	for _frame in 4:
		await process_frame
	changes = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for _frame in 4:
		await process_frame
	print("VIEWPORT_TEXTURE_CHANGED_RESULT changes=%d mode=%d" % [changes, viewport.render_target_update_mode])
	viewport.queue_free()
	await process_frame
	quit(0)
