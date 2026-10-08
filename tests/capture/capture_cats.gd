extends SceneTree
## Isolated presentation preview, not a gameplay/performance acceptance test.
## Run rendered with the project's Godot 4.7.2 .NET after building Harbor.csproj.

const CAT := preload("res://runtime/cats/CatModel.gd")
const FURNITURE := preload("res://runtime/cats/CatFurniture.gd")
const AUDIO := preload("res://runtime/cats/CatAudio.gd")
var models: Array = []
var toys: Array[Node3D] = []
var output := "res://evidence/cats-preview.png"
var finished := false


func _initialize() -> void:
	create_timer(40.0).timeout.connect(func():
		if not finished:
			push_error("Cat presentation capture exceeded 40 seconds")
			quit(3))
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cat preview requires rendered Godot .NET")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	root.size = Vector2i(1600, 1000)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("28343c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c2d1df")
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -38, 0)
	sun.light_color = Color("fff0d7")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18, 18)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("59625d")
	floor_material.roughness = 0.97
	floor.material_override = floor_material
	scene.add_child(floor)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.8
	camera.near = 0.03
	scene.add_child(camera)
	camera.position = Vector3(3.6, 5.4, -7.0)
	camera.look_at(Vector3(0.0, 0.08, 0.0))
	camera.make_current()
	for index in range(10):
		var cat = CAT.new()
		cat.configure(index)
		cat.position = Vector3((float(index % 5) - 2.0) * 1.27, 0.0, -0.86 if index < 5 else 0.86)
		cat.rotation.y = [-0.20, 0.22, 0.6, -0.45, 0.05][index % 5]
		cat.set_activity(["sleep", "sit", "play", "walk", "sit", "sit", "walk", "sit", "scratch", "sleep"][index])
		scene.add_child(cat)
		models.append(cat)
		if index in [0, 9]:
			var bed := FURNITURE.create("bed")
			bed.position = cat.position
			scene.add_child(bed)
		if index == 2:
			var toy := FURNITURE.create("toy")
			toy.position = cat.position + Vector3(0.02, 0.0, -0.43)
			scene.add_child(toy)
			toys.append(toy)
		if index == 8:
			var post := FURNITURE.create("scratcher")
			post.position = cat.position + Vector3(-0.03, 0.0, -0.4)
			scene.add_child(post)
	# Also exercise WAV construction, without playing proximity audio ten times.
	for index in range(4):
		assert(AUDIO.make_meow(index).data.size() > 20000)
	assert(AUDIO.make_collect().data.size() > 10000)
	for frame in range(100):
		for cat in models:
			cat.animate(1.0 / 60.0, 0.62 if cat.activity == "walk" else 0.0)
		for toy in toys:
			FURNITURE.animate(toy, 1.0 / 60.0, true)
		await process_frame
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := root.get_texture().get_image().save_png(absolute)
	if error != OK:
		push_error("Cat preview could not save %s: %s" % [absolute, error_string(error)])
		quit(1)
		return
	print("CAT_PREVIEW ", absolute)
	finished = true
	quit(0)
