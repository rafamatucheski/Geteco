extends SceneTree

## Deterministic top-down evidence for points also present in the V1 Harbor
## overview capture. Visual evidence only; never use this script as a benchmark.

var region: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	# Match capture_harbor_preview.gd exactly: 2000x1100 and the same centres.
	root.size = Vector2i(2000, 1100)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("82939a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5d1bd")
	environment.ambient_light_energy = 0.92
	world_environment.environment = environment
	fixture.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -32, 0)
	sun.light_color = Color("ffe0ac")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	fixture.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.near = 0.1
	camera.far = 400.0
	fixture.add_child(camera)
	camera.make_current()
	region = preload("res://world/regions/NativeRegion.gd").build_region("harbor", Vector3(101.25, 0, 56.25))
	fixture.add_child(region)
	for frame in 45: await process_frame
	await _shot(Vector3(101.25, 0, 56.25), 1100.0 / 0.85 / 16.0, "res://evidence/harbor-comparison-v2-market.png")
	region.set_focus(Vector3(345.625, 0, 76.875))
	for frame in 45: await process_frame
	await _shot(Vector3(345.625, 0, 76.875), 1100.0 / 0.60 / 16.0, "res://evidence/harbor-comparison-v2-northbank.png")
	quit(0)

func _shot(point: Vector3, size: float, path: String) -> void:
	camera.size = size
	camera.position = point + Vector3(0, 180, 0)
	camera.reset_physics_interpolation()
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK)
	print("HARBOR_COMPARISON_CAPTURE ", ProjectSettings.globalize_path(path))
