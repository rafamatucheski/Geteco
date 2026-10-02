extends SceneTree

const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const CAMERA := preload("res://scripts/CameraRig.gd")
const OUTPUT := "res://evidence/mountain-tunnel-20261002/enclosure-fixture/"
class Walker extends CharacterBody3D:
	var visual := Node3D.new()
	func _ready() -> void: add_child(visual)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(CONNECTION.new())
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(130,.2,8.75)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(600,-.1,CONNECTION.CENTER_Z)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("30373b")
	floor_mesh.material_override = asphalt
	stage.add_child(floor_mesh)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8398ac")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .35
	stage.add_child(environment)
	var walker := Walker.new()
	stage.add_child(walker)
	var camera := CAMERA.new()
	camera.target = walker
	stage.add_child(camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var failures := 0
	for direction in [-1.0,1.0]:
		walker.position = Vector3(605,.07,CONNECTION.CENTER_Z+2.0)
		walker.visual.rotation.y = direction*PI*.5
		walker.reset_physics_interpolation()
		camera.initialized = false
		for i in 90: await process_frame
		if camera.projection != Camera3D.PROJECTION_PERSPECTIVE or camera.position.y > 4.1: failures += 1
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT+"inside_%s.png" % direction)
	walker.position.x = CONNECTION.TUNNEL_END_X+30
	walker.reset_physics_interpolation()
	camera.initialized = false
	for i in 90: await process_frame
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL: failures += 1
	print("MOUNTAIN_ENCLOSURE_CAMERA failures=",failures)
	quit(0 if failures==0 else 1)
