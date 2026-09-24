extends SceneTree

func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	root.size = Vector2i(1000, 700)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-1000,-1000),Vector2(1000,-1000),Vector2(1000,1000),Vector2(-1000,1000)])
	ground.color = Color("586265")
	world.add_child(ground)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * 3.0
	world.add_child(camera)
	camera.make_current()
	await process_frame
	var truck = root.get_node("EmergencyPool").get_vehicle("fire")
	truck.set_physics_process(false)
	truck.position = Vector2(-55, 0)
	truck.rotation = -0.12
	truck.ensure_presentation()
	var target := Node2D.new()
	target.position = Vector2(95, -15)
	world.add_child(target)
	var member = load("res://emergency/Firefighter.tscn").instantiate()
	world.add_child(member)
	member.set_physics_process(false)
	member.position = Vector2(45, 12)
	member.fire_truck = truck
	member.target = target
	member.state = member.State.EXTINGUISH
	member.model_root.rotation.y = -PI * 0.5
	member.right_upper_arm.rotation = Vector3(1.35,-0.08,0)
	member.left_upper_arm.rotation = Vector3(1.05,0.15,0.55)
	member.left_lower_arm.rotation = Vector3(0.45,0,0.70)
	member.water_hose.emitting = true
	member._update_hose()
	await create_timer(0.8).timeout
	member._update_hose()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var output := "res://_codex_diag/fixes0920/firefighter_hose.png"
	print("CAPTURE ", root.get_texture().get_image().save_png(output))
	quit()
