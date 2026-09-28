extends SceneTree
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
var world
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	print("MOTOCROSS_SESSION ","PASS " if ok else "FAIL ",title)
	if not ok: failures.append(title)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("World not ready"); quit(1); return
	var session = world.session
	var mx = session.motocross
	session.state.intro.stage = "complete"
	world.player.teleport(COURSE.ENTRY+Vector3.UP*.1)
	world.production.region.set_focus(COURSE.ENTRY)
	await frames(180)
	check(session.nearest().get("id","")=="motocross","entrada acessível pela interação real")
	check(mx.ambient.rows.size()==3,"aproximação ativa três pilotos decorativos")
	check(not mx.start_race(0) and mx.progress.data.serial==0,"saldo insuficiente não inicia nem cobra")
	mx._bike_menu(0)
	for child in session.column.get_children():
		if child is Button and child.text.begins_with("Víbora"):
			child.pressed.emit()
			break
	check(mx.selected_model==2 and session.state.economy.balance==0 and not mx.active,"seleção real de modelo não cobra inscrição")
	session.close_menu()
	session.state.economy.grant_reward("motocross_test",2000)
	check(mx.start_race(0),"inscrição inicia prova na cena real")
	check(session.state.economy.balance==1900 and session.state.world_state.motocross.active==0,"débito e tentativa capturados antes da corrida")
	check(mx.racers.size()==4 and mx.mounted and not world.player.visible,"jogador monta com três adversários")
	check(mx.ambient.rows.is_empty() and mx.player_bike.profile_id==2 and mx.player_bike.turn_response>1,"moto escolhida entra na prova sem pilotos decorativos")
	check(mx.start_shot.active and world.get_viewport().get_camera_3d()==mx.start_shot.camera,"largada abre câmera de montagem")
	var intro_before: float = mx.start_shot.elapsed
	session._menu("Pausa da montagem")
	await frames(20)
	check(mx.start_shot.elapsed==intro_before and mx.countdown==3,"menu pausa montagem e contagem de largada")
	session.close_menu()
	await frames(70)
	check(mx.start_shot.active and mx.player_bike.rider.position.x > -.9 and mx.player_bike.rider.position.x < 0,"Dante se desloca do lado até o banco")
	check(not session.state.can_attack() and not session.save_block_reason().is_empty(),"montaria bloqueia ataque e save intermediário")
	await frames(270)
	check(not mx.start_shot.active and world.get_viewport().get_camera_3d()==world.camera,"montagem devolve câmera antes da corrida")
	var gate_before: int = mx.racers[0].gate
	mx.player_bike.position = Vector3(-270,1,-100)
	await frames(85)
	check(mx.racers[0].respawns==1 and mx.racers[0].gate==gate_before,"fora da pista volta sem ganhar checkpoint")
	var rival = mx.racers[1].bike
	rival.crash(.7)
	check(rival.health < 100 and rival.crash_state=="fallen","rival cai e sofre dano real")
	var time_before: float = mx.elapsed
	session._menu("Pausa da prova")
	await frames(30)
	check(is_equal_approx(mx.elapsed,time_before),"menu suspende cronômetro da prova")
	session.close_menu()
	check(world.player.input_locked,"fechar menu mantém controle da moto")
	await frames(400)
	check(rival.crash_state=="riding","rival levanta e remonta durante corrida")
	mx.finish(false)
	await frames(2)
	check(session.state.economy.balance==1900 and not mx.mounted and world.player.visible and world.player.is_physics_processing(),"derrota restaura jogador sem reembolso")
	mx.selected_model = 0
	check(mx.start_race(0),"nova prova após derrota")
	mx.autopilot = true
	# Slow opponents to exercise a deterministic player win through real gates.
	for i in range(1,mx.racers.size()): mx.racers[i].bike.max_speed = 4
	for i in 12000:
		await physics_frame
		if not mx.active: break
	check(not mx.active and mx.progress.data.wins[0]==1,"duas voltas reais liquidam vitória")
	check(session.state.economy.balance==1940,"vitória real retorna entrada mais lucro40")
	check(mx.progress.data.unlocked==1,"vitória real libera intermediário")
	# Ownership is tested with the real ledger; mounting and dismounting use real world geometry.
	mx.selected_model = 2
	var before_win: int = session.state.economy.balance
	check(mx.start_race(1),"modelo de curva entra no intermediário")
	mx.finish(true)
	# Crossing R$ 2.000 also triggers the existing first_grand achievement (+50).
	var receipts: Dictionary = session.state.economy.snapshot().transactions
	check(receipts["reward:motocross_prize:%d"%mx.progress.data.serial].amount==280 and receipts["reward:achievement:first_grand"].amount==50 and session.state.economy.balance==before_win+130,"vitória paga80 de lucro e conquista existente paga50 separadamente")
	check(mx.progress.data.bike_model==2 and not mx.start_shot.active,"vitória guarda modelo conquistado e encerra câmera")
	mx._park_owned(true)
	await frames(30)
	check(is_instance_valid(mx.owned_bike) and mx.owned_bike.profile_id==2,"moto própria aparece no pátio com modelo conquistado")
	mx._mount(mx.owned_bike)
	await frames(30)
	check(mx.mounted and mx.player_bike==mx.owned_bike,"moto conquistada pode ser pilotada fora da prova")
	check(mx.dismount() and not mx.mounted,"desembarque encontra chão livre")
	check(session.save_game() and session.state.world_state.motocross.owned,"checkpoint conserva propriedade")
	check(session.state.world_state.motocross.bike_model==2,"save conserva modelo da moto própria")
	world.player.teleport(COURSE.ENTRY+Vector3(1,0,1))
	var before_rental: int = session.state.economy.balance
	mx.selected_model = 1
	check(mx.rent_bike() and session.state.economy.balance==before_rental-35,"aluguel inicia treino pago")
	await frames(20)
	check(mx.mounted and not mx.active and is_instance_valid(mx.rental_bike) and mx.rental_bike.profile_id==1 and mx.ambient.rows.is_empty(),"aluguel usa modelo de arrancada sem pilotos decorativos")
	check(mx.dismount() and not is_instance_valid(mx.rental_bike),"devolução retira moto alugada")
	world.queue_free()
	await process_frame
	print("MOTOCROSS_SESSION_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
