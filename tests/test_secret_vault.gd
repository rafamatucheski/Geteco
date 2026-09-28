extends SceneTree
## Cofre do setor lacrado no jogo real: dígitos, energia, portão, teclado, travessia
## para o forte e volta. Exige --no-save. Movimento por Actor.gd (sem teleporte
## entre pontos de uma mesma etapa).

var world
var session
var passage
var tunnel
var progression
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("SECRET_VAULT FAIL "+label)

func settle(frames := 10) -> void:
	for _frame in frames: await process_frame

func walk_to(target: Vector3,limit_ms := 20000) -> bool:
	var started := Time.get_ticks_msec()
	while world.player.global_position.distance_to(target) > .25:
		var direction: Vector3 = target-world.player.global_position
		direction.y = 0
		world.player.automatic_direction = direction.normalized()
		await physics_frame
		if Time.get_ticks_msec()-started > limit_ms:
			world.player.automatic_direction = Vector3.ZERO
			return false
	world.player.automatic_direction = Vector3.ZERO
	return true

func hq(offset: Vector3) -> Vector3:
	return tunnel.to_global(tunnel.HQ_CENTER+offset)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	seed(195107)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 420:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("SECRET_VAULT Main did not become ready")
		quit(1)
		return
	session = world.session
	await settle(120)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	if is_instance_valid(session.world.hud): session.world.hud.hide()
	passage = session.urban_operations.secret_passage
	tunnel = passage.tunnel
	progression = session.urban_operations.secret_network
	progression.receive_dossier()
	for id in progression.FRAGMENT_IDS: progression.collect_fragment(id)
	for id in progression.KEYPAD_CLUE_IDS: progression.discover_keypad_clue(id)
	progression.discover_house()
	progression.unlock_keypad()
	progression.discover_headquarters()
	progression.activate_power_node("power_main")
	progression.activate_power_node("power_drainage")
	progression.activate_route("route_village_house")
	progression.activate_route("route_harbor_sewer")
	progression.discover_sealed_sector()
	passage.refresh_state()
	passage.set_region_active(true)
	tunnel.set_enabled(true)

	# Antes da energia: o quadro e o portão fecham a entrada do setor lacrado.
	check(tunnel.console_body.collision_layer == 1 and tunnel.gate_body.collision_layer == 1,"quadro e portão bloqueiam antes da energia")
	world.player.teleport(hq(Vector3(0,.04,-5.6)))
	await settle(20)
	check(passage.nearest_action().get("target","").ends_with("power_sealed"),"console oferece energizar o setor lacrado")
	check(passage.perform(passage.nearest_action().target),"energizar setor lacrado")
	await settle(150)
	check(progression.has_power_node("power_sealed_sector"),"energia do setor registrada")
	check(tunnel.console_body.collision_layer == 0 and tunnel.gate_body.collision_layer == 0,"quadro e portão liberam a passagem")

	# Caminhada real pelo portão até o pedestal do cofre.
	check(await walk_to(hq(Vector3(0,.04,-8.6))),"atravessa o portão aberto")
	check(await walk_to(tunnel.vault_console_global()),"chega ao pedestal do cofre sem cair nem prender")
	check(world.player.global_position.y > tunnel.global_position.y-.3,"piso do setor lacrado sustenta o jogador")
	var action: Dictionary = passage.nearest_action()
	check(action.get("target","").ends_with("vault_keypad"),"pedestal oferece o teclado do cofre")
	passage._open_vault_keypad()
	check(not progression.can_unlock_final_door() and not progression.data.final_door_unlocked,"teclado recusa sem os quatro dígitos")

	# Os quatro dígitos, cada um no seu objeto.
	var expected := ["3","1","9","4"]
	for index in passage.VAULT_DIGITS.size():
		var entry: Dictionary = passage.VAULT_DIGITS[index]
		world.player.teleport(hq(entry.local))
		await settle(6)
		action = passage.nearest_action()
		check(action.get("target","").ends_with("digit_%d"%index),"objeto %s oferece o dígito"%entry.id)
		check(passage.perform(action.target),"registra %s"%entry.id)
		check(passage.VAULT_CODE[int(entry.digit)] == expected[index],"dígito %d confere"%index)
	check(progression.can_unlock_final_door(),"quatro indícios habilitam a porta final")

	# Código errado, depois o certo.
	world.player.teleport(tunnel.vault_console_global())
	await settle(6)
	passage._keypad_vault = true
	passage._keypad_buffer = "1234"
	passage._submit_keypad()
	check(not progression.data.final_door_unlocked,"código errado não abre")
	passage._keypad_buffer = "3194"
	passage._submit_keypad()
	await settle(120)
	check(progression.data.final_door_unlocked and tunnel.vault_open and tunnel.vault_portal.visible,"código 3194 abre o cofre")
	var restored = progression.get_script().new()
	check(restored.restore_snapshot(progression.snapshot()),"snapshot com o cofre aberto restaura")

	# Travessia para o forte.
	action = passage.nearest_action()
	check(action.get("target","").ends_with("travel_fort"),"pedestal oferece atravessar")
	passage.perform(action.target)
	for _frame in 600:
		await physics_frame
		if session.state.place_id == "mountain_fort" and not session.is_transition_blocked(): break
	check(session.state.place_id == "mountain_fort","entrou no forte")
	if session.state.place_id == "mountain_fort":
		var fort = session.room
		check(fort.solid_bodies.size() > 15,"forte tem inventário físico")
		await settle(10)
		print("VAULT_CAMERA current=",root.get_camera_3d().get_path()," world=",world.camera.get_path()," tunnel_active=",tunnel._active)
		check(root.get_camera_3d() == world.camera,"câmera do mundo é a atual no forte")
		check(fort.is_floor_clear(fort.spawn_position),"ponto de chegada livre")
		check(await walk_to(fort.model.to_global(Vector3(0,.04,1.0))),"caminha do portal até o centro")
		check(await walk_to(fort.model.to_global(Vector3(0,.04,-3.0))),"corredor central até a porta blindada livre")
		check(not await walk_to(fort.model.to_global(Vector3(0,.04,-8.5)),2500),"porta blindada selada bloqueia")
		world.player.automatic_direction = Vector3.ZERO
		world.player.teleport(fort.exit_position)
		await settle(10)
		var exit_action: Dictionary = session.nearest()
		check(exit_action.get("id","") == "exit","porta do cofre oferece sair")
		await session.leave_place()
		await settle(20)
		check(session.state.place_id.is_empty(),"voltou ao mundo")
		check(world.player.global_position.distance_to(tunnel.vault_arrival_global()) < 2.5,"volta ao setor lacrado, diante do cofre")
		check(tunnel.contains(world.player.global_position),"jogador está no túnel ao voltar")
	print("SECRET_VAULT PASS checks=%d failures=%d"%[checks,failures])
	world.free()
	await process_frame
	quit(1 if failures else 0)
