extends SceneTree
## Directed V1 -> V2 Harbor acceptance route.
## Required: rendered Godot with --no-save --skip-arrival --population=8.
## Fixture teleports only place Dante at distant action starts; the actions use
## production input, physical admission and the live session controller.

const ACTOR := preload("res://scripts/Actor.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SERVICES := preload("res://runtime/Services.gd")

var world: Node3D
var session: Node
var state: RefCounted
var gameplay: Node3D
var failures: Array[String] = []
var checks := 0
var evidence: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail := "") -> bool:
	checks += 1
	evidence.append({"ok":ok,"label":label,"detail":detail})
	print(("ACCEPT PASS " if ok else "ACCEPT FAIL ")+label+((" | "+detail) if detail!="" else ""))
	if not ok:
		failures.append(label)
		push_error(label+((" | "+detail) if detail!="" else ""))
	return ok

func frames(count: int) -> void:
	for _i in count: await physics_frame

func press_key(code: Key, settle := 2) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code; event.physical_keycode=code; event.pressed=pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(settle)

func click_button(button: Button) -> void:
	await frames(2)
	var point:Vector2=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new()
	motion.position=point; motion.global_position=point
	Input.parse_input_event(motion); Input.flush_buffered_events(); await frames(2)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT; event.position=point; event.global_position=point; event.pressed=pressed
		Input.parse_input_event(event); Input.flush_buffered_events(); await frames(2)

func hold(actions: Array[String], count: int) -> void:
	for action in actions: Input.action_press(action)
	await frames(count)
	for action in actions: Input.action_release(action)
	await frames(3)

func wait_until(predicate: Callable, maximum_frames: int, label: String) -> bool:
	for _i in maximum_frames:
		if predicate.call(): return true
		await physics_frame
	check(false,label,"timeout_frames=%d"%maximum_frames)
	return false

func drain_dialogue(limit := 16) -> int:
	var advanced:=0
	while session.dialogue_open and advanced<limit:
		await press_key(KEY_E)
		advanced+=1
	return advanced

func render_signature(label: String) -> Dictionary:
	if DisplayServer.get_name()=="headless":
		check(false,label+": renderizacao real disponivel","display=headless")
		return {}
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_viewport().get_texture().get_image()
	var hash:=2166136261
	var colored:=0
	for y in range(0,image.get_height(),12):
		for x in range(0,image.get_width(),12):
			var color:=image.get_pixel(x,y)
			var packed:=color.to_rgba32()
			hash=int((hash^packed)*16777619)&0x7fffffff
			if color.a>.95 and maxf(color.r,maxf(color.g,color.b))-minf(color.r,minf(color.g,color.b))>.03: colored+=1
	var result:={"label":label,"width":image.get_width(),"height":image.get_height(),"hash":hash,"colored_samples":colored}
	print("ACCEPT RENDER ",JSON.stringify(result))
	check(image.get_width()>=1024 and image.get_height()>=576 and colored>250,label+": quadro renderizado nao vazio",JSON.stringify(result))
	return result

func playing_audio_count(node: Node) -> int:
	var count:=0
	for child in node.find_children("*","AudioStreamPlayer",true,false):
		if child.stream!=null and child.playing: count+=1
	for child in node.find_children("*","AudioStreamPlayer3D",true,false):
		if child.stream!=null and child.playing: count+=1
	return count

func place_player(point: Vector3) -> void:
	world.production.region.set_focus(point)
	world.player.teleport(point+Vector3.UP*.08)
	await frames(4)

func enter_place(id: String) -> bool:
	if id == "harbor_ammunation":
		var facade: Vector3 = PLACES.get_definition(id).exterior_position
		await place_player(facade + Vector3(0, 0, 6.92))
		check(session.nearest().get("id", "") != "enter", "Ammu-Nation sem E na entrada")
		Input.action_press("move_up")
		await frames(20)
		Input.action_release("move_up")
		if not await wait_until(func(): return state.place_id == id and is_instance_valid(session.room), 180, "entrada caminhando: " + id): return false
		return await wait_until(func(): return not session.is_transition_blocked(), 180, "entrada revelada: " + id)
	var point: Vector3
	if id=="maciota": point=world.maciota_place.entry_position
	else:
		var definition:Dictionary=PLACES.get_definition(id)
		if definition.is_empty(): return check(false,"acesso conhecido: "+id)
		point=definition.entry_position
	await place_player(point)
	var offered:Dictionary=session.nearest()
	check(offered.get("id","")=="enter" and offered.get("place","")==id,"entrada fisica oferecida: "+id,str(offered))
	await press_key(KEY_E)
	if not await wait_until(func(): return state.place_id==id and is_instance_valid(session.room),180,"entrada conclui: "+id): return false
	return await wait_until(func(): return not session.is_transition_blocked(),180,"entrada revelada: "+id)

func leave_place(id: String) -> bool:
	if id == "harbor_ammunation":
		await place_player(session.room.exit_position + Vector3(0, 0, -0.53))
		check(session.nearest().get("id", "") != "exit", "Ammu-Nation sem E na saída")
		Input.action_press("move_down")
		await frames(16)
		Input.action_release("move_down")
		if not await wait_until(func(): return state.place_id.is_empty() and not is_instance_valid(session.room), 180, "saída caminhando: " + id): return false
		return await wait_until(func(): return not session.is_transition_blocked(), 180, "saída revelada: " + id)
	await place_player(session.room.exit_position)
	check(session.nearest().get("id","")=="exit","saida fisica oferecida: "+id,str(session.nearest()))
	await press_key(KEY_E)
	if not await wait_until(func(): return state.place_id.is_empty() and not is_instance_valid(session.room),180,"saida conclui: "+id): return false
	return await wait_until(func(): return not session.is_transition_blocked(),180,"saída revelada: "+id)

func interact_at(point: Vector3, expected_id: String) -> bool:
	await place_player(point)
	var offered:Dictionary=session.nearest()
	check(str(offered.get("id",""))==expected_id,"interacao fisica oferecida: "+expected_id,str(offered))
	await press_key(KEY_E)
	await frames(3)
	return str(offered.get("id",""))==expected_id

func find_button(fragment: String) -> Button:
	var root_control: Node = session.storefronts if session.storefronts != null and session.storefronts.is_open() else session.column
	for child in root_control.find_children("*","Button",true,false):
		if fragment.to_lower() in child.text.to_lower(): return child
	return null

func ground(point: Vector3) -> Vector3:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*4.0,point-Vector3.UP*4.0,1)
	var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else point

func clear_line(from: Vector3,to: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(from+Vector3.UP,to+Vector3.UP,1)
	return world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func combat_direction() -> Vector3:
	for candidate in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,Vector3(1,0,1).normalized(),Vector3(-1,0,1).normalized()]:
		var target:=ground(world.player.global_position+candidate*7.0)
		if absf(target.y-world.player.global_position.y)<.4 and clear_line(world.player.global_position,target): return candidate
	return Vector3.RIGHT

func aim_at(target: Vector3) -> void:
	var flat:Vector3=target-world.player.global_position; flat.y=0; flat=flat.normalized()
	var right:Vector3=world.camera.global_basis.x; var down:Vector3=world.camera.global_basis.z
	right.y=0; down.y=0
	root.get_node("GameInput").touch_aim=Vector2(flat.dot(right.normalized()),flat.dot(down.normalized()))
	await frames(3)

func fire_at(target: Vector3) -> void:
	await aim_at(target)
	Input.action_press("fire"); await frames(2); Input.action_release("fire"); await frames(2)

func wait_weapon_ready() -> void:
	await wait_until(func(): return gameplay.cooldown<=0.0 and gameplay.reload_timer<=0.0,300,"arma volta a ficar pronta")

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if not "--no-save" in args or not "--skip-arrival" in args:
		push_error("HARBOR_ACCEPTANCE refuses to run without --no-save --skip-arrival")
		quit(2); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene=world
	if not await wait_until(func(): return world.session!=null and world.session.ready_for_play and world.production.ready_for_play,900,"sessao de producao inicia"):
		quit(1); return
	session=world.session; state=session.state; gameplay=world.gameplay
	check(world.production.no_save,"sessao integrada recusa save pessoal","no_save=%s"%world.production.no_save)
	check(world.player.visible and not world.player.input_locked and world.camera.current,"inicio libera jogador e camera")
	var baseline_render:=await render_signature("inicio jogavel")

	var start:Vector3=world.player.global_position
	Input.action_press("move_right"); await frames(45)
	var walked:float=world.player.global_position.distance_to(start)
	var walk_animation:String=world.player.animation.current_animation if is_instance_valid(world.player.animation) else ""
	var walk_audio:=playing_audio_count(world.player)
	Input.action_release("move_right"); await frames(3)
	check(walked>1.4,"andar responde a entrada real","distance=%.2f"%walked)
	check(walk_animation=="Walking","andar apresenta animacao de caminhada",walk_animation)
	start=world.player.global_position
	Input.action_press("move_right"); Input.action_press("sprint"); await frames(45)
	var ran:float=world.player.global_position.distance_to(start)
	var run_animation:String=world.player.animation.current_animation if is_instance_valid(world.player.animation) else ""
	var run_audio:=playing_audio_count(world.player)
	Input.action_release("move_right"); Input.action_release("sprint"); await frames(3)
	check(ran>walked*1.45,"correr e mais rapido que andar","walk=%.2f run=%.2f"%[walked,ran])
	check(run_animation=="Running","correr apresenta animacao de corrida",run_animation)
	check(maxi(walk_audio,run_audio)>0,"locomocao aciona voz de passos","walk=%d run=%d"%[walk_audio,run_audio])

	if await enter_place("maciota"):
		check(world.camera.locked and not state.weapons_allowed(),"interior trava camera e armas")
		for target in ["maciota","mechanic","part","maciota"]:
			await interact_at(world.maciota_place.interaction_points[target],target)
			check(await drain_dialogue()>0,"dialogo visivel conclui: "+target)
		check(state.intro.stage=="complete","tarefa introdutoria conclui pelas interacoes",state.intro.stage)
		await render_signature("garagem apos tarefa")
		await leave_place("maciota")
	check(not world.camera.locked and state.weapons_allowed(),"saida restaura camera e regras exteriores")

	var car:CharacterBody3D=world.driving.car
	var route:Curve3D=world.production.traffic_routes.route_near(car.position)
	var offset:=route.get_closest_offset(car.position)
	var road:=route.sample_baked(offset,true)
	var road_direction:=route.sample_baked(offset+1.0,true)-road
	car.place(road+Vector3.UP*.12,atan2(-road_direction.x,-road_direction.z))
	for side in [-1.0,1.0]:
		if world.driving.occupied: break
		await place_player(car.to_global(Vector3(side*(car.half_width+.65),.04,.15)))
		var event:=InputEventKey.new(); event.keycode=KEY_F; event.physical_keycode=KEY_F; event.pressed=true
		Input.parse_input_event(event); Input.flush_buffered_events(); await frames(2)
		check(car.has_meta("vehicle_boarding"),"embarque conserva fase de animacao do V1")
		event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); Input.flush_buffered_events(); await frames(2)
	check(world.driving.occupied and car.controlled and not world.player.visible,"entrar no carro por entrada real")
	var car_start:=car.global_position; var wheel_before:float=car.wheel_spin
	Input.action_press("move_up"); await frames(120)
	var driven:=car.global_position.distance_to(car_start)
	var driving_audio:=playing_audio_count(world.production.world_audio)
	Input.action_release("move_up"); await frames(3)
	check(driven>4.0 and absf(car.speed)>1.0,"dirigir desloca o carro","distance=%.2f speed=%.2f"%[driven,car.speed])
	check(absf(car.wheel_spin-wheel_before)>1.0,"rodas apresentam giro durante conducao")
	check(driving_audio>0,"conducao aciona audio no mixer do mundo","playing=%d"%driving_audio)
	await render_signature("conducao")
	await hold(["handbrake"],150)
	check(absf(car.speed)<=.5,"freio para o carro antes do desembarque","speed=%.3f"%car.speed)
	await press_key(KEY_F)
	check(not world.driving.occupied and world.player.visible and world.player.is_physics_processing(),"desembarcar restaura Dante")

	if await enter_place("harbor_ammunation"):
		await interact_at(session.room.interaction_points.service,"service")
		check(session.storefronts.is_open() and session.storefronts.active_kind=="weapons" and session.modal,"loja abre interface especifica de compra")
		var shop_render:=await render_signature("loja de armas")
		check(shop_render.get("hash",0)!=baseline_render.get("hash",-1),"interface muda o quadro renderizado")
		var pistol_button:Button=session.storefronts.ammunation.buy
		check(is_instance_valid(pistol_button) and session.storefronts.ammunation.stock[session.storefronts.ammunation.selection]=="pistol","interface V1 inicia na pistola")
		if is_instance_valid(pistol_button): pistol_button.grab_focus(); await press_key(KEY_ENTER)
		var accepted_by_keyboard:bool=state.owns_weapon("pistol") and state.equipped_weapon=="pistol"
		check(accepted_by_keyboard,"botao focado do modal aceita Enter")
		if not accepted_by_keyboard and is_instance_valid(pistol_button): await click_button(pistol_button)
		check(state.owns_weapon("pistol") and state.equipped_weapon=="pistol","comprar/equipar por interacao de interface atualiza inventario")
		session.close_menu(); await frames(2)
		await leave_place("harbor_ammunation")

	var direction:=combat_direction()
	var civilian:=ACTOR.new(); civilian.identity=2; world.add_child(civilian)
	civilian.global_position=ground(world.player.global_position+direction*6.0)
	var witness:CharacterBody3D=world.people[0] if not world.people.is_empty() else null
	if is_instance_valid(witness):
		var side:=Vector3(-direction.z,0,direction.x)
		witness.teleport(ground(world.player.global_position+side*4.0))
		witness.controlled_automatically=false
	await frames(5); await aim_at(civilian.global_position)
	Input.action_press("aim"); await frames(8)
	var target_flat:Vector3=civilian.global_position-world.player.global_position; target_flat.y=0
	var gun_flat:Vector3=-gameplay.gun.global_basis.z; gun_flat.y=0
	check(gameplay.aiming and gameplay.aim_active and gameplay.gun.visible,"mira real mostra arma e entra no estado de mira")
	check(gun_flat.normalized().dot(target_flat.normalized())>.97,"arma apresentada aponta para o alvo","dot=%.3f"%gun_flat.normalized().dot(target_flat.normalized()))
	await render_signature("mira armada"); Input.action_release("aim")
	var health_before:float=civilian.health; var ammo_before:Dictionary=state.get_ammo("pistol"); var crime_before:int=gameplay.crime_points
	await fire_at(civilian.global_position)
	check(civilian.health<health_before,"disparo real fere civil","%.1f -> %.1f"%[health_before,civilian.health])
	check(int(state.get_ammo("pistol").magazine)==int(ammo_before.magazine)-1,"disparo consome uma municao")
	check(gameplay.crime_points>crime_before,"ferir civil registra crime","%d -> %d"%[crime_before,gameplay.crime_points])
	check(absf(civilian.visual.rotation.x)>.02,"civil apresenta reacao ao ferimento","rotation_x=%.3f"%civilian.visual.rotation.x)
	check(is_instance_valid(witness) and witness.controlled_automatically and witness.speed>=5.0,"testemunha proxima entra em fuga como no V1","director=%s speed=%s"%[witness.controlled_automatically if is_instance_valid(witness) else false,witness.speed if is_instance_valid(witness) else -1])
	check(playing_audio_count(gameplay)>0,"disparo aciona voz de audio","playing=%d"%playing_audio_count(gameplay))
	await render_signature("reacao civil ao tiro")
	await press_key(KEY_R)
	check(gameplay.reload_timer>0.0,"recarga inicia pela tecla real","timer=%.3f"%gameplay.reload_timer)
	check(is_instance_valid(gameplay.get("_reload_audio")) and gameplay.get("_reload_audio").stream!=null and gameplay.get("_reload_audio").playing,"recarga aciona amostra de audio")
	await wait_weapon_ready()
	check(int(state.get_ammo("pistol").magazine)==int(ammo_before.magazine),"recarga repoe o pente")
	var shot_guard:=0
	while not civilian.dead and shot_guard<12:
		await wait_weapon_ready(); await fire_at(civilian.global_position); shot_guard+=1
	check(civilian.dead,"sequencia de disparos produz morte civil","additional_shots=%d"%shot_guard)
	await frames(20)
	check(absf(civilian.visual.rotation.z-PI/2.0)<.05 and civilian.collision_layer==0,"morte apresenta queda e remove colisao")
	check(gameplay.stars>=1,"crime escala para procurado","stars=%d crime=%d"%[gameplay.stars,gameplay.crime_points])
	if is_instance_valid(world.dispatch):
		await wait_until(func(): return not world.dispatch.events_named("dispatched").is_empty() or int(world.dispatch.status().police)>0,900,"policia responde ao crime")
		var dispatched_events:Array=world.dispatch.events_named("dispatched")
		check(not dispatched_events.is_empty() or int(world.dispatch.status().police)>0,"resposta policial materializada","dispatches=%d status=%s"%[dispatched_events.size(),JSON.stringify(world.dispatch.status())])
	else: check(false,"despacho policial integrado existe")

	state.economy.grant_reward("acceptance_service_funds",250)
	var balance_before_service:int=state.economy.balance
	car.repair(); car.health=maxf(1.0,car.max_health-60.0)
	car.place(SERVICES.AUTO_ORIGIN+Vector3(0,.12,-131.0/16.0),0.0)
	await place_player(car.to_global(Vector3(car.half_width+.65,.04,.15))); await press_key(KEY_F)
	check(world.driving.occupied,"entrar no carro para o servico")
	var serviced_before:int=session.services.serviced_count
	await wait_until(func(): return session.services.serviced_count>serviced_before,480,"Northgate conclui servico")
	check(state.economy.balance==balance_before_service-100,"servico cobra R$ 100 uma vez","%d -> %d"%[balance_before_service,state.economy.balance])
	check(is_equal_approx(car.health,car.max_health),"servico entrega reparo")
	check(gameplay.stars==0,"servico limpa procurado como no V1")
	check(session.notice_time>0.0 and "reparado" in session.notice.text.to_lower(),"HUD comunica resultado do servico",session.notice.text)
	await render_signature("resultado Northgate")
	await hold(["handbrake"],5); await press_key(KEY_F)
	check(not world.driving.occupied,"sair do carro depois do servico")

	await press_key(KEY_J)
	check(session.panel.visible,"diario de missoes abre por entrada real")
	var mission_button:=find_button("Primeiro Giro")
	check(is_instance_valid(mission_button),"diario oferece Primeiro Giro")
	if is_instance_valid(mission_button): await click_button(mission_button)
	await drain_dialogue(12)
	check(state.campaign.active_id=="primeiro_giro" and state.campaign.step==0,"missao inicia com objetivo")
	check("Banco" in session.objective.text or "North Pier" in session.objective.text,"HUD apresenta objetivo da missao",session.objective.text)
	if state.equipped_weapon!="fists": await press_key(KEY_X)
	check(state.equipped_weapon=="fists","arma guardada antes do banco")
	if await enter_place("harbor_bank"):
		await interact_at(session.room.interaction_points.service,"service")
		check(await drain_dialogue(12)>0,"dialogo de Helena aparece")
		check(state.campaign.step==1,"comprovante avanca objetivo")
		await leave_place("harbor_bank")
	await interact_at(session.mission_world.targets.harbor_parcel,"mission")
	check(await drain_dialogue(8)>0,"coleta da encomenda apresenta feedback")
	check(state.campaign.step==2,"encomenda avanca objetivo")
	var reward_before:int=state.economy.balance
	if await enter_place("maciota"):
		await interact_at(world.maciota_place.interaction_points.maciota,"maciota")
		check(await drain_dialogue(12)>0,"entrega final apresenta dialogo")
		check(state.campaign.active_id.is_empty() and state.campaign.snapshot().completed.has("primeiro_giro"),"missao conclui")
		check(state.economy.balance==reward_before+150,"recompensa de R$ 150 e entregue uma vez","%d -> %d"%[reward_before,state.economy.balance])
		await render_signature("missao concluida"); await leave_place("maciota")

	var death_position:Vector3=world.player.global_position; var balance_before_death:int=state.economy.balance
	world.player.receive_damage(500.0); await frames(3)
	check(gameplay.health==0.0 and session.rescue_pending and session.panel.visible,"morte abre resgate e bloqueia controle")
	await render_signature("tela de resgate")
	var rescue_button:=find_button("Continuar")
	check(is_instance_valid(rescue_button),"resgate oferece acao Continuar")
	if is_instance_valid(rescue_button): await click_button(rescue_button)
	await wait_until(func(): return not session.rescue_pending and not session.respawn_busy,240,"resgate conclui")
	check(gameplay.health==100.0 and world.player.visible and not world.player.input_locked,"resgate restaura vida e controle")
	check(world.player.global_position.distance_to(death_position)>2.0 and state.place_id.is_empty(),"resgate retorna ao ponto seguro exterior")
	check(state.economy.balance==balance_before_death,"resgate V2 nao altera saldo","%d -> %d"%[balance_before_death,state.economy.balance])
	check(world.camera.target==world.player and not world.camera.locked,"resgate restaura camera")
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(state.snapshot()),"estado posterior ao resgate permanece publicavel pelo SaveStore")

	print("HARBOR_ACCEPTANCE_EVIDENCE ",JSON.stringify(evidence))
	print("HARBOR_GAMEPLAY_ACCEPTANCE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	world.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
