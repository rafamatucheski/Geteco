extends SceneTree

var failures: Array[String] = []
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
const OFFSET := Vector2(4300,-4960)

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)

func _run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	seed(9102026)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var scene := current_scene
	var stream := scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	stream.set_process(false)
	var mountain: Node2D = stream.mountain
	mountain.process_mode = Node.PROCESS_MODE_INHERIT
	mountain.show()
	var player: CharacterBody2D = scene.get_node("Player")
	player.set_physics_process(false)
	player.collision_layer = 4
	player.global_position = OFFSET+Vector2(6000,560)
	var traffic: Node = mountain.get_node("MountainTraffic")
	var minimum := INF
	var fleet := {}
	for car in traffic.vehicles:
		fleet[car.vehicle_id] = true
		for other in traffic.vehicles:
			if other != car: minimum = minf(minimum,car.global_position.distance_to(other.global_position))
	check(minimum >= 96,"Veículos da serra nascem separados no mundo contínuo (%.1f px)"%minimum)
	check(fleet.size() >= 6,"Frota regional tem ao menos seis tipos de veículo")
	var resident_count := get_nodes_in_group("winter_resident").filter(func(n): return mountain.is_ancestor_of(n)).size()
	check(resident_count >= 15,"Moradores de inverno presentes na serra: %d"%resident_count)
	var snow_residents := 0
	for npc in get_nodes_in_group("winter_resident"):
		if mountain.to_local(npc.global_position).y < -1400: snow_residents += 1
	check(snow_residents >= 5,"Moradores distribuídos também na região de neve")
	for car in get_nodes_in_group("vehicle"):
		car.set_process(false)
		car.set_physics_process(false)
	var outbound: Path2D
	var inbound: Path2D
	for path in get_nodes_in_group("unified_traffic_lane"):
		var id := String(path.get_meta("traffic_road_id",""))
		if id.ends_with("mountain_bridge_outbound"): outbound = path
		if id.ends_with("mountain_bridge_inbound"): inbound = path
	check(outbound != null and inbound != null,"Duas faixas da ponte encontradas")
	# Uma transferência bloqueada não pode mover ou duplicar o carro.
	var blocker = traffic.vehicles[0]
	var block_follow: PathFollow2D = blocker.get_parent()
	block_follow.progress = 40
	var probe := FACTORY.spawn_moving_vehicle(outbound,"BridgeQueueProbe","summit_suv",0.65,90,0)
	probe.set_process(false)
	probe.set_physics_process(false)
	var follow: PathFollow2D = probe.get_parent()
	follow.progress = outbound.curve.get_baked_length()-1
	var origin := probe.global_position
	check(not stream._handoff(follow,traffic.lane),"Ponte aguarda espaço na faixa da serra")
	check(follow.get_parent() == outbound and probe.global_position == origin,"Fila bloqueada preserva a posição do veículo")
	block_follow.progress = 500
	check(stream._handoff(follow,traffic.lane),"Transferência liberada quando a fila anda")
	check(probe.global_position.distance_to(origin)<8,"Transferência sem salto entre regiões")
	follow.reparent(outbound,false)
	follow.progress = 140
	# A sonda percorre a curva com outra carroceria adiante, nunca atravessando-a.
	var lead := FACTORY.spawn_moving_vehicle(outbound,"BridgeLeadProbe","polar_van",0.55,75,0)
	lead.set_process(false)
	lead.set_physics_process(false)
	var lead_follow: PathFollow2D = lead.get_parent()
	lead_follow.progress = 250
	var start_progress := follow.progress
	var crossed := false
	for i in 150:
		lead.advance_on_lane(1.0/30.0)
		probe.advance_on_lane(1.0/30.0)
		if follow.get_parent() == outbound and lead_follow.get_parent() == outbound:
			crossed = crossed or follow.progress >= lead_follow.progress
		await physics_frame
	check(not crossed,"Carros mantêm a ordem ao fazer a curva da ponte")
	check(follow.progress > start_progress+120,"Carro completa o arco sem ficar preso")
	check(probe._mountain_hull_is_clear(outbound,follow.progress),"Carrocerias não se sobrepõem na saída da curva")
	# Portas verificadas com a camada real de Dante, que vem do mapa 1.
	var manager: Node = mountain.interior_manager
	var doors: Array = manager._exterior_doors.keys()
	for door in doors:
		var id: StringName = manager._exterior_doors[door].interior_id
		if id not in [&"mountain_outfitters",&"mountain_cabin",&"lumberjack_shelter"]: continue
		player.global_position = door.global_position+Vector2(0,18)
		for i in 5: await physics_frame
		check(door.request_interaction(player),"Porta detecta jogador do porto: "+str(door.get_path()))
		await create_timer(0.3).timeout
		check(player.get_meta("mountain_interior_id",&"") == id,"Entrada leva ao interior correto: "+str(id))
		var interior: Node = manager._interiors[id]
		var exit_door: Node2D = interior.get_node_or_null("ExitDoor")
		if exit_door == null: exit_door = interior.get_node("InteriorExit")
		player.global_position = exit_door.global_position+Vector2(0,-14)
		for i in 5: await physics_frame
		check(exit_door.request_interaction(player),"Saída detecta o jogador: "+str(id))
		await create_timer(0.3).timeout
		check(not player.get_meta("mountain_interior",false),"Saída devolve ao exterior: "+str(id))
		await create_timer(1.0).timeout
	# Saída do asfalto para a grama diante da primeira casa, com colisão real.
	var grass_car := FACTORY.spawn_parked_vehicle(scene,"GrassProbe",OFFSET+Vector2(5980,480),PI*0.5,"arctic_jeep",0)
	grass_car.set_process(false)
	grass_car.set_physics_process(false)
	player.global_position = OFFSET+Vector2(5900,800)
	await physics_frame
	var impacts := []
	var health: float = grass_car.health
	for i in 9:
		var hit := grass_car.move_and_collide(Vector2(0,10))
		if hit: impacts.append(str(hit.get_collider().get_path()))
		await physics_frame
	check(impacts.is_empty() and grass_car.health == health,"Grama diante do abrigo é transitável sem colisão/dano: "+str(impacts))
	for sample in [[Vector2(8000,-4300),true],[Vector2(8000,-4800),true],[Vector2(10300,-4300),false],[Vector2(10300,-4800),false],[Vector2(7000,2500),true]]:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = sample[0]
		query.collision_mask = 1
		var water_blocked := false
		for hit in scene.get_world_2d().direct_space_state.intersect_point(query):
			if str(hit.collider.name).begins_with("EastWaterBoundary"): water_blocked = true
		check(water_blocked == sample[1],"Costa preservada e terra da serra livre em "+str(sample[0]))
	print("MOUNTAIN WORLD FAILURES: ",failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
