extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1200,800)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var cab := preload("res://prototypes/living_cast/models/YellowCabModel.gd").new()
	stage.add_child(cab)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("16232d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = 1.5
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.7
	camera.position = Vector3(5,4,-6)
	camera.look_at(Vector3(0,0.6,0))
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/taxi-yellow-cab.png")
	quit()
