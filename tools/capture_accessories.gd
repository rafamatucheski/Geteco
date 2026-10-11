extends SceneTree
## Cada corpo do catálogo de pedestres com um acessório de cabeça, de frente e de lado (cabeça em primeiro plano).
## Uso: "$GODOT" --path . --script res://tools/capture_accessories.gd -- --out=res://evidence/npc-meshy/accessories [--folder=res://assets/civilians/meshy/country/]
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const KINDS := ["", "straw", "cowboy+sunglasses", "straw+sunglasses"]
var output_dir := "res://evidence/npc-meshy/accessories"
var folder := ""
var files: Array[String] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
		elif arg.begins_with("--folder="): folder = arg.substr(9)
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if folder == "":
		for entry in CATALOG.available(): files.append(CATALOG.FOLDER + String(entry.file))
	else:
		for f in DirAccess.get_files_at(folder):
			if f.ends_with(".glb"): files.append(folder + f)
	root.size = Vector2i(1600, 800)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.8
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	stage.add_child(sun)
	var models: Array[Node3D] = []
	for k in files.size():
		var model := CIVILIAN.new() as Node3D
		model.appearance_locked = true
		model.appearance_variant = k
		model.body_source = files[k]
		var kinds: PackedStringArray = KINDS[k % KINDS.size()].split("+")
		for kind in kinds:
			if kind == "": continue
			model.body_accessories.append({"kind": kind, "color": Color("6b4a2c") if kind in ["cowboy", "straw"] else Color("2f3b52"), "band": Color("2a1d12")})
		model.position = Vector3((k - (files.size() - 1) * 0.5) * 0.9, 0, 0)
		model.rotation.y = PI
		stage.add_child(model)
		models.append(model)
	var camera := Camera3D.new()
	camera.fov = 18.0
	stage.add_child(camera)
	camera.current = true
	for i in 20: await process_frame
	var spread := files.size() * 0.9
	for view in [["front", 0.0], ["side", 90.0]]:
		for model in models: model.rotation.y = PI + deg_to_rad(float(view[1]))
		camera.position = Vector3(0, 1.62, 6.0 + spread * 0.5)
		camera.look_at(Vector3(0, 1.62, 0), Vector3.UP)
		for i in 6: await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, view[0]]))
	print("capturas em ", output_dir)
	quit(0)
