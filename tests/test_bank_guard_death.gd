extends SceneTree
const OUTPUT := "res://docs/measurements/bank-death-0910/"
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")

func _run() -> void:
	create_timer(65).timeout.connect(func(): printerr("BANK_DEATH TIMEOUT"); quit(2))
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var state=root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_arrival_call_complete",true)
	var world: Node2D
	var room: Node2D
	var player: CharacterBody2D
	if OS.get_cmdline_user_args().has("--isolated"):
		world=Node2D.new()
		root.add_child(world)
		current_scene=world
		player=load("res://Player.gd").new()
		var camera := Camera2D.new()
		camera.name="Camera"
		player.add_child(camera)
		world.add_child(player)
		room=load("res://world/harbor/interiors/RobberyRoom3D.gd").new()
		room.entrance=Node2D.new()
		world.add_child(room.entrance)
		world.add_child(room)
		room.set_npc_rendering_active(true)
		player.global_position=room.spawn_point.global_position
		room.on_actor_entered(player)
		camera.set_process(false)
		camera.set_physics_process(false)
		camera.zoom=Vector2.ONE*2.35
		room._sync_actor_scale()
	else:
		world=load("res://world/harbor/HarborGame.tscn").instantiate()
		root.add_child(world)
		current_scene=world
		while not world.gameplay_ready: await process_frame
		var manager=world.get_node("Interiors")
		while not manager.has_node("InteriorSpaces/BankInterior"): await process_frame
		room=manager.get_node("InteriorSpaces/BankInterior")
		player=world.get_node("Player")
		manager._on_exterior_destination_requested(room.entrance,player,&"",null,&"",room,room.spawn_point)
	player.active_weapon_id="fists"
	player.set_physics_process(false)
	await create_timer(.6).timeout
	room.set_process(false)
	for civilian in room.civilians: civilian.set_physics_process(false)
	for guard in room.guards:
		guard.take_damage(1,false)
		check(guard.get_node("NPCCombatRig").current_gun_mesh.visible,"Guarda vivo continua segurando sua arma")
		guard.take_damage(1000,true)
		guard.take_damage(1000,true)
		guard._drop_loot()
		check(not guard.get_node("NPCCombatRig").current_gun_mesh.visible,"Arma sai da mão ao morrer")
		check(not guard.muzzle_flash_3d.visible,"Corpo não mantém clarão de disparo")
		check(guard.eyes.size()==2 and guard.eyes.all(func(eye): return eye.mesh.size.y<.008 and eye.mesh.size.x>.045),"Olhos fechados viram dois traços")
	await create_timer(1.7).timeout
	var pickups=get_nodes_in_group("bank_guard_weapon")
	check(pickups.size()==2,"Cada guarda solta exatamente uma arma, sem duplicar em dano repetido")
	check(pickups.any(func(item): return item.weapon_id==&"pistol") and pickups.any(func(item): return item.weapon_id==&"shotgun"),"Pistola e escopeta correspondem às armas dos guardas")
	var pools=get_nodes_in_group("bank_guard_blood")
	check(pools.size()==2 and pools.all(func(pool): return pool.scale.x>1.0),"Poças maiores terminam de se espalhar sob os corpos")
	check(pools.all(func(pool): return pool.z_index<room.guards[0].z_index),"Sangue fica no chão, abaixo dos corpos")
	player.global_position=room.to_global(room.project_floor(Vector2(0,-.6)))
	await capture("01_guardas_desarmados")
	if DisplayServer.get_name()!="headless":
		for i in room.guards.size(): room.guards[i].viewport_3d.get_texture().get_image().save_png(OUTPUT+"rosto_guarda%d.png"%i)
	for pickup in pickups:
		var id: String=pickup.weapon_id
		var before: int=player.weapon_ammo.get(id,{}).get("reserve",0)
		var expected: int=pickup.ammo_amount
		player.global_position=pickup.global_position
		await create_timer(.12).timeout
		check(not pickup._consumed and player.weapon_ammo.get(id,{}).get("reserve",0)==before,"Pode passar pela arma sem pegar: "+id)
		check(pickup._prompt_label.visible,"E aparece ao chegar perto: "+id)
		await capture("02_escolha_"+id)
		var event := InputEventAction.new()
		event.action="interact"
		event.pressed=true
		Input.parse_input_event(event)
		await process_frame
		await process_frame
		event=InputEventAction.new()
		event.action="interact"
		Input.parse_input_event(event)
		check(pickup._consumed and player.weapon_ammo[id].reserve==before+expected,"E recolhe arma e munição: "+id)
		pickup._take(player)
		check(player.weapon_ammo[id].reserve==before+expected,"Coleta repetida não duplica munição: "+id)
		await create_timer(.3).timeout
	check(get_nodes_in_group("bank_guard_weapon").is_empty(),"Armas recolhidas somem do chão")
	# Atropelamento usa outro caminho de morte no ator base.
	var extra=load("res://world/harbor/events/BankGuard.gd").new()
	extra.room=room
	room.add_child(extra)
	extra.global_position=room.to_global(room.project_floor(Vector2(0,1)))
	extra.get_run_over(Vector2(80,0),false)
	await process_frame
	await process_frame
	check(extra.death_presented and not extra.get_node("NPCCombatRig").current_gun_mesh.visible and get_nodes_in_group("bank_guard_weapon").size()==1,"Outro caminho de morte também solta a arma uma única vez")
	print("BANK_DEATH: ",failures)
	quit(0 if failures.is_empty() else 1)
