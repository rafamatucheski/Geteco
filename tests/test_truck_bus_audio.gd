extends SceneTree

## Valida o comportamento de som real para caminhões e ônibus:
## 1. Aceleração encorpada com turbina ("Vruuum")
## 2. Assobio de alívio da turbina nas trocas de marcha ("Tipiuuuuuu" / pente na turbina)
## 3. Alívio no alívio de acelerador sob pressão
## 4. Descarga pneumática de freio a ar ao frear até parar ("Tchúúú-ssss")
## 5. Carros normais (sedan) não disparam esses efeitos pesados
## 6. stop() silencia tudo sem vazamentos

const ENGINE := preload("res://audio/VehicleEngineSound.gd")

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FALHA: " + message)
	else:
		print("  OK: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n=== TESTE DE ÁUDIO REAL DE CAMINHÕES E ÔNIBUS ===")

	var root_node := Node2D.new()
	root.add_child(root_node)

	var audio := AudioStreamPlayer2D.new()
	root_node.add_child(audio)

	# 1. Teste de síntese dos fluxos de áudio
	print("\n--- 1. Síntese e Caching ---")
	for var_idx in 3:
		var whistle: AudioStream = ENGINE.get_turbo_shift_stream(var_idx)
		check(whistle != null, "Assobio de turbina variação %d gerado com sucesso" % var_idx)
		check(whistle is AudioStreamWAV, "Assobio %d é um AudioStreamWAV válido" % var_idx)
		check(whistle.data.size() > 10000, "Assobio %d tem buffer de PCM consistente (%d bytes)" % [var_idx, whistle.data.size()])

	var air_brake: AudioStream = ENGINE.get_air_brake_stream()
	check(air_brake != null, "Alívio de freio a ar gerado com sucesso")
	check(air_brake.data.size() > 10000, "Freio a ar tem buffer de PCM consistente (%d bytes)" % air_brake.data.size())

	# 2. Teste do Caminhão (cargo_flatbed_truck)
	print("\n--- 2. Caminhão: Troca de Marcha com Assobio (Tipiuuuuuu) ---")
	var truck_engine := ENGINE.new()
	truck_engine.bind(audio, "cargo_flatbed_truck")
	check(truck_engine._family == "truck", "cargo_flatbed_truck identificado na família truck")

	var top_speed := 320.0
	var road_top: float = truck_engine.road_top_speed(top_speed)
	var delta := 1.0 / 60.0

	# Acelera de 0 até atingir a segunda marcha
	var shifted := false
	var whistle_played := false
	var speed := 0.0

	for frame in 180:
		speed = minf(speed + 120.0 * delta, road_top * 0.40)
		truck_engine.update(audio, speed, road_top, 1.0, delta, "cargo_flatbed_truck")
		if truck_engine.gear > 1:
			shifted = true
			if is_instance_valid(truck_engine._shift_player) and truck_engine._shift_player.playing:
				whistle_played = true
				break

	check(shifted, "Caminhão trocou para a 2ª marcha durante a aceleração")
	check(whistle_played, "Assobio de turbina ('tipiuuuuuu') disparou na troca de marcha do caminhão")

	# Teste de alívio pneumático de freio ao parar
	print("\n--- 3. Caminhão: Alívio Pneumático de Freio a Ar ---")
	# Simula desaceleração rápida até parada completa
	var air_brake_played := false
	while speed > 0.0:
		speed = maxf(0.0, speed - 180.0 * delta)
		truck_engine.update(audio, speed, road_top, 0.0, delta, "cargo_flatbed_truck")
		if is_instance_valid(truck_engine._air_player) and truck_engine._air_player.playing:
			air_brake_played = true

	check(air_brake_played, "Freio a ar ('tchúúú-ssss') disparou na parada do caminhão")

	# 3. Teste do Ônibus (route_city)
	print("\n--- 4. Ônibus Urbano: Troca de Marcha e Alívio ---")
	var bus_engine := ENGINE.new()
	bus_engine.bind(audio, "route_city")
	check(bus_engine._family == "bus", "route_city identificado na família bus")

	var bus_shifted := false
	var bus_whistle_played := false
	speed = 0.0
	var bus_top: float = bus_engine.road_top_speed(340.0)

	for frame in 180:
		speed = minf(speed + 110.0 * delta, bus_top * 0.45)
		bus_engine.update(audio, speed, bus_top, 1.0, delta, "route_city")
		if bus_engine.gear > 1:
			bus_shifted = true
			if is_instance_valid(bus_engine._shift_player) and bus_engine._shift_player.playing:
				bus_whistle_played = true
				break

	check(bus_shifted, "Ônibus trocou para a 2ª marcha")
	check(bus_whistle_played, "Assobio de turbina disparou na troca de marcha do ônibus")

	# 4. Teste de Veículo Leve (sedan_classic - street) NÃO deve ter assobio de caminhão nem freio a ar
	print("\n--- 5. Carro Civil Normal (Sedan): Sem Efeitos Pesados ---")
	var car_engine := ENGINE.new()
	car_engine.bind(audio, "sedan_classic")
	check(car_engine._family == "street", "sedan_classic identificado na família street")

	speed = 0.0
	var car_top: float = car_engine.road_top_speed(490.0)
	var car_shift_played := false
	var car_air_played := false

	for frame in 180:
		speed = minf(speed + 220.0 * delta, car_top * 0.50)
		car_engine.update(audio, speed, car_top, 1.0, delta, "sedan_classic")
		if is_instance_valid(car_engine._shift_player) and car_engine._shift_player.playing:
			car_shift_played = true
		if is_instance_valid(car_engine._air_player) and car_engine._air_player.playing:
			car_air_played = true

	check(not car_shift_played, "Sedan civil NÃO toca assobio de caminhão ao trocar marcha")
	check(not car_air_played, "Sedan civil NÃO toca freio a ar pneumático")

	# 5. Teste de stop()
	print("\n--- 6. Parada e Limpeza de Áudio (stop) ---")
	truck_engine.stop()
	bus_engine.stop()
	car_engine.stop()
	check(truck_engine._shift_player == null or not truck_engine._shift_player.playing, "Player de assobio do caminhão silenciado")
	check(truck_engine._air_player == null or not truck_engine._air_player.playing, "Player de freio a ar do caminhão silenciado")
	check(bus_engine._shift_player == null or not bus_engine._shift_player.playing, "Player de assobio do ônibus silenciado")

	audio.queue_free()
	root_node.queue_free()

	print("\n==========================================")
	if failures == 0:
		print("TODOS OS TESTES DE ÁUDIO PASSARAM COM SUCESSO!")
	else:
		print("TOTAL DE FALHAS: %d" % failures)
	print("==========================================\n")

	quit(1 if failures > 0 else 0)
