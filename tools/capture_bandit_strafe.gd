extends SceneTree
## Evidência visual do moveset de combate dos NPCs: bandidos com lenço no rosto mirando num ponto fixo
## enquanto andam de lado e recuam. As pernas devem pisar na direção do movimento, não "de frente".
## Uso: "$GODOT" --path . --script res://tools/capture_bandit_strafe.gd -- --out=res://evidence/npc-strafe
const COBRA := preload("res://gameplay/CobraModel.gd")
var output_dir := "res://evidence/npc-strafe"
var models: Array[Node3D] = []
var velocity := Vector3.ZERO
var camera: Camera3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	run.call_deferred()

func _process(delta: float) -> bool:
	for model in models:
		model.position += velocity * delta
		model.update_pose(delta, true, false, 0.0, 0.0)
	if camera != null and not models.is_empty(): camera.position += velocity * delta
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1600, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("8a8f92")
	ground.material_override = floor_material
	root.add_child(ground)
	for i in 5:
		var model := COBRA.new()
		model.tier = i % 3
		model.look_seed = 4100 + i * 37
		model.cobra_uniform = i % 2 == 0
		model.position = Vector3((i - 2) * 1.6, 0, 0)
		root.add_child(model)
		models.append(model)
	camera = Camera3D.new()
	camera.fov = 30.0
	root.add_child(camera)
	camera.current = true
	# Modelos olham para -Z (para a câmera em -Z): o "alvo" é a câmera.
	camera.look_at_from_position(Vector3(0, 1.6, -11), Vector3(0, 1.0, 0))
	for i in 40: await process_frame
	await _shot("1-parado-mirando")
	velocity = Vector3(2.2, 0, 0)
	for step in 3:
		for i in 9: await process_frame
		await _shot("2-de-lado-%d" % step)
	velocity = Vector3(0, 0, 2.2)
	for i in 30: await process_frame
	for step in 2:
		for i in 9: await process_frame
		await _shot("3-recuando-%d" % step)
	velocity = Vector3.ZERO
	camera.look_at_from_position(models[0].position + Vector3(0.8, 1.7, -1.3), models[0].position + Vector3(0, 1.55, 0))
	for i in 20: await process_frame
	await _shot("4-lenco-perto")
	quit(0)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output_dir.path_join(label + ".png"))
	root.get_texture().get_image().save_png(path)
	print("captura: ", path)
