extends SceneTree
const AID := preload("res://gameplay/PoliceOcclusionSilhouette.gd")
class Controller extends Node3D:
	var state := {"place_id": ""}

func _initialize() -> void: run.call_deferred()

func box(parent: Node3D, size: Vector3, point: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	parent.add_child(node)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(960, 640)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("404854")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.far = 180
	scene.add_child(camera)
	camera.position = Vector3(0, 9, 12)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	box(scene, Vector3(20, 0.2, 20), Vector3(0, -0.1, 0), Color("555b62"))
	box(scene, Vector3(4, 4.0, 0.6), Vector3(-1.5, 2.0, 1.5), Color("88847e"))
	var gameplay := Controller.new()
	scene.add_child(gameplay)
	for x in [-2.5, -0.5, 3.0]:
		var officer := preload("res://gameplay/dispatch/DispatchOfficer.gd").new()
		scene.add_child(officer)
		officer.set_physics_process(false)
		officer.controller = gameplay
		officer.position = Vector3(x, 0, 0)
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://evidence/police-silhouette-20260926.png"
	var result := root.get_texture().get_image().save_png(path)
	print("POLICE_CAPTURE ", result, " ", path)
	scene.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
