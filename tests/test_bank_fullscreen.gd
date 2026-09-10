extends SceneTree
const OUTPUT := "res://docs/measurements/bank-fullscreen-0910/"
var failures: Array[String] = []
var room: Node2D
var player: CharacterBody2D
var camera: Camera2D

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func settle() -> void:
	for i in 35: await physics_frame
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")
func check_frame(label: String) -> void:
	var bounds: Rect2=room.get_gameplay_camera_bounds()
	var visible_size:=camera.get_viewport_rect().size/camera.zoom
	var visible_rect:=Rect2(camera.global_position-visible_size*.5,visible_size)
	check(bounds.grow(.1).encloses(visible_rect),label+": cenário cobre o quadro inteiro")
	check(visible_rect.grow(-10).has_point(player.global_position),label+": personagem permanece visível")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var cached: Image=room.view.get_texture().get_image()
		var covered:=0
		for uv in [Vector2(.01,.01),Vector2(.99,.01),Vector2(.01,.99),Vector2(.99,.99)]:
			var world_point: Vector2=visible_rect.position+visible_size*uv
			var texel: Vector2=room.room_display.to_local(world_point)+Vector2(room.view.size)*.5
			if cached.get_pixelv(Vector2i(texel)).a>.95: covered+=1
		check(covered==4,label+": quatro cantos têm arquitetura renderizada, sem moldura preta")

func _run() -> void:
	create_timer(100).timeout.connect(func(): printerr("BANK_FULLSCREEN TIMEOUT"); quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1280,720)
	# Expande o viewport lógico para exercitar proporções reais; o padrão do
	# projeto usa letterbox 16:9 mesmo quando a janela é redimensionada.
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	var state=root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_arrival_call_complete",true)
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	var manager=world.get_node("Interiors")
	while not manager.has_node("InteriorSpaces/BankInterior"): await process_frame
	room=manager.get_node("InteriorSpaces/BankInterior")
	player=world.get_node("Player")
	camera=player.get_node("Camera")
	player.active_weapon_id="fists"
	manager._on_exterior_destination_requested(room.entrance,player,&"",null,&"",room,room.spawn_point)
	await settle()
	check(room.status.text.is_empty(),"Atendimento normal sem texto de orientação")
	check(room.civilians[0].model.appearance_female and not room.civilians[1].model.appearance_female,"Uma atendente mulher e um atendente homem")
	check(room.civilians[0].model.limbs.size()==4 and room.civilians[1].model.limbs.size()==4,"Corpos completos com articulações preservadas")
	await check_frame("Entrada 16:9")
	await capture("01_entrada_fullscreen")
	var entry_center:=camera.global_position
	Input.action_press("move_up")
	for i in 100:
		await physics_frame
		if player.global_position.y<room.global_position.y-40: break
	Input.action_release("move_up")
	await settle()
	check(camera.global_position.y<entry_center.y-25,"Câmera percorre o salão com o movimento real do personagem")
	await check_frame("Atendimento 16:9")
	await capture("02_atendimento_fullscreen")
	player.active_weapon_id="pistol"
	await settle()
	check(not room.status.text.is_empty() and room.status.get_viewport_rect().encloses(room.status.get_global_rect()),"Advertência permanece legível e dentro da tela com a câmera em movimento")
	player.active_weapon_id="fists"
	for size in [Vector2i(1024,768),Vector2i(1920,810)]:
		root.size=size
		await settle()
		print("BANK_VIEWPORT window=",root.size," logical=",camera.get_viewport_rect().size)
		await check_frame("Janela %s"%str(size))
		await capture("03_formato_%dx%d"%[size.x,size.y])
	root.size=Vector2i(1280,720)
	await settle()
	# Simula o contrato usado ao restaurar um save já dentro do banco.
	camera.remove_meta("compact_interior")
	camera.remove_meta("interior_follow_bounds")
	player.remove_meta("interior_camera_overview")
	manager._frame_interior_camera(player,room.get_camera_rect())
	check(camera.has_meta("interior_follow_bounds"),"Restauração do interior recupera câmera fullscreen")
	var clerk=room.civilians[1]
	check(clerk.model.limbs[0].is_visible_in_tree(),"Pernas presentes no atendimento")
	clerk.global_position=room.to_global(room.project_floor(Vector2(2.3,.5)))
	await settle()
	check(clerk.model.limbs[2].is_visible_in_tree(),"Pernas presentes ao caminhar")
	await capture("04_atendente_corpo_inteiro")
	manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",room.entrance.destination_id)
	await settle()
	check(not camera.has_meta("interior_follow_bounds") and not camera.has_meta("compact_interior"),"Saída remove enquadramento interno e devolve câmera externa")
	check(not room.status.visible,"Mensagens do banco não permanecem sobre a rua")
	print("BANK_FULLSCREEN: ",failures)
	quit(0 if failures.is_empty() else 1)
