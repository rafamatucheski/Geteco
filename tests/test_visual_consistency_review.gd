extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	print("=================================================================")
	print("=== INICIANDO TESTE E CAPTURA DE CONSISTÊNCIA VISUAL 3D ===")
	print("=================================================================")
	root.size = Vector2i(1280, 800)

	var world := Node3D.new()
	root.add_child(world)

	# 1. Environment & Lighting
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("141820")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d0d8e8")
	env.environment.ambient_light_energy = 0.85
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(25, 145, 0)
	fill_light.light_energy = 0.45
	world.add_child(fill_light)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(100, 100)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("1c222c")
	floor_mat.roughness = 0.8
	floor_mesh.material_override = floor_mat
	world.add_child(floor_mesh)

	var camera := Camera3D.new()
	world.add_child(camera)

	# -------------------------------------------------------------
	# 2. VALIDAR E CAPTURAR DANTE RIBEIRO (CGI FIDELITY)
	# -------------------------------------------------------------
	print("\n--- 1. VERIFICANDO MODELO 3D DO DANTE (CGI) ---")
	var dummy_player := CharacterBody2D.new()
	dummy_player.set_script(load("res://characters/Player.gd"))
	var dante_root := Node3D.new()
	dante_root.name = "DanteRoot"
	dummy_player.model_root = dante_root
	world.add_child(dante_root)

	var shadow := MeshInstance3D.new()
	shadow.mesh = CylinderMesh.new()
	shadow.mesh.top_radius = 0.28
	shadow.mesh.bottom_radius = 0.28
	shadow.mesh.height = 0.01
	shadow.position.y = 0.01
	dante_root.add_child(shadow)

	var adapter = load("res://scripts/player/DanteVisualAdapter.gd")
	adapter.build_dante_rig(dummy_player, "dante_classic")

	# Contract checks
	assert(dummy_player.torso_node != null, "torso_node ausente")
	assert(dummy_player.head_node != null, "head_node ausente")
	assert(dummy_player.left_upper_arm != null, "left_upper_arm ausente")
	assert(dummy_player.right_upper_arm != null, "right_upper_arm ausente")
	assert(dummy_player.weapon_mount_node != null, "weapon_mount_node ausente")
	assert(dummy_player.mat_black_jacket != null, "mat_black_jacket ausente")

	var dante_meshes := _count_meshes(dante_root)
	print("Dante mesh count: ", dante_meshes)
	assert(dante_meshes >= 50, "Dante deve possuir malha detalhada (>= 50)")

	# Equip a pistol in weapon mount for the action shot
	var pistol_mesh := MeshInstance3D.new()
	pistol_mesh.mesh = BoxMesh.new()
	pistol_mesh.mesh.size = Vector3(0.04, 0.09, 0.18)
	var mat_gun := StandardMaterial3D.new()
	mat_gun.albedo_color = Color("1a1e24")
	mat_gun.metallic = 0.9
	mat_gun.roughness = 0.2
	pistol_mesh.material_override = mat_gun
	dummy_player.weapon_mount_node.add_child(pistol_mesh)
	pistol_mesh.position = Vector3(0, 0, -0.06)

	# Add key light facing Dante from front (-Z)
	var key_dante := DirectionalLight3D.new()
	key_dante.rotation_degrees = Vector3(-25, -155, 0)
	key_dante.light_energy = 1.1
	world.add_child(key_dante)

	# A) Capture Dante Close-up (face, hair, stubble, henley, flannel)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 22.0
	camera.position = Vector3(-0.25, 1.44, -1.50)
	camera.look_at(Vector3(0.0, 1.38, 0.0))

	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var img_dante_close := root.get_texture().get_image()
	img_dante_close.save_png("res://tests/test_dante_cgi_closeup.png")
	print("Salvo: tests/test_dante_cgi_closeup.png")

	# B) Capture Dante Full-Body Action (flannel, belt, jeans, boots, pistol)
	camera.fov = 38.0
	camera.position = Vector3(-1.10, 1.10, -2.35)
	camera.look_at(Vector3(0.0, 0.90, 0.0))

	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var img_dante_full := root.get_texture().get_image()
	img_dante_full.save_png("res://tests/test_dante_fullbody_turnaround.png")
	print("Salvo: tests/test_dante_fullbody_turnaround.png")

	dante_root.visible = false

	# -------------------------------------------------------------
	# 3. VALIDAR E CAPTURAR MONALIZA COUPE (FMIC, SPOILER, LIVERY)
	# -------------------------------------------------------------
	print("\n--- 2. VERIFICANDO MODELO 3D DA MONALIZA ---")
	var monaliza_class = load("res://world/harbor/monaliza/MonalizaModel.gd")
	var car: Node3D = monaliza_class.new()
	world.add_child(car)

	assert(car.trunk_pivot != null, "trunk_pivot ausente na Monaliza")
	assert(car.trunk_pivot.name == "MonalizaTrunkHinge", "Nome de trunk_pivot incorreto")
	assert(car.trunk_pivot.position.is_equal_approx(Vector3(0, 0.86, 1.48)), "Posição de trunk_pivot incorreta")

	var car_meshes := _count_meshes(car)
	print("Monaliza mesh count: ", car_meshes)
	assert(car_meshes >= 30, "Monaliza deve possuir malha detalhada (>= 30)")

	# C) Capture Monaliza Front 3/4 Review (FMIC, canards, splitter, headlights, rims)
	camera.fov = 38.0
	camera.position = Vector3(3.6, 1.7, -4.5)
	camera.look_at(Vector3(0.0, 0.55, -0.6))

	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var img_car_front := root.get_texture().get_image()
	img_car_front.save_png("res://tests/test_monaliza_front_review.png")
	print("Salvo: tests/test_monaliza_front_review.png")

	# D) Capture Monaliza Rear 3/4 Review with Open Trunk & Swan-Neck Wing
	car.trunk_pivot.rotation.x = -1.1 # Trunk open state
	camera.position = Vector3(-3.4, 2.0, 4.4)
	camera.look_at(Vector3(0.0, 0.70, 1.2))

	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var img_car_trunk := root.get_texture().get_image()
	img_car_trunk.save_png("res://tests/test_monaliza_trunk_wing_review.png")
	print("Salvo: tests/test_monaliza_trunk_wing_review.png")

	# Copy files to artifact dir so they can be viewed
	var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"
	img_dante_close.save_png(artifact_dir + "/test_dante_cgi_closeup.png")
	img_dante_full.save_png(artifact_dir + "/test_dante_fullbody_turnaround.png")
	img_car_front.save_png(artifact_dir + "/test_monaliza_front_review.png")
	img_car_trunk.save_png(artifact_dir + "/test_monaliza_trunk_wing_review.png")

	print("\n>>> VISUAL_CONSISTENCY_PASS: Todas as verificações e capturas concluídas com sucesso! <<<")

	dummy_player.queue_free()
	world.queue_free()
	await process_frame
	quit()

func _count_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _count_meshes(child)
	return count
