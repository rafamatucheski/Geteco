extends SceneTree
## Vitrine dos NPCs com o corpo articulado dos pedestres: polícia (escalões e
## armas), socorristas com maca, residentes, caixas, garagem do Maciota e
## moradores da montanha. Só evidência visual.
## Uso: "$GODOT" --path . --script res://tests/capture/capture_npc_showcase.gd -- --out=<pasta res://>
var output_dir := "res://evidence/npc-look-0922"
var police: Array = []
var movers: Array = []
var _last_usec := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = .55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("8c8b86")
	ground.material_override = gm
	stage.add_child(ground)
	# Fileira 1: polícia nos cinco escalões, mirando; segurança do banco.
	var x := -7.0
	for tier in 5:
		var m = preload("res://gameplay/PoliceModel.gd").new()
		m.tier = tier
		_place(stage, m, Vector3(x, 0, -3.5), 0.0)
		m.equip(["pistol", "pistol", "m4a1", "smg", "ak47"][tier])
		police.append({"model": m, "aim": tier != 1})
		x += 1.8
	var guard = preload("res://runtime/BankGuardModel.gd").new()
	_place(stage, guard, Vector3(x, 0, -3.5), 0.0)
	guard.equip("shotgun")
	police.append({"model": guard, "aim": false})
	# Fileira 2: socorristas (com maca) andando, residentes.
	x = -7.0
	for entry in [["res://gameplay/emergency/FirefighterModel.gd", false], ["res://gameplay/emergency/ParamedicModel.gd", true], ["res://gameplay/emergency/MorticianModel.gd", true]]:
		var m = load(entry[0]).new()
		m.is_stretcher_bearer = entry[1]
		_place(stage, m, Vector3(x, 0, 0.0), 1.3)
		if entry[1]: m.stretcher_mesh.show()
		x += 1.9
	for path in ["res://world/places/ServiceResidentModel.gd", "res://world/places/MedicalResidentModel.gd", "res://world/places/NecoModel.gd"]:
		_place(stage, load(path).new(), Vector3(x, 0, 0.0), 0.0, true)
		x += 1.5
	# Fileira 3: caixas, atendentes, garagem do Maciota, montanha.
	x = -7.0
	var clerk_f = load("res://assets/regions/source/world/harbor/events/BankClerkModel.gd").new()
	clerk_f.appearance_female = true
	for m in [load("res://runtime/FuelCashierModel.gd").new(), clerk_f, load("res://assets/regions/source/world/harbor/events/BankClerkModel.gd").new(),
			load("res://assets/maciota/MechanicModel.gd").new(), load("res://assets/maciota/MaciotaModel.gd").new()]:
		_place(stage, m, Vector3(x, 0, 3.5), 0.0, true)
		x += 1.5
	for entry in [["ranger", "drink", 0.0], ["logger", "work", 0.0], ["ranger", "talk", 1.0]]:
		var m = load("res://assets/regions/source/world/mountain_pass/WinterResidentModel.gd").new()
		m.role = entry[0]
		m.coat_color = Color("8a3b2e") if entry[0] == "logger" else Color("3f6872")
		_place(stage, m, Vector3(x, 0, 3.5), 0.0, true)
		m.activity = entry[1]
		if entry[1] == "work":
			m.work_pose_active = true
			m.work_target = Vector3(0, .695, 1.0)
		if entry[2] > 0.0: m.set_seat_pose(1.0, 0.45, 0)
		movers.append({"winter": m})
		x += 1.6
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	for shot in [["jogo", 16.0, Vector3(0, 0, 0)], ["policia", 6.0, Vector3(-3.0, 0, -3.5)], ["socorro", 6.0, Vector3(-3.0, 0, 0.0)], ["residentes", 6.0, Vector3(4.0, 0, 0.0)], ["garagem", 6.0, Vector3(-2.0, 0, 3.5)], ["montanha", 6.0, Vector3(4.5, 0, 3.5)]]:
		camera.size = shot[1]
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 4, 0, 0)), shot[2] + Vector3(0, 30, 30))
		for frame in 3:
			for step in 12: await _advance()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_dir + "/%s-%02d.png" % [shot[0], frame]))
	print("NPC_SHOWCASE ok ", output_dir)
	quit(0)

func _place(stage: Node3D, model: Node3D, point: Vector3, speed: float, faces_positive_z := false) -> void:
	var carrier := Node3D.new()
	carrier.position = point
	stage.add_child(carrier)
	carrier.add_child(model)
	# Todos de frente para a câmera (+Z); quem anda vai para +X.
	if speed > 0.0: model.rotation.y = -PI / 2 if not faces_positive_z else PI / 2
	else: model.rotation.y = 0.0 if faces_positive_z else PI
	if speed > 0.0: movers.append({"node": carrier, "speed": speed, "origin": point})

func _advance() -> void:
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_usec) / 1000000.0, 0.001, 0.25) if _last_usec > 0 else 1.0 / 60.0
	_last_usec = now
	for entry in movers:
		if entry.has("winter"):
			entry.winter.work_time += delta
			continue
		var node: Node3D = entry.node
		node.position.x += entry.speed * delta
		if node.position.x - entry.origin.x > 1.2:
			node.position.x -= 2.4
			var body = null
			for child in node.get_children(): body = child.get_meta("rig_body", null)
			if body: body.teleported()
	for entry in police:
		if is_instance_valid(entry.model.weapon): entry.model.update_pose(delta, entry.aim, false, 0.0, 0.0)
	await process_frame
