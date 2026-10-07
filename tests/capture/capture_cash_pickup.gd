extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(640,480)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("303b40")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .8
	scene.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.3
	scene.add_child(camera)
	camera.position = Vector3(.5,2,1.3)
	camera.look_at(Vector3(0,.85,0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = .6
	scene.add_child(light)
	var pickup := preload("res://gameplay/LootPickup.gd").new()
	pickup.setup("cash","",100)
	scene.add_child(pickup)
	pickup.advance(.15)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/cash-drops"))
	root.get_texture().get_image().save_png("res://evidence/cash-drops/icon-detail.png")
	scene.free()
	quit()
