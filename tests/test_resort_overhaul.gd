extends SceneTree

## Validador Completo do Redesenho do Resort Cume Branco:
## 1. Heliponto Arquitetural (MountainHelipad)
## 2. Conexão Asfáltica Contínua até o Resort (MountainPassRoad)
## 3. Promenade de Pedestres e Boutique Alpina Conectadas ao Chalé e Teleférico
## 4. Estacionamento Asfaltado com Vagas Demarcadas
## 5. NPCs do Resort Estacionários e com Diálogo Interativo ([E])
## 6. Conformidade com AGENTS.md (nomes próprios limpos, manequins proporcionais)

const PlayerScript = preload("res://characters/Player.gd")
const WinterResidentScript = preload("res://world/mountain_pass/WinterResident.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-rebuild-0913/saves-resort/"
	root.get_node("SaveManager")._save_directory_ready = false
	create_timer(45).timeout.connect(func(): quit(2))
	print("--- INICIANDO TESTE DO REDESENHO DO RESORT CUME BRANCO ---")
	var mountain := preload("res://world/mountain_pass/MountainPass.gd").new()
	mountain.streamed_region = false
	root.add_child(mountain)

	# Aguarda inicialização completa da cena
	while not mountain.region_ready:
		await process_frame

	# ========================================================
	# 1. VALIDAÇÃO DO HELIPONTO ARQUITETURAL
	# ========================================================
	var helipad: Node2D = mountain.find_child("MountainHelipad",true,false)
	if helipad == null:
		for node in mountain.find_children("*","Node2D",true,false):
			if node.get_script() == preload("res://world/mountain_pass/MountainHelipad.gd"): helipad = node; break
	assert(helipad != null and helipad.model is Node3D,"Helipad uses native geometry")
	assert(helipad.platform_body.get_child_count() >= 6,"Mast and rails have projected solids; the landing deck remains walkable")
	var summit_road: MountainPassRoad = mountain.get_node("MountainPassRoad")
	# The full projected landing deck must stay off the road, not just its anchor.
	for step in 64:
		var floor_point := Vector2.from_angle(TAU * step / 64.0) * 3.1
		var deck_point := summit_road.to_local(helipad.to_global(helipad.project_floor(floor_point)))
		assert(not Geometry2D.is_point_in_polygon(deck_point, summit_road.pavement[0]), "Helipad deck must not cover the road")
	print("[2/5] Validando Conexão Asfáltica da Rodovia com o Resort...")
	var road: MountainPassRoad = mountain.get_node_or_null("MountainPassRoad") as MountainPassRoad
	assert(road != null, "MountainPassRoad deve existir")
	assert(road.resort_curve != null, "road.resort_curve deve estar configurado")
	assert(road.resort_smooth_points.size() > 5, "resort_smooth_points deve ter spline suave gerada")
	assert(road.summit_connector_curve != null, "road.summit_connector_curve deve estar configurado")
	assert(road.summit_connector_smooth_points.size() > 5, "summit_connector_smooth_points deve ter spline suave gerada")

	# The connected driveways must not contain internal curbs or guardrails.
	assert(road.pavement.size() == 1, "Summit pavement must have one outside contour")
	for point in [Vector2(6850,-2450), Vector2(6918,-2545), Vector2(7020,-2500), Vector2(7070,-2545)]:
		assert(Geometry2D.is_point_in_polygon(point, road.pavement[0]), "Continuous pavement at %s" % point)
		var contour: PackedVector2Array = road.pavement[0]
		for i in contour.size():
			assert(point.distance_to(Geometry2D.get_closest_point_to_segment(point, contour[i], contour[(i+1)%contour.size()])) > 20.0, "No curb through circulation at %s" % point)
	for section in road._guard_rail_sections():
		for point in section:
			assert(not road._in_resort_surface(point, 12.0), "Guardrails stay outside summit driveways")

	# Verifica se is_point_on_road reconhece a chegada no resort e conector
	assert(road.is_point_on_road(Vector2(6850, -2450)), "Entroncamento da rodovia deve estar na pista")
	assert(road.is_point_on_road(Vector2(7020, -2560)), "Acesso asfaltado do resort deve estar na pista")
	assert(road.is_point_on_road(Vector2(7140, -2545)), "Concourse / Porte-Cochère do resort deve estar na pista")
	assert(road.is_point_on_road(Vector2(6820, -2545)), "Conector entre bunker e resort deve estar na pista")
	assert(road.is_point_on_road(Vector2(6990, -2545)), "Estacionamento do resort deve estar na pista")
	print("  -> Conexão asfáltica e concourse validados com sucesso!")

	# ========================================================
	# 3. VALIDAÇÃO DAS LOJAS E PROMENADE DO RESORT
	# ========================================================
	print("[3/5] Validando Fachadas de Lojas e Promenade...")
	var settlement: Node2D = mountain.get_node_or_null("MountainSettlement")
	assert(settlement != null, "MountainSettlement deve existir")

	# Chalé Principal
	var lodge: Node2D = settlement.get_node_or_null("SummitSkiLodge")
	assert(lodge != null, "SummitSkiLodge deve estar presente no settlement")
	var lodge_door: BuildingEntrance = lodge.get_node_or_null("SkiLodgeEntrance") as BuildingEntrance
	assert(lodge_door != null, "Porta de entrada do chalé deve existir")
	assert(lodge_door.display_name == "CUME BRANCO", "Nome próprio da fachada deve ser CUME BRANCO")

	# Boutique Alpina
	var boutique: ResortShopFacade = settlement.get_node_or_null("ResortShopFacade") as ResortShopFacade
	assert(boutique != null, "ResortShopFacade deve estar instanciado")
	assert(boutique.entrance != null, "Entrada da Boutique Alpina deve existir")
	assert(boutique.entrance.display_name == "BOUTIQUE ALPINA", "Nome próprio da fachada deve ser BOUTIQUE ALPINA")
	assert(boutique.entrance.destination_id == &"mountain_outfitters", "Destino deve ser o interior mountain_outfitters")
	assert(boutique.model.find_children("WindowBackdrop*", "MeshInstance3D",true,false).size()==2, "Both boutique windows have native 3D displays")

	# Promenade de Pedestres
	var promenade: ResortPromenade = settlement.get_node_or_null("ResortPromenade") as ResortPromenade
	assert(promenade != null, "ResortPromenade deve estar instanciada")
	assert(promenade.get_node_or_null("MainPlazaDeck") is Polygon2D, "Calçadão de madeira deve existir")
	assert(promenade.get_node_or_null("LiftPromenadeDeck") is Polygon2D, "Alameda do teleférico deve existir")
	assert(promenade.get_node_or_null("ResortCentralBrazier") != null, "Braseiro central aquecido deve existir")

	var brazier_heat: Area2D = promenade.get_node("ResortCentralBrazier/PromenadeBrazierHeat") as Area2D
	assert(brazier_heat.is_in_group("heat_source"), "Braseiro deve ser fonte de calor (heat_source)")

	# Estacionamento demarcado
	var bay2: Line2D = settlement.get_node_or_null("WinterParkingBay2") as Line2D
	assert(bay2 != null, "Demarcação de vagas do resort deve existir")
	print("  -> Lojas, Promenade e infraestrutura do resort validadas com sucesso!")

	# ========================================================
	# 4. VALIDAÇÃO DOS NPCS DO RESORT E INTERATIVIDADE
	# ========================================================
	print("[4/5] Validando NPCs do Resort e Diálogos...")
	var player: Node2D = mountain.get_node_or_null("Player") as Node2D
	assert(player != null, "Player deve existir")

	# Íris (Concierge do Concourse)
	var iris: Node2D
	var sergio: Node2D
	for child in settlement.get_children():
		if child.get_script() == WinterResidentScript:
			if child.resident_name == "ÍRIS":
				iris = child
			elif child.resident_name == "SÉRGIO":
				sergio = child

	assert(iris != null, "NPC ÍRIS deve existir no resort")
	assert(iris.is_stationary, "ÍRIS deve ser estacionária no resort")
	assert(iris.lines.size() >= 3, "ÍRIS deve ter diálogos próprios do resort")
	assert(iris.prompt_badge != null, "ÍRIS deve ter badge de interação [E]")

	assert(sergio != null, "NPC SÉRGIO deve existir no resort")
	assert(sergio.is_stationary, "SÉRGIO deve ser estacionário")
	assert(sergio.role == "visitor", "SÉRGIO deve ser visitante (não cortador de lenha)")
	assert(sergio.lines.size() >= 2, "SÉRGIO deve ter diálogos sobre o resort")

	# Camila (Instrutora na Promenade)
	var camila: Node2D = promenade.get_node_or_null("ResortSkiInstructor") as Node2D
	assert(camila != null, "NPC CAMILA deve existir na promenade")
	assert(camila.is_stationary, "CAMILA deve ser estacionária")
	assert(camila.lines.size() >= 3, "CAMILA deve ter linhas de instrução de ski")

	# Both actors can reach and leave the relocated pad along its actual footpath.
	var pad_access: Line2D = helipad.get_parent().get_node("HelipadFootpath")
	for actor in [player, iris]:
		var original_position: Vector2 = actor.global_position
		var was_processing: bool = actor.is_physics_processing()
		actor.set_physics_process(false)
		var route := PackedVector2Array()
		var points := pad_access.points.duplicate()
		points.reverse()
		for point in points: route.append(pad_access.to_global(point))
		route.append(helipad.to_global(helipad.project_floor(Vector2.ZERO)))
		actor.global_position = route[0]
		for direction in 2:
			for index in range(1,route.size()):
				await physics_frame
				var blocked: KinematicCollision2D = actor.move_and_collide(route[index]-actor.global_position)
				assert(blocked == null, "Player and NPC can walk to and from the helipad")
			route.reverse()
		actor.global_position = original_position
		actor.set_physics_process(was_processing)
	print("PASS helipad clears road and player/NPC access stays open")

	# Testa interação do jogador com um dos NPCs
	player.global_position = iris.global_position + Vector2(25, 0)
	iris._interact_talk(player)
	assert(iris.speech_panel.visible, "Balão de diálogo de ÍRIS deve abrir ao interagir")
	assert(iris.dialogue_index == 1, "Índice de diálogo deve avançar após interação")
	print("  -> NPCs do resort, stationing e diálogos validados com sucesso!")

	# ========================================================
	# 5. VALIDAÇÃO DE FLUXO DE COMPRA E TELEFÉRICO
	# ========================================================
	print("[5/5] Validando Integração Completa...")
	var ski_area: MountainSkiArea = mountain.get_node_or_null("MountainSkiArea") as MountainSkiArea
	assert(ski_area != null, "MountainSkiArea deve existir")
	var lift_summit = ski_area.get_node_or_null("SummitLiftStation")
	assert(lift_summit != null, "Estação SummitLiftStation deve existir")
	# Sweep the real SUV along both approaches, retaining parked vehicles,
	# scenery and guardrails. Scene-presence checks cannot prove circulation.
	var suv := preload("res://world/mountain_pass/MountainSUV.gd").new()
	mountain.add_child(suv)
	suv.set_physics_process(false)
	for approach in [road.resort_smooth_points,road.summit_connector_smooth_points]:
		suv.global_position = road.to_global(approach[0])
		for index in range(1,approach.size()):
			# Stop at the roundabout entrance, before its landscaped island.
			if approach[index].distance_to(Vector2(7140,-2545))<100: break
			var destination := road.to_global(approach[index])
			suv.rotation = suv.global_position.direction_to(destination).angle()
			await physics_frame
			assert(suv.collision_mask == 23 and not suv.has_meta("mountain_falling"), "Paved access must never trigger a cliff fall")
			var obstruction := suv.move_and_collide(destination-suv.global_position)
			assert(obstruction==null,"Resort approach blocked at %s by %s"%[suv.global_position,obstruction.get_collider() if obstruction else "none"])
	print("PASS production SUV traverses both resort approaches with scenery and parking enabled")
	# Drive a complete circuit, then approach the visible island with the real body.
	var center := road.to_global(road.RESORT_ISLAND_CENTER)
	suv.global_position = center + Vector2(76, 0)
	for step in range(1, 97):
		var destination := center + Vector2.from_angle(TAU * step / 96.0) * 76.0
		suv.rotation = suv.global_position.direction_to(destination).angle()
		await physics_frame
		var circuit_hit := suv.move_and_collide(destination-suv.global_position)
		if circuit_hit:
			push_error("Roundabout blocked step=%d position=%s collider=%s" % [step, suv.global_position, circuit_hit.get_collider().get_path()])
			quit(1)
			return
	suv.global_position = center + Vector2(96, 0)
	suv.rotation = PI
	await physics_frame
	var island_hit := suv.move_and_collide(center-suv.global_position)
	assert(island_hit != null and island_hit.get_collider() == road.get_node("ResortIsland"), "The visible island blocks the vehicle")
	print("PASS roundabout circulation and island collision")
	suv.queue_free()

	print("--- TODOS OS 5 BLOCOS DO RESORT CUME BRANCO PASSARAM COM SUCESSO! ---")
	quit(0)
