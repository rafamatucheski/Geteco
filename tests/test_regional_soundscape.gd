extends SceneTree
const BANK := preload("res://audio/regional/RegionalAudio.gd")
const OUTPUT := "res://docs/measurements/regional-audio-0910/"
var failures: Array[String] = []
var world: Node2D
var player: Node2D
var capture := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func visit(point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	await create_timer(2.0).timeout

func record(label: String, duration: float) -> void:
	if not capture: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	await create_timer(duration).timeout
	recorder.set_recording_active(false)
	check(recorder.get_recording().save_to_wav(OUTPUT+label+".wav") == OK, "Captura " + label)
	AudioServer.remove_bus_effect(0, slot)

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Regional audio timeout"); quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	state.set_campaign_flag(&"harbor_arrival_seen", true)
	state.set_campaign_flag(&"harbor_arrival_call_complete", true)
	root.get_node("SaveManager").clear_pending_save()
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 25: await process_frame
	player = world.get_node("Player")
	player.set_physics_process(false)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .4
	world.weather.is_dark = false
	var soundscape = world.get_node("HarborSoundscape")
	var regional = soundscape.regional
	check(BANK.sound("wind").loop and not BANK.sound("gust").loop, "Base contínua e rajadas com término")
	check(BANK.sound("wind").get_length() > 30 and BANK.sound("scrap", 0) != BANK.sound("scrap", 5), "Arquivos longos e sucata variada")
	var yard: Node2D = get_first_node_in_group("chop_shop")
	await visit(yard.global_position + Vector2(0, 100))
	check(regional.yard_active, "Ferro-velho real ativa sucata por proximidade")
	await record("01_ferro_velho", 13)
	var first: AudioStream = regional.metal.stream
	regional.metal.stop()
	regional._timer = 0
	await create_timer(.15).timeout
	check(regional.metal.playing and regional.metal.stream != first, "Batidas usam variante diferente sem repetição imediata")
	check(regional.metal.global_position.distance_to(yard.global_position) < 700, "Metal vem do pátio")
	yard.art.animating = true
	await create_timer(.1).timeout
	check(not regional.metal.playing, "Ambiente cede espaço à prensa sincronizada")
	yard.art.animating = false
	await visit(Vector2(1700, 1130))
	check(not regional.yard_active and not regional.metal.playing and not regional.sea.playing, "Metal e mar não vazam no centro")
	await visit(Vector2(5900, -3800))
	check(regional.sea_gain < .001, "Acesso terrestre ainda sem ondas")
	await visit(Vector2(6870, -4510))
	check(regional.sea_gain > .9 and regional.sea.playing, "Ondas audíveis sobre o mar na rodovia")
	await record("02_mar_rodovia", 8)
	var car: Node2D
	for candidate in get_nodes_in_group("vehicle"):
		if candidate.has_method("_ensure_radio_audio"):
			car = candidate
			break
	check(car != null, "Veículo real disponível para verificar o ouvinte")
	if car != null:
		car.set_physics_process(false)
		car.set_process(false)
		var original_position := car.global_position
		car.global_position = player.global_position
		car.is_driven_by_player = true
		player.hide()
		player.global_position = Vector2(1700, 1130)
		await create_timer(.8).timeout
		check(regional.sea_gain > .9, "Mar acompanha o veículo com jogador oculto na cabine")
		player.global_position = car.global_position
		player.show()
		car.is_driven_by_player = false
		car.global_position = original_position
	player.is_in_dialogue = true
	await create_timer(.8).timeout
	check(regional.sea.volume_db < -12, "Mar recua durante diálogo")
	player.is_in_dialogue = false
	var stream = world.get_node("ContinuousWorld")
	while not stream.ready_for_crossing: await process_frame
	var mountain = stream.mountain
	var storm = mountain.storm_manager
	var snow = storm.get_node("SnowWindAudio")
	check(not snow.active and not snow.bed.playing, "Serra pré-carregada não toca vento na ponte")
	await visit(Vector2(7900, -4430))
	storm.dynamic_weather = false
	storm.set_storm_state(0)
	storm.storm_intensity = 0.0
	await create_timer(1).timeout
	check(snow.active and snow.bed.playing and not snow.gale.playing, "Neve calma usa brisa sem vendaval")
	check(not regional.sea.playing, "Mar some ao entrar no interior da serra")
	storm.set_storm_state(2)
	storm.storm_intensity = 1.5
	await create_timer(3.8).timeout
	snow._timer = 0
	await create_timer(.2).timeout
	check(snow.gale.playing and snow.strength > .9, "Nevasca acrescenta camada de vento forte")
	await record("03_nevasca", 10)
	var outside_db: float = snow.bed.volume_db
	# Suspende somente a atualização de abrigo para exercitar seu contrato real.
	mountain.set_process(false)
	storm.set_sheltered(true)
	await create_timer(1.2).timeout
	check(snow.bed.volume_db < outside_db - 14 and snow._filter.cutoff_hz < 900 and not snow.gust.playing, "Abrigo abafa vento e cancela rajadas")
	await record("04_abrigo", 5)
	player.set_meta("mountain_interior", true)
	await visit(mountain.interior_manager.cabin_interior.global_position)
	check(soundscape._district_gain == 0.0 and not soundscape.beds.city.playing and not soundscape.beds.terminal.playing, "Cabana fora do mapa não toca vozes da cidade")
	check(snow.bed.playing and storm.sheltered, "Cabana mantém vento de neve abafado")
	player.remove_meta("mountain_interior")
	mountain.set_process(true)
	await visit(Vector2(1700, 1130))
	check(mountain.process_mode == Node.PROCESS_MODE_DISABLED and not snow.bed.playing and not snow.gale.playing and not snow.gust.playing, "Volta à cidade desliga vento mesmo com região suspensa")
	var bus: StringName = snow._bus
	world.queue_free()
	await process_frame
	check(AudioServer.get_bus_index(bus) == -1, "Mixer de neve liberado ao sair do mundo")
	print("REGIONAL_AUDIO: %d falhas" % failures.size())
	quit(0 if failures.is_empty() else 1)
