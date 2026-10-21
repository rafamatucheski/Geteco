extends SceneTree
## Evidência visual dos corpos do catálogo de pedestres sob pose de estresse: em pé, andando, mãos no alto,
## mãos à frente, sentado e correndo. Procura pele esticada (mangas e calças viram "lâminas").
## Uso: "$GODOT" --path . --script res://tools/capture_catalog_bodies.gd -- --out=res://evidence/npc-meshy/catalog
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const SKIERS := preload("res://assets/civilians/SkierBodyCatalog.gd")
## --catalog=skiers: esquiadores do Cume Branco (20/10/2026) em vez dos pedestres.
## --catalog=vicente: só o corpo próprio do Vicente (20/10/2026).
var catalog_name := "pedestres"
var output_dir := "res://evidence/npc-meshy/catalog"
var rig: Node3D
var camera: Camera3D
var models: Array[Node3D] = []
var speed := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
		if arg.begins_with("--catalog="): catalog_name = arg.substr(10)
	run.call_deferred()

func _process(delta: float) -> bool:
	if rig != null: rig.position.z += speed * delta
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1600, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.75
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var checker := Image.create(2, 2, false, Image.FORMAT_RGB8)
	checker.set_pixel(0, 0, Color("7d8387")); checker.set_pixel(1, 1, Color("7d8387"))
	checker.set_pixel(1, 0, Color("a1a7aa")); checker.set_pixel(0, 1, Color("a1a7aa"))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(checker)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = Vector3(200, 200, 1)
	ground.material_override = material
	stage.add_child(ground)
	rig = Node3D.new()
	stage.add_child(rig)
	var entries := SKIERS.available() if catalog_name == "skiers" else CATALOG.available()
	var folder: String = SKIERS.FOLDER if catalog_name == "skiers" else CATALOG.FOLDER
	if catalog_name == "vicente":
		entries = [{"file": "vicente.glb"}]
		folder = "res://assets/civilians/meshy/vicente/"
	print("catálogo: ", entries.size(), " entradas")
	var count := entries.size()
	for i in count:
		var model := CIVILIAN.new()
		model.appearance_locked = true
		model.appearance_variant = 100 + i
		model.body_source = folder + String(entries[i].file)
		model.position = Vector3((i - (count - 1) * 0.5) * 1.15, 0, 0)
		rig.add_child(model)
		models.append(model)
	camera = Camera3D.new()
	camera.fov = 26.0
	rig.add_child(camera)
	camera.current = true
	_front(8.6 + count * 0.55)
	for i in 25: await process_frame
	await _shot("1-em-pe")
	# Mãos no alto, à frente e dos lados: estressa ombro, cotovelo e manga.
	_hands(Vector3(0.0, 1.95, 0.25), Vector3(0.0, 1.95, 0.25), 0.25)
	for i in 25: await process_frame
	await _shot("2-maos-no-alto")
	_hands(Vector3(-0.2, 1.2, 0.55), Vector3(0.2, 1.2, 0.55), 0.2)
	for i in 25: await process_frame
	await _shot("3-maos-a-frente")
	_hands(Vector3(-0.85, 1.4, 0.0), Vector3(0.85, 1.4, 0.0), 0.0)
	for i in 25: await process_frame
	await _shot("4-bracos-abertos")
	for model in models: model.hand_provider = Callable(); model.hand_targets = [null, null]
	for model in models: model.sit_amount = 1.0
	for i in 40: await process_frame
	_side(8.6 + count * 0.55)
	await _shot("5-sentado-lado")
	for model in models: model.sit_amount = 0.0
	_front(8.6 + count * 0.55)
	speed = 1.5
	for i in 90: await process_frame
	await _shot("6-andando-frente")
	_side(8.6 + count * 0.55)
	for i in 15: await process_frame
	await _shot("7-andando-lado")
	speed = 3.6
	for i in 60: await process_frame
	await _shot("8-correndo-lado")
	print("capturas em ", output_dir)
	quit(0)

func _hands(left: Vector3, right: Vector3, forward: float) -> void:
	for model in models:
		var body: Node3D = model
		body.hand_provider = func() -> Array: return [body.to_global(left + Vector3(0, 0, forward)), body.to_global(right + Vector3(0, 0, forward))]

func _front(distance: float) -> void:
	camera.position = Vector3(0, 1.0, distance)
	camera.look_at(rig.global_position + Vector3(0, 0.9, 0), Vector3.UP)
	for model in models: model.rotation.y = 0.0

func _side(distance: float) -> void:
	# Câmera de lado: cada boneco gira 90° para ficar de perfil na mesma fileira.
	camera.position = Vector3(0, 1.0, distance)
	camera.look_at(rig.global_position + Vector3(0, 0.9, 0), Vector3.UP)
	for model in models: model.rotation.y = -PI * 0.5

func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, shot_name]))
