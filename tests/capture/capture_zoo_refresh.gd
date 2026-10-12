extends SceneTree
## Finite visual comparison and temporal samples; this fixture does not certify FPS.
var folder := "res://evidence/zoo-refresh-20261010/after"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var before := "--before" in OS.get_cmdline_user_args()
	if before: folder = "res://evidence/zoo-refresh-20261010/before"
	DirAccess.make_dir_recursive_absolute(folder)
	var scene := Node3D.new()
	root.add_child(scene)
	var source := "res://evidence/zoo-refresh-20261010/before-source/MountainZoo.gd" if before else "res://world/mountain_detail/zoo/MountainZoo.gd"
	var zoo = load(source).new()
	scene.add_child(zoo)
	zoo.set_process(false)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(100,100)
	ground.mesh = plane
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("65725a")
	ground.material_override = mat; scene.add_child(ground)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("9babb0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e2e7ea")
	environment.environment.ambient_light_energy = .65
	scene.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50,-30,0)
	sun.shadow_enabled = true; scene.add_child(sun)
	var cashier = load("res://scripts/Actor.gd").new()
	cashier.identity = 624; cashier.controlled_automatically = true
	zoo.add_child(cashier); cashier.position = Vector3(-3.2,.06,21.1)
	cashier.set_physics_process(false)
	if not before: cashier.visual.rotation.y = PI
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(camera); camera.make_current()
	root.size = Vector2i(1280,720)
	for row in [
		["giraffe",Vector3(-10.5,0,-8.5)], ["lion",Vector3(10.5,0,-8.5)],
		["monkey",Vector3(10.5,0,8.5)], ["zebra",Vector3(-10.5,0,8.5)],
		["booth",Vector3(-3.2,0,22)]]:
		camera.size = 7.0 if row[0] == "booth" else 13.0
		camera.position = row[1]+Vector3(5,8,12)
		camera.look_at(row[1]+Vector3.UP)
		await save_frame(camera, str(row[0])+".png")
	# Temporal samples expose gait, foot clearance and body/tail/head movement.
	if not before:
		for species in ["giraffe","lion","zebra","monkey"]:
			var subject: Node3D
			for animal in zoo.animals:
				if animal.species == species:
					subject = animal
					break
			subject.clock = 2.0-subject.phase*1.7
			subject._motion_initialized = false
			subject.advance(0.0)
			camera.size = 6.2 if species == "giraffe" else 4.3
			for frame in 24:
				for animal in zoo.animals: animal.advance(.125)
				camera.position = subject.position+Vector3(6,5,8)
				camera.look_at(subject.position+Vector3.UP*(2.0 if species == "giraffe" else .9))
				await save_frame(camera, "%s-motion-%02d.png" % [species,frame])
	print("ZOO_REFRESH_CAPTURE ",folder)
	scene.queue_free(); await process_frame
	quit()

func save_frame(_camera: Camera3D, filename: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(filename))
