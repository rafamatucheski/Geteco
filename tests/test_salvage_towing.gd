extends SceneTree
const JOBS := preload("res://world/shared/salvage/TowJobs.gd")
const LEDGER := preload("res://world/shared/salvage/SalvageLedger.gd")
const OUT := "res://docs/measurements/towing-0910/"
var checks := 0
var failures: Array[String] = []
var world: Node2D
var yard: Node2D
var service: Node
var player: Node2D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	create_timer(210).timeout.connect(func(): push_error("TOW_TIMEOUT"); quit(2))
	var book := LEDGER.new()
	check(JOBS.is_night(.9) and JOBS.is_night(.1) and not JOBS.is_night(.5),"Janela noturna separada do clima")
	for i in 6:
		book.advance(0,i+1)
		var spec := JOBS.next_job(book.data)
		check(spec.stage==i%5+1,"Sequência reinicia depois de cinco entregas")
		spec.merge({"tow_required":true,"tow_loaded":false})
		check(book.accept(spec),"Aceita serviço")
		var token: String = book.data.contract.token
		check(book.settle(token,500)==0 and not book.data.contract.is_empty(),"Não paga encomenda sem usar plataforma")
		book.data.contract.tow_loaded=true
		check(book.settle(token,500)==int(spec.reward),"Paga valor do serviço")
	check(int(book.data.tow_completed)==6,"Progresso persistente da série")
	var restored := LEDGER.new(JSON.parse_string(JSON.stringify(book.data)))
	check(JOBS.next_job(restored.data).stage==2,"JSON mantém etapa seguinte")
	root.size=Vector2i(1280,720)
	var state := root.get_node("CampaignState")
	state.salvage_state.clear()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_delivery_complete"]: state.set_campaign_flag(StringName(flag),true)
	world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	await ready_world()
	check(is_instance_valid(service.truck),"Guincho presente no jogo real")
	var truck: Node2D=service.truck
	truck.ensure_presentation()
	check(not yard.eligible(truck),"Guincho protegido da prensa")
	var q:=PhysicsShapeQueryParameters2D.new()
	q.shape=truck.collision.shape
	q.transform=truck.global_transform
	q.collision_mask=3
	q.exclude=[truck.get_rid()]
	check(truck.get_world_2d().direct_space_state.intersect_shape(q).is_empty(),"Estacionamento do guincho livre de sólidos")
	for i in 5:
		state.salvage_state.tow_completed=i
		var target: Node2D=service.choose_target(JOBS.next_job(state.salvage_state))
		check(is_instance_valid(target),"Alvo real disponível para etapa %d" % (i+1))
		if is_instance_valid(target) and i in [2,4]: check(target.is_police_vehicle,"Encomenda seleciona viatura do estacionamento")
	state.salvage_state.tow_completed=0
	player.global_position=yard.npc.global_position+Vector2(30,0)
	yard.open_panel()
	await shot("01_jobs")
	yard._close_panel()
	service._offer=service.choose_target(JOBS.next_job(state.salvage_state))
	service.accept_job()
	var target: Node2D=yard._target
	check(is_instance_valid(target) and yard.ledger().data.contract.tow_required,"Aceitação cria encomenda de guincho")
	# Espaço livre junto à estrada privada, para testar física sem tráfego ambiente.
	truck.global_position=yard.to_global(Vector2(170,440))
	truck.global_rotation=0
	target.global_position=truck.to_global(Vector2(-115,0))
	target.global_rotation=0
	target.ensure_presentation()
	target.has_theft_alarm=false
	await physics_frame
	var wall:=StaticBody2D.new()
	var col:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=Vector2(6,80)
	col.shape=box
	wall.add_child(col)
	world.add_child(wall)
	wall.global_position=truck.to_global(Vector2(-58,0))
	await physics_frame
	check(not service.attach(target),"Não guincha através de parede")
	wall.queue_free()
	await physics_frame
	await physics_frame
	check(service.attach(target),"Carrega alvo parado pela traseira")
	check(target.has_meta("tow_carried") and not target.visible and target.collision_layer==0,"Carga usa apresentação na plataforma sem colisão duplicada")
	check(is_instance_valid(service.payload) and service.payload.get_parent()==truck.body_model,"Modelo 3D da carga está no caminhão")
	check(yard.navigation_target().distance_to(yard.to_global(yard.dock))<1,"GPS aponta para entrega quando carregado")
	check(not service.attach(target),"Uma carga por vez")
	check(not yard.confirm_delivery(target),"Prensa não recebe carro ainda carregado")
	await create_timer(1.6).timeout
	await shot("02_loaded")
	# Salva a pé: o guincho e a carga também precisam persistir sem veículo conduzido.
	root.get_node("WantedManager").reset()
	var slot: String="qa_tow_%d" % OS.get_process_id()
	check(root.get_node("SaveManager").save_game(slot).get("success",false),"Save real com carga na plataforma")
	var loaded: Dictionary=root.get_node("SaveManager").load_game(slot)
	check(loaded.get("success",false),"Lê save real")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await scene_changed
	world=current_scene
	await ready_world()
	truck=service.truck
	target=service.cargo
	check(is_instance_valid(target),"Carga restaurada após trocar cena")
	check(is_instance_valid(target) and target==yard._target,"Carga restaurada é o alvo da mesma encomenda")
	var count:=0
	for car in get_nodes_in_group("vehicle"):
		if String(car.name)=="NecoTowTruck": count+=1
	check(count==1,"Restaura um único caminhão")
	if not is_instance_valid(target): finish(); return
	truck.enter_vehicle(player)
	while truck.has_meta("vehicle_boarding"): await process_frame
	await physics_frame
	var start: Vector2=truck.global_position
	Input.action_press("move_up")
	await create_timer(.35).timeout
	Input.action_release("move_up")
	check(truck.global_position.distance_to(start)>2,"Guincho conduzido com carga responde ao acelerador")
	check(target.global_position.distance_to(truck.global_position)<15,"Carga acompanha a condução real")
	truck.velocity=Vector2.ZERO
	check(root.get_node("SaveManager").save_game(slot).get("success",false),"Salva dirigindo guincho carregado")
	root.get_node("SaveManager").load_game(slot)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await scene_changed
	world=current_scene
	await ready_world()
	truck=service.truck
	target=service.cargo
	count=0
	for car in get_nodes_in_group("vehicle"):
		if String(car.name)=="NecoTowTruck": count+=1
	check(count==1 and truck.is_driven_by_player and is_instance_valid(target),"Save ao volante restaura um guincho, motorista e carga")
	truck.force_exit_vehicle()
	await create_timer(.8).timeout
	player.set_physics_process(false)
	truck.global_rotation=0
	truck.global_position=yard.to_global(yard.dock)+Vector2(112,0)
	truck.velocity=Vector2.ZERO
	await physics_frame
	check(service.unload(),"Descarrega na baia com consulta de colisão")
	check(target.visible and not target.has_meta("tow_carried") and target.collision_layer!=0,"Descarregar restaura visibilidade e colisão")
	player.global_position=target.global_position+Vector2(-60,0)
	root.get_node("WantedManager").reset()
	var money: int=player.money
	var achievements_before: Array = player.unlocked_achievements.duplicate()
	check(yard.confirm_delivery(target),"Entrega à prensa depois de guinchar")
	check(yard._current_reward==1800,"Serviço contratado preserva recompensa de 1800")
	check(player.money==money,"Não antecipa pagamento")
	while yard.art.animating: await process_frame
	# The first crushed vehicle also unlocks PRIMEIRA SUCATA. Keep the service
	# reward exact while accounting for the independently authored achievement.
	var achievement_bonus := 0
	for achievement_id in player.unlocked_achievements:
		if not achievement_id in achievements_before:
			achievement_bonus += preload("res://AchievementCatalog.gd").cash_reward(achievement_id)
	check(player.money==money+1800+achievement_bonus,"Primeiro serviço paga depois de esmagar, mais somente conquistas novas")
	check(int(yard.ledger().data.get("tow_completed",0))==1,"Entrega avança série")
	# Reação policial depende da hora de carregar, nunca de quando aceitou.
	for time in [.5,.9]:
		var weather:=get_first_node_in_group("day_night_manager")
		world.get_node("CobraCampaign").ledger.data.day_elapsed=fposmod(time-.35,1.0)*600.0
		weather.time_of_day=time
		weather.is_dynamic_time=false
		truck.global_position=yard.to_global(Vector2(170,440))
		truck.global_rotation=0
		var factory=load("res://world/shared/emergency/ModernTrafficFactory.gd")
		var patrol: Node2D=factory.spawn_parked_vehicle(world,"TowPoliceTest",truck.position+Vector2(-115,0),0,"police_cruiser",0)
		patrol.ensure_presentation()
		await physics_frame
		root.get_node("WantedManager").reset()
		check(service.attach(patrol),"Guincha viatura estacionada")
		check(root.get_node("WantedManager").current_stars==(3 if time==.5 else 1),"Alerta policial depende do horário")
		service._discard_cargo()
		await process_frame
	root.get_node("WantedManager").reset()
	finish()

func ready_world() -> void:
	for i in 35: await process_frame
	while not world.gameplay_ready: await process_frame
	yard=get_first_node_in_group("chop_shop")
	service=yard.tow_service
	check(absf(yard.dock.y)<200,"Baia projetada dentro do pátio durante carregamento")
	player=world.get_node("Player")
	player.set_physics_process(false)
	player.is_in_dialogue=false
	if root.get_node("RegionTravel").controlled_car()==null:
		player.is_control_disabled=false
		player.show()
	for i in 8: await process_frame

func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=service.truck.global_position if name=="02_loaded" else yard.global_position
	camera.zoom=Vector2.ONE*(2.8 if name=="02_loaded" else .8)
	camera.make_current()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name+".png"))
	camera.queue_free()

func finish() -> void:
	print("TOW_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
