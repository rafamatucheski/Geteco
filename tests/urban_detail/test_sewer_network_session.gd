extends SceneTree
## Rede de bueiros de Harbor pela sessão integrada: para cada bueiro novo, a tampa existe na calçada, a entrada
## (andar, tampa, escada) leva à sala certa, os moradores aparecem e falam, as recompensas são coletadas pelo
## laço normal do FullSession e a saída devolve o jogador à calçada com os controles livres.
## Uso obrigatório: -- --no-save --skip-arrival
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
var world
var failures: Array[String] = []
var premature_darkness := false
var prepared_darkness_observed := false

func observe_entry_darkness() -> void:
	for node in world.find_children("*", "CanvasLayer", true, false):
		if node.get_script() != preload("res://world/places/sewers/SewerDarkness.gd"): continue
		if world.session.state.place_id.is_empty():
			prepared_darkness_observed = true
			if node.visible: premature_darkness = true

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		print("FAIL rode com -- --no-save: o teste coleta recompensas e não pode tocar no save real")
		quit(1)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "mundo integrado inicia")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var state = session.state
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="): only = arg.trim_prefix("only=")
	for id in SEWERS.extra_ids():
		if only != "" and id != only: continue
		var definition := PLACES.get_definition(id)
		var access: Vector3 = definition.entry_position
		session.controller.region.set_focus(access)
		world.player.teleport(access + Vector3(-1.0, 0.08, 0.0))
		for i in 30: await physics_frame
		var hatch: Node3D = session._find_sewer_hatch(id)
		check(is_instance_valid(hatch), id + ": tampa carregada na calçada")
		if not is_instance_valid(hatch): continue
		check(hatch.name == id and is_zero_approx(hatch.open_amount), id + ": tampa fechada e com o nome do lugar")
		var action: Dictionary = session.nearest()
		check(action.get("id", "") == "enter" and action.get("place", "") == id, id + ": E leva ao bueiro certo")
		var started := Time.get_ticks_msec()
		premature_darkness = false
		prepared_darkness_observed = false
		process_frame.connect(observe_entry_darkness)
		var entered: bool = await session.enter_place(id, false, id)
		process_frame.disconnect(observe_entry_darkness)
		check(prepared_darkness_observed and not premature_darkness, id + ": rua permanece sem escurecimento durante preparação e descida")
		check(entered and state.place_id == id, id + ": entra pela escada e chega na sala (%d ms)" % (Time.get_ticks_msec() - started))
		if not entered: continue
		var room: Node3D = session.room
		await process_frame
		await process_frame
		var darkness_visible := false
		for node in room.find_children("*", "CanvasLayer", true, false):
			if node.get_script() == preload("res://world/places/sewers/SewerDarkness.gd") and node.visible: darkness_visible = true
		check(darkness_visible, id + ": escuridão ativa após chegar ao subterrâneo")
		check(room != null and room.definition.id == id, id + ": sala ativa é a certa")
		check(is_zero_approx(hatch.open_amount), id + ": tampa fecha depois da descida")
		check(world.player.is_physics_processing(), id + ": física do Dante volta depois da descida")
		check(session.room_npcs.size() == definition.npcs.size(), id + ": moradores presentes (%d)" % session.room_npcs.size())
		# Conversa: perto do morador a interação existe e abre o diálogo.
		for resident in definition.npcs:
			world.player.teleport(room.to_global(resident.local_position + Vector3(0.0, 0.05, 1.0)))
			for i in 10: await physics_frame
			var talk: Dictionary = session.services.nearest_action() if session.get("services") != null else {}
			check(talk.get("target", "") == resident.id, id + ": " + resident.name + " aparece como Conversar")
			check(session.services.perform(resident.id), id + ": " + resident.name + " fala")
			session.close_menu()
		# Recompensas pelo laço normal.
		for item in definition.rewards:
			world.player.teleport(room.to_global(item.local_position + Vector3(0, 0.05, 0)))
			for i in 30: await physics_frame
			var got: bool = state.world_state.rewards.has(item.id)
			if not got: print("MOTIVO ", item.id, " aviso=", session.notice.text, " armas=", state.economy.owned_weapons() if state.economy.has_method("owned_weapons") else "?")
			check(got, id + ": coleta " + str(item.id))
			if item.kind == "weapon": check(state.owns_weapon(item.item), id + ": recebe a arma " + str(item.item))
		world.player.teleport(room.to_global(definition.exit + Vector3.UP * 0.05))
		var left: bool = await session.leave_place()
		check(left and state.place_id.is_empty(), id + ": sai para a rua")
		for i in 20: await physics_frame
		var back: float = Vector2(world.player.global_position.x - definition.exterior_position.x, world.player.global_position.z - definition.exterior_position.z).length()
		check(back < 3.0, id + ": reaparece junto à tampa (%.2f m)" % back)
		check(not world.player.input_locked, id + ": controles livres na rua")
		check(is_zero_approx(hatch.open_amount), id + ": tampa fechada depois da subida")
	print("SEWER_NETWORK_SESSION failures=", failures)
	world.free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
