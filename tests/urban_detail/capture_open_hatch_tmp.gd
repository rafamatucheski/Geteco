extends SceneTree

## Render fixture used while tuning the animated V2 sewer hatch.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1200, 800)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8a9699")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5d1bd")
	environment.environment.ambient_light_energy = 0.9
	fixture.add_child(environment)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("3a3d40")
	ground.material_override = asphalt
	fixture.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 0.7
	fixture.add_child(sun)
	var hatch := preload("res://world/urban_detail/HarborManholeExterior3D.gd").new()
	hatch.setup({"id":"harbor_sewer", "kind":"sewer", "size":Vector2(2,2)})
	fixture.add_child(hatch)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.8
	camera.position = Vector3(0, 7.5, 6.5)
	fixture.add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	camera.make_current()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	hatch.set_open_amount(1.0)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("C:/Users/rafae/.codex/visualizations/2026/09/22/01a0caca-5235-7402-8ab3-4a69084e6fa4/sewer-hatch-open-0922.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tests/urban_detail/capture_open_hatch_tmp.gd"))
	quit()
