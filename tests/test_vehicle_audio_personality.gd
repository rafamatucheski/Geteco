extends SceneTree

const ENGINE_SOUND := preload("res://audio/VehicleEngineSound.gd")

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _make_voice(name: String) -> AudioStreamPlayer2D:
	var holder := Node2D.new()
	holder.name = name
	root.add_child(holder)
	var voice := AudioStreamPlayer2D.new()
	holder.add_child(voice)
	return voice

func _sweep(engine: RefCounted, voice: AudioStreamPlayer2D, vehicle_id: String, frames := 240) -> void:
	var top: float = engine.road_top_speed(float(VehicleCatalog.get_vehicle_spec(vehicle_id).max_speed))
	for frame in frames:
		var ratio := (float(frame) + 1.0) / float(frames)
		engine.update(voice, top * ratio, top, 1.0, 1.0 / 60.0, vehicle_id)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var forklift_voice := _make_voice("ForkliftVoice")
	var forklift := ENGINE_SOUND.new()
	forklift.bind(forklift_voice, "port_forklift")
	check(forklift._family == "electric", "a empilhadeira usa a família elétrica dedicada")
	check(forklift._gear_tops().size() == 1, "a empilhadeira tem tração direta, sem trocas de marcha")
	_sweep(forklift, forklift_voice, "port_forklift", 180)
	check(forklift.gear == 1, "a empilhadeira permanece em uma única relação")
	check(forklift._shift_player == null, "a empilhadeira não cria apito, flutter ou válvula pneumática")
	check(forklift_voice.volume_db <= -20.0, "o motor elétrico fica discreto no mix")

	var truck_voice := _make_voice("TruckVoice")
	var truck := ENGINE_SOUND.new()
	truck.bind(truck_voice, "cargo_flatbed_truck")
	check(truck._gear_tops().size() == 7, "o caminhão recebeu a sétima relação final")
	_sweep(truck, truck_voice, "cargo_flatbed_truck")
	check(truck.gear == 7, "o caminhão chega à última marcha na varredura")
	check(truck._shift_player == null, "o caminhão não apita a cada troca de marcha")

	var sport_voice := _make_voice("SportVoice")
	var sport := ENGINE_SOUND.new()
	sport.bind(sport_voice, "sport_coupe")
	check(sport._gear_tops().size() == 6, "o cupê esportivo recebeu a sexta marcha")
	_sweep(sport, sport_voice, "sport_coupe")
	check(sport.gear == 6, "o cupê percorre todas as seis marchas")
	check(sport.turbo_release_count > 0, "o turbo do cupê espirra/fluttera nas trocas sob pressão")
	var releases_after_shifts: int = sport.turbo_release_count
	var top: float = sport.road_top_speed(float(VehicleCatalog.get_vehicle_spec("sport_coupe").max_speed))
	for frame in 45:
		sport.update(sport_voice, top * 0.72, top, 1.0, 1.0 / 60.0, "sport_coupe")
	sport.update(sport_voice, top * 0.72, top, 0.0, 1.0 / 60.0, "sport_coupe")
	check(sport.turbo_release_count > releases_after_shifts, "tirar o pé com turbo carregado dispara um novo flutter")
	check(is_instance_valid(sport._shift_player) and sport._shift_player.playing, "o flutter toca numa voz espacial ligada ao carro")

	print("VEHICLE_AUDIO_PERSONALITY failures=%d" % failures)
	quit(1 if failures else 0)
