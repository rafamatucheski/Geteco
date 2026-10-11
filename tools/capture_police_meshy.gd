extends SceneTree
## Os 5 escalões da polícia com corpo importado (substituto ou final), em repouso e mirando, de frente e de lado.
## Uso: "$GODOT" --path . --script res://tools/capture_police_meshy.gd -- --body=res://assets/civilians/meshy/pedestrians/m_medium_a.glb --out=res://evidence/npc-meshy/police
const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/PoliceBodyCatalog.gd")
const WEAPONS := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
var output_dir := "res://evidence/npc-meshy/police"
var body := ""
var solo := -1
var models: Array[Node3D] = []
var camera: Camera3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
		elif arg.begins_with("--body="): body = arg.substr(7)
		elif arg.begins_with("--solo="): solo = int(arg.substr(7))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if body != "":
		for tier in 5: CATALOG.override[tier] = body
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
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	stage.add_child(ground)
	for tier in 5:
		var police := MODEL.new()
		police.tier = tier
		police.appearance_index = tier * 2 + 1
		police.position = Vector3((tier - 2) * 1.4, 0, 0)
		stage.add_child(police)
		police.equip(WEAPONS[tier])
		models.append(police)
	camera = Camera3D.new()
	camera.fov = 26.0
	stage.add_child(camera)
	camera.current = true
	for i in 20: await process_frame
	if solo >= 0:
		# Um escalão só, girando o policial diante de uma câmera fixa: arma, mãos e equipamento de todos os lados.
		for index in models.size(): models[index].visible = index == solo
		models[solo].position = Vector3.ZERO
		camera.position = Vector3(0, 1.2, 5.2)
		camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
		camera.fov = 22.0
		for angle in [0, 90, 180, 270]:
			models[solo].rotation.y = deg_to_rad(float(angle))
			await _shot("solo%d-%d" % [solo, angle], true)
		print("capturas em ", output_dir)
		quit(0)
		return
	_view(0.0)
	await _shot("1-repouso-frente", false)
	await _shot("2-mirando-frente", true)
	_view(90.0)
	await _shot("3-mirando-lado", true)
	print("capturas em ", output_dir)
	quit(0)

func _view(yaw: float) -> void:
	var direction := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	camera.position = Vector3(0, 1.1, 0) + direction * 9.5
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	for police in models:
		# De lado: um atrás do outro sairia sobreposto; gira cada policial para ficar de perfil.
		police.rotation.y = 0.0 if yaw == 0.0 else deg_to_rad(-90.0)

func _shot(shot_name: String, aiming: bool) -> void:
	for step in 40:
		for police in models: police.update_pose(1.0 / 60.0, aiming, false, 0.0, 0.0)
		await process_frame
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, shot_name]))
