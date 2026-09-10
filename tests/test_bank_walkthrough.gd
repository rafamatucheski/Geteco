extends SceneTree
## Exercita a porta com movimento e colisão reais, sem chamar o teleporte.
const OUTPUT := "res://docs/measurements/bank-passage-0910/"
var failures: Array[String] = []
var entries := 0
var exits := 0
var peak_fade := 0.0
var manager: Node
var player: CharacterBody2D
var room: Node2D

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		peak_fade=maxf(peak_fade,manager._fade.color.a)

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")

func walk(action: String, until: Callable, maximum := 180) -> bool:
	Input.action_press(action)
	for i in maximum:
		await frames(1)
		if until.call(): break
	Input.action_release(action)
	return until.call()

func _run() -> void:
	create_timer(100).timeout.connect(func(): printerr("BANK_WALK TIMEOUT"); quit(2))
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var campaign=root.get_node("CampaignState")
	campaign.set_campaign_flag(&"harbor_arrival_seen",true)
	campaign.set_campaign_flag(&"harbor_arrival_call_complete",true)
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	manager=world.get_node("Interiors")
	while not manager.has_node("InteriorSpaces/BankInterior"): await process_frame
	room=manager.get_node("InteriorSpaces/BankInterior")
	player=world.get_node("Player")
	manager.actor_entered_interior.connect(func(_actor,_id): entries+=1)
	manager.actor_returned_to_exterior.connect(func(_actor,_id): exits+=1)
	player.active_weapon_id="fists"
	player.global_position=room.entrance.to_global(Vector2(0,65))
	player.reset_physics_interpolation()
	await frames(80)
	check(entries==0 and peak_fade==0,"Proximidade abre a porta sem fade e sem entrar")
	check(room.entrance.open_amount>.95,"Folhas abertas ao se aproximar")
	await capture("01_aproximacao")
	await walk("move_up",func(): return room.entrance.to_local(player.global_position).y<22,90)
	await frames(65)
	check(entries==0 and peak_fade==0,"Parado diante da soleira continua no exterior, sem piscar")
	# Varrida lateral perto da porta não pode ser confundida com passagem.
	await walk("move_right",func(): return room.entrance.to_local(player.global_position).x>52,90)
	await walk("move_left",func(): return room.entrance.to_local(player.global_position).x<1,90)
	await frames(10)
	check(entries==0 and peak_fade==0,"Passar ao lado da entrada não troca de ambiente")
	for cycle in 3:
		check(await walk("move_up",func(): return entries==cycle+1),"Atravessar a porta andando entra no banco, ciclo %d"%cycle)
		await frames(55)
		check(room.actor_inside() and exits==cycle,"Spawn interno não aciona saída involuntária")
		check(manager._fade.color.a<.01 and not manager.is_transitioning(),"Cortina termina e libera o salão")
		check(player.get_node("Camera").has_meta("compact_interior"),"Enquadramento interno acompanha a entrada física")
		if cycle==0:
			if DisplayServer.get_name()!="headless":
				var cached: Image=room.view.get_texture().get_image()
				var readable:=0
				for point in [Vector2(-2,2),Vector2(2,2),Vector2(-2,3.5),Vector2(2,3.5)]:
					var pixel: Vector2=room.room_camera.unproject_position(Vector3(point.x,0,point.y))
					if cached.get_pixelv(Vector2i(pixel)).a>.9: readable+=1
				check(readable==4,"Piso renderizado coincide com projeção física, sem vista frontal congelada")
			await capture("02_salao")
			# Percurso lateral e volta ao centro usam o mesmo player da partida.
			var start_x:=player.global_position.x
			check(await walk("move_right",func(): return player.global_position.x>start_x+90),"Circulação no salão entre passadeira e banco de espera")
			await walk("move_left",func(): return player.global_position.x<start_x,120)
		check(await walk("move_down",func(): return exits==cycle+1),"Chegar à saída andando retorna à rua, ciclo %d"%cycle)
		await frames(85)
		check(not room.actor_inside() and entries==cycle+1,"Retorno à calçada não reentra sozinho")
		check(not player.has_meta("harbor_interior") and not player.get_node("Camera").has_meta("compact_interior"),"Saída restaura estado e câmera externa")
		check(player.sprite_3d_display.scale.x<1.0,"Escala do personagem restaurada no exterior")
	await capture("03_retorno")
	check(await walk("move_up",func(): return entries==4),"Entrada para testar reversão rápida")
	check(await walk("move_down",func(): return exits==4),"Voltar imediatamente à saída funciona durante cooldown")
	check(await walk("move_up",func(): return entries==5),"Reentrar imediatamente não perde a passagem durante cooldown")
	check(await walk("move_down",func(): return exits==5),"Segunda reversão rápida retorna corretamente à rua")
	await frames(70)
	check(peak_fade>.9,"Passagens confirmadas usam a cortina de transição")
	# A interação explícita continua utilizável nas outras portas.
	var fuel=manager.get_node("InteriorSpaces/FuelInterior")
	player.global_position=fuel.entrance.to_global(Vector2(0,42))
	player.reset_physics_interpolation()
	await frames(60)
	peak_fade=0
	await frames(30)
	check(peak_fade==0,"Porta do posto também abre por proximidade sem fade falso")
	check(fuel.entrance.request_interaction(player),"Interação explícita aceita ator no sensor do posto")
	await frames(70)
	check(fuel.actor_inside() and manager._fade.color.a<.01,"Interação com porta já aberta transfere e encerra a cortina")
	print("BANK_WALK: ",failures)
	quit(0 if failures.is_empty() else 1)
