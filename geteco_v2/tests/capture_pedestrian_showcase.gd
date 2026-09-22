extends SceneTree
## Vitrine dos pedestres civis: parados, andando e correndo, na mesma projeção
## ortográfica de 45° do jogo e num close. Só evidência visual; nada aqui é
## medida de desempenho (ver tests/measure_pedestrian_cost.gd).
## Uso: "$GODOT" --path . --script res://tests/capture_pedestrian_showcase.gd -- --out=<pasta res://>
const MODEL := preload("res://assets/CivilianModel.gd")
var output_dir := "res://evidence/pedestrian-look-0922"
var movers: Array = []
var _last_usec := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("capture_pedestrian_showcase: precisa de renderização real")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8fa3ad")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c4cc")
	environment.environment.ambient_light_energy = .55
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("8c8b86")
	ground.material_override = ground_material
	stage.add_child(ground)
	# Três fileiras: parados, andando (1,1–1,75 m/s como a rua) e correndo (fuga).
	for i in 8:
		_spawn(stage, i, Vector3(-7.0 + i * 2.0, 0, -3.0), 0.0)
	for i in 8:
		_spawn(stage, 20 + i * 7, Vector3(-7.0 + i * 2.0, 0, 0.5), lerpf(1.15, 1.75, i / 7.0))
	for i in 8:
		_spawn(stage, 60 + i * 5, Vector3(-7.0 + i * 2.0, 0, 4.0), lerpf(3.4, 5.6, i / 7.0))
	# Estivador das rotinas V1: EPI preso às articulações, carregando e conversando.
	for entry in [["carry", 0.0, -4.6], ["talk", 0.0, -2.2], ["carry", 1.2, 0.2]]:
		var carrier := Node3D.new()
		carrier.position = Vector3(float(entry[2]), 0, -1.3)
		stage.add_child(carrier)
		var worker: Node3D = preload("res://gameplay/routines_v1/DockWorkerModel.gd").new()
		worker.worker_index = movers.size()
		worker.activity = entry[0]
		worker.rotation.y = PI
		carrier.add_child(worker)
		carrier.rotation.y = -PI / 2 if entry[1] > 0.0 else 0.0
		movers.append({"node": carrier, "model": worker, "speed": entry[1], "origin": carrier.position})
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	for shot in [["jogo", 16.0, Vector3(0, 0, 0.5)], ["close", 6.0, Vector3(-3.0, 0, 0.5)], ["close_idle", 6.0, Vector3(-3.0, 0, -2.2)], ["close_run", 6.0, Vector3(-3.0, 0, 4.0)]]:
		camera.size = shot[1]
		var focus: Vector3 = shot[2]
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 4, 0, 0)), focus + Vector3(0, 30, 30))
		for frame in 6:
			for step in 9:
				await _advance(1.0 / 60.0)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png(ProjectSettings.globalize_path(output_dir + "/%s-%02d.png" % [shot[0], frame]))
	# Vista lateral, quadro a quadro: é aqui que se lê a mecânica da passada.
	for row in [["lado_andando", 0.5, 12.0], ["lado_correndo", 4.0, 12.0]]:
		camera.size = 2.6
		camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.0, float(row[1]) + row[2]))
		for frame in 10:
			for step in 3:
				await _advance(1.0 / 60.0)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_dir + "/%s-%02d.png" % [row[0], frame]))
	print("PEDESTRIAN_SHOWCASE ok ", output_dir)
	quit(0)

func _spawn(stage: Node3D, identity: int, point: Vector3, speed: float) -> void:
	# O pai faz o papel do Actor: gira o visual em PI e desloca em -Z local.
	var carrier := Node3D.new()
	carrier.position = point
	stage.add_child(carrier)
	var model := MODEL.new()
	model.appearance_locked = true
	model.appearance_variant = identity
	# Mesma paleta que `Actor` passa aos civis da rua.
	model.coat_color = [Color("426c70"), Color("a35d42"), Color("d3c3a1"), Color("42556f"), Color("8e5362"), Color("70835d")][identity % 6]
	model.pants_color = [Color("293849"), Color("484644"), Color("615342")][identity % 3]
	model.rotation.y = PI
	carrier.add_child(model)
	carrier.rotation.y = -PI / 2 if speed > 0.0 else 0.0
	movers.append({"node": carrier, "model": model, "speed": speed, "origin": point})

func _advance(_nominal: float) -> void:
	# Delta real do quadro: o modelo mede a própria velocidade pelo deslocamento.
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_usec) / 1000000.0, 0.001, 0.25) if _last_usec > 0 else 1.0 / 60.0
	_last_usec = now
	for entry in movers:
		var node: Node3D = entry.node
		if entry.speed <= 0.0: continue
		node.position += -node.global_basis.z * entry.speed * delta
		# Esteira: volta ao início sem que o modelo leia o salto como velocidade.
		if node.position.x - entry.origin.x > 1.2:
			node.position.x -= 2.4
			if entry.model.has_method("teleported"): entry.model.teleported()
		entry.model.walking = true
	await process_frame
