extends SceneTree
const FIXTURE = preload("res://tests/fixtures/TravelBagScene.gd")
const GRID = preload("res://systems/inventory/GridInventory.gd")
const STORE = preload("res://runtime/SaveStore.gd")
const STATE = preload("res://runtime/GameState.gd")
var world
var checks := 0
var failures := 0
var out := "res://evidence/travel-bag-20261007/flow"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("TRAVEL_BAG ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1; push_error(label)
func frames(count := 5) -> void:
	for i in count: await physics_frame
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"/"+label+".png")
func button() -> Button:
	return world.session.field_inventory.ui.find_child("ClaimTravelBag",true,false) as Button

func transition_owners(label: String) -> void:
	var session=world.session
	print("TRAVEL_BAG_TRANSITION_OWNERS ",label," ",{"transition_kind":session.transition_kind,"vehicle_transition_busy":session.vehicle_transition_busy,"rescue_pending":session.rescue_pending,"arrest_pending":session.arrest_pending,"respawn_busy":session.respawn_busy,"jessica_riding":session.jessica!=null and session.jessica.riding,"controller_travel_busy":session.controller.travel_busy,"arrival_controls":session.arrival!=null and session.arrival.controls_locked,"arrival_phase":session.arrival.phase if session.arrival!=null else "","railway":session.railway!=null and session.railway.busy(),"coach":session.regional_coach!=null and session.regional_coach.busy(),"player_position":world.player.position,"health":world.gameplay.health,"locked":world.player.input_locked})
func trunk_diagnostic(label: String) -> void:
	var personal=world.session.personal_car
	var car=personal._car()
	var rear: Vector3=personal._rear()
	var ray:=PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP*.8,rear+Vector3.UP*.8,7)
	ray.exclude=[world.player.get_rid(),car.get_rid()]
	print("TRAVEL_BAG_TRUNK_DIAGNOSTIC ",label," ",{"action":personal.nearest_action(),"near":personal._near_trunk(),"available":personal._available(),"modal":world.session.modal,"blocked":world.session.is_transition_blocked(),"distance":world.player.position.distance_to(rear),"player":world.player.position,"rear":rear,"speed":car.speed,"awaiting_ground":car.has_meta("awaiting_ground"),"ray":str(world.get_world_3d().direct_space_state.intersect_ray(ray).get("collider","clear"))})
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); root.add_child(world); current_scene = world
	var startup_ready: bool=await FIXTURE.wait_for_startup(world)
	check(startup_ready,"Main real pronta após cortina, streaming e solo físico")
	if failures: quit(1); return
	var session = world.session
	# Isolate this inventory fixture from unrelated traffic damage. Explicit
	# health=0 below still exercises the dead-player transfer restriction.
	world.gameplay.god_mode=true
	var field = session.field_inventory
	var personal = session.personal_car
	var economy = session.state.economy
	check(not personal.travel_bag_available(),"novo jogo não recebe mala")
	check(FIXTURE.complete_through(session,"primeiro_giro"),"primeira missão concluída na fixture")
	session.personal_car.refresh()
	check(economy.grid_snapshot().bag == "backpack","Maciota entrega mochila ao concluir a primeira missão")
	var car = FIXTURE.park_monaliza(world)
	check(await FIXTURE.wait_for_vehicle_support(world,car),"Monaliza estacionada tem suporte físico real")
	if failures: world.free(); print("TRAVEL_BAG_RESULT checks=",checks," failures=",failures); quit(1); return
	world.player.teleport(personal._rear()+Vector3(0,.05,.8)); await frames(30)
	var opened: bool=personal.perform("trunk")
	if not opened: trunk_diagnostic("first interaction")
	check(opened,"interação física abre porta-malas sem alterar mochila")
	if not opened:
		world.free(); print("TRAVEL_BAG_RESULT checks=",checks," failures=",failures); quit(1); return
	check(economy.grid_snapshot().bag == "backpack","mochila vem antes da mala")
	check(button() == null and not field.claim_travel_bag(),"recompensa bloqueada antes da corrida")
	field.close()
	check(FIXTURE.complete_through(session,"cobra_contact"),"contato completo ainda não libera mala")
	check(session.state.campaign.begin("cobra_race"),"corrida pode começar")
	check(not personal.travel_bag_available(),"iniciar corrida não libera mala")
	session.state.campaign.cancel("race_lost")
	check(not personal.travel_bag_available(),"perder ou cancelar não libera mala")
	check(FIXTURE.complete_through(session,"cobra_race"),"vitória persistida na campanha")
	check(personal.travel_bag_available(),"vitória libera retirada, inclusive em saves anteriores")
	var dialogue = preload("res://systems/campaign/OriginalDialogue.gd").new()
	for language in ["pt","en"]:
		var lines: Array = dialogue.lines("cobra_race_clue",language)
		check(lines.any(func(row): return "Monaliza" in row.message),"conversa pós-corrida indica retirada em "+language)
	economy.grant_item("apple",3); economy.grant_item("water",2); economy.grant_item("sandwich",2)
	economy.grant_weapon("hunting_rifle")
	check(session.state.equip_weapon("hunting_rifle"),"arma longa equipada antes da troca")
	var storage: Array = economy.grid_snapshot().storage
	var pockets: Array = economy.grid_snapshot().pockets
	var inventory: Dictionary = economy.snapshot().inventory
	check(not storage.is_empty(),"mochila contém suprimentos para verificar transferência")
	field.open(true); await frames()
	check(button() != null and not button().disabled,"botão de troca disponível no porta-malas real")
	if button()==null:
		trunk_diagnostic("offer missing")
		world.free(); print("TRAVEL_BAG_RESULT checks=",checks," failures=",failures); quit(1); return
	check(button().get_global_rect().end.y <= 720,"retirada visível dentro da tela")
	await shot("offer")
	var before: Dictionary = economy.snapshot()
	world.player.teleport(world.player.position+Vector3(12,0,0))
	# The live inventory refreshes physical access at 4 Hz.
	await create_timer(.3).timeout
	check(button().disabled,"afastar-se desabilita retirada com painel aberto")
	check(not field.claim_travel_bag() and economy.snapshot() == before,"chamada atrasada remota não altera itens ou recibos")
	field.close()
	world.player.teleport(personal._rear()+Vector3(0,.05,.8)); await frames()
	car.speed = 1.0
	check(not field.claim_travel_bag() and economy.snapshot() == before,"carro em movimento impede retirada")
	car.speed = 0.0
	world.gameplay.health = 0
	check(not field.claim_travel_bag() and economy.snapshot() == before,"morte impede retirada")
	world.gameplay.health = 100
	# Full ground-bag capacity must reject the entire exchange, including receipt.
	var full: Dictionary = economy.grid_snapshot()
	for i in 512:
		full.serial += 1
		full.ground.append({"uid":full.serial,"bag":"backpack","region":"mountain","place":"","position":[1.0,0.0,1.0],"entries":[]})
	economy._data.grid_inventory = full
	var full_before: Dictionary = economy.snapshot()
	check(not field.claim_travel_bag() and economy.snapshot() == full_before,"limite de bagagens rejeita troca sem perda ou recibo")
	check(economy.restore_snapshot(before),"fixture restaura estado anterior ao teste de limite")
	# Block the three physical drop candidates, leaving the trunk ray clear.
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.visual.rotation.y = PI
	var obstacles := Node3D.new(); world.add_child(obstacles)
	for direction in [Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
		var body := StaticBody3D.new(); body.collision_layer=1
		var shape := BoxShape3D.new(); shape.size=Vector3(.8,3,.8)
		var collision := CollisionShape3D.new(); collision.shape=shape
		body.add_child(collision); obstacles.add_child(body)
		body.global_position=world.player.global_position+direction*1.15+Vector3.UP*1.5
	await frames()
	check(field.trunk_access() and not field.bag_drop_point().is_finite(),"solo obstruído com porta-malas ainda acessível")
	check(not field.claim_travel_bag() and economy.snapshot() == before,"sem espaço no chão preserva mochila e oferta")
	obstacles.free(); await frames()
	if failures:
		print("TRAVEL_BAG_RESULT checks=",checks," failures=",failures)
		world.free(); quit(1); return
	field.open(true); await frames()
	button().pressed.emit(); await frames()
	check(economy.grid_snapshot().bag == "handbag","botão entrega e equipa mala")
	check(GRID.dimensions(economy.grid_snapshot(),"storage") == Vector2i(4,6),"mala tem 24 espaços")
	check(economy.grid_snapshot().storage == storage and economy.grid_snapshot().pockets == pockets and economy.snapshot().inventory == inventory,"transferência preserva todos os itens e posições")
	check(economy.grid_snapshot().ground.size() == 1 and economy.grid_snapshot().ground[0].bag == "backpack" and economy.grid_snapshot().ground[0].entries.is_empty(),"mochila vazia fica recuperável sem duplicar conteúdo")
	check(session.state.equipped_weapon == "fists" and not session.state.equip_weapon("hunting_rifle"),"mala guarda e bloqueia arma longa")
	check(button() == null and not personal.travel_bag_available(),"recibo remove a oferta")
	before = economy.snapshot()
	check(not field.claim_travel_bag() and economy.snapshot() == before,"clique repetido não duplica recompensa")
	check(is_instance_valid(field.carried) and field.carried.kind == "handbag" and field.carried.opened,"mala aparece aberta no inventário após troca")
	await shot("received")
	field.close(); await frames()
	check(not field.carried.opened and not world.player.input_locked,"fechar painel devolve controle e mala à mão")
	await shot("carried")
	# Persistência real em arquivo exclusivo, sem tocar slots pessoais.
	check(session.save_game(),"sessão captura estado integrado")
	var store = STORE.new()
	store.path = "user://travel_bag_tests/"+str(Time.get_ticks_usec())+".json"
	check(store.save(session.state) == OK,"snapshot completo salvo em disco isolado")
	var restored = STATE.new()
	check(store.load_into(restored).get("ok",false),"snapshot completo relido de disco")
	var saved_grid: Dictionary = economy.grid_snapshot()
	var loaded_grid: Dictionary = restored.economy.grid_snapshot()
	var matching := true
	for property in ["bag","serial","claimed","pockets","storage","trunk"]:
		matching = matching and loaded_grid[property] == saved_grid[property]
	check(matching and loaded_grid.ground.size() == saved_grid.ground.size(),"recibo e conteúdo sobrevivem ao arquivo")
	for i in saved_grid.ground.size():
		var saved: Dictionary = saved_grid.ground[i]
		var loaded: Dictionary = loaded_grid.ground[i]
		for property in ["uid","bag","region","place","entries"]:
			check(loaded[property] == saved[property],"mochila salva preserva "+property)
		var saved_point := Vector3(saved.position[0],saved.position[1],saved.position[2])
		var loaded_point := Vector3(loaded.position[0],loaded.position[1],loaded.position[2])
		check(saved_point.is_equal_approx(loaded_point),"posição preservada na precisão do JSON")
	transition_owners("before snapshot restore")
	check(session.state.restore_snapshot(restored.snapshot()),"sessão restaura snapshot relido")
	transition_owners("after snapshot restore")
	economy = session.state.economy
	check(not personal.travel_bag_available() and not field.claim_travel_bag(),"load não reabre recompensa recebida")
	check(field.drop_bag(),"mala conquistada pode ser solta")
	transition_owners("after drop")
	await frames()
	var drop: Dictionary = economy.grid_snapshot().ground.back()
	var key := "drop_"+str(drop.uid)
	world.player.teleport(field.pickups[key].node.global_position+Vector3(0,.01,.9)); await frames()
	check(field.perform(key),"mala conquistada pode ser recuperada por interação física")
	transition_owners("after recover")
	check(economy.grid_snapshot().storage == storage and not personal.travel_bag_available(),"recuperação mantém conteúdo e recibo")
	# Approach the actual authored entrance and let the actor land after the
	# pickup teleport; admission correctly rejects an airborne actor.
	var entrance: Vector3=world.maciota_place.entry_position+Vector3(0,.08,1.0)
	var collision_ready: bool=world.production.region.prepare_collision_at(entrance)
	await frames(3)
	var landing_ray:=PhysicsRayQueryParameters3D.create(entrance+Vector3.UP*2,entrance-Vector3.UP*2000,1)
	landing_ray.exclude=[world.player.get_rid()]
	var landing: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(landing_ray)
	var landing_clear: bool=not landing.is_empty() and landing.normal.y>=.65 and session.position_clear(landing.position+Vector3.UP*.08)
	check(collision_ready and landing_clear,"solo da entrada preparado antes de transportar a fixture")
	if not collision_ready or not landing_clear:
		print("TRAVEL_BAG_ENTRANCE_DIAGNOSTIC ",{"entrance":entrance,"collision_ready":collision_ready,"landing":str(landing),"landing_clear":landing_clear})
		world.free(); print("TRAVEL_BAG_RESULT checks=",checks," failures=",failures); quit(1); return
	var grounded_entrance: Vector3=landing.position+Vector3.UP*.08
	world.player.teleport(grounded_entrance)
	world.production.region.set_focus(grounded_entrance,true)
	var approach_ready:=false
	for i in 300:
		await physics_frame
		if world.player.is_on_floor() and not world.player.get_meta("player_air_busy",false) and not world.player.input_locked and not session.is_transition_blocked():
			approach_ready=true; break
	check(approach_ready,"aproximação física à garagem está no solo e pronta")
	if not approach_ready:
		transition_owners("garage not ready")
		print("TRAVEL_BAG_GARAGE_DIAGNOSTIC ",{"modal":session.modal,"locked":world.player.input_locked,"air_busy":world.player.get_meta("player_air_busy",false),"on_floor":world.player.is_on_floor(),"blocked":session.is_transition_blocked(),"position":world.player.position,"stars":world.gameplay.stars,"health":world.gameplay.health})
	var entered:=false
	if approach_ready: entered=await session.enter_place("maciota",false,"maciota")
	check(entered,"entrada na garagem com mala")
	if not entered:
		print("TRAVEL_BAG_GARAGE_DIAGNOSTIC admission ",{"modal":session.modal,"locked":world.player.input_locked,"air_busy":world.player.get_meta("player_air_busy",false),"blocked":session.is_transition_blocked(),"region":session.state.region_id,"place":session.state.place_id,"stars":world.gameplay.stars,"health":world.gameplay.health,"room":str(session.room)})
	check(not session.state.equip_weapon("pistol") and not world.gameplay.fire_at(world.player.position+Vector3.FORWARD*3),"garagem continua bloqueando armas")
	for actor in [world.maciota_place.maciota,world.maciota_place.mechanic]:
		check(not actor.has_method("damage") and not actor.has_method("take_damage"),"morador da garagem continua protegido")
	world.free(); await process_frame
	print("TRAVEL_BAG_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
