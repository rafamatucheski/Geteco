extends SceneTree
const OUTPUT := "res://docs/measurements/dock-circuit-0910/"
var failures := 0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var worker := preload("res://world/harbor/HarborDockWorker.gd").new()
	worker.work_route = PackedVector2Array([Vector2.ZERO, Vector2(56,0), Vector2(56,66), Vector2(0,66)])
	worker.work_points = PackedVector2Array([Vector2.ZERO, Vector2(56,66)])
	worker.station_points = PackedVector2Array([Vector2(0,-12), Vector2(56,78)])
	scene.add_child(worker)
	worker.set_physics_process(false)
	worker.phase = "carry"
	worker.carrying = true
	worker.carried_box.show()
	worker.viewport.size = Vector2i(512,512)
	worker.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = worker.viewport.get_camera_3d()
	camera.position = Vector3(0,1.6,-3.2)
	camera.look_at(Vector3(0,.8,0))
	for i in 4:
		worker.model_root.rotation.y = i*PI*.5
		worker._update_carry_pose()
		var left := worker.left_crate_grip.global_position
		var right := worker.right_crate_grip.global_position
		var center := worker.carried_box.global_position
		if center.distance_to((left+right)*.5) > .065: failures += 1
		# A caixa deve ficar do mesmo lado do rosto em qualquer orientação.
		var forward := -worker.model_root.global_transform.basis.z.normalized()
		if (center-worker.torso_node.global_position).dot(forward) < .25: failures += 1
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		worker.viewport.get_texture().get_image().save_png(OUTPUT + "grip_%d.png" % i)
	print("DOCK_CARRY_POSE: %d falhas, quatro orientações verificadas" % failures)
	scene.queue_free()
	await process_frame
	quit(failures)
