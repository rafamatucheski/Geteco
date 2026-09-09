extends SceneTree

## Gera capturas de showcase do Dante CGI v2 em gameplay real:
## Frente, Costas, Perfil, Mirando Pistola 1H e Fuzil 2H.

const HARBOR_SCENE: PackedScene = preload("res://world/harbor/HarborGame.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = HARBOR_SCENE.instantiate()
	root.add_child(world)
	current_scene = world

	for f in 8:
		await physics_frame

	paused = false
	var arrival = world.get_node_or_null("ArrivalMission")
	if arrival: arrival.queue_free()

	for f in 5:
		await physics_frame

	var player = world.get_node_or_null("Player") as CharacterBody2D
	player.show()
	player.set_physics_process(true)
	player.is_control_disabled = false
	player.is_in_dialogue = false

	# Posicionar na praça iluminada da orla
	player.global_position = Vector2(1720, 1150)
	var cam = player.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.zoom = Vector2(3.0, 3.0) # Zoom próximo para detalhe nítido
		cam.position_smoothing_enabled = false

	# 1. Frente com Pistola
	player.active_weapon_id = "pistol"
	player._update_equipped_weapon_3d_mesh()
	player.model_root.rotation.y = PI # Frente para a câmera
	for f in 10:
		await physics_frame

	var img_front = root.get_viewport().get_texture().get_image()
	img_front.save_png("res://tests/dante_showcase_front_pistol.png")

	# 2. Mirando Fuzil AK47
	player.active_weapon_id = "ak47"
	player._update_equipped_weapon_3d_mesh()
	player.combat_pose.on_attack("ak47")
	player.model_root.rotation.y = PI * 0.75 # Ângulo 3/4 frontal
	for f in 10:
		await physics_frame

	var img_ak = root.get_viewport().get_texture().get_image()
	img_ak.save_png("res://tests/dante_showcase_aim_ak47.png")

	# 3. Costas
	player.model_root.rotation.y = 0.0 # Costas para a câmera
	for f in 10:
		await physics_frame

	var img_back = root.get_viewport().get_texture().get_image()
	img_back.save_png("res://tests/dante_showcase_back.png")

	var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/ac7b8daf-4790-408c-8376-3690d7044e34"
	var d := DirAccess.open(artifact_dir)
	if d:
		d.copy("res://tests/dante_showcase_front_pistol.png", artifact_dir + "/dante_showcase_front_pistol.png")
		d.copy("res://tests/dante_showcase_aim_ak47.png", artifact_dir + "/dante_showcase_aim_ak47.png")
		d.copy("res://tests/dante_showcase_back.png", artifact_dir + "/dante_showcase_back.png")

	print("Capturas de showcase salvas com sucesso!")
	quit(0)
