extends SceneTree
## Subida do forte até o esqui e entrada pela laje de pedra, no jogo real.
## Exige --no-save. Com --shots grava capturas em evidence/fort-exit-20260928/.

const SHOTS := "res://evidence/fort-exit-20260928/ascent"
var world
var session
var passage
var progression
var checks := 0
var failures := 0
var shots := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("FORT_ASCENT ","PASS " if ok else "FAIL ",label)
	if ok: return
	failures += 1
	push_error("FORT_ASCENT FAIL "+label)

func frames(count: int) -> void:
	for _frame in count: await physics_frame

func until(condition: Callable,limit_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < limit_seconds*1000.0:
		if condition.call(): return true
		await physics_frame
	return condition.call()

func shot(id: String) -> void:
	if not shots: return
	for _frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS+"/"+id+".png"))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	shots = "--shots" in OS.get_cmdline_user_args()
	if shots: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	root.size = Vector2i(1600,900)
	seed(195107)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 420:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("FORT_ASCENT Main did not become ready")
		quit(1)
		return
	session = world.session
	await frames(120)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	if is_instance_valid(session.world.hud): session.world.hud.hide()
	passage = session.urban_operations.secret_passage
	progression = session.urban_operations.secret_network
	progression.receive_dossier()
	for id in progression.FRAGMENT_IDS: progression.collect_fragment(id)
	for id in progression.KEYPAD_CLUE_IDS: progression.discover_keypad_clue(id)
	progression.discover_house()
	progression.unlock_keypad()
	progression.discover_headquarters()
	progression.activate_power_node("power_main")
	progression.activate_power_node("power_drainage")
	progression.discover_sealed_sector()
	progression.activate_power_node("power_sealed_sector")
	progression.discover_audio_log("audio_sealed_sector")
	for id in progression.LAB_CLUE_IDS: progression.discover_lab_clue(id)
	progression.unlock_final_door()
	passage.refresh_state()
	var exit_node = passage.ski_exit
	check(is_instance_valid(exit_node),"saída do esqui existe no mundo")
	check(not exit_node.visible,"laje escondida enquanto o jogador está em Harbor")

	passage.tunnel.set_return_camera(world.camera)
	check(await session.enter_place("mountain_fort",false,"secret_network"),"entra no forte")
	await frames(30)
	var fort = session.room
	fort.model.set_blast_open(true)
	fort.operation.rebuild_navigation()
	world.player.teleport(fort.to_global(fort.model.LIFT_POINT))
	await frames(6)
	var action: Dictionary = passage.nearest_action()
	check(action.get("target","").ends_with("fort_ascend"),"elevador oferece subir")
	# Sob fogo o elevador não parte.
	var soldier: Node = fort.operation.alive_soldiers()[0]
	soldier.alert(world.player.global_position)
	check(not fort.operation.can_ascend(),"elevador recusa com a sala em combate")
	for each in fort.operation.alive_soldiers(): each.receive_damage(999.0,world.player)
	await frames(6)
	check(fort.operation.can_ascend(),"sala calma libera o elevador")
	check(passage.perform(passage.nearest_action().target),"aciona o elevador")
	var arrived := await until(func(): return session.state.region_id == "mountain" and session.state.place_id.is_empty() and not session.controller.travel_busy and not session.transition_kind.is_empty() == false,45.0)
	check(arrived,"viagem da subida chega à serra")
	await frames(30)
	var arrival: Vector3 = exit_node.arrival_global()
	check(world.player.global_position.distance_to(arrival) < 2.5,"jogador sai diante da laje (%.1f m)"%world.player.global_position.distance_to(arrival))
	check(exit_node.visible and exit_node.slab_open and exit_node.slab.position.x > 2.0,"laje aberta ao sair")
	check(absf(world.player.global_position.y-exit_node.global_position.y) < 1.0,"jogador pisa o solo da serra")
	await shot("01-saida-aberta")
	await frames(60*9)
	check(not exit_node.slab_open and exit_node.slab.position.x < .2,"laje se arrasta de volta e fecha")
	await shot("02-laje-fechada")

	# Entrada por fora, agora que o cofre foi aberto.
	world.player.teleport(exit_node.interaction_global())
	await frames(10)
	action = passage.nearest_action()
	check(action.get("target","").ends_with("ski_enter"),"laje oferece abrir a passagem de pedra")
	check(passage.perform(action.target),"abre a passagem")
	await frames(60)
	await shot("03-laje-abrindo")
	var entered := await until(func(): return session.state.place_id == "mountain_fort" and session.transition_kind.is_empty(),25.0)
	check(entered,"entra no forte pela serra")
	await frames(20)
	check(session.return_point.distance_to(exit_node.arrival_global()) < .5 and session.state.region_id == "mountain","retorno do forte é a laje do esqui")
	# Sair pela porta redonda devolve ao esqui.
	fort = session.room
	world.player.teleport(fort.exit_position)
	await frames(10)
	check(session.nearest().get("id","") == "exit","porta do cofre oferece sair")
	await session.leave_place()
	await frames(30)
	check(session.state.place_id.is_empty() and session.state.region_id == "mountain" and world.player.global_position.distance_to(exit_node.arrival_global()) < 3.0,"sai do forte de volta ao esqui")
	print("FORT_ASCENT PASS checks=%d failures=%d"%[checks,failures])
	world.free()
	await process_frame
	quit(1 if failures else 0)
