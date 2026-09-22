extends SceneTree
## Pátio da delegacia na sessão real: viaturas trancadas, lockpick, alarme com
## giroflex, estrela por roubo, reposição da vaga e aviso da lanterna da arma.
## Paridade com V1 `tests/test_police_car_alarm_theft.gd`. Rodar com --no-save.
var world
var session
var pool
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)
func settle(frames := 3) -> void:
	for i in frames: await physics_frame

func stand_at_door(car) -> void:
	world.player.teleport(car.driver_door_anchor(-1) + Vector3.UP * .05)
	await settle(4)
	if world.driving._entry_option().get("car") != car:
		world.player.teleport(car.driver_door_anchor(1) + Vector3.UP * .05)
		await settle(4)

func solve() -> void:
	var lock = pool.lockpick
	for pin in 3:
		lock.angle = lock.target_angle
		lock.attempt()

func wait_boarding() -> void:
	for i in 600:
		if not world.driving.is_body_transition_active(): return
		await physics_frame

func leave_car() -> void:
	await wait_boarding()
	world.driving.car.speed = 0
	check(world.driving.leave(), "Sai da viatura parada")
	await wait_boarding()

func beacon_lit(car) -> bool:
	for i in 30:
		for beacon in car.equipment.beacons:
			if beacon.material.emission_enabled: return true
		await process_frame
	return false

func run() -> void:
	create_timer(240).timeout.connect(func(): print("TIMEOUT"); quit(2))
	if not "--no-save" in OS.get_cmdline_user_args():
		print("Use --no-save: este teste não pode tocar o save do jogador.")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	session = world.session
	check(session != null and session.ready_for_play, "Sessão integrada inicia")
	if not failures.is_empty(): quit(1); return
	pool = session.police_motor_pool
	check(pool != null, "Pátio da delegacia instalado na sessão")
	var gameplay = world.gameplay
	# O pátio fica a oeste da delegacia; o foco do streaming segue o jogador.
	var lot: Vector3 = pool.BAYS[0].position.lerp(pool.BAYS[1].position, .5) + Vector3(6, .1, 0)
	world.player.teleport(lot)
	session.controller.region.set_focus(lot)
	for i in 900:
		await physics_frame
		if is_instance_valid(pool.cars[0]) and is_instance_valid(pool.cars[1]): break
	var cruiser = pool.cars[0]
	var suv = pool.cars[1]
	check(is_instance_valid(cruiser) and is_instance_valid(suv), "Duas viaturas estacionadas no pátio")
	if not failures.is_empty(): quit(1); return
	await settle(30)
	check(cruiser.archetype == "police_cruiser" and suv.archetype == "police_suv", "Cruiser e SUV, como na V1")
	check(not cruiser.traffic and absf(cruiser.speed) < .05 and cruiser.global_position.distance_to(pool.BAYS[0].position) < 1.0, "Cruiser parada na vaga")
	check(cruiser.get_meta("police_locked", false) and suv.get_meta("police_locked", false), "Viaturas começam trancadas")
	check(cruiser.equipment.beacons.size() == 2 and suv.equipment.beacons.size() == 2, "Giroflex real nas duas viaturas")
	check(cruiser.equipment.alarm_remaining == 0 and not cruiser.equipment.alarm_audio.playing, "Sem alarme em repouso")

	await stand_at_door(cruiser)
	check(world.driving._entry_option().get("car") == cruiser, "Porta da cruiser alcançável")
	check(world.driving.interact(), "F na viatura trancada é tratado")
	check(pool.lockpick_active() and not world.driving.occupied, "Lockpick abre em vez de entrar")
	check(world.player.input_locked and session.modal and gameplay.stars == 0, "Lockpick trava o jogador e não gera crime")
	var first_target = pool.target
	check(not world.driving.interact() and pool.target == first_target, "Interação repetida não duplica o lockpick")
	pool.lockpick.angle = pool.lockpick.target_angle + PI
	pool.lockpick.attempt()
	await settle()
	check(not pool.lockpick_active() and not world.driving.occupied, "Erro nega a entrada")
	check(not session.modal and not world.player.input_locked, "Erro devolve os controles")
	check(cruiser.equipment.alarm_remaining >= 10 and cruiser.equipment.alarm_remaining <= 15, "Alarme dura 10 a 15 s")
	check(cruiser.equipment.alarm_audio.playing and await beacon_lit(cruiser), "Alarme toca e pisca o giroflex com a viatura vazia")
	var halo_colors := {}
	var headlight_states := {}
	for i in 40:
		await process_frame
		if cruiser.equipment.halo.visible: halo_colors[cruiser.equipment.halo.light_color.to_html(false)] = true
		headlight_states[cruiser.equipment.lamps[0].visible] = true
	check(halo_colors.size() == 2, "Halo do giroflex alterna vermelho e azul (V1 SirenHalo)")
	check(headlight_states.size() == 2, "Faróis piscam durante o alarme")
	check(gameplay.stars == 0, "Falha no lockpick não gera estrela")
	var remaining: float = cruiser.equipment.alarm_remaining
	check(not cruiser.equipment.start_alarm() and cruiser.equipment.alarm_remaining <= remaining, "Novo disparo não prolonga o alarme")

	check(world.driving.interact() and pool.lockpick_active(), "Nova tentativa abre o lockpick")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	pool.lockpick._input(cancel)
	await settle()
	check(not pool.lockpick_active() and not session.modal and gameplay.stars == 0, "ESC fecha o lockpick e fica local")

	check(world.driving.interact() and pool.lockpick_active(), "Abre de novo para testar o clique")
	Input.action_press("fire")
	pool.lockpick.finish(false)
	await settle()
	check(session.modal and world.player.input_locked, "Clique que falhou não vaza para o tiro")
	Input.action_release("fire")
	# A espera pela soltura corre em _process: aguardar quadros de processo, não de física.
	for i in 3: await process_frame
	check(not session.modal and not world.player.input_locked, "Soltar o clique devolve os controles")

	check(world.driving.interact() and pool.lockpick_active(), "Abre para arrombar")
	solve()
	await settle()
	check(not cruiser.get_meta("police_locked", false) and world.driving.occupied and world.driving.car == cruiser, "Três travas destrancam e iniciam o embarque")
	check(gameplay.stars == 1 and gameplay.crime_points == gameplay.STAR_THRESHOLDS[1], "Roubo gera exatamente uma estrela")
	await process_frame
	check(cruiser.equipment.alarm_remaining == 0 and not cruiser.equipment.alarm_audio.playing and not cruiser.equipment.halo.visible, "Destrancar silencia o alarme e apaga o halo")
	check(pool.restock[0] > 40, "Vaga entra em reposição")
	await wait_boarding()
	check(cruiser.controlled and cruiser.equipment.toggle_siren() and cruiser.equipment.siren_audio.playing, "Sirene da viatura roubada funciona")
	cruiser.equipment.toggle_siren()
	await leave_car()
	await stand_at_door(cruiser)
	check(world.driving.interact() and not pool.lockpick_active() and world.driving.occupied, "Viatura roubada não pede lockpick de novo")
	check(gameplay.stars == 1, "Reentrar não repete o crime")
	await leave_car()

	await stand_at_door(suv)
	check(world.driving.interact() and pool.lockpick_active(), "SUV também está trancada")
	solve()
	await settle()
	check(gameplay.stars == 2, "Segunda viatura soma mais uma estrela")
	await wait_boarding()
	check(suv.equipment.toggle_siren() and suv.equipment.siren_audio.playing, "SUV roubada tem sirene e giroflex")
	suv.equipment.toggle_siren()
	await leave_car()

	# Reposição: a viatura roubada ainda na vaga bloqueia a nova; afastada, a vaga é reposta.
	pool.restock[0] = 0
	pool._sync()
	check(pool.cars[0] == null, "Viatura roubada na vaga bloqueia a reposição")
	cruiser.global_position += Vector3(14, 0, 0)
	world.player.teleport(lot + Vector3(4, 0, 0))
	await settle(4)
	pool._sync()
	check(is_instance_valid(pool.cars[0]) and pool.cars[0] != cruiser and is_instance_valid(cruiser), "Reposição preserva a viatura roubada")
	var fresh = pool.cars[0]
	check(fresh.get_meta("police_locked", false), "Viatura reposta vem trancada")

	gameplay.clear_wanted()
	gameplay.health = 100
	# Lanterna: sem acessório instalado, a tecla explica onde comprar (V1).
	session.state.grant_weapon("pistol")
	session.state.equip_weapon("pistol")
	await settle(2)
	session.notice_time = 0
	session._toggle_weapon_flashlight()
	check(session.notice_time > 0 and "Ammu-Nation" in session.notice.text, "Lanterna ausente mostra o aviso")
	gameplay.customization["pistol"] = {"owned": true, "installed": true, "owned_parts": [], "parts": {}}
	gameplay.visual_id = "@rebuild"
	session._toggle_weapon_flashlight()
	await settle(3)
	check(gameplay.flashlight_enabled and gameplay.flashlight.visible, "Lanterna instalada acende")


	await settle(20)
	await stand_at_door(fresh)
	check(world.driving.interact() and pool.lockpick_active(), "Lockpick na viatura reposta")
	gameplay.health = 0
	await settle(2)
	check(not pool.lockpick_active() and not world.driving.occupied, "Morte durante o lockpick não concede a entrada")
	check(fresh.equipment.alarm_remaining > 0, "Interrupção dispara o alarme")
	gameplay.health = 100
	gameplay.clear_wanted()

	print("POLICE_MOTOR_POOL ", checks, " checks failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
