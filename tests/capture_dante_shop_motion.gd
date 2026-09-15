extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("SaveManager").clear_pending_save()
	# Isolate the production shop and player from unrelated world construction.
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var actor = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 16.0
	collision.shape = capsule
	actor.add_child(collision)
	world.add_child(actor)
	var room = load("res://world/harbor/interiors/HarborAmmunationInterior.gd").new()
	world.add_child(room)
	room.set_npc_rendering_active(true)
	actor.equip_weapon("fists")
	actor.global_position = room.to_global(room.floor_point(Vector2(0, 1)))
	for frame in 10: await physics_frame
	var output := "D:/geteco/artifacts/dante-0910/shop"
	DirAccess.make_dir_recursive_absolute(output)
	# All recorded movement goes through native player input and collision.
	for frame in 180:
		for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
			Input.action_release(action)
		if frame >= 20 and frame < 50: Input.action_press("move_right")
		if frame >= 60 and frame < 100:
			Input.action_press("move_left")
			Input.action_press("sprint")
		if frame >= 110 and frame < 135: Input.action_press("move_right")
		if frame >= 145 and frame < 165: Input.action_press("move_down")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/frame_%03d.png" % frame)
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(action)
	room.set_npc_rendering_active(false)
	world.queue_free()
	await process_frame
	print("DANTE_SHOP_CAPTURE complete")
	quit()
