extends SceneTree
## Production rigs on controlled paths: isolated visual QA, not an FPS certificate.
var actors: Array[Node2D] = []
var speeds := [0.0, 52.0, 125.0, 52.0, 125.0, 52.0, 125.0, 52.0]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color("777b78"))
	seed(913)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	camera.position = Vector2(300, 180)
	camera.zoom = Vector2.ONE * 1.7
	world.add_child(camera)
	for index in speeds.size():
		var actor := preload("res://AnimatedPedestrian3D.gd").new()
		actor.position = Vector2(20, 30 + index * 42)
		world.add_child(actor)
		actor.set_physics_process(false)
		actors.append(actor)
	for frame in 30: await process_frame
	var pool := preload("res://world/shared/combat/GroundBlood.gd")
	for index in actors.size():
		var actor := actors[index]
		if index < 3: preload("res://world/shared/combat/BodyWound.gd").apply(actor)
		else:
			var stain := pool.spawn(actor, true)
			stain.position.x += 22
			stain.scale = Vector2.ONE * 1.6
			stain._process(3)
			stain.scale = Vector2.ONE * 1.6
			stain.set_process(false)
	await process_frame
	var system := get_first_node_in_group("blood_transfer_system")
	system.set_physics_process(false)
	system._refresh_contacts()
	for frame in 300:
		for index in actors.size():
			var actor := actors[index]
			actor.position.x += speeds[index] / 60.0
			actor.is_scared = speeds[index] > 100
			actor.walk_dir = Vector2.RIGHT
			if actor.model_root: actor.model_root.rotation.y = -PI * 0.5
			actor._advance_gait(1.0 / 60.0)
			if actor.gait != null: actor.gait.apply_pose()
			actor._update_viewport_render_state(1.0 / 60.0)
			system.sample_actor(actor, system.tracks[actor.get_instance_id()])
		system._physics_process(1.0 / 60.0)
		await physics_frame
		if frame in [90, 210, 299]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/blood-footsteps-0913/paths-%d.png" % frame)
	print("BLOOD_VISUAL actors=", actors.size(), " marks=", system.marks.size())
	world.queue_free()
	await process_frame
	quit()
