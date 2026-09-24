extends SceneTree

## Deterministic Harbor evidence at the same authored centres used by the V1
## companion capture. This is visual evidence, never a performance benchmark.

const REGION := preload("res://world/regions/NativeRegion.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const OUTPUT_ROOT := "C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c5d4-0aa6-7ba0-819f-d0c3afa28d07/harbor-fidelity"
const SCALE := 1.0 / 16.0

var fixture: Node3D
var region: Node3D
var camera: Camera3D
var label := "before"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=").validate_filename()
	DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	_build_fixture()
	region = REGION.build_region("harbor", Vector3(1550.0 * SCALE, 0.0, 140.0 * SCALE))
	fixture.add_child(region)
	for frame in 30:
		await process_frame
	var shots: Array[Dictionary] = [
		{"id":"ammunation", "center":Vector2(1550, 140), "zoom":1.20},
		{"id":"northstar", "center":Vector2(3570, 1500), "zoom":0.55},
		{"id":"south_port", "center":Vector2(4750, 4450), "zoom":0.36},
		{"id":"salvage", "center":Vector2(-750, 550), "zoom":0.80},
		{"id":"cemetery", "center":Vector2(-650, 1740), "zoom":0.70},
		{"id":"cobra", "center":Vector2(7700, 1700), "zoom":0.50},
		{"id":"access_port_boss", "center":Vector2(5515, 5870), "zoom":1.00},
		{"id":"access_sewer", "center":Vector2(1182, 2114), "zoom":1.65},
		{"id":"restaurant_anchor", "center":Vector2(620, 1132), "zoom":1.55},
		{"id":"restaurant_tideline", "center":Vector2(5790, 1644), "zoom":1.55},
		{"id":"restaurant_early_shift", "center":Vector2(6200, -1238), "zoom":1.55},
	]
	for shot in shots:
		await _capture_area(shot)
	await _capture_seam()
	quit(0)

func _build_fixture() -> void:
	fixture = Node3D.new()
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

func _capture_area(shot: Dictionary) -> void:
	var source_center: Vector2 = shot.center
	var point := Vector3(source_center.x * SCALE, 0.0, source_center.y * SCALE)
	region.set_focus(point)
	for frame in 20:
		await process_frame
	camera.size = 900.0 / float(shot.zoom) * SCALE
	camera.position = point + Vector3(0, 180, 0)
	camera.reset_physics_interpolation()
	for frame in 4:
		await process_frame
	await _save(str(shot.id))

func _capture_seam() -> void:
	region.queue_free()
	await process_frame
	var seam := Vector3(7160.0 * SCALE, 0.0, -4560.0 * SCALE)
	var harbor := REGION.build_region("harbor", seam)
	var mountain := REGION.build_region("mountain", seam)
	fixture.add_child(harbor)
	fixture.add_child(mountain)
	fixture.add_child(CONNECTION.new())
	for frame in 35:
		await process_frame
	camera.size = 46.0
	camera.position = seam + Vector3(0, 180, 0)
	camera.reset_physics_interpolation()
	for frame in 4:
		await process_frame
	await _save("connection_seam")

func _save(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%s.png" % [OUTPUT_ROOT, label, id]
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK)
	print("HARBOR_FIDELITY_CAPTURE ", path)
