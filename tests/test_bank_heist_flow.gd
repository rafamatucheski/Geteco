extends SceneTree

const OUTPUT := "res://docs/measurements/bank-heist-0910/"
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")

func _run() -> void:
	create_timer(90).timeout.connect(func(): printerr("BANK_HEIST TIMEOUT"); quit(2))
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_call_complete", true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	for i in 3: await physics_frame
	var manager = world.get_node("Interiors")
	var room = manager.get_node("InteriorSpaces/BankInterior")
	var player = world.get_node("Player")
	player.active_weapon_id = "fists"
	player.weapon_aim_active = false
	Input.action_press("interact")
	manager._on_exterior_destination_requested(room.entrance, player, room.entrance.destination_id, null, &"", room, room.spawn_point)
	player.set_physics_process(false)
	await create_timer(0.6).timeout
	check(player.global_position.distance_to(room.to_global(room.vault_position))>140,"Entrada chega ao salão, longe do cofre")
	check(not room.lockpick.active and not room.alarm_started,"E da entrada não abre lockpick nem dispara alarme")
	check(player.get_node("Camera").has_meta("compact_interior"),"Câmera enquadra o banco inteiro sem varrer o mapa")
	var minimap=world.get_node("Minimap")
	check(minimap.map_world_position(player).distance_to(room.entrance.global_position)<1,"Minimapa mantém o banco como localização exterior")
	Input.action_release("interact")
	await capture("01_entrada")
	var guard_origins: Array[Vector2]=[]
	for guard in room.guards: guard_origins.append(guard.global_position)
	player.active_weapon_id="pistol"
	player.weapon_aim_active=true
	room._process(0.5)
	for guard in room.guards: guard._physics_process(0.5)
	check(room.armed_warning and not room.alarm_started,"Sacar e mirar provocam advertência sem tiros ou alarme automático")
	check(room.guards[0].fire_cooldown<=0 and room.guards[0].global_position.is_equal_approx(guard_origins[0]),"Guarda mantém posto durante advertência")
	await capture("02_advertencia")
	player.active_weapon_id="fists"
	player.weapon_aim_active=false
	room._process(0.1)
	check(not room.armed_warning and not room.alarm_started,"Guardar arma encerra advertência pacificamente")
	player.active_weapon_id="pistol"
	player.global_position=room.to_global(room.project_floor(Vector2(0,0)))
	player._respawn_grace_active=true
	player.weapon_fired.emit()
	check(room.alarm_started and room.shots_fired,"Primeiro tiro inicia combate e contagem da polícia")
	for guard in room.guards: guard._physics_process(0.2)
	check(room.guards[0].fire_cooldown>0 or room.guards[1].fire_cooldown>0,"Segurança revida com projéteis reais")
	player.global_position=room.to_global(room.vault_position)
	var vault_ray:=PhysicsRayQueryParameters2D.create(player.global_position,room.to_global(room.loot_positions[1]),1)
	check(not player.get_world_2d().direct_space_state.intersect_ray(vault_ray).is_empty(),"Porta fechada bloqueia fisicamente a sala do dinheiro")
	room._tick_vault(2,true)
	check(not room.lockpick.active,"Cofre não ignora os guardas vivos")
	for guard in room.guards: guard.take_damage(1000,true)
	for i in 70: await physics_frame
	check(room._security_clear() and room.keycard_available,"Segurança neutralizada deixa cartão coletável")
	room.set_process(false)
	player.global_position=room.keycard_position
	room._tick_vault(1.3,true)
	check(room.keycard_taken,"Cartão exige coleta junto ao guarda")
	player.global_position=room.to_global(room.vault_position)
	room._tick_vault(0.7,true)
	check(room.lockpick.active and player.is_in_dialogue,"Cartão e interação deliberada iniciam o cofre")
	var before_timer: float=room.alarm_time
	room._process(0.5)
	check(room.alarm_time<before_timer,"Relógio da polícia continua durante lockpick")
	await capture("03_cofre")
	room.lockpick.finish(false)
	check(not room.vault_open and not player.is_in_dialogue,"Cancelar devolve controle sem abrir cofre")
	Input.action_press("interact")
	room._process(1.0)
	check(not room.lockpick.active,"Cancelar exige soltar E antes de tentar novamente")
	Input.action_release("interact")
	room._tick_vault(0.7,true)
	room.lockpick.angle=room.lockpick.target_angle+1
	room.lockpick.attempt()
	check(room.lockpick.mistakes==1 and not room.vault_open,"Erro na fechadura não abre o cofre")
	for i in 3:
		room.lockpick.angle=room.lockpick.target_angle
		room.lockpick.attempt()
	check(room.opening_time>0 and not room.vault_open,"Porta pesada abre gradualmente após destravar")
	room._process(3.1)
	check(room.vault_open and room.vault_body.collision_layer==0,"Cofre aberto libera passagem física")
	await physics_frame
	check(player.get_world_2d().direct_space_state.intersect_ray(vault_ray).is_empty(),"Porta destravada permite atravessar até o dinheiro")
	var wallet: int=player.money
	player.global_position=room.to_global(room.loot_positions[0])
	room._tick_vault(1.3,true)
	room._tick_vault(2,true)
	check(player.money==wallet+400,"Dinheiro recompensa uma vez por pilha")
	room._process(0.1)
	await capture("04_coleta")
	room.alarm_time=0.1
	room._process(0.2)
	check(room.dispatched and is_instance_valid(room.blockade),"Fim da contagem inicia cerco externo")
	var blockade=room.blockade
	var first_unit=blockade.units[0] if not blockade.units.is_empty() else null
	check(first_unit!=null and first_unit.global_position.distance_to(room.entrance.global_position)>350,"Viatura parte da cidade, sem surgir na porta")
	Engine.time_scale=5.0
	for i in 2400:
		await physics_frame
		if blockade.units.size()==3 and blockade.units.all(func(unit): return unit.is_acting): break
	Engine.time_scale=1.0
	check(blockade.units.size()==3,"Três viaturas despachadas em sequência")
	check(blockade.is_ready() and blockade.units.all(func(unit): return unit.is_acting),"Três viaturas chegam fisicamente e formam cerco")
	for unit in blockade.units: print("BANK_UNIT ",unit.global_position," target=",unit.target.global_position if is_instance_valid(unit.target) else Vector2.ZERO," acting=",unit.is_acting)
	var exterior_camera:=Camera2D.new()
	world.add_child(exterior_camera)
	exterior_camera.global_position=room.entrance.global_position+Vector2(0,120)
	exterior_camera.zoom=Vector2(2,2)
	exterior_camera.make_current()
	await capture("05_cerco")
	manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",room.entrance.destination_id)
	player.set_physics_process(false)
	for i in 10: await physics_frame
	check(not player.has_meta("police_exterior_position") and player.global_position.distance_to(room.entrance.global_position)<100,"Saída retorna à mesma porta e restaura coordenadas externas")
	var threatening:=0
	for officer in get_nodes_in_group("police_officer"):
		if officer.service_vehicle in blockade.units and officer.target==player and officer.response_aggression>0: threatening+=1
	check(threatening>=2,"Duplas cobrem a saída e enfrentam o assaltante")
	await capture("06_fuga")
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	player.set_physics_process(false)
	room._process(0.1)
	check(room.vault_open and room._taken("cash0") and not room.lockpick.active,"Reentrar preserva cofre e pilhas coletadas sem repetir lockpick")
	manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",room.entrance.destination_id)
	player.global_position=room.entrance.global_position+Vector2(1200,0)
	blockade._physics_process(0.1)
	check(not blockade.active and not player.has_meta("bank_heist_active"),"Sair do quarteirão encerra o cerco e libera a perseguição normal")
	var fuel=manager.get_node("InteriorSpaces/FuelInterior")
	manager._on_exterior_destination_requested(fuel.entrance,player,fuel.entrance.destination_id,null,&"",fuel,fuel.spawn_point)
	player.set_physics_process(false)
	room._process(0.1)
	fuel.set_process(false)
	fuel.cashier_resists=false
	player.global_position=fuel.to_global(Vector2(0,10))
	var clerk=fuel.civilians[0]
	exterior_camera.global_position=fuel.global_position
	for i in 3: await process_frame
	Input.warp_mouse(player.get_global_transform_with_canvas()*player.to_local(clerk.global_position))
	await process_frame
	player.weapon_aim_active=true
	wallet=player.money
	fuel._tick_cashier(3.2,clerk.global_position)
	fuel._tick_cashier(4,clerk.global_position)
	check(fuel.cash_paid and player.money==wallet+180,"Posto preserva intimidação e pagamento único do caixa")
	print("BANK_HEIST: ",failures)
	quit(0 if failures.is_empty() else 1)
