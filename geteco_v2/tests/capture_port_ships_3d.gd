extends SceneTree
## Controlled oblique views of native V2 harbor geometry; visual QA only.
const REGION := preload("res://world/regions/NativeRegion.gd")
var region: Node3D
var camera: Camera3D
var label := "before"
var output_root := "user://port-ships-v2"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
		if arg.begins_with("--output="): output_root = arg.trim_prefix("--output=")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root)) == OK)
	root.size = Vector2i(1600,900)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("82939a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5d1bd")
	environment.ambient_light_energy = 0.92
	var sky := WorldEnvironment.new()
	sky.environment = environment
	root.add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62,-32,0)
	sun.light_color = Color("ffe0ac")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	root.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 400.0
	root.add_child(camera)
	camera.make_current()
	region = REGION.build_region("harbor",Vector3(223,0,90))
	root.add_child(region)
	await _capture("northstar",Vector3(223,0,90),100,Vector3(22,70,60))
	await _capture("northstar-close",Vector3(223,0,92),65,Vector3(17,48,39))
	await _capture("santa-mare",Vector3(299,0,183),125,Vector3(28,80,62))
	await _capture("santa-mare-close",Vector3(299,0,183),85,Vector3(20,57,43))
	quit(0)

func _capture(id: String, point: Vector3, size: float, offset: Vector3) -> void:
	region.set_focus(point)
	for i in 45: await process_frame
	camera.size = size
	camera.position = point+offset
	camera.look_at(point)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path := output_root.path_join("port-ships-3d-%s-%s.png" % [label,id])
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("PORT_SHIP_CAPTURE ",path)
