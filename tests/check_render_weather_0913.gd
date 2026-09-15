extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := preload("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.viewport_3d.size = Vector2i(512,512)
	player.sprite_3d_display.scale = Vector2.ONE
	player.position = Vector2(300,300)
	player.get_node("Camera").enabled = false
	root.size = Vector2i(1100,700)
	var grave := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	world.add_child(grave)
	grave.build_view(preload("res://world/harbor/cemetery/CemeteryGrave3D.gd"),6.8,40,Vector3(0,.6,0),Vector3(0,24,20),Vector2i(512,512))
	grave.position = Vector2(800,300)
	var rain := preload("res://world/harbor/HarborRainPuddles.gd").new()
	world.add_child(rain)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-300,-300),Vector2(300,-300),Vector2(300,300),Vector2(-300,300)])
	ground.add_to_group("audio_ground")
	ground.set_meta("footstep_surface","dirt")
	ground.color = Color("596653")
	world.add_child(ground)
	var grass := ground.duplicate() as Polygon2D
	grass.position = Vector2(1600,0)
	grass.set_meta("footstep_surface","grass")
	world.add_child(grass)
	var solid := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(100,100)
	collision.shape = box
	solid.add_child(collision)
	world.add_child(solid)
	await physics_frame
	rain._rng.seed = 913
	rain._begin_rain()
	assert(rain.get_child_count()>0 and rain.get_child_count()<=96)
	var surfaces: Array = []
	for puddle in rain.get_children(): surfaces.append(puddle._surface)
	assert("dirt" in surfaces and "grass" in surfaces)
	var probe := Node2D.new()
	world.add_child(probe)
	assert(not rain._clear_surface(probe,Vector2.ZERO,Vector2(20,10),0,"dirt"))
	probe.queue_free()
	print("NATURAL_PUDDLES ",rain.get_child_count())
	var settings := preload("res://ui/SettingsMenu.tscn").instantiate()
	world.add_child(settings)
	settings.hide()
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	player.viewport_3d.get_texture().get_image().save_png("D:/geteco/artifacts/render-weather-0913/dante.png")
	grave.viewport_3d.get_texture().get_image().save_png("D:/geteco/artifacts/render-weather-0913/grave.png")
	root.get_texture().get_image().save_png("D:/geteco/artifacts/render-weather-0913/composed.png")
	print("RENDER_WEATHER_CHECK_OK")
	quit()
