extends SceneTree

const ENGINE := preload("res://audio/VehicleEngineSound.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

## Nível audível somado de todas as camadas. Com crossfade o volume de um player
## sozinho não descreve mais o motor: a camada de marcha lenta emudece quando o
## giro sobe e quem carrega o som é a de cima.
func _audible_db(engine, audio: AudioStreamPlayer2D) -> float:
	var linear := 0.0
	if audio.playing:
		linear += db_to_linear(audio.volume_db)
	for player in engine._layer_players:
		if is_instance_valid(player) and player.playing:
			linear += db_to_linear(player.volume_db)
	return linear_to_db(maxf(linear, 0.000001))

## Maior esticamento aplicado a uma camada que esteja realmente audível. É o
## número que separa motor de chiptune: reamostrar muito além de 2x deixa o
## timbre com aquele caráter de sintetizador que o pedido chamou de
## "computadorizado".
func _worst_audible_stretch(engine, audio: AudioStreamPlayer2D) -> float:
	var worst := 1.0
	var players: Array = [audio]
	players.append_array(engine._layer_players)
	for player in players:
		if is_instance_valid(player) and player.playing and player.volume_db > -45.0:
			var stretch: float = maxf(player.pitch_scale, 1.0 / maxf(player.pitch_scale, 0.001))
			worst = maxf(worst, stretch)
	return worst

func _settle(engine, audio: AudioStreamPlayer2D, speed: float, throttle: float, frames: int, vehicle_id: String) -> void:
	for i in frames:
		engine.update(audio, speed, 500.0, throttle, 1.0 / 60.0, vehicle_id)

func _run() -> void:
	var audio := AudioStreamPlayer2D.new()
	root.add_child(audio)

	# --- marcha lenta, acelerada parado e volta -----------------------------
	var engine := ENGINE.new()
	_settle(engine, audio, 0.0, 0.0, 90, "sedan_classic")
	var idle_hz: float = engine.engine_hz
	var idle_db := _audible_db(engine, audio)
	check(idle_hz > 10.0 and idle_hz < 40.0, "Marcha lenta fica na faixa de um quatro cilindros: %.1f Hz" % idle_hz)
	_settle(engine, audio, 0.0, 1.0, 90, "sedan_classic")
	check(engine.engine_hz > idle_hz * 1.6, "Acelerar parado sobe o giro sem o carro andar: %.1f -> %.1f Hz" % [idle_hz, engine.engine_hz])
	check(_audible_db(engine, audio) > idle_db, "Acelerar parado também sobe o volume")
	_settle(engine, audio, 0.0, 0.0, 120, "sedan_classic")
	check(absf(engine.engine_hz - idle_hz) < idle_hz * 0.08, "Soltar o acelerador volta para a marcha lenta")

	# --- escada de marchas --------------------------------------------------
	engine.update(audio, 90.0, 500.0, 1.0, 0.1, "sedan_classic")
	check(engine.gear == 1, "A primeira marcha ainda está engatada a 18%% da máxima")
	engine.update(audio, 145.0, 500.0, 1.0, 0.1, "sedan_classic")
	check(engine.gear == 2, "Acelerando, engata a segunda")
	var rpm_after_shift: float = engine.rpm
	check(rpm_after_shift < 0.98, "Ao engatar a próxima marcha o giro CAI (%.2f): é essa serra que soa como troca de marcha" % rpm_after_shift)
	check(engine.shift_remaining > 0.0, "A troca corta torque e giro")
	engine.update(audio, 130.0, 500.0, 1.0, 0.1, "sedan_classic")
	check(engine.gear == 2, "A histerese evita subir e descer marcha em cima do limiar")

	# --- arrancada completa -------------------------------------------------
	var road_engine := ENGINE.new()
	var road_top: float = ENGINE.road_top_speed(500.0)
	var road_speed := 0.0
	var shift_times: Array[float] = []
	var last_gear := 1
	var time_to_top := 0.0
	for frame in 1800:
		road_speed = minf(road_top, road_speed + 880.0 * road_engine.drive_force(road_speed, 500.0) / 60.0)
		road_engine.update(audio, road_speed, road_top, 1.0, 1.0 / 60.0, "sedan_classic")
		if road_engine.gear > last_gear:
			shift_times.append(frame / 60.0)
		last_gear = road_engine.gear
		if time_to_top <= 0.0 and road_speed >= road_top * 0.97:
			time_to_top = frame / 60.0
	check(shift_times.size() == 5, "A arrancada passa pelas seis marchas do sedan: %s" % str(shift_times))
	check(shift_times[0] > 0.20, "A primeira marcha dura tempo de ser ouvida (%.2fs)" % shift_times[0])
	# O relato foi "parece que chega no final muito rápido". A curva antiga
	# entregava 45%% da força na velocidade máxima e vencia a escada inteira em
	# 1.8 s; a nova cai com o quadrado da velocidade e o último terço leva o
	# dobro do tempo, sem mexer na largada.
	check(time_to_top > 2.6, "Chegar perto da velocidade máxima leva vários segundos (%.2fs)" % time_to_top)
	var previous_span := 0.0
	var lengthening := true
	for i in shift_times.size():
		var span: float = shift_times[i] - (shift_times[i - 1] if i > 0 else 0.0)
		if span < previous_span - 0.01:
			lengthening = false
		previous_span = span
	check(lengthening, "Cada marcha demora mais que a anterior, como numa caixa real: %s" % str(shift_times))

	# --- crossfade das camadas ---------------------------------------------
	var layer_engine := ENGINE.new()
	_settle(layer_engine, audio, 0.0, 0.0, 90, "sedan_classic")
	check(audio.playing and audio.volume_db > -45.0, "Na marcha lenta quem toca é a camada de baixo giro")
	var worst_stretch := 1.0
	var high_share_at_top := 0.0
	for step in 40:
		var speed: float = road_top * float(step) / 39.0
		for i in 20:
			layer_engine.update(audio, speed, road_top, 1.0, 1.0 / 60.0, "sedan_classic")
		worst_stretch = maxf(worst_stretch, _worst_audible_stretch(layer_engine, audio))
		if step == 39:
			var top_player: AudioStreamPlayer2D = layer_engine._layer_players.back()
			high_share_at_top = db_to_linear(top_player.volume_db) if top_player.playing else 0.0
	check(worst_stretch < 2.05, "Nenhuma camada audível é esticada além de 2x (pior: %.2fx)" % worst_stretch)
	check(high_share_at_top > 0.0, "Na velocidade máxima quem toca é a camada de alto giro")
	check(layer_engine.rpm < 0.9, "Sobremarcha deixa reserva de giro na máxima de rua")
	var cruise_min := INF
	var cruise_max := -INF
	for i in 360:
		layer_engine.update(audio, road_top, road_top, 1.0, 1.0 / 60.0, "sedan_classic")
		var level := _audible_db(layer_engine, audio)
		cruise_min = minf(cruise_min, level)
		cruise_max = maxf(cruise_max, level)
	check(cruise_max - cruise_min > 0.5 and cruise_max - cruise_min < 2.5, "Escape varia suavemente em velocidade constante")

	# --- famílias -----------------------------------------------------------
	var expected_family := {
		"sedan_classic": "street", "sport_coupe": "sport", "muscle_classic": "muscle",
		"cobra_v8": "muscle", "winter_suv_heavy": "suv", "summit_suv": "suv",
		"courier_van": "diesel", "cargo_flatbed_truck": "truck", "route_city": "bus",
		"rescue_pumper": "fire_diesel", "medic_box": "ambulance", "police_cruiser": "police",
		"metro_hatch": "sport", "ranch_pickup": "suv", "snow_plow_truck": "truck",
	}
	for id in expected_family:
		check(ENGINE.family_for_vehicle(id) == expected_family[id],
			"%s soa como %s (deu %s)" % [id, expected_family[id], ENGINE.family_for_vehicle(id)])
	check(ENGINE.get_stream("street") == ENGINE.get_stream("street"), "Os laços de motor compartilham recurso em cache")
	var fingerprints := {}
	for family in ["street", "sport", "muscle", "suv", "diesel", "truck", "bus", "fire_diesel", "ambulance", "police"]:
		var layers: Array = ENGINE.get_layer_streams(family)
		check(layers.size() == 7, "A família %s tem sete camadas de rotação" % family)
		var key := hash(layers[0].data)
		check(not fingerprints.has(key), "O timbre de %s é próprio (colidiu com %s)" % [family, fingerprints.get(key, "")])
		fingerprints[key] = family
		check(hash(layers[0].data) != hash(layers[2].data), "Marcha lenta e alto giro de %s são timbres diferentes" % family)
	# Caminhão e ônibus têm que girar pouco e trocar muito; esportivo o contrário.
	var truck_range: float = float(ENGINE._PROFILES.truck.redline) / float(ENGINE._PROFILES.truck.idle)
	var sport_range: float = float(ENGINE._PROFILES.sport.redline) / float(ENGINE._PROFILES.sport.idle)
	check(truck_range < sport_range * 0.75, "O diesel do caminhão gira numa faixa bem menor que o esportivo (%.1fx contra %.1fx)" % [truck_range, sport_range])
	check(ENGINE._GEARBOX.truck.size() > ENGINE._GEARBOX.muscle.size(), "O caminhão tem muito mais marchas que o muscle")

	# --- nome do veículo no HUD --------------------------------------------
	var hud = load("res://HUD.tscn").instantiate()
	root.add_child(hud)
	hud.show_vehicle_name("Sedan Premier 2.0")
	check(hud.vehicle_name_label.visible and hud.vehicle_name_label.text == "Sedan Premier 2.0", "Entry name appears")
	hud.show_vehicle_name("Infernus GT Turbo")
	check(hud.vehicle_name_label.text == "Infernus GT Turbo", "New entry replaces the previous name")
	await create_timer(4.4).timeout
	check(not hud.vehicle_name_label.visible, "Vehicle name disappears automatically")
	hud.show_vehicle_name("Infernus GT Turbo")
	check(hud.vehicle_name_label.visible, "Entering the same car again shows its name again")
	hud.queue_free()
	audio.queue_free()
	await process_frame
	print("VEHICLE_ENGINE_AND_NAME failures=%d" % failures)
	quit(1 if failures else 0)
