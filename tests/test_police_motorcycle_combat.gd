extends SceneTree

class Suspect extends CharacterBody2D:
	var health := 100
	var is_dead := false
	var fire_cooldown := 0.0
	func take_damage(amount: int, _attacker := false) -> void: health -= amount

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	seed(917)
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		root.size = Vector2i(1280, 720)
		DisplayServer.window_set_position(Vector2i(-3000, -3000))
		var camera := Camera2D.new()
		camera.position = Vector2(70, 10)
		camera.zoom = Vector2(3, 3)
		scene.add_child(camera)
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	wanted.current_stars = 2
	var target := Suspect.new()
	target.position = Vector2(150, 60)
	target.collision_layer = 4
	target.add_to_group("player")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12
	shape.shape = circle
	target.add_child(shape)
	scene.add_child(target)
	var wall := StaticBody2D.new()
	wall.position = Vector2(0, -23)
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(100, 8)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	var pool := root.get_node("EmergencyPool")
	var patrol: Node2D = pool.get_vehicle("police")
	patrol.set_physics_process(false)
	patrol.position = Vector2(-1000, -1000)
	var bike: Node2D = pool.get_vehicle("police")
	bike.configure_police_response(2, 2)
	bike.position = Vector2.ZERO
	bike.rotation = 0
	bike.target = target
	wanted.report_visual_contact(bike)
	# Normal vehicle physics must stop and initiate the dismount itself.
	await create_timer(7).timeout
	var okay: bool = bike.deployed_officers == 1 and bike._police_crew.size() == 1
	if okay:
		var officer: Node2D = bike._police_crew[0]
		print("MOTO officer=", officer.global_position, " exiting=", officer.service_disembark_active, " side=", officer.crew_side, " health=", target.health)
		okay = not officer.service_disembark_active and officer.global_position.distance_to(bike.global_position) > 20 and target.health < 100
		okay = okay and not bike.visual_3d.model.rider.visible
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/living-response-0912/moto-dismounted.png")
		if okay:
			officer.return_to_service_vehicle()
			await create_timer(4).timeout
			okay = bike.returned_officers == 1 and bike.visual_3d.model.rider.visible
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/living-response-0912/moto-remounted.png")
	print("POLICE_MOTORCYCLE_COMBAT ", "PASS" if okay else "FAIL", ": automatic stop, clear-side dismount, real bullets, visible rider, physical remount")
	wanted.dismiss_all_police()
	quit(0 if okay else 1)
