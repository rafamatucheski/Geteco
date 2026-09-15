extends SceneTree
const OUT := "D:/geteco/artifacts/shot-feedback-0913/visual"
var world: Node2D
var person: CharacterBody2D
var camera: Camera2D

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280,720)
	root.get_node("SaveManager")._save_dir = OUT + "/saves/"
	root.get_node("SaveManager").clear_pending_save()
	seed(913)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-2000,-2000),Vector2(2000,-2000),Vector2(2000,2000),Vector2(-2000,2000)])
	ground.color = Color("64716b")
	ground.z_index = -10
	world.add_child(ground)
	for x in range(-1500,1500,50):
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(x,-1500),Vector2(x,1500)])
		line.default_color = Color("58645d")
		line.width = .6
		line.z_index = -9
		world.add_child(line)
	person = preload("res://AnimatedPedestrian3D.gd").new()
	person.district_theme = 0
	person.archetype_override = 1
	world.add_child(person)
	person.is_gangster = false
	person.set_physics_process(false)
	person.model_root.rotation.y = -.5
	var player = preload("res://Player.gd").new()
	var player_camera := Camera2D.new()
	player_camera.name = "Camera"
	player.add_child(player_camera)
	player.position = Vector2(-65,0)
	world.add_child(player)
	player.set_physics_process(false)
	player.model_root.rotation.y = -.5
	player.get_node("Camera").enabled = false
	var ambulance = preload("res://EmergencyVehicle.gd").new()
	ambulance.type = 1
	ambulance.position = Vector2(70,65)
	world.add_child(ambulance)
	ambulance.set_physics_process(false)
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE*5
	camera.position = Vector2(-5,20)
	world.add_child(camera)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/before.png")
	var start := person.global_position
	for frame in 150:
		if frame == 2:
			var round = preload("res://Bullet.tscn").instantiate()
			round.position = Vector2(70,-10)
			round.direction = Vector2.DOWN
			round.speed = 1200
			round.damage = 1
			round.impact_resolved.connect(func(_target,_point,_material,_accepted): _capture_named.call_deferred("vehicle-impact"))
			world.add_child(round)
		if frame == 15:
			var bullet = preload("res://Bullet.tscn").instantiate()
			bullet.position = person.global_position + Vector2(-35,0)
			bullet.direction = Vector2.RIGHT
			bullet.speed = 1200
			bullet.damage = 24
			bullet.owner_body = player
			world.add_child(bullet)
		if frame == 30: person.set_physics_process(true)
		if frame >= 30: camera.position = camera.position.lerp(person.global_position+Vector2(-15,-18),.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(OUT + "/frame-%03d.jpg" % frame,.92)
		if frame == 21: root.get_texture().get_image().save_png(OUT + "/hit.png")
		if frame == 90: root.get_texture().get_image().save_png(OUT + "/wounded.png")
	print("VISUAL wounded health=",person.health," movement=",person.global_position.distance_to(start))
	person.set_physics_process(false)
	ambulance.hide()
	player.position = person.position + Vector2(-65,0)
	camera.position = person.position + Vector2(-30,-18)
	for angle in 4:
		person.model_root.rotation.y = angle*PI*.5
		player.model_root.rotation.y = angle*PI*.5
		for i in 3:
			player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
			person.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
		await _capture_named("direction-%d" % angle)
	world.queue_free()
	await process_frame
	quit(0)

func _capture_named(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + label + ".png")
