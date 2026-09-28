extends SceneTree
## Geometry inspection; integrated behavior is covered by capture_air_k9.
const ART := preload("res://gameplay/police_response/air_k9/PoliceHelicopterArt.gd")
var folder := "res://evidence/police-response-20260928/airframe"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("697780")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c2d5e2")
	environment.environment.ambient_light_energy = .5
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -25, 0)
	scene.add_child(sun)
	var airframe := Node3D.new()
	scene.add_child(airframe)
	var rig := ART.build(airframe)
	for door in rig.doors: door.position.z = .23
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.5
	camera.current = true
	var views := {"front": Vector3(12, 7, -16), "rear": Vector3(-12, 6, 18), "side": Vector3(15, 4, 1)}
	for label in views:
		camera.position = views[label]
		camera.look_at(Vector3(0, .5, 1.8))
		for index in 4: await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
		print("AIRFRAME_CAPTURE ", label, " result=", result)
	scene.queue_free()
	await process_frame
	quit(0)
