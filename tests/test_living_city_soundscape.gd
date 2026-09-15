extends SceneTree
const AUDIO := preload("res://audio/living_city/LivingCityAudio.gd")
var failures: Array[String] = []
var world: Node2D
var soundscape: Node
var player: Node2D
var capture := false
var recorder: AudioEffectRecord
var record_slot := 0
const OUTPUT := "res://docs/measurements/living-city-0910/"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func visit(point: Vector2, label: String) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	await create_timer(2.8).timeout
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + label + ".png")
		recorder.set_recording_active(true)
		await create_timer(5.0).timeout
		recorder.set_recording_active(false)
		check(recorder.get_recording().save_to_wav(OUTPUT + label + ".wav") == OK, "Captura " + label)

func run() -> void:
	create_timer(110).timeout.connect(func(): push_error("Tempo limite da ambientação"); quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		recorder = AudioEffectRecord.new()
		recorder.format = AudioStreamWAV.FORMAT_16_BITS
		record_slot = AudioServer.get_bus_effect_count(0)
		AudioServer.add_bus_effect(0, recorder)
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	state.set_campaign_flag(&"harbor_arrival_seen", true)
	state.set_campaign_flag(&"harbor_arrival_call_complete", true)
	root.get_node("SaveManager").clear_pending_save()
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 30: await process_frame
	player = world.get_node("Player")
	player.set_physics_process(false)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 0.4
	world.weather.is_dark = false
	soundscape = world.get_node("HarborSoundscape")
	var quarter = soundscape.quarter
	var count := soundscape.find_children("*", "AudioStreamPlayer2D", true, false).size()
	check(count == 11, "Onze emissores espaciais fixos, incluindo oficina interior e pátio de sucata")
	var stations := AUDIO.stations()
	check(stations.size() == 8 and stations[0].get_length() > 120 and stations[1].get_length() > 200, "Sete músicas completas e opção desligado")
	check(stations[2].get_length() > 120 and stations[3].get_length() > 120, "Novas estações têm músicas completas")
	check(stations[-1].data.size() == 16000 and stations[-1].data.count(0) == 16000, "Estação desligada contém apenas silêncio")
	check(stations[0] == AUDIO.stations()[0] and stations[0].loop, "Músicas em cache e reprodução contínua")
	check(AUDIO.bed("street").get_length() >= 28 and AUDIO.bed("street") != AUDIO.bed("street", 1), "Ambiente longo com gravações variantes")
	check(AUDIO.detail("gull", 0) != AUDIO.detail("gull", 1), "Gaivotas variam o trecho gravado")
	await visit(Vector2(621, 1160), "01_diner")
	check(quarter.sources.cafe.playing and quarter.sources.cafe_radio.playing, "Café e rádio audíveis nas mesas")
	check(not quarter.sources.indoor_radio.playing and not quarter.sources.garage_radio.playing, "Rádios distantes param de decodificar")
	check(quarter.neighbors.size() == 2 and quarter.neighbors[0].visible, "Dois clientes visíveis no diner")
	quarter.neighbors[0].is_scared = true
	quarter.neighbors[0].panic_timer = 5.0
	await create_timer(1.0).timeout
	check(float(quarter._gains.cafe) < 0.2, "Conversa do café recua quando seus clientes entram em pânico")
	quarter.neighbors[0].is_scared = false
	await visit(Vector2(1700, 1130), "02_terminal")
	check(soundscape.weights.terminal > 0.8 and soundscape.weights.water < 0.01, "Terminal localizado")
	await visit(Vector2(790, 1750), "03_oficina_rua")
	check(quarter.sources.garage_radio.playing and quarter.sources.tools.playing, "Oficina tem rádio e atividade na fachada")
	var garage = world.get_node("Interiors").garage_interior
	await visit(garage.spawn_point.global_position, "04_oficina_dentro")
	check(not quarter.sources.indoor_radio.playing and not quarter.sources.cafe.playing, "Garagem silencia radio e rua")
	check(not quarter.sources.garage_radio.playing and soundscape.weights.workshop > 0.8, "Sem rádio duplicada entre fachada e interior")
	player.is_in_dialogue = true
	await create_timer(1.0).timeout
	check(soundscape.focus_gain <= 0.36 and float(quarter._gains.indoor_radio) <= 0.36, "Rádio e ambiente abrem espaço ao diálogo")
	player.is_in_dialogue = false
	await visit(Vector2(3500, 1700), "05_cais")
	check(soundscape.weights.water > 0.8 and soundscape.weights.workshop < 0.01, "Água gravada substitui a oficina no cais")
	world.weather.time_of_day = 0.85
	world.weather.is_dark = true
	await visit(Vector2(855, 900), "06_noite")
	check(not quarter.sources.courtyard.playing and not quarter._bird.playing, "Pássaros diurnos param à noite")
	await visit(Vector2(7300, -4430), "07_limite_montanha")
	check(soundscape.weights.city < 0.001, "Ruído urbano não acompanha o jogador até a montanha")
	for source in quarter.sources.values():
		check(not source.playing, "Fonte distante suspensa: " + String(source.name))
	check(soundscape.find_children("*", "AudioStreamPlayer2D", true, false).size() == count, "Número de emissores permanece constante durante o percurso")
	check(quarter.sources.cafe.bus == &"Ambient" and quarter.sources.garage_radio.bus == &"Music", "Ambiente e rádio respeitam seus controles de volume")
	# Exercita o receptor de verdade em um veículo do mundo.
	var car: Node2D
	for candidate in get_nodes_in_group("vehicle"):
		if candidate.has_method("_ensure_radio_audio"):
			car = candidate
			break
	check(car != null, "Veículo de trânsito disponível para verificar a rádio")
	if car != null:
		car.set_process(false)
		car.set_physics_process(false)
		# O mixer espacial só avança streams dentro do alcance do ouvinte.
		car.global_position = player.global_position
		var radio: AudioStreamPlayer2D = car._ensure_radio_audio()
		car.is_driven_by_player = true
		radio.stream = stations[0]
		radio.play(12.0)
		await create_timer(0.4).timeout
		var receiver = radio.get_node("RadioReceiver")
		check(radio.bus == &"Music" and receiver._notice.text.contains("PORTO FM"), "Rádio veicular segue Música e identifica a estação")
		car.is_driven_by_player = false
		radio.stop()
		await create_timer(0.2).timeout
		car.is_driven_by_player = true
		radio.play()
		await create_timer(0.2).timeout
		print("RADIO_RESUME backend=", AudioServer.get_driver_name(), " saved=", receiver._saved_position, " playback=", radio.get_playback_position())
		check(radio.get_playback_position() > 11.0, "Sair e voltar ao carro preserva o ponto da música")
		receiver._mute_button.pressed.emit()
		await process_frame
		await process_frame
		check(radio.volume_db == -80.0 and radio.playing, "Mute mantém a música avançando")
		receiver._controls.get_child(2).pressed.emit()
		await process_frame
		await process_frame
		check(car.radio_index == 1 and radio.stream == stations[1] and radio.volume_db == -80.0, "Botão troca estação e preserva mute")
		receiver._mute_button.pressed.emit()
		await process_frame
		await process_frame
		check(radio.volume_db > -80.0, "Botão restaura som")
		radio.stream = stations[-1]
		radio.play()
		await create_timer(0.2).timeout
		check(receiver._notice.text.contains("DESLIGADO") or receiver._notice.text == "RADIO OFF", "Opção desligado identificada")
		car.radio_index = 0
		car.set_physics_process(true)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_R
		key.pressed = true
		Input.parse_input_event(key)
		for i in 8: await physics_frame
		check(car.radio_index == 1, "Segurar R por oito quadros troca apenas uma estação")
		key.pressed = false
		Input.parse_input_event(key)
		car.set_physics_process(false)
		if capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "08_radio_estacao.png")
		car.is_driven_by_player = false
		radio.stop()
	if capture:
		AudioServer.remove_bus_effect(0, record_slot)
	world.queue_free()
	await process_frame
	print("LIVING_CITY: %d falhas" % failures.size())
	quit(0 if failures.is_empty() else 1)
