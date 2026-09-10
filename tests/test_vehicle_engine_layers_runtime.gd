extends SceneTree

## Dirige carros de verdade dentro da árvore de cena e confere o que o motor de
## som faz em runtime — não só o que o sintetizador produz no buffer.
##
## O que uma suíte só de buffer NÃO pega e este teste pega: as camadas extras
## são players irmãos criados durante o _physics_process do carro, então erro de
## reparent, camada que continua tocando depois de sair do veículo, ou vazamento
## de um player por quadro só aparecem com o nó vivo.

## HarborPreview traz um PlayerCar montado com Camera/InteractArea, que o script
## exige por @onready. Trocar o arquétipo nele também exercita o caminho de
## apply_archetype -> _refresh_vehicle_sound_sets, onde a família muda com o
## carro já vivo.
const PREVIEW := "res://world/harbor/HarborPreview.tscn"
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _init() -> void:
	call_deferred("run")

func _players(car: Node) -> int:
	var count := 0
	for child in car.get_children():
		if child is AudioStreamPlayer2D:
			count += 1
	return count

## Só os players do motor: o carro tem rádio, buzina e derrapagem pendurados no
## mesmo nó, e eles têm ciclo de vida próprio.
func _engine_players(car: Node) -> Array:
	var players: Array = [car.engine_audio]
	players.append_array(car._engine_sound._layer_players)
	players.append(car._engine_sound._road_player)
	return players

func _audible_layers(car: Node) -> int:
	var count := 0
	for player in _engine_players(car):
		if is_instance_valid(player) and player.playing and player.volume_db > -45.0:
			count += 1
	return count

## Impõe a rampa de velocidade em vez de contar com o acelerador: o objetivo
## aqui é varrer a faixa toda do motor, não medir a física (que já tem teste
## próprio). Sem isso os veículos pesados mal saem do lugar contra o atrito.
func _drive(car: Node, frames: int) -> void:
	var top: float = car._engine_sound.road_top_speed(car.max_speed)
	for i in frames:
		car.velocity = car.transform.x * top * (float(i) + 1.0) / float(frames)
		await physics_frame

func run() -> void:
	var scene = load(PREVIEW).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 6:
		await physics_frame
	var car = scene.get_node("PlayerCar")

	# Um de cada família que o pedido nomeou, mais o sedan de referência.
	for archetype in ["sedan_classic", "sport_coupe", "cargo_flatbed_truck", "route_city", "winter_suv_heavy", "cobra_v8"]:
		car.apply_archetype(archetype)
		car.is_driven_by_player = true
		car.velocity = Vector2.ZERO
		for i in 4:
			await physics_frame
		var family: String = car._engine_sound.family_for_vehicle(archetype)
		check(car._engine_sound._family == family, "%s liga na família %s no _ready (deu '%s')" % [archetype, family, car._engine_sound._family])

		var before := _players(car)
		await _drive(car, 90)
		var after := _players(car)
		check(after - before <= 3, "%s cria no máximo três players extras (duas camadas + rolagem), criou %d" % [archetype, after - before])
		check(_audible_layers(car) >= 1, "%s tem motor audível dirigindo" % archetype)
		var driving_hz: float = car._engine_sound.engine_hz
		check(driving_hz > 0.0, "%s reporta frequência de ignição enquanto anda" % archetype)
		print("RUNTIME %-20s familia=%-12s vel=%.0f/%.0f marcha=%d hz=%.0f camadas=%d" % [
			archetype, family, car.velocity.length(), car._engine_sound.road_top_speed(car.max_speed),
			car._engine_sound.gear, driving_hz, _audible_layers(car),
		])
		check(car._engine_sound.gear > 1, "%s já trocou de marcha acelerando de zero à máxima" % archetype)

		# Estabiliza para confirmar que nenhum player nasce por quadro.
		var settled := _players(car)
		await _drive(car, 60)
		check(_players(car) == settled, "%s não vaza um player por quadro (%d -> %d)" % [archetype, settled, _players(car)])

		car.exit_vehicle()
		for i in 6:
			await physics_frame
		check(_audible_layers(car) == 0, "%s silencia TODAS as camadas ao sair do veículo" % archetype)

	# Caminhão e esportivo têm que soar em faixas diferentes na mesma fração da
	# própria velocidade máxima: é o pedido "caminhão tem que ter som de
	# caminhão, esportivo som de esportivo" transformado em número.
	var probe := AudioStreamPlayer2D.new()
	root.add_child(probe)
	var readings := {}
	for archetype in ["cargo_flatbed_truck", "route_city", "sport_coupe", "cobra_v8", "winter_suv_heavy", "sedan_classic"]:
		var engine = preload("res://audio/VehicleEngineSound.gd").new()
		var top: float = engine.road_top_speed(float(VehicleCatalog.get_vehicle_spec(archetype).get("max_speed", 400.0)))
		for i in 120:
			engine.update(probe, top * 0.95, top, 1.0, 1.0 / 60.0, archetype)
		readings[archetype] = engine.engine_rpm
	print("GIRO_A_95_PORCENTO_RPM ", readings)
	check(readings.cargo_flatbed_truck < readings.sport_coupe * 0.45,
		"O caminhão a fundo gira muito abaixo do esportivo (%.0f rpm contra %.0f rpm)" % [readings.cargo_flatbed_truck, readings.sport_coupe])
	check(readings.route_city < readings.sedan_classic * 0.6,
		"O ônibus gira bem abaixo do sedan (%.0f rpm contra %.0f rpm)" % [readings.route_city, readings.sedan_classic])
	check(readings.winter_suv_heavy < readings.sedan_classic,
		"O SUV pesado gira abaixo do sedan (%.0f rpm contra %.0f rpm)" % [readings.winter_suv_heavy, readings.sedan_classic])
	for archetype in readings:
		check(readings[archetype] > 1500.0 and readings[archetype] < 8200.0,
			"%s a fundo fica numa rotação plausível para o tipo de motor (%.0f rpm)" % [archetype, readings[archetype]])
	probe.queue_free()

	await physics_frame
	print("VEHICLE_ENGINE_LAYERS_RUNTIME failures=%d" % failures)
	quit(1 if failures else 0)
