extends SceneTree
## Entradas subterrâneas do deserto pela sessão integrada: a estrutura externa existe, a entrada (andar, abrir, descer)
## leva à sala certa, os moradores falam, as recompensas são coletadas pelo laço normal e a saída devolve o jogador.
## Uso: -- --no-save [only=<id>] ; um jogo novo por local (a grade de inventário enche com várias armas).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const UNDER := preload("res://world/desert/underground/DesertUnderground.gd")
var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="): only = arg.trim_prefix("only=")
	var id := only if only != "" else UNDER.ids()[0]
	var definition := PLACES.get_definition(id)
	var entry: Vector3 = definition.entry_position
	var folder := FIXTURE.output_dir("desert-underground-" + id)
	var snapshot := FIXTURE.full_snapshot(entry + Vector3(0, 0.08, 3.0), true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region": "desert", "position": [entry.x, 0.08, entry.z + 3.0]}
	var path := FIXTURE.write_fixture(folder, "save.json", snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while (world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled) and Time.get_ticks_msec() < deadline: await physics_frame
	check(world.session != null and world.session.ready_for_play, "mundo integrado inicia no deserto")
	if not failures.is_empty(): quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var session = world.session
	var state = session.state
	check(state.region_id == "desert", id + ": jogo começa no deserto")
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	for i in 30: await physics_frame
	world.player.teleport(entry + Vector3(0, 0.08, 0.0))
	for i in 60: await physics_frame
	var hatch: Node3D = session._find_sewer_hatch(id)
	check(is_instance_valid(hatch), id + ": estrutura externa carregada")
	if not is_instance_valid(hatch): quit(1); return
	check(hatch.name == id and is_zero_approx(hatch.open_amount), id + ": fechada e com o nome do lugar")
	var action: Dictionary = session.nearest()
	check(action.get("id", "") == "enter" and action.get("place", "") == id, id + ": E leva à entrada certa")
	var started := Time.get_ticks_msec()
	var entered: bool = await session.enter_place(id, false, id)
	check(entered and state.place_id == id, id + ": entra e chega na sala (%d ms)" % (Time.get_ticks_msec() - started))
	if not entered: quit(1); return
	var room: Node3D = session.room
	check(room != null and room.definition.id == id, id + ": sala ativa é a certa")
	check(is_zero_approx(hatch.open_amount), id + ": estrutura fecha depois da descida")
	check(world.player.is_physics_processing(), id + ": física do Dante volta depois da descida")
	check(session.room_npcs.size() == definition.npcs.size(), id + ": moradores presentes (%d)" % session.room_npcs.size())
	for resident in definition.npcs:
		world.player.teleport(room.to_global(resident.local_position + Vector3(0.0, 0.05, 1.0)))
		for i in 10: await physics_frame
		var talk: Dictionary = session.services.nearest_action()
		check(talk.get("target", "") == resident.id, id + ": " + resident.name + " aparece como Conversar")
		check(session.services.perform(resident.id), id + ": " + resident.name + " fala")
		session.close_menu()
	for item in definition.rewards:
		world.player.teleport(room.to_global(item.local_position + Vector3(0, 0.05, 0)))
		for i in 30: await physics_frame
		var got: bool = state.world_state.rewards.has(item.id)
		if not got: print("MOTIVO ", item.id, " aviso=", session.notice.text)
		check(got, id + ": coleta " + str(item.id))
	world.player.teleport(room.to_global(definition.exit + Vector3.UP * 0.05))
	var left: bool = await session.leave_place()
	check(left and state.place_id.is_empty(), id + ": sai para o deserto")
	for i in 20: await physics_frame
	var back := Vector2(world.player.global_position.x - entry.x, world.player.global_position.z - entry.z).length()
	check(back < 4.0, id + ": reaparece junto à entrada (%.2f m)" % back)
	check(not world.player.input_locked, id + ": controles livres no deserto")
	check(is_zero_approx(hatch.open_amount), id + ": estrutura fechada depois da saída")
	print("DESERT_UNDERGROUND_SESSION failures=", failures)
	world.free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
