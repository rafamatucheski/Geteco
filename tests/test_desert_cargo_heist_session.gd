extends SceneTree
## Integração Main com save isolado. Posicionamentos de fixture não aprovam a rota longa.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://gameplay/desert_heist/DesertHeistState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const GAME_STATE := preload("res://runtime/GameState.gd")
var world
var heist
var output := ""
var failures: Array[String] = []
var checks := 0
var shots := 0

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): failures.append("Timeout global 360s"); finish(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks += 1
	print("CARGO_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"Exige save isolado e backend .NET"):
		finish(2); return
	output = FIXTURE.output_dir("cargo-session")
	var start := Vector3(-710,.08,-1525.5)
	var snapshot := FIXTURE.full_snapshot(start,true)
	# A chamada pós-campanha pertence a outro fluxo e bloquearia controles neste cenário.
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[start.x,start.y,start.z]}
	snapshot.world.time = 1.0/24.0
	var cargo := STATE.initial(0,0)
	cargo.position = [-710,.08,STATE.START.z]
	cargo.distance = 370.0
	snapshot.world[STATE.KEY] = cargo
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"Fixture de carga valida no SaveStore"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	# O prewarm global do porto precede o deserto e ultrapassa 90s nesta máquina.
	# O limite da atividade continua separado dos recursos globais de inicialização.
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled and world.production.store.path == path,"Main carrega somente fixture isolada"):
		finish(1); return
	world.dispatch.router.nearest_edge(start)
	if not check(world.dispatch.router._native != null,"Roteador C# compilado ativo"): finish(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.god_mode = true
	heist = world.session.desert.heist
	world.session.weather.time_of_day = 1.0/24.0
	world.session.weather.weather_timer = 3600
	deadline = Time.get_ticks_msec()+15000
	while not is_instance_valid(heist.truck) and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(is_instance_valid(heist.truck),"Carga admitida fisicamente na estrada"): finish(1); return
	var truck: CharacterBody3D = heist.truck
	var before: Vector3 = truck.global_position
	await create_timer(2).timeout
	check(truck.global_position.x>before.x+3 and truck.global_position.y>-.3,"Caminhão anda na faixa real com suporte físico")
	world.player.teleport(truck.global_position+Vector3(0,.08,12))
	world.gameplay.npc_gunfire.connect(func(_origin: Vector3,_direction: Vector3,shooter: Node3D):
		if heist.guards.has(shooter): shots += 1)
	# Mesmo sinal consumido pelo runtime após um disparo; o alvo aqui é o contrato de interceptação.
	world.gameplay.weapon_fired.emit("pistol",world.player.global_position)
	deadline = Time.get_ticks_msec()+10000
	while live_guards()<2 and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(heist.data.phase == "intercepted" and live_guards() == 2,"Tiro próximo faz exatamente dois guardas desembarcarem"):
		finish(1); return
	for guard in heist.guards:
		check(guard.weapon_id == "shotgun" and guard.armor > 0,"Cada guarda usa calibre 12 e colete funcional")
		var health: float = guard.health
		var armor: float = guard.armor
		guard.receive_damage(20.0,world.player)
		check(guard.armor < armor and guard.health > health-20,"Colete absorve parte do dano sem imunidade")
	deadline = Time.get_ticks_msec()+7000
	while shots == 0 and Time.get_ticks_msec()<deadline: await physics_frame
	check(shots > 0,"Escolta dispara projéteis reais")
	check(not heist.save_block_reason().is_empty(),"Escolta próxima bloqueia salvamento durante confronto")
	var combat_position: Vector3 = world.player.global_position
	world.player.global_position = truck.global_position+Vector3(0,0,95)
	check(heist.save_block_reason().is_empty(),"Abandonar interceptação não prende salvamento global")
	world.player.global_position = combat_position
	await photo("escolta")
	world.session.state.grant_weapon("m4a1")
	world.session.state.add_ammo("m4a1",120)
	world.session.state.equip_weapon("m4a1")
	for guard in heist.guards:
		deadline = Time.get_ticks_msec()+10000
		while not guard.dead and Time.get_ticks_msec()<deadline:
			world.gameplay.aim_point = guard.global_position+Vector3.UP
			world.gameplay.fire_at(guard.global_position+Vector3.UP)
			await physics_frame
		if not check(guard.dead,"Arma do jogador derrota guarda protegido"): finish(1); return
	world.player.teleport(truck.driver_door_anchor(1)+truck.global_basis.x*.5)
	await physics_frame
	if not check(world.driving.interact(),"Embarque normal aceita roubo da carga"): finish(1); return
	deadline = Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	await create_timer(.5).timeout
	if not check(world.driving.occupied and world.driving.car == truck and heist.data.phase == "stolen","Controle real do caminhão e estado roubado"): finish(1); return
	check(heist.nearest_action().is_empty(),"Contêiner não abre com jogador dentro da cabine")
	before = truck.global_position
	Input.action_press("accelerate",.5)
	await create_timer(2).timeout
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	await create_timer(2).timeout
	check(truck.global_position.distance_to(before)>2,"Jogador dirige caminhão pela física real")
	# O acesso completo até a desova exige condução/validação separada; esta fixture cobre entrega e abertura.
	world.production.region.prepare_collision_at(STATE.DROP_POINT)
	truck.global_position = STATE.DROP_POINT+Vector3.UP*.08
	truck.speed = 0
	truck.velocity = Vector3.ZERO
	await physics_frame
	if not check(world.driving.leave(),"Desembarque padrão na desova"): finish(1); return
	deadline = Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	Input.action_release("handbrake")
	world.player.teleport(truck.door_point()+Vector3.UP*.08)
	await create_timer(.5).timeout
	var action: Dictionary = heist.nearest_action()
	if not check(not action.is_empty(),"Traseira parada na desova oferece abertura"): finish(1); return
	world.player.input_locked = true
	check(heist.nearest_action().is_empty() and not heist.perform(action),"Controle bloqueado impede abertura e ação obsoleta")
	world.player.input_locked = false
	paused = true
	check(heist.nearest_action().is_empty() and not heist.perform(action),"Pausa impede abertura e ação obsoleta")
	paused = false
	var wallet_before: int = world.session.state.economy.balance
	if not check(await world.session.interact(),"Interação produtiva abre contêiner"): finish(1); return
	check(heist.data.phase == "opened" and world.session.state.economy.balance == wallet_before,"Abrir revela carga sem pagar antecipadamente")
	await create_timer(1.4).timeout
	for id in ["CargoLeafSolidLeft","CargoLeafSolidRight"]:
		var solid := truck.get_node_or_null(id) as CollisionShape3D
		if not check(solid != null and not solid.disabled,"Folha aberta possui sólido ativo"): finish(1); return
		var normal: Vector3=solid.global_basis.z.normalized()
		var query:=PhysicsRayQueryParameters3D.create(solid.global_position+normal*.4,solid.global_position-normal*.4,4)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider==truck,"Folha aberta bloqueia travessia fora do casco")
	await photo("conteiner-aberto-com-carga")
	await physics_frame
	if not check(await world.session.interact(),"Segunda interação recolhe carga visível"): finish(1); return
	check(heist.data.phase == "looted","Carga marcada como saqueada")
	var receipt := STATE.receipt(heist.data)
	check(world.session.state.economy.has_reward_receipt(receipt),"Recompensa possui recibo persistente")
	check(world.session.state.economy.balance>=wallet_before+STATE.reward(heist.data),"Carga adiciona seu valor à carteira")
	var balance: int = world.session.state.economy.balance
	check(not heist.perform(action) and world.session.state.economy.balance == balance,"Repetir abertura não duplica prêmio")
	heist.write_snapshot()
	var store := STORE.new()
	store.path = output.path_join("looted.json")
	if not check(store.save(world.session.state) == OK,"SaveStore grava resultado isoladamente"): finish(1); return
	var restored := GAME_STATE.new()
	if not check(store.load_into(restored).get("ok",false),"SaveStore restaura estado e recibo"): finish(1); return
	check(restored.world_state[STATE.KEY].phase == "looted" and restored.economy.has_reward_receipt(receipt),"Saque e pagamento sobrevivem ao load")
	check(not restored.economy.grant_reward(receipt,STATE.reward(heist.data)),"Load não permite pagamento repetido")
	await photo("carga-aberta")
	finish(0 if failures.is_empty() else 1)

func live_guards() -> int:
	var count := 0
	for guard in heist.guards:
		if is_instance_valid(guard) and not guard.dead: count += 1
	return count

func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func finish(code: int) -> void:
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	if not output.is_empty():
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"shots":shots,
			"display_server":DisplayServer.get_name(),"startup_prewarm":"--no-prewarm" not in OS.get_cmdline_user_args(),
			"scope":"Main .NET, movimento físico, sinal de disparo, combate real, coletes, embarque e direção, interação e SaveStore. Reposicionamentos diagnósticos não aprovam acesso completo/desova; FPS e temporal visual separados."},"\t"))
	print("CARGO_SESSION_DONE ",output," code=",code)
	quit(code)
