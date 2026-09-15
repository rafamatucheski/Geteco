extends SceneTree
const MODEL := preload("res://world/harbor/restaurants/RestaurantTable3D.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280,800)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var model := MODEL.new()
	world.add_child(model)
	model.build(1,Color("b96a46"))
	model.set_conditions(2,0.0,0.0,true)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(5.5,.06,4.2)
	floor_mesh.mesh = floor_box
	floor_mesh.position.y = -.04
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ac9378")
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("253b42")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c1d3d8")
	env.environment.ambient_light_energy = .55
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	world.add_child(camera)
	camera.position = Vector3(3.8,3.5,4.7)
	camera.look_at(Vector3(0,1.0,0))
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/restaurant-terrace-clear.png")
	model.set_conditions(2,.7,3.0,true)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/restaurant-terrace-rain.png")
	world.queue_free()
	await process_frame
	quit()
