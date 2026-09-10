extends SceneTree
const OUTPUT := "res://docs/measurements/bank-aftermath-0910/"
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")

func _run() -> void:
	create_timer(100).timeout.connect(func(): printerr("BANK_AFTERMATH TIMEOUT"); quit(2))
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var state=root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_arrival_call_complete",true)
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	var manager=world.get_node("Interiors")
	while not manager.has_node("InteriorSpaces/BankInterior"): await process_frame
	var room=manager.get_node("InteriorSpaces/BankInterior")
	var player=world.get_node("Player")
	var event=room.aftermath
	player.active_weapon_id="fists"
	manager._on_exterior_destination_requested(room.entrance,player,&"",null,&"",room,room.spawn_point)
	player.set_physics_process(false)
	await create_timer(.7).timeout
	player.global_position=room.to_global(room.project_floor(Vector2(0,-.6)))
	player.active_weapon_id="pistol"
	player.weapon_aim_active=true
	room._process(.1)
	check(room.civilians.all(func(npc): return npc.frightened and npc.reaction=="flee"),"Apontar arma inicia evacuação dos dois atendentes")
	check(not room.alarm_started and state.bank_incident.is_empty(),"Ameaça sem assalto ainda não interdita o banco")
	var evacuees: Array=room.civilians.duplicate()
	for i in 450:
		await physics_frame
		if evacuees.all(func(npc): return is_instance_valid(npc) and npc.outside_bank): break
	check(evacuees.all(func(npc): return is_instance_valid(npc) and npc.outside_bank and npc.global_position.distance_to(room.entrance.global_position)<450),"Atendentes atravessam a saída e continuam na rua")
	var street_cam := Camera2D.new()
	world.add_child(street_cam)
	street_cam.global_position=room.entrance.global_position+Vector2(0,65)
	street_cam.zoom=Vector2(2,2)
	street_cam.make_current()
	await capture("01_evacuacao")
	player.get_node("Camera").make_current()
	player.active_weapon_id="fists"
	player.weapon_aim_active=false
	for guard in room.guards: guard.take_damage(1000,true)
	room._process(.01)
	room.set_process(false)
	await create_timer(1.3).timeout
	for guard in room.guards:
		var fall=guard.fall_presentation
		check(guard.viewport_3d.get_camera_3d().transform.is_equal_approx(fall.camera_transform),"Queda preserva a projeção do piso")
		var head_pixel: Vector2=guard.viewport_3d.get_camera_3d().unproject_position(guard.head_node.global_position)-Vector2(guard.viewport_3d.size)*.5
		var head_point: Vector2=room.to_local(guard.sprite_3d_display.to_global(head_pixel))
		check(head_point.y>room.project_floor(Vector2(0,-.4)).y,"Cabeça fica à frente do balcão, sobre o chão")
	await capture("02_corpos_no_piso")
	check(state.bank_incident.phase=="pending" and room.can_enter(),"Consequência aguarda a saída sem prender o jogador dentro")
	manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",room.entrance.destination_id)
	player.set_physics_process(false)
	room._process(.01)
	await create_timer(.6).timeout
	check(event.closed and not room.entrance.enabled and not room.can_enter(),"Banco fica interditado após o assalto")
	var origin: Vector2=player.global_position
	manager._on_exterior_destination_requested(room.entrance,player,&"",null,&"",room,room.spawn_point)
	check(player.global_position.is_equal_approx(origin),"Entrada direta também respeita interdição")
	player.set_physics_process(true)
	Input.action_press("move_up")
	for i in 45: await physics_frame
	Input.action_release("move_up")
	player.set_physics_process(false)
	check(not room.actor_inside() and player.global_position.y>=room.entrance.global_position.y-2,"Barreira impede atravessar a porta caminhando")
	player.global_position=origin
	check(is_instance_valid(event.patrol) and event.officers.size()==2,"Viatura com dupla vigia a lateral do banco")
	street_cam.make_current()
	await capture("03_interditado")
	var saved: Dictionary=state.to_save_data()
	state.bank_incident.clear()
	check(state.restore_from_save(saved) and state.bank_incident.phase=="closed","Save restaura o evento e o prazo de interdição")
	event.free()
	await process_frame
	event=load("res://world/harbor/events/BankAftermath.gd").new()
	event.room=room
	room.aftermath=event
	room.add_child(event)
	for i in 60:
		await physics_frame
		if event.officers.size()==2: break
	check(event.officers.size()==2,"Restaurar não duplica a patrulha")
	var days: float=state.bank_incident.elapsed_days
	state._process(get_first_node_in_group("day_night_manager").day_length_seconds)
	check(is_equal_approx(state.bank_incident.elapsed_days,days+1.0),"Relógio converte o tempo da partida em dias de interdição")
	paused=true
	state._process(180)
	check(is_equal_approx(state.bank_incident.elapsed_days,days+1.0),"Pausa não avança os dias do evento")
	paused=false
	state.restore_from_save(saved)
	player.global_position=room.entrance.global_position+Vector2(700,80)
	root.get_node("WantedManager").report_crime(1)
	check(event.officers.all(func(officer): return not officer.responding),"Vigilância não reage a crime distante")
	player.global_position=room.entrance.global_position+Vector2(210,100)
	await process_frame
	check(event.officers.all(func(officer): return not officer.responding),"Passar perto sem novo crime não dispara reação")
	var officer_origin: Vector2=event.officers[0].global_position
	root.get_node("WantedManager").report_crime(1)
	await create_timer(.35).timeout
	check(event.officers.all(func(officer): return officer.responding and officer.target==player),"Novo crime perto do banco mobiliza a dupla")
	check(event.officers[0].global_position.distance_to(officer_origin)>5,"Policial caminha para abordar o jogador")
	await capture("04_vigilancia_reage")
	state.advance_bank_days(2.8)
	event._sync()
	check(is_instance_valid(event.patrol) and event.closed,"Vigilância permanece antes do terceiro dia")
	state.advance_bank_days(.3)
	event._sync()
	await process_frame
	check(not is_instance_valid(event.patrol) and event.closed and not room.can_enter(),"Após três dias a viatura sai, mas o banco continua fechado")
	var continued := false
	for officer in get_nodes_in_group("police_officer"):
		if officer.get("responding")==true and officer.target==player: continued=true
	check(continued,"Fim da vigilância não apaga policiais no meio de uma abordagem")
	state.advance_bank_days(1.0)
	event._sync()
	await process_frame
	check(not event.closed and room.can_enter() and room.entrance.enabled,"No quarto dia o banco reabre")
	check(state.bank_incident.is_empty() and room.guards.size()==2 and room.guards.all(func(guard): return not guard.is_dead),"Reabertura repõe a segurança e encerra o evento")
	check(room.civilians.size()==2 and not room.vault_open and room.remaining_loot()==10000,"Atendimento e cofre são restaurados para um novo ciclo")
	await capture("05_reaberto")
	manager._on_exterior_destination_requested(room.entrance,player,&"",null,&"",room,room.spawn_point)
	check(room.actor_inside(),"Depois da reabertura é possível entrar novamente")
	print("BANK_AFTERMATH: ",failures)
	quit(0 if failures.is_empty() else 1)
