extends SceneTree
## Captura funcional (não é benchmark) da garagem do Maciota e da vista do porta-malas
## da Monaliza no Main real, em 16:9 (1280x720) e 21:9 (1720x720: mesma proporção e o
## mesmo layout de interface de 3440x1440, que a escala canvas_items reduz a 1720x720).
## Save isolado de fixture; com --no-save não grava saves nem opções do jogador.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/capture/capture_maciota_garage_trunk.gd -- --no-save --label=antes
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const OUTPUT := "res://evidence/maciota-garagem-portamalas-20261021/"
const SIZES := [["16x9", Vector2i(1280, 720)], ["21x9", Vector2i(1720, 720)]]
var world
var label := "antes"
var failures: Array[String] = []
var records: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func frames(count: int) -> void:
	for index in count: await physics_frame

func wait_startup_curtain() -> void:
	for frame in 900:
		var present := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"):
				present = true
				break
		if not present: return
		await process_frame
	failures.append("cortina de início não terminou")

func resize(size: Vector2i) -> void:
	root.size = size
	await frames(12)

func capture(name: String, extra := {}) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var file := OUTPUT + label + "-" + name + ".png"
	if root.get_texture().get_image().save_png(file) != OK: failures.append("captura " + name)
	var row := {"capture": file, "window": str(root.size), "visible_rect": str(root.get_visible_rect().size), "place": world.session.state.place_id,
		"camera_size": world.camera.size, "camera_focus": str(world.camera.focus), "camera_position": str(world.camera.global_position),
		"player": str(world.player.global_position), "prompt": world.session.prompt.text}
	row.merge(extra)
	records.append(row)
	print("MACIOTA_CAPTURE ", JSON.stringify(row))

func ladder_info() -> Dictionary:
	var roofs = world.session.service_roofs
	if roofs == null or not is_instance_valid(roofs.access_visual): return {"ladder": "ausente"}
	var room: Node3D = world.maciota_place.room
	var local: Vector3 = room.to_local(roofs.access_point)
	var facing: Vector3 = room.global_basis.inverse() * (roofs.access_frame * Vector3.BACK)
	return {"ladder_local": str(local.snapped(Vector3.ONE * .01)), "ladder_facing": str(facing.snapped(Vector3.ONE * .01)), "ladder_owner": str(roofs.access_definition.get("id", ""))}

func trunk_spot() -> bool:
	var car = world.session.personal_car._car()
	if not is_instance_valid(car):
		failures.append("Monaliza ausente na baia")
		return false
	var rear: Vector3 = world.session.personal_car._rear()
	var side: Vector3 = car.global_basis.x
	var back: Vector3 = car.global_basis.z
	# Procura um ponto de pé real atrás do carro onde a ação do porta-malas vence.
	for offset in [side * 1.3 + back * .1, -side * 1.3 + back * .1, side * 1.4 - back * .9, -side * 1.4 - back * .9, back * .2, side * .6 + back * .3]:
		var point: Vector3 = rear + offset
		point.y = car.global_position.y + .06
		if not world.session.position_clear(point): continue
		world.player.teleport(point)
		await frames(6)
		if world.session.nearest().get("target", "") == "trunk": return true
	failures.append("nenhum ponto de acesso ao porta-malas")
	return false

## Emulação do enquadramento anterior a 21/10/2026, na mesma sessão e sem trocar arquivos:
## painel centralizado e câmera travada no centro do carro (o que TrunkView fazia antes).
func capture_old_trunk_framing(name: String) -> void:
	var ui = world.session.field_inventory.ui
	var view: Vector2 = ui.get_viewport_rect().size
	ui.card.position = ((view - ui.card.size) * .5).max(Vector2(16, 16))
	var anchor = world.camera.target
	var offset: Vector3 = world.camera.offset
	world.camera.target = world.session.personal_car._car()
	world.camera.offset = Vector3(0, 6.2, 4.6)
	# Troca de alvo com a câmera travada desliza ~1 s (CameraRig): esperar assentar.
	await frames(90)
	await capture(name, {"emulated_old_framing": true})
	world.camera.target = anchor
	world.camera.offset = offset
	ui._layout()
	await frames(90)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args():
		push_error("Captura exige render real e --no-save")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var fixture_folder := FIXTURE.output_dir("maciota-garagem-portamalas-20261021/save")
	var place_entry := Vector3(166, .1, 112)
	var snapshot := FIXTURE.full_snapshot(place_entry, true)
	# Como em test_harbor_service_roofs: a ligação do pós-campanha já aconteceu.
	snapshot.campaign.aftermath = {"call_complete": true}
	var save_path := FIXTURE.write_fixture(fixture_folder, "save.json", snapshot)
	if save_path.is_empty():
		push_error("fixture de save não gravou")
		quit(2)
		return
	await resize(SIZES[0][1])
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 6000:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main não iniciou")
		await finish()
		return
	await wait_startup_curtain()
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	var entry: Vector3 = world.maciota_place.entry_position
	var garage = world.session.garage_rewards
	if garage != null and garage.data.vehicles.has("cobra_boss_ironback"):
		# A Ironback do fim da campanha usa a mesma baia da Monaliza. Só nesta captura (save de
		# fixture, --no-save) ela fica longe, para o porta-malas da Monaliza aparecer na baia.
		var record: Dictionary = garage.data.vehicles["cobra_boss_ironback"]
		record.place_id = ""
		record.position = [entry.x + 400.0, 0.04, entry.z + 400.0]
	# Fora do alcance da porta a pé: a entrada é a transição normal da sessão.
	world.player.teleport(entry + Vector3(0, .08, 4))
	world.production.region.set_focus(entry)
	await frames(20)
	for frame in 600:
		if not world.player.input_locked and not world.session.is_transition_blocked(): break
		await physics_frame
	if world.session.state.place_id != "maciota":
		await world.session.enter_place("maciota", false, "maciota")
	await frames(10)
	if world.session.state.place_id != "maciota":
		print("MACIOTA_CAPTURE_ENTRY place=", world.session.state.place_id, " transition=", world.session.transition_kind, " locked=", world.player.input_locked, " driving=", world.driving.occupied, " room=", world.session.room)
		failures.append("entrar na garagem")
		await finish()
		return
	await frames(90)
	for row in SIZES:
		await resize(row[1])
		await capture("garagem-" + row[0], ladder_info())
	var roofs = world.session.service_roofs
	if is_instance_valid(roofs.access_visual):
		world.player.teleport(roofs.access_point)
		await frames(20)
		for row in SIZES:
			await resize(row[1])
			await capture("escada-" + row[0], ladder_info())
	else:
		failures.append("escada da cobertura ausente")
	if await trunk_spot():
		if not world.session.personal_car.perform("trunk"): failures.append("abrir porta-malas")
		await frames(60)
		for row in SIZES:
			await resize(row[1])
			await frames(20)
			var card: Control = world.session.field_inventory.ui.card if world.session.field_inventory != null else null
			var card_rect := str(card.get_global_rect()) if is_instance_valid(card) else ""
			await capture("portamalas-" + row[0], {"inventory_card": card_rect, "camera_target": str(world.camera.target.name) if is_instance_valid(world.camera.target) else ""})
			if "--emulate-old-trunk" in OS.get_cmdline_user_args(): await capture_old_trunk_framing("portamalas-antes-emulado-" + row[0])
		world.session.close_menu()
		await frames(90)
		await capture("portamalas-fechado-" + SIZES[-1][0])
	await finish()

func finish() -> void:
	var report := {"type": "functional_render_capture_not_benchmark", "label": label, "engine": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"records": records, "failures": failures,
		"notes": "Main de produção com save de fixture isolado, despacho desligado, entrada direta na garagem. Teleportes de preparo. Não mede FPS nem certifica colisão/oclusão."}
	var file := FileAccess.open(OUTPUT + label + "-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MACIOTA_CAPTURE_DONE failures=", failures)
	if is_instance_valid(world): world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
