extends SceneTree
## Contagem de fontes da P4 no Main real, sem FPS, spans ou tempo de quadro.
## --no-save --play-at=harbor,64,82; rodar em processos separados com o interruptor ligado/desligado.
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BUDGET := preload("res://gameplay/lights/LightBudget.gd")
var world: Node
var additions: Array[CharacterBody3D] = []
var failures: Array[String] = []
var finishing := false
var capture_rows: Array[Dictionary] = []
var capture_directory := ""

func _initialize() -> void:
	create_timer(240).timeout.connect(func():
		if not finishing:
			push_error("Contagem P4 excedeu o limite de execução; nenhuma contagem aprovada")
			quit(3))
	run.call_deferred()

func count_sources(label: String) -> Dictionary:
	var equipments := 0
	var traffic := 0
	var traffic_active := 0
	var instantiated := 0
	var active := 0
	var decals := 0
	var decals_active := 0
	var sprites := 0
	var sprites_active := 0
	var shadows := 0
	var player_sources := 0
	var family_counts := {}
	for node in world.find_children("*", "", true, false):
		if node.get_script() != EQUIPMENT or not is_instance_valid(node.car): continue
		equipments += 1
		var car: CharacterBody3D = node.car
		if car.traffic: traffic += 1
		var lights: Array[Light3D] = []
		for item: Dictionary in node.lamps: lights.append(item.lamp)
		if is_instance_valid(node.npc_beam): lights.append(node.npc_beam)
		if is_instance_valid(node.halo): lights.append(node.halo)
		for light in lights:
			instantiated += 1
			if not light.is_visible_in_tree() or light.light_energy <= 0: continue
			active += 1
			if light.shadow_enabled: shadows += 1
			if car.traffic: traffic_active += 1
			if car.controlled and not car.external_input: player_sources += 1
		if node.ground_pool is Decal:
			decals += 1
			if node.ground_pool.is_visible_in_tree(): decals_active += 1
		for item: Dictionary in node.glows:
			sprites += 1
			if item.sprite.is_visible_in_tree(): sprites_active += 1
		var family := str(node.profile.get("family", ""))
		family_counts[family] = int(family_counts.get(family, 0)) + 1
	var result := {"scenario":label, "enabled":BUDGET.enabled, "region":world.session.state.region_id,
		"position":[world.player.global_position.x, world.player.global_position.y, world.player.global_position.z],
		"equipment":equipments, "traffic_equipped":traffic, "equipment_sources_instantiated":instantiated,
		"equipment_sources_active":active, "traffic_sources_active":traffic_active, "player_sources_active":player_sources,
		"active_shadows":shadows, "decals_instantiated":decals, "decals_active":decals_active,
		"sprites_instantiated":sprites, "sprites_active":sprites_active, "families":family_counts,
		"scope":"faróis e giroflex de VehicleEquipment; neon, incêndio e outras fontes fora do registro não entram nesta contagem"}
	print("P4_LIGHT_COUNTS ", JSON.stringify(result))
	if BUDGET.enabled:
		if active > 8: failures.append(label + ": mais de oito fontes reais de Equipment")
		if traffic_active != 0: failures.append(label + ": trânsito com fonte real de Equipment")
		if decals_active > 8: failures.append(label + ": mais de oito decals ativos")
	return result

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-save para preservar saves pessoais")
		quit(2)
		return
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("A contagem integrada exige Godot .NET e C# compilado")
		quit(2)
		return
	if "--capture-p4" in OS.get_cmdline_user_args() and DisplayServer.get_name() == "headless":
		push_error("--capture-p4 exige a cena realmente renderizada")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for index in 7200:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main não concluiu admissão")
		finish()
		return
	if "--capture-p4" in OS.get_cmdline_user_args():
		# Protege somente a fixture visual contra respawn; não simula jogo normal.
		world.gameplay.god_mode = true
		world.gameplay._sync_god_mode()
	if not world.session.controller.no_save:
		failures.append("Proteção de save não ativada")
		finish()
		return
	if world.session.state.region_id != "harbor":
		failures.append("Execute no porto com --play-at=harbor,64,82")
		finish()
		return
	world.player.teleport(Vector3(64, .12, 82))
	world.session.controller.region.set_focus(world.player.global_position)
	world.session.weather.time_of_day = .95
	world.session.weather.set_process(false)
	world.session.weather._update()
	world.session.state.world_state.time = .95
	await create_timer(30).timeout
	count_sources("oeste_noturno_producao_30s")

	# A população de produção pode ficar abaixo de 16 por densidade/localização.
	# Esta segunda contagem identifica explicitamente uma carga autorada, sem atribuí-la ao spawn natural.
	var origin := Vector3(51, .12, 70)
	for index in 18:
		var car := VEHICLE.new()
		car.archetype = ["union_sedan", "sedan_classic", "aurora_executive", "vertice_midengine", "arctic_jeep", "route_city"][index % 6]
		car.position = origin + Vector3((index % 6) * 4.5, 0, floorf(index / 6.0) * 7)
		car.traffic = true
		world.add_child(car)
		car.set_physics_process(false)
		if "--capture-p4" in OS.get_cmdline_user_args():
			car.collision_layer = 0
			car.collision_mask = 0
		car.ensure_equipment(world)
		additions.append(car)
	var player_car := VEHICLE.new()
	player_car.archetype = "union_sedan"
	player_car.position = Vector3(64, .12, 82)
	world.add_child(player_car)
	player_car.set_physics_process(false)
	if "--capture-p4" in OS.get_cmdline_user_args():
		player_car.collision_layer = 0
		player_car.collision_mask = 0
	player_car.controlled = true
	player_car.ensure_equipment(world).toggle_headlights()
	additions.append(player_car)
	world.camera.target = player_car
	await create_timer(2).timeout
	var fixture: Dictionary = count_sources("oeste_noturno_carga_autorada_18_transito_1_jogador")
	if fixture.traffic_equipped < 18: failures.append("Carga autorada não tem 18 veículos de trânsito equipados")
	if not player_car.equipment.lamps.all(func(item): return item.lamp.is_visible_in_tree() and item.lamp.light_energy > 0):
		failures.append("Par do jogador apagado na câmera real de gameplay")
	if "--capture-p4" in OS.get_cmdline_user_args(): await capture_sequence(player_car)
	finish()

func set_hour(hour: float) -> void:
	world.session.weather.time_of_day = hour
	world.session.weather._update()
	world.session.state.world_state.time = hour

func capture_frame(label: String) -> bool:
	await RenderingServer.frame_post_draw
	var captured_at := Time.get_ticks_msec()
	var filename := "%04d_%s.png" % [capture_rows.size(), label]
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("Frame renderizado indisponível na captura " + label)
		return false
	var path := capture_directory.path_join(filename)
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		failures.append("Falha ao gravar captura " + path)
		return false
	# Timestamp permite correlacionar eventos; não se calculam intervalos/FPS.
	capture_rows.append({"file":filename, "timestamp_msec":captured_at, "segment":label,
		"camera":[world.camera.global_position.x, world.camera.global_position.y, world.camera.global_position.z]})
	return true

func capture_sequence(player_car: CharacterBody3D) -> void:
	var prefix := "render-on" if BUDGET.enabled else "render-off"
	capture_directory = "res://evidence/otimizacao-p4-20261013/%s-%d" % [prefix, Time.get_ticks_msec()]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory)) != OK:
		failures.append("Pasta de captura indisponível")
		return
	var settings := root.get_node_or_null("V2Settings")
	if settings != null:
		# O contador do usuário sai apenas desta gravação, sem salvar preferências.
		settings.show_fps = false
		settings._update_fps_overlay()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	await create_timer(.25).timeout
	var previous_limit := Engine.max_fps
	# Limita somente a gravação a aproximadamente 900 imagens, sem benchmark.
	Engine.max_fps = 30
	var police := VEHICLE.new()
	police.archetype = "police_cruiser"
	police.position = player_car.position + Vector3(8, 0, 0)
	world.add_child(police)
	police.set_physics_process(false)
	police.collision_layer = 0
	police.collision_mask = 0
	police.controlled = true
	police.external_input = true
	police.ensure_equipment(world)
	additions.append(police)
	set_hour(.5)
	player_car.equipment.headlights_on = false
	player_car.equipment._refresh()
	await create_timer(.25).timeout
	await capture_frame("shot_dia")
	set_hour(.75)
	await create_timer(.25).timeout
	await capture_frame("shot_crepusculo")
	set_hour(.95)
	player_car.equipment.headlights_on = true
	player_car.equipment._refresh()
	await create_timer(.25).timeout
	await capture_frame("shot_noite_jogador_npcs")
	police.equipment.toggle_siren()
	await create_timer(.25).timeout
	await capture_frame("shot_sirene")
	police.equipment.toggle_siren()
	var origin := player_car.position
	var original_heading: float = world.camera.heading
	var first_sequence_frame := capture_rows.size()
	var began := Time.get_ticks_msec()
	var deadline := began + 30000
	var segment := ""
	var siren_started := false
	while Time.get_ticks_msec() < deadline:
		var elapsed: int = Time.get_ticks_msec() - began
		if elapsed < 10000:
			segment = "noite_parado"
		elif elapsed < 20000:
			segment = "noite_camera_movimento"
			var progress := (elapsed - 10000) / 10000.0
			player_car.position = origin + Vector3(sin(progress * TAU) * 9, 0, (1 - cos(progress * TAU)) * 5)
			world.camera.heading = original_heading + progress * PI
		else:
			segment = "noite_sirene_limites"
			if not siren_started:
				siren_started = true
				police.equipment.toggle_siren()
			var progress := (elapsed - 20000) / 10000.0
			player_car.position = origin + Vector3(sin(progress * TAU) * 9, 0, 0)
			world.camera.heading = original_heading + PI + progress * PI
		player_car.equipment._refresh()
		if not await capture_frame(segment): break
	player_car.position = origin
	world.camera.heading = original_heading
	Engine.max_fps = previous_limit
	var manifest := {"enabled":BUDGET.enabled, "started_timestamp_msec":began,
		"finished_timestamp_msec":Time.get_ticks_msec(), "renderer":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(), "resolution":str(root.size), "frames":capture_rows,
		"sequence_first_frame_index":first_sequence_frame, "capture_limit_config":30, "sequence_hour":.95,
		"capture_configuration":"janela1280x720 e overlay desativado somente neste processo, sem salvar Settings; limite30 usado só para volume de PNG",
		"fixture_protection":"god_mode de Gameplay ativo somente no processo; colisão e física desativadas nos carros autorados e viatura da captura; cenário visual não simula jogo normal",
		"scope":"Main renderizado com carga autorada; screenshots e sequência contínua para inspeção visual, sem medição de FPS/tempo de quadro; não certifica performance"}
	var output := FileAccess.open(capture_directory.path_join("manifest.json"), FileAccess.WRITE)
	if output == null: failures.append("Falha ao gravar manifest de captura")
	else: output.store_string(JSON.stringify(manifest, "\t"))
	print("P4_CAPTURE_DIRECTORY ", ProjectSettings.globalize_path(capture_directory))

func finish() -> void:
	finishing = true
	if is_instance_valid(world): world.free()
	await process_frame
	print("P4_COUNT_RESULT failures=", failures, " estado_visual=não_validado estado_performance=não_medido")
	quit(0 if failures.is_empty() else 1)
