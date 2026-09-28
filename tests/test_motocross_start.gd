extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_START ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	var session = world.session
	var mx = session.motocross
	session.state.intro.stage = "complete"
	session.state.economy.grant_reward("mx_start_fixture",2000)
	mx.progress.begin(session.state.economy,0)
	mx.progress.settle(session.state.economy,true)
	world.player.teleport(mx.COURSE.ENTRY)
	world.production.region.set_focus(mx.COURSE.ENTRY)
	for i in 90: await physics_frame
	var balance: int = session.state.economy.balance
	mx.selected_model = 2
	check(mx.start_race(1),"intermediário inicia com modelo escolhido")
	mx.finish(true)
	var receipts: Dictionary = session.state.economy.snapshot().transactions
	check(receipts["reward:motocross_prize:%d"%mx.progress.data.serial].amount==280,"vitória credita inscrição e lucro de80")
	check(receipts["reward:achievement:first_grand"].amount==50 and session.state.economy.balance==balance+130,"conquista de2000 mantém bônus separado de50")
	check(mx.progress.data.bike_model==2 and mx.owned_bike.profile_id==2,"moto conquistada conserva perfil de curva")
	check(not mx.start_shot.active and world.get_viewport().get_camera_3d()==world.camera,"encerramento durante montagem restaura câmera")
	for i in 3: await physics_frame
	check(mx.start_race(0),"segunda montagem disponível")
	mx.finish(false)
	check(not mx.mounted and world.player.visible and not mx.start_shot.active,"desistência durante montagem restaura jogador")
	check(mx.start_race(0),"terceira montagem disponível")
	world.queue_free()
	await process_frame
	await process_frame
	print("MOTOCROSS_START_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
