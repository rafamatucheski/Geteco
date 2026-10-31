extends SceneTree
## Integração depois da corrida do líder vencida. O prefixo consistente é uma fixture;
## este teste valida o acesso real à casa, a lista, a recompensa, o save e a garagem.
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
const STORY := preload("res://systems/campaign/HarborStory.gd")
const JESSICA := preload("res://systems/campaign/JessicaProgress.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String] = []
var checks := 0
var world
var review_dir := ""
var depth_report: Array[Dictionary] = []

func capture_frame(label: String) -> void:
	if review_dir.is_empty() or DisplayServer.get_name() == "headless": return
	Engine.max_fps = 60
	# Os fades de transição usam tempo de parede; oito quadros a uma taxa sem limite ainda
	# podem capturar uma sobreposição preta de admissão em vez da sala real.
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(review_dir.path_join(label+".png"))

func depth_pixels(actor: CharacterBody3D, image: Image) -> int:
	# A cor de diagnóstico identifica só este ator. Amostrar o framebuffer
	# inteiro evita misturar coordenadas lógicas de projeção da UI com as coordenadas
	# da imagem escalada (a primeira sonda viu um ator visível fora da ROI dele).
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var count := 0
	for index in range(0,pixels.size(),4):
		if pixels[index]>115 and pixels[index+2]>115 and pixels[index+1]<76: count += 1
	return count

func verify_depth(actor: CharacterBody3D, room: Node3D, object_id: String, role_id: String) -> void:
	Engine.max_fps = 60
	var previous_mode: int = actor.process_mode
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.reset_physics_interpolation()
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var materials: Array = []
	for mesh in actor.visual.find_children("*","MeshInstance3D",true,false):
		materials.append([mesh,mesh.material_override])
		mesh.material_override = diagnostic
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var actual := root.get_texture().get_image()
	var props: Array = []
	for mesh in room.model.find_children("*","MeshInstance3D",true,false):
		if (object_id=="desk" and str(mesh.name).begins_with("Desk")) or (object_id=="sofa" and (str(mesh.name).begins_with("Sofa") or str(mesh.name).begins_with("Cushion"))):
			props.append([mesh,mesh.visible])
			mesh.hide()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var control := root.get_texture().get_image()
	var actual_pixels := depth_pixels(actor,actual)
	var control_pixels := depth_pixels(actor,control)
	depth_report.append({"role":role_id,"object":object_id,"occluded_pixels":actual_pixels,"unobstructed_pixels":control_pixels})
	print("TAKESHI_DEPTH ",role_id," ",object_id," visible=",actual_pixels," control=",control_pixels)
	check(control_pixels>100,role_id+" "+object_id+" has a positive visible pixel control")
	check(actual_pixels>100 and actual_pixels<control_pixels-10,role_id+" "+object_id+" hides the lower body while preserving the visible upper body")
	actual.save_png(review_dir.path_join("takeshi-mask-"+role_id+"-"+object_id+".png"))
	control.save_png(review_dir.path_join("takeshi-control-"+role_id+"-"+object_id+".png"))
	for prop in props: prop[0].visible = prop[1]
	for material in materials: material[0].material_override = material[1]
	actor.process_mode = previous_mode

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func settle(count := 4) -> void:
	for i in count: await physics_frame

func finish_dialogue(session) -> String:
	var spoken: Array[String] = []
	var count := 0
	while session.dialogue_open and count < 40:
		# A FullSession apresenta as falas no DialogueCard compartilhado; a
		# coluna do menu de serviço continua escondida e não contém mais este texto.
		if is_instance_valid(session.dialogue_card): spoken.append(session.dialogue_card.message.text)
		count += 1
		session._advance_dialogue()
	return "\n".join(spoken)

func install_post_race_prefix(session) -> bool:
	var value: Dictionary = session.state.campaign.snapshot()
	value.completed = MISSIONS.ORDER.slice(0,MISSIONS.ORDER.find("cobra_finale"))
	value.claimed_rewards = value.completed.duplicate()
	value.flags = {}
	value.active_id = "cobra_finale"
	value.step = 6
	value.pending_rewards = {}
	value.race_elapsed = 0.0
	value.race_outside = 0.0
	value.race_run = {}
	value.failure = ""
	for id in value.completed:
		for flag in MISSIONS.MISSIONS[id].sets_flags: value.flags[flag] = true
		session.state.economy.grant_reward("campaign:"+str(id),int(MISSIONS.MISSIONS[id].reward))
	if not CAMPAIGN.validate_snapshot(value) or not session.state.campaign.restore_snapshot(value): return false
	# Recibo/estado anterior do banco correspondentes mantêm válido o prefixo concluído da Jessica.
	var bank: Dictionary = session.robberies.snapshot()
	bank.bank_cash0 = true
	bank.bank_alarm = true
	bank.bank_dispatched = true
	bank.vault_open = true
	bank.keycard_available = true
	bank.keycard_taken = true
	bank.guards[0] = 0.0
	if not session.robberies.restore_snapshot(bank): return false
	var jessica := JESSICA.fresh_snapshot()
	jessica.met = true
	jessica.bank_complete = true
	jessica.bank_phase = "complete"
	jessica.bank_cycle = int(bank.bank_cycle)
	jessica.haul_mask = 1
	jessica.haul_receipt = "bank_haul:%d:1" % int(bank.bank_cycle)
	jessica.conversations = ["first_meeting","bank_debrief"]
	if not JESSICA.validate_snapshot(jessica): return false
	session.state.world_state.jessica = jessica
	session.state.economy.grant_reward(jessica.haul_receipt,5000)
	session.state.intro.set_location("harbor_garage")
	session.state.intro.complete_meeting()
	STORY.mark_opening(session.state.world_state)
	STORY.mark_maciota(session.state.world_state)
	return true

func sweep(actor: CharacterBody3D, room: Node3D, start: Vector3, direction: Vector3) -> Dictionary:
	actor.set_physics_process(false)
	actor.global_position = room.to_global(start+Vector3.UP*.08)
	actor.velocity = Vector3.ZERO
	await settle(2)
	var began: Vector3 = actor.global_position
	var obstacle_hit := false
	for i in 45:
		await physics_frame
		actor.velocity = direction.normalized()*8.0
		actor.velocity.y = -1.0
		actor.move_and_slide()
		for collision_index in actor.get_slide_collision_count():
			var collider = actor.get_slide_collision(collision_index).get_collider()
			if collider is StaticBody3D and collider.name != "Floor": obstacle_hit = true
	actor.velocity = Vector3.ZERO
	return {"point":room.to_local(actor.global_position),"distance":Vector2(actor.global_position.x-began.x,actor.global_position.z-began.z).length(),"obstacle_hit":obstacle_hit}

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--story-review-dir="): review_dir = argument.trim_prefix("--story-review-dir=")
	var catalog = preload("res://world/places/PlaceCatalog.gd")
	var hidden_accesses := 0
	for definition in catalog.definitions():
		if definition.get("hidden_access",false): hidden_accesses += 1
	print("STORY_CATALOG accesses=",catalog.access_points().size()+hidden_accesses+1," interiors=",catalog.definitions().size()+1," (+18 existing port containers separately)")
	root.get_node("V2Launch").selected_path = "user://cobra-house-main-isolated.json"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Leader house: Main did not finish startup"); world.free(); quit(1); return
	check(world.production.no_save,"fixture never writes a user journey")
	if not world.production.no_save: world.free(); quit(1); return
	if not review_dir.is_empty():
		world.session.set_process_input(false)
		world.camera.set_process_unhandled_input(false)
		world.driving.set_process_unhandled_input(false)
		world.player.controlled_automatically = true
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("pt_BR")
	var session = world.session
	session.arrival.active = false
	check(not await session.enter_place("cobra_leader_house",false),"house access is denied before the leader race is won")
	check(install_post_race_prefix(session),"post-victory campaign, wallet, Jessica and Maciota prefix is consistent")
	if not failures.is_empty(): world.free(); quit(1); return
	var definition: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("cobra_leader_house")
	world.player.set_physics_process(false)
	world.player.teleport(definition.entry_position+Vector3.UP*.08)
	world.production.region.set_focus(world.player.global_position)
	deadline = Time.get_ticks_msec()+20000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	await settle()
	check(session.position_clear(world.player.global_position),"authored house street entrance admits the full player capsule")
	check(session.mission_world.nearest_action().get("target","") != "leader_house","physical entrance has no explicit post-race entry action")
	world.player.set_physics_process(true)
	world.player.controlled_automatically = true
	world.player.automatic_direction = session.weapon_shop_entrance._inward("cobra_leader_house")
	deadline = Time.get_ticks_msec()+15000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if session.state.place_id == "cobra_leader_house" and session.state.campaign.step == 7: break
	world.player.automatic_direction = Vector3.ZERO
	check(session.state.place_id == "cobra_leader_house" and session.state.campaign.step == 7,"entering the real room advances to the list")
	if session.state.place_id != "cobra_leader_house": world.free(); quit(1); return
	var room: Node3D = session.room
	check(session.position_clear(world.player.global_position),"house spawn admits the full player capsule")
	await capture_frame("takeshi-room-entry")
	var npc := preload("res://scripts/Actor.gd").new()
	npc.controlled_automatically = true
	npc.position = room.to_global(Vector3(-3.2,.08,2.8))
	world.add_child(npc)
	npc.set_physics_process(false)
	world.player.set_physics_process(false)
	for actor: CharacterBody3D in [world.player,npc]:
		var other: CharacterBody3D = npc if actor == world.player else world.player
		other.global_position = room.to_global(Vector3(-3.2,.08,2.8))
		var role := "player" if actor == world.player else "real NPC"
		var result := await sweep(actor,room,Vector3(2.4,0,-.25),Vector3(0,0,-1))
		check(result.obstacle_hit and result.distance>.1 and result.point.z>=-.82,role+" is blocked by the whole desk footprint")
		check(result.point.y<.14,role+" stays on the floor instead of climbing onto the desk")
		result = await sweep(actor,room,Vector3(4.2,0,-.25),Vector3(-1,0,-1))
		check(result.obstacle_hit and not Rect2(1.15,-2.4,2.5,1.3).grow(.26).has_point(Vector2(result.point.x,result.point.z)),role+" cannot cut through the desk corner")
		result = await sweep(actor,room,Vector3(-3.6,0,-3),Vector3(0,0,-1))
		check(result.obstacle_hit and result.distance>.1 and result.point.z>=-3.95,role+" is blocked by the rear wall")
		result = await sweep(actor,room,Vector3(4.9,0,1.5),Vector3(1,0,0))
		check(result.obstacle_hit and result.distance>.1 and result.point.x<=5.45,role+" is blocked by the side wall")
		result = await sweep(actor,room,Vector3(0,0,3),Vector3(0,0,-1))
		check(result.distance>1.5,role+" can move through the free room corridor")
		if not review_dir.is_empty() and DisplayServer.get_name() != "headless":
			var role_id := "player" if actor == world.player else "npc"
			# Em z=-3.35 a câmera de cima vê por sobre a ponta baixa do sofá.
			# Esta posição mais próxima, ainda livre para a cápsula, de fato põe os pés
			# atrás da silhueta do assento; o mesmo controle positivo é mantido.
			for pose in [["desk",Vector3(2.4,.08,-3.0)],["sofa",Vector3(-4.85,.08,-3.15)]]:
				var point: Vector3 = room.to_global(pose[1])
				check(session.position_clear(point),role+" depth capture uses supported unoccupied ground")
				actor.global_position = point
				actor.velocity = Vector3.ZERO
				actor.reset_physics_interpolation()
				await capture_frame("takeshi-depth-"+role_id+"-"+str(pose[0]))
				await verify_depth(actor,room,str(pose[0]),role_id)
			actor.global_position = room.to_global(Vector3(0,.08,2.8))
	npc.free()
	world.player.set_physics_process(false)
	var list_point: Vector3 = session.mission_world.target_position()
	check(session.position_clear(list_point),"list interaction stands in front of the table")
	check(await session.arrival._walk(world.player,list_point),"real player reaches the list without crossing furniture")
	await capture_frame("takeshi-desk-front")
	# O prefixo já tem mais de R$2000 do banco. Acerta a conquista existente
	# antes de medir esta missão; não a conta como taxa do final.
	session.activities.refresh_achievements()
	var balance: int = session.state.economy.balance
	check(session.mission_world.perform("transfer_document"),"actual list interaction opens the story dialogue")
	var spoken := finish_dialogue(session)
	check("Vicente" in spoken and "deserto" in spoken.to_lower(),"displayed list identifies Vicente and the desert races")
	check(session.state.campaign.has_progress("cobra_finale") and session.state.campaign.active_id.is_empty(),"reading the list completes the chapter mission")
	var wallet: Dictionary = session.state.economy.snapshot()
	var receipt: Dictionary = wallet.transactions.get("reward:campaign:cobra_finale",{})
	check(receipt.get("kind") == "reward" and receipt.get("item") == "campaign:cobra_finale" and receipt.get("amount") == 600,"finale receipt contains its exact authored R$600")
	check(session.state.campaign.snapshot().claimed_rewards.count("cobra_finale") == 1,"finale has one claimed reward entry")
	print("COBRA_HOUSE_WALLET before=",balance," after=",session.state.economy.balance," finale=",receipt," achievements=",wallet.achievements)
	check(session.state.economy.balance == balance+600,"finale pays its authored reward exactly once")
	var story := STORY.data(session.state.world_state)
	check(story.brother_route_found and story.act_two_available,"the physical list opens the next act")
	check(not session.mission_world.perform("transfer_document") and session.state.economy.balance == balance+600,"repeating the list cannot duplicate the reward")
	var reward_point: Vector3 = room.to_global(Vector3(-2.5,.08,-3.3))
	check(await session.arrival._walk(world.player,reward_point),"house cash reward is reachable on the floor")
	await capture_frame("takeshi-room-depth")
	await settle(3)
	session._collect_reward(room)
	check(session.state.world_state.rewards.has("cobra_leader_house_cash_01") and session.state.economy.balance == balance+1800,"house's useful reward grants its authored R$1200")
	session._collect_reward(room)
	check(session.state.economy.balance == balance+1800,"house reward cannot repeat on the same visit")
	session.garage_rewards._sync()
	check(session.garage_rewards.snapshot().vehicles.has("cobra_boss_ironback"),"finale authorizes the Ironback reward in Maciota's garage")
	check(session.save_game(true),"live session captures its completed chapter state")
	var store := STORE.new()
	store.path = "user://tests/cobra_house_%d/progress.json" % Time.get_ticks_usec()
	check(store.save(session.state) == OK,"completed house checkpoint saves to an isolated file")
	var loaded := STATE.new()
	check(store.load_into(loaded).get("ok",false),"completed house checkpoint reloads through SaveStore")
	check(loaded.place_id == "cobra_leader_house" and loaded.campaign.has_progress("cobra_finale") and STORY.data(loaded.world_state).act_two_available,"save restores house, chapter and next-act availability")
	var paid: int = loaded.economy.balance
	check(not loaded.campaign.claim_reward(loaded.economy,"cobra_finale") and loaded.economy.balance == paid,"loading cannot pay the finale again")
	var saved: Dictionary = loaded.snapshot()
	check(await session.leave_place(),"house exit returns to its authored street access")
	await settle()
	finish_dialogue(session)
	check(session.state.restore_snapshot(saved),"live state accepts the serialized house checkpoint")
	await session.restore_location()
	check(session.state.place_id == "cobra_leader_house" and session.position_clear(world.player.global_position),"restored house re-admits the physical player")
	check(await session.leave_place(),"restored house can exit again")
	await settle()
	finish_dialogue(session)
	check(session.state.grant_weapon("pistol") and session.state.equip_weapon("pistol"),"outside the garage the player can carry a weapon")
	var ammunition: Dictionary = session.state.get_ammo("pistol").duplicate(true)
	check(await session.enter_place("maciota",false),"reward workshop remains accessible after the new finale")
	await capture_frame("maciota-workshop-entry")
	world.player.input_locked = false
	check(session.state.equipped_weapon == "fists" and not session.state.weapons_allowed(),"garage entry holsters the weapon")
	check(not session.state.equip_weapon("pistol") and not session.state.can_attack(),"garage blocks weapon draw and every attack class")
	check(not session.state.reload_weapon("pistol") and not session.state.consume_ammo("pistol"),"garage blocks reload and firing consumers")
	check(session.state.owns_weapon("pistol") and session.state.get_ammo("pistol") == ammunition,"garage restriction preserves inventory and ammunition")
	for resident in [world.maciota_place.maciota,world.maciota_place.mechanic]:
		check(resident.get_meta("invulnerable",false) and not resident.has_method("receive_damage") and not resident.has_method("die"),"workshop resident has no damage or death routine")
	check(session.save_game(true),"garage restriction checkpoint captures")
	check(store.save(session.state) == OK and store.load_into(loaded).get("ok",false),"garage restriction survives isolated save and reload")
	check(loaded.place_id == "maciota" and loaded.equipped_weapon == "fists" and not loaded.can_attack() and loaded.owns_weapon("pistol"),"restored garage derives protection and preserves the weapon")
	check(await session.leave_place(),"garage exits after the chapter reward")
	await settle()
	finish_dialogue(session)
	check(session.state.weapons_allowed() and session.state.equip_weapon("pistol"),"garage exit restores weapon use")
	TranslationServer.set_locale(previous_locale)
	if not review_dir.is_empty():
		FileAccess.open(review_dir.path_join("takeshi-depth-metrics.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"depth":depth_report},"\t"))
	world.free()
	await process_frame
	print("COBRA_LEADER_HOUSE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
