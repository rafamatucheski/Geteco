extends SceneTree
## Presentation fixture only; does not certify production performance or access.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280,720)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("667a80")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	scene.add_child(light)
	var plaza := preload("res://world/urban_detail/HarborPublicRealm3D.gd").new()
	plaza.zone_id = "union_plaza"
	scene.add_child(plaza)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	scene.add_child(camera)
	camera.position = Vector3(12,19,19)
	camera.look_at(Vector3(5,0,-.8))
	await create_timer(1).timeout
	var piano := plaza.get_node("UnionPiano")
	piano.timer.stop()
	var folder := "res://artifacts/union-piano/preview"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("idle.png"))
	for note in piano.MELODY: piano.play_note(note, true)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("melody.png"))
	quit()
