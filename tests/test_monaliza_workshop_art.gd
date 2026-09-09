@tool
extends SceneTree

## Suíte de Testes e Renderização da Oficina do Maciota (MonalizaWorkshopProps3D)
## Valida contratos de engenharia, desobstrução da vaga de 3.5 x 6.0 m para o cupê
## de 1.86 x 4.46 m, corredor de circulação a pé, vão da porta do escritório (1.40 m),
## get_obstacle_bounds(), get_interaction_points() e renderiza capturas no Vulkan Forward+
## com manequim de 1,80 m e caixa métrica de reserva do carro.

const WORKSHOP_SCRIPT := preload("res://district/harbor_preview/art/monaliza_workshop/MonalizaWorkshopProps3D.gd")
const HUMAN_SCRIPT    := preload("res://district/mountain_pass/art/winter_props/HumanScaleReference3D.gd")

var failures: Array[String] = []
var mesh_count: int = 0

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [OK] " + message)
	else:
		failures.append(message)
		printerr("  [FALHA] " + message)

func _count_meshes(node: Node) -> int:
	var count: int = 0
	if node is MeshInstance3D:
		count += 1
	for c in node.get_children():
		count += _count_meshes(c)
	return count

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n==================================================================")
	print("=== TESTE DA OFICINA DO MACIOTA: CENÁRIO 3D PROCEDURAL (09/08) ===")
	print("==================================================================\n")

	# --------------------------------------------------------------------------
	# 1. VALIDAÇÃO DE CONTRATOS E ESTRUTURA DO NÓ
	# --------------------------------------------------------------------------
	print("--- 1. Validação de Contratos de Engenharia, Vaga e Acessos ---")
	var workshop = WORKSHOP_SCRIPT.new()
	root.add_child(workshop)
	await process_frame
	await process_frame

	_check(workshop is Node3D, "MonalizaWorkshopProps3D herda de Node3D")
	var stall: Vector2 = workshop.get_stall_size()
	_check(stall == Vector2(3.50, 6.00), "get_stall_size() é (3.50, 6.00)m")
	var car_ref: Vector3 = workshop.get_car_reference_size()
	_check(car_ref == Vector3(1.86, 1.25, 4.46), "get_car_reference_size() é (1.86, 1.25, 4.46)m")
	var room_bounds: AABB = workshop.get_room_bounds()
	_check(room_bounds.size.x >= 10.0 and room_bounds.size.z >= 8.0, "get_room_bounds() engloba oficina e escritório (%s)" % str(room_bounds.size))

	# --------------------------------------------------------------------------
	# 2. VALIDAÇÃO DOS PONTOS DE INTERAÇÃO (get_interaction_points)
	# --------------------------------------------------------------------------
	print("\n--- 2. Validação dos Pontos de Interesse e Navegação ---")
	var ipt: Dictionary = workshop.get_interaction_points()
	var expected_keys := [
		"shop_entrance", "car_driver_door", "car_passenger_door",
		"car_hood", "car_trunk", "workbench", "lift_controls",
		"office_doorway", "maciota_desk", "maciota_seat"
	]
	var all_keys_found := true
	for k in expected_keys:
		if not ipt.has(k):
			all_keys_found = false
			printerr("  [FALTA] Ponto de interação não encontrado: ", k)
	_check(all_keys_found, "Todos os 10 pontos de interação principais cadastrados")

	# --------------------------------------------------------------------------
	# 3. VALIDAÇÃO DOS OBSTÁCULOS E DESOBSTRUÇÃO TOTAL (AABB)
	# --------------------------------------------------------------------------
	print("\n--- 3. Validação dos Limites de Obstáculos (get_obstacle_bounds) ---")
	var obstacles: Array[AABB] = workshop.get_obstacle_bounds()
	_check(not obstacles.is_empty(), "get_obstacle_bounds() retorna obstáculos cadastrados (%d volumes)" % obstacles.size())

	# Vaga livre em coordenadas locais: X de -1.75 a +1.75, Z de -3.0 a +3.0, Y de 0.0 a 2.5
	var stall_aabb := AABB(Vector3(-1.75, 0.0, -3.00), Vector3(3.50, 2.50, 6.00))

	var stall_clean: bool = true
	var front_exit_clean: bool = true

	for o in obstacles:
		if o.intersects(stall_aabb):
			stall_clean = false
			printerr("  [VIOLAÇÃO] Obstáculo intercepta a vaga livre: ", o)
		# Verifica que não há obstáculos bloqueando a saída frontal do veículo (+Z em frente à vaga)
		if o.position.z + o.size.z > 2.90 and absf(o.position.x) < 1.75:
			front_exit_clean = false
			printerr("  [VIOLAÇÃO] Obstáculo bloqueia a saída frontal: ", o)

	_check(stall_clean, "Nenhum obstáculo invade a vaga livre central de 3.50 x 6.00m")
	_check(front_exit_clean, "Saída frontal (+Z) completamente desobstruída para manobra do carro")

	# Vão da porta do escritório do Maciota livre no chão (X ~ 2.40m, Z entre +0.90 e +2.10, Y de 0 a 2.0m)
	var doorway_aabb := AABB(Vector3(2.30, 0.0, 0.90), Vector3(0.20, 2.00, 1.20))
	var door_clean := true
	for o in obstacles:
		if o.intersects(doorway_aabb):
			door_clean = false
			printerr("  [VIOLAÇÃO] Obstáculo obstrui o vão livre da porta do escritório: ", o)
	_check(door_clean, "Vão de acesso a pé à sala do Maciota desobstruído (largura > 1.20m, altura 2.00m)")

	# Valida que todos os pontos de interação são acessíveis (não ficam cravados dentro de um obstáculo sólido)
	var points_clear := true
	for k in ipt.keys():
		var pt: Vector3 = ipt[k]
		for o in obstacles:
			if o.grow(-0.02).has_point(pt + Vector3(0, 0.2, 0)):
				points_clear = false
				printerr("  [VIOLAÇÃO] Ponto de interação '%s' está embutido dentro de obstáculo: %s" % [k, str(o)])
	_check(points_clear, "Todos os pontos de interação estão em espaço aberto navegável")

	mesh_count = _count_meshes(workshop)
	_check(mesh_count < 220, "Contagem elegante e econômica de meshes da oficina: %d (< 220)" % mesh_count)

	workshop.queue_free()
	await process_frame

	# --------------------------------------------------------------------------
	# 4. RENDERIZAÇÃO REAL NO GODOT 4.7.2 (VULKAN FORWARD+)
	# --------------------------------------------------------------------------
	print("\n--- 4. Renderização Visual no Vulkan Forward+ com Manequim 1,80 m ---")
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] Capturas exigem renderer real; apenas contratos validados neste modo.")
	else:
		await _render_all_shots()

	# --------------------------------------------------------------------------
	# CONCLUSÃO
	# --------------------------------------------------------------------------
	print("\n==================================================================")
	if failures.is_empty():
		print("=== SUCESSO TOTAL: 0 FALHAS NA OFICINA DO MACIOTA (09/08) ===")
		print("==================================================================\n")
		quit(0)
	else:
		printerr("=== ENCONTRADAS %d FALHAS ===" % failures.size())
		for f in failures:
			printerr("  - " + f)
		print("==================================================================\n")
		quit(1)

func _render_all_shots() -> void:
	var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"

	var world := Node3D.new()
	world.name = "WorkshopWorld3D"
	root.add_child(world)

	# Iluminação ambiente de galpão/oficina
	var main_light := DirectionalLight3D.new()
	main_light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	main_light.light_color = Color(1.0, 0.98, 0.95)
	main_light.light_energy = 1.35
	main_light.shadow_enabled = false
	world.add_child(main_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(40.0, -140.0, 0.0)
	fill_light.light_color = Color(0.85, 0.90, 0.98)
	fill_light.light_energy = 0.60
	fill_light.shadow_enabled = false
	world.add_child(fill_light)

	# Luz aconchegante dourada emitida no escritório do Maciota
	var office_light := OmniLight3D.new()
	office_light.position = Vector3(4.50, 2.50, -1.80)
	office_light.light_color = Color(1.0, 0.88, 0.72)
	office_light.light_energy = 1.60
	office_light.omni_range = 6.0
	office_light.shadow_enabled = false
	world.add_child(office_light)

	var cam := Camera3D.new()
	cam.name = "WorkshopCamera"
	cam.current = true
	world.add_child(cam)

	# Instancia o kit procedural da oficina
	var workshop = WORKSHOP_SCRIPT.new()
	world.add_child(workshop)

	# Manequim métrico 1: Dante (1,80 m) no escritório conversando com o Maciota
	var dante = HUMAN_SCRIPT.new(Color("#2c3e50"), Color("#e67e22"))
	dante.name = "DanteHuman180"
	dante.position = Vector3(4.50, 0.0, -0.20)
	dante.rotation_degrees.y = 180.0
	world.add_child(dante)

	# Manequim métrico 2: Jäger "Maciota" (1,80 m) atrás de sua mesa executiva
	var maciota = HUMAN_SCRIPT.new(Color("#581845"), Color("#d4ac0d"))
	maciota.name = "MaciotaHuman180"
	maciota.position = Vector3(3.40, 0.0, -1.80)
	maciota.rotation_degrees.y = 90.0
	world.add_child(maciota)

	# Caixa métrica translúcida reservando a vaga do cupê Monaliza (1.86 x 4.46 x 1.25 m)
	var car_ghost := _create_car_reservation_box()
	world.add_child(car_ghost)

	# --------------------------------------------------------------------------
	# CAPTURA 1: VISÃO GERAL EM PERSPECTIVA (BAÍA DO CARRO + ELEVADOR + SALA)
	# --------------------------------------------------------------------------
	cam.position = Vector3(-0.60, 2.35, 4.10)
	cam.look_at(Vector3(1.20, 1.10, -1.20))
	for i in range(12):
		await process_frame

	var img1 := root.get_viewport().get_texture().get_image()
	if img1:
		img1.save_png("res://tests/test_monaliza_workshop_overview.png")
		img1.save_png(artifact_dir + "/test_monaliza_workshop_overview.png")
		print("  [OK] Captura 1 salva: Visão Geral Baía do Carro + Elevador + Sala Maciota")

	# --------------------------------------------------------------------------
	# CAPTURA 2: CLOSE-UP DO ESCRITÓRIO DO MACIOTA COM MANEQUIM 1,80 M
	# --------------------------------------------------------------------------
	cam.position = Vector3(3.20, 1.85, 0.50)
	cam.look_at(Vector3(4.50, 1.05, -1.80))
	for i in range(12):
		await process_frame

	var img2 := root.get_viewport().get_texture().get_image()
	if img2:
		img2.save_png("res://tests/test_monaliza_workshop_maciota_office.png")
		img2.save_png(artifact_dir + "/test_monaliza_workshop_maciota_office.png")
		print("  [OK] Captura 2 salva: Sala Própria do Maciota (Mesa, Poltrona, Decanter, Abajur)")

	# --------------------------------------------------------------------------
	# CAPTURA 3: CLOSE-UP DO ELEVADOR AUTOMOTIVO E BANCADA DE MOTORES
	# --------------------------------------------------------------------------
	cam.position = Vector3(-0.60, 2.20, 2.10)
	cam.look_at(Vector3(-0.70, 1.10, -2.60))
	for i in range(12):
		await process_frame

	var img3 := root.get_viewport().get_texture().get_image()
	if img3:
		img3.save_png("res://tests/test_monaliza_workshop_lift_and_bench.png")
		img3.save_png(artifact_dir + "/test_monaliza_workshop_lift_and_bench.png")
		print("  [OK] Captura 3 salva: Elevador Hidráulico de 2 Colunas e Bancada Mecânica")

	# --------------------------------------------------------------------------
	# CAPTURA 4: PLANTA ISOMÉTRICA DE CIRCULAÇÃO E ACESSOS
	# --------------------------------------------------------------------------
	cam.position = Vector3(1.20, 7.80, 2.60)
	cam.look_at(Vector3(1.20, 0.0, 0.20))
	for i in range(12):
		await process_frame

	var img4 := root.get_viewport().get_texture().get_image()
	if img4:
		img4.save_png("res://tests/test_monaliza_workshop_clearance.png")
		img4.save_png(artifact_dir + "/test_monaliza_workshop_clearance.png")
		print("  [OK] Captura 4 salva: Circulação Livre, Corredores e Vão da Porta do Escritório")

	workshop.queue_free()
	dante.queue_free()
	maciota.queue_free()
	car_ghost.queue_free()
	world.queue_free()
	await process_frame

## Cria o volume métrico translúcido do cupê Monaliza (1.86m x 4.46m x 1.25m)
func _create_car_reservation_box() -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "MonalizaCoupeReservation"

	# Corpo translúcido azul e laranja
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.86, 1.25, 4.46)
	mi.mesh = box
	mi.position = Vector3(0.0, 0.625, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.22, 0.60, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.30
	mi.material_override = mat
	root_node.add_child(mi)

	# Contorno estrutural em linhas de arame sólido laranja vibrante
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color("#e67e22")
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Longarinas superiores e inferiores
	for ey in [0.03, 1.22]:
		for ex in [-0.91, 0.91]:
			var wire := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.03, 0.03, 4.44)
			wire.mesh = bm
			wire.position = Vector3(ex, ey, 0.0)
			wire.material_override = edge_mat
			root_node.add_child(wire)

	# Travessas dianteiras e traseiras
	for ey in [0.03, 1.22]:
		for ez in [-2.21, 2.21]:
			var wire_cross := MeshInstance3D.new()
			var bm_cross := BoxMesh.new()
			bm_cross.size = Vector3(1.82, 0.03, 0.03)
			wire_cross.mesh = bm_cross
			wire_cross.position = Vector3(0.0, ey, ez)
			wire_cross.material_override = edge_mat
			root_node.add_child(wire_cross)

	# Pilares verticais dos 4 cantos
	for ex in [-0.91, 0.91]:
		for ez in [-2.21, 2.21]:
			var post := MeshInstance3D.new()
			var bm_post := BoxMesh.new()
			bm_post.size = Vector3(0.03, 1.20, 0.03)
			post.mesh = bm_post
			post.position = Vector3(ex, 0.625, ez)
			post.material_override = edge_mat
			root_node.add_child(post)

	# Aerofólio traseiro
	var wing := MeshInstance3D.new()
	var bm_wing := BoxMesh.new()
	bm_wing.size = Vector3(1.50, 0.04, 0.28)
	wing.mesh = bm_wing
	wing.position = Vector3(0.0, 1.36, -2.05)
	wing.material_override = edge_mat
	root_node.add_child(wing)

	return root_node
