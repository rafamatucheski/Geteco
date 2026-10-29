extends SceneTree
## Carro passando por cima de corpo caído (playtest 29/10): a ~8 m/s espirra sangue no chão, banha
## o pneu e toca o esmagamento uma vez por passada; parado ou rastejando não; o mesmo corpo não
## repete dentro do cooldown; GETECO_RUNOVER_GORE=0 (runover_gore falso) desliga tudo.
const ACTOR := preload("res://scripts/Actor.gd")
const SQUISH := preload("res://gameplay/street_physics/RunOverSquish.gd")
class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		blood = BLOOD.new()
		add_child(blood)
		tracks = TRACKS.new()
		tracks.director = self
		add_child(tracks)
		_setup_audio()
		SQUISH.prewarm()
		set_physics_process(false)
class Car extends CharacterBody3D:
	var half_length := 2.3
	var half_width := 1.0
	var horizontal_velocity := Vector3.ZERO
var world: Node3D
var street: Street
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func car_at(point: Vector3) -> Car:
	var car := Car.new()
	world.add_child(car)
	car.global_position = point
	return car
## Desloca os carros em linha reta (rumo -Z) chamando o teste de esmagamento a cada passo de
## física, como o vehicle_pre_move faz no jogo. Devolve os esmagamentos de cada carro.
func drive(cars: Array, speed: float, distance: float) -> Array[int]:
	var hits: Array[int] = []
	hits.resize(cars.size())
	hits.fill(0)
	var travelled := 0.0
	var velocity := Vector3(0, 0, -speed)
	var guard := 0
	while travelled < distance and guard < 2000:
		guard += 1
		await physics_frame
		var step := speed / 60.0
		for index in cars.size():
			cars[index].horizontal_velocity = velocity
			hits[index] += street.run_over_downed(cars[index], velocity)
			cars[index].global_position += Vector3(0, 0, -step)
		travelled += step
	return hits
func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, .2, 60)
	shape.shape = box
	ground.add_child(shape)
	world.add_child(ground)
	ground.position = Vector3(0, -.1, 0)
	street = Street.new()
	world.add_child(street)
	var body = ACTOR.new()
	body.controlled_automatically = true
	world.add_child(body)
	body.teleport(Vector3(0, .04, 0))
	for tick in 3: await physics_frame
	body.receive_damage(float(body.health) + 500.0, null)
	for tick in 10: await physics_frame
	check(body.dead == true, "corpo morto no chão")
	street.refresh_downed([body])
	check(street._downed.has(body), "corpo morto entra na lista de caídos")

	# Parado em cima do corpo e rastejando: nada.
	var parked := car_at(Vector3(0, .04, 0))
	for tick in 20:
		await physics_frame
		street.run_over_downed(parked, Vector3.ZERO)
	check(street.runover_sounds == 0 and street.runover_hits == 0, "carro parado sobre o corpo não esmaga")
	var creeping := street.run_over_downed(parked, Vector3(0, 0, -1.0))
	check(creeping == 0 and street.runover_sounds == 0, "carro a 1 m/s não esmaga")
	parked.queue_free()
	await physics_frame

	# Passada a ~8 m/s: uma mancha nova (respingo + poça), som uma vez, pneu banhado.
	var stains_before: int = street.blood.stains.size()
	var car := car_at(Vector3(0, .04, 7))
	# Um segundo carro 5 m atrás (~0,6 s, dentro de RUNOVER_COOLDOWN_MS) passa pelo mesmo corpo.
	var follower := car_at(Vector3(0, .04, 12))
	var both := await drive([car, follower], 8.0, 15.0)
	var hits: int = both[0]
	check(hits == 1 and street.runover_sounds == 1, "passada a 8 m/s esmaga uma vez (%d, som %d)" % [hits, street.runover_sounds])
	check(street.blood.stains.size() > stains_before, "passada gera mancha no chão (%d -> %d)" % [stains_before, street.blood.stains.size()])
	var track: Dictionary = street.tracks._tracks.get(car.get_instance_id(), {})
	check(not track.is_empty() and track.kind == "tire" and float(track.residue) > 0.0, "pneu sai banhado de sangue")
	var played := false
	for player in street._audio:
		if player.stream != null and SQUISH.takes().has(player.stream): played = true
	check(played and SQUISH.takes().size() == SQUISH.TAKES, "esmagamento sintetizado tocou num player retido")
	check(int(body.get_meta("street_runover_count", 0)) == 1, "corpo registra uma passada")

	var follow_hits: int = both[1]
	check(follow_hits == 0 and street.runover_sounds == 1, "segundo carro dentro do cooldown não repete (%d)" % follow_hits)
	# Passada lenta (2,5 m/s, ~2,3 s sob o carro) depois do cooldown: conta uma vez só.
	var wait_until := Time.get_ticks_msec() + street.RUNOVER_COOLDOWN_MS + 100
	while Time.get_ticks_msec() < wait_until: await physics_frame
	var slow_hits: int = (await drive([car_at(Vector3(0, .04, 4.5))], 2.5, 9.0))[0]
	check(slow_hits == 1 and street.runover_sounds == 2, "passada lenta depois do cooldown esmaga uma vez (%d)" % slow_hits)

	# Interruptor desligado: nada, nem a lista é mantida.
	street.runover_gore = false
	wait_until = Time.get_ticks_msec() + street.RUNOVER_COOLDOWN_MS + 100
	while Time.get_ticks_msec() < wait_until: await physics_frame
	street.refresh_downed([body])
	var off_hits: int = (await drive([car_at(Vector3(0, .04, 7))], 8.0, 14.0))[0]
	check(off_hits == 0 and street.runover_sounds == 2 and street._downed.is_empty(), "GETECO_RUNOVER_GORE=0 desliga")

	# Corpo ainda voando não é "caído".
	street.runover_gore = true
	body.set_meta("street_flying", true)
	street.refresh_downed([body])
	check(street._downed.is_empty(), "corpo em voo fica fora da lista")
	body.remove_meta("street_flying")

	world.queue_free()
	await process_frame
	print("RESULT %s (%d falhas)" % ["OK" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
