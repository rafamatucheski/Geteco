extends SceneTree
## Compara o corpo antigo (cópia congelada em evidence/) com o corpo único do Meshy, lado a lado, em
## repouso, andando, correndo, sentado, com a mão num alvo e reagindo a um tiro. Só evidência visual.
## Uso: "$GODOT" --path . --script res://tools/capture_meshy_body.gd -- --out=res://evidence/npc-meshy/pilot-mechanic
const OLD := "res://evidence/npc-meshy/before/MechanicModelBefore.gd"
const NEW := "res://assets/maciota/MechanicModel.gd"
var output_dir := "res://evidence/npc-meshy/pilot-mechanic"
var rig: Node3D
var old_model: Node3D
var new_model: Node3D
var camera: Camera3D
var speed := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	run.call_deferred()

func _process(delta: float) -> bool:
	if rig != null: rig.position.z += speed * delta
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.7
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
	old_model = (load(OLD) as GDScript).new()
	old_model.position = Vector3(-0.8, 0, 0)
	rig.add_child(old_model)
	new_model = (load(NEW) as GDScript).new()
	new_model.position = Vector3(0.8, 0, 0)
	rig.add_child(new_model)
	camera = Camera3D.new()
	camera.fov = 24.0
	rig.add_child(camera)
	camera.current = true
	_view(0.0, 8.2)
	for i in 20: await process_frame
	await _shot("01-parado-frente")
	_view(90.0, 8.2)
	for i in 6: await process_frame
	await _shot("02-parado-lado")
	_view(180.0, 8.2)
	for i in 6: await process_frame
	await _shot("03-parado-costas")
	# Andando de lado para ver a passada.
	_view(90.0, 8.2)
	speed = 1.4
	for i in 90: await process_frame
	await _shot("04-andando-a")
	for i in 11: await process_frame
	await _shot("05-andando-b")
	speed = 3.6
	for i in 90: await process_frame
	await _shot("06-correndo-a")
	for i in 6: await process_frame
	await _shot("07-correndo-b")
	speed = 0.0
	for i in 60: await process_frame
	# Sentado.
	for model in [old_model, new_model]:
		if model == new_model: model.body.sit_amount = 1.0
	for i in 40: await process_frame
	await _shot("08-sentado")
	new_model.body.sit_amount = 0.0
	# Mão direita num alvo à frente (arma ou maca): a IK dos braços continua valendo.
	new_model.body.hand_provider = func() -> Array: return [new_model.body.to_global(Vector3(-0.2, 1.15, 0.45)), new_model.body.to_global(Vector3(0.2, 1.15, 0.45))]
	_view(0.0, 8.2)
	for i in 30: await process_frame
	await _shot("09-maos-no-alvo")
	new_model.body.hand_provider = Callable()
	new_model.body.hand_targets = [null, null]
	# Tiro vindo de trás.
	new_model.body.take_hit(Vector3(0, 0, 1), 1.0)
	for i in 8: await process_frame
	await _shot("10-reacao-ao-tiro")
	print("capturas em ", output_dir)
	quit(0)

func _view(yaw_degrees: float, distance: float) -> void:
	# De frente ou de costas os dois ficam lado a lado em X; de lado, um à frente do outro em Z.
	var side_on := absf(sin(deg_to_rad(yaw_degrees))) > 0.5
	old_model.position = Vector3(0, 0, -0.9) if side_on else Vector3(-0.8, 0, 0)
	new_model.position = Vector3(0, 0, 0.9) if side_on else Vector3(0.8, 0, 0)
	var direction := Vector3(sin(deg_to_rad(yaw_degrees)), 0, cos(deg_to_rad(yaw_degrees)))
	camera.position = Vector3(0, 1.0, 0) + direction * distance
	camera.look_at(rig.global_position + Vector3(0, 0.9, 0), Vector3.UP)

func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, shot_name]))
