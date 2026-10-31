extends Node
## Condição do veículo sem loop por quadro: a dirigibilidade existente a consome.
const NODE_NAME := "PoliceTirePuncture"
const POP_RATE := 32000
const POP_SECONDS := .85
const POP_TAKES := 3
## Tomadas do estouro sintetizadas numa thread (ver `prewarm`): ~27 mil amostras por tomada
## custariam alguns ms no quadro do primeiro pneu.
static var _pop_takes: Array[AudioStreamWAV] = []
static var _pop_task := -1
var vehicle: CharacterBody3D
var count := 0
## Índices em `vehicle.wheels` que já murcharam: o tiro escolhe a roda; os ferros e o save completam
## pelas primeiras ainda cheias.
var flat_wheels: Array[int] = []
var original: Dictionary = {}
var wheel_scales: Array[Vector3] = []

## `audible` falso ao restaurar o save: o pneu já estava furado, não estoura de novo.
static func puncture(car: CharacterBody3D, tires := 2, audible := true) -> bool:
	var condition := _condition_for(car)
	return condition != null and condition.apply(tires, -1, audible)

## Tiro na roda: o segmento `from`→`to` da bala passa a menos de um raio do centro de uma roda.
## Fica com a primeira roda ao longo do tiro, para a bala não furar o pneu do outro lado do carro.
static func shoot(car: Node, from: Vector3, to: Vector3) -> bool:
	if not car is CharacterBody3D or car.get("wheels") == null or car.get("max_forward_speed") == null or not from.is_finite() or not to.is_finite(): return false
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < .0001: return false
	var wheels: Array = car.get("wheels")
	var best := -1
	var best_along := INF
	for index in wheels.size():
		var wheel: Node3D = wheels[index]
		if not is_instance_valid(wheel): continue
		var center := wheel.global_position
		var along := clampf((center - from).dot(segment) / length_squared, 0.0, 1.0)
		var parent := wheel.get_parent() as Node3D
		# Roda assentada no chão: a altura do centro no visual é o raio do pneu.
		var radius := clampf(wheel.position.y * (parent.scale.y if parent != null else 1.0), .22, .75)
		if center.distance_to(from + segment * along) <= radius and along < best_along:
			best = index
			best_along = along
	if best < 0: return false
	var condition := _condition_for(car as CharacterBody3D)
	return condition != null and condition.apply(0, best)

static func _condition_for(car: CharacterBody3D) -> Node:
	if not is_instance_valid(car) or car.health <= 0 or car.archetype == "army_tank": return null
	var condition: Node = car.get_node_or_null(NODE_NAME)
	if condition == null:
		condition = load("res://gameplay/police_response/ground/TirePuncture.gd").new()
		condition.name = NODE_NAME
		condition.vehicle = car
		car.add_child(condition)
	return condition

func apply(tires: int, wheel := -1, audible := true) -> bool:
	if wheel >= 0 and (wheel >= vehicle.wheels.size() or flat_wheels.has(wheel)): return false
	var next := clampi(maxi(tires, count + (1 if wheel >= 0 else 0)), 0, 4)
	if next <= count: return false
	if original.is_empty():
		original = {"speed": vehicle.max_forward_speed, "drive_acceleration": vehicle.drive_acceleration}
		if vehicle.handling != null:
			for key in ["max_speed", "acceleration", "braking", "turn_speed", "drift_factor"]:
				original[key] = vehicle.handling.get(key)
		for each in vehicle.wheels: wheel_scales.append(each.scale)
	var popped: Array[int] = []
	if wheel >= 0: popped.append(wheel)
	for index in vehicle.wheels.size():
		if flat_wheels.size() + popped.size() >= next: break
		if not flat_wheels.has(index) and not popped.has(index): popped.append(index)
	flat_wheels.append_array(popped)
	if audible: _play_puncture(popped)
	count = next
	var ratio := float(count) / 4.0
	vehicle.max_forward_speed = float(original.speed) * lerpf(1.0, .32, ratio)
	vehicle.drive_acceleration = float(original.drive_acceleration) * lerpf(1.0, .48, ratio)
	if vehicle.handling != null:
		vehicle.handling.max_speed = float(original.max_speed) * lerpf(1.0, .32, ratio)
		vehicle.handling.acceleration = float(original.acceleration) * lerpf(1.0, .48, ratio)
		vehicle.handling.braking = float(original.braking) * lerpf(1.0, .68, ratio)
		vehicle.handling.turn_speed = float(original.turn_speed) * lerpf(1.0, .62, ratio)
		vehicle.handling.drift_factor = minf(1.3, float(original.drift_factor) + .34 * ratio)
	for index in flat_wheels:
		if index < mini(vehicle.wheels.size(), wheel_scales.size()):
			vehicle.wheels[index].scale = wheel_scales[index] * Vector3(1.0, .66, .82)
	vehicle.set_meta("punctured_tires", count)
	return true

static func snapshot(car: Node) -> int:
	return clampi(int(car.get_meta("punctured_tires", 0)), 0, 4)

static func repair_vehicle(car: Node) -> void:
	var condition: Node = car.get_node_or_null(NODE_NAME)
	if condition != null: condition.restore()

func restore() -> void:
	if is_instance_valid(vehicle) and not original.is_empty():
		vehicle.max_forward_speed = float(original.speed)
		vehicle.drive_acceleration = float(original.drive_acceleration)
		if vehicle.handling != null:
			for key in ["max_speed", "acceleration", "braking", "turn_speed", "drift_factor"]:
				vehicle.handling.set(key, original[key])
		for index in mini(wheel_scales.size(), vehicle.wheels.size()):
			vehicle.wheels[index].scale = wheel_scales[index]
		vehicle.remove_meta("punctured_tires")
	queue_free()

## Chamado no `_ready` do Gameplay: sintetiza as tomadas fora do quadro, antes do primeiro pneu.
static func prewarm() -> void:
	if not _pop_takes.is_empty() or _pop_task >= 0: return
	_pop_task = WorkerThreadPool.add_task(_build_takes, false, "Estouro de pneu")

## Sem `prewarm` (testes isolados) ou com a thread ainda rodando, espera ou sintetiza aqui: no jogo
## o Gameplay já pediu as tomadas muito antes do primeiro pneu.
static func _ensure_takes() -> void:
	if not _pop_takes.is_empty(): return
	if _pop_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_pop_task)
		_pop_task = -1
	if _pop_takes.is_empty(): _build_takes()

static func _build_takes() -> void:
	var takes: Array[AudioStreamWAV] = []
	for take in POP_TAKES: takes.append(_synth_pop(5113 + take * 977, 1.0 + (float(take) - 1.0) * .07))
	_pop_takes = takes

## Estouro em três camadas, sem amostra externa: o estalo seco da carcaça rompendo (ruído largo,
## ataque de 1 ms), o "bum" grave do ar saindo de uma vez (seno que cai de ~150 para ~50 Hz) e o
## chiado do pneu esvaziando, que escurece e treme enquanto a borracha bate.
static func _synth_pop(take_seed: int, pitch: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = take_seed
	var frames := int(POP_RATE * POP_SECONDS)
	var mix := PackedFloat32Array()
	mix.resize(frames)
	var dt := 1.0 / POP_RATE
	var phase := 0.0
	var previous := 0.0
	var low := 0.0
	var peak := 0.0
	for index in frames:
		var t := index * dt
		var noise := rng.randf_range(-1.0, 1.0)
		# Diferença de ruído = ruído agudo: o estalo fica "seco", sem embolar com o bum.
		var crack := (noise - previous) * .5 * minf(1.0, t / .001) * exp(-t * 85.0)
		previous = noise
		phase += TAU * pitch * (50.0 + 100.0 * exp(-t * 22.0)) * dt
		var thump := sin(phase) * exp(-t * 26.0) * minf(1.0, t / .002)
		# Passa-baixa de um polo que vai fechando: o ar sai claro e termina abafado.
		var cutoff := 2400.0 * exp(-t * 3.2) + 350.0
		low += (noise - low) * (1.0 - exp(-TAU * cutoff * dt))
		var flutter := 1.0 + .3 * sin(TAU * (22.0 + 9.0 * pitch) * t)
		var hiss := low * minf(1.0, t / .006) * exp(-t * 4.2) * flutter
		var sample := crack * 1.1 + thump * .8 + hiss * .9
		mix[index] = sample
		peak = maxf(peak, absf(sample))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var gain := .95 / maxf(peak, .001)
	# Os últimos 30 ms descem a zero para o fim da tomada não dar clique.
	var fade := int(POP_RATE * .03)
	for index in frames:
		var tail := minf(1.0, float(frames - index) / fade)
		bytes.encode_s16(index * 2, clampi(int(mix[index] * gain * tail * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = POP_RATE
	stream.data = bytes
	return stream

func _play_puncture(popped: Array[int]) -> void:
	if popped.is_empty(): return
	_ensure_takes()
	# Nos ferros estouram vários pneus: no máximo dois estouros, o segundo um eixo depois.
	for order in mini(popped.size(), 2):
		var wheel: Node3D = vehicle.wheels[popped[order]] if popped[order] < vehicle.wheels.size() else null
		var sound := AudioStreamPlayer3D.new()
		sound.name = "TirePunctureSound"
		sound.stream = _pop_takes[randi() % _pop_takes.size()]
		sound.bus = "Vehicles" if AudioServer.get_bus_index("Vehicles") >= 0 else "Master"
		sound.volume_db = -1.0 if order == 0 else -4.0
		sound.pitch_scale = randf_range(.93, 1.07)
		sound.max_distance = 70.0
		sound.unit_size = 10.0
		vehicle.add_child(sound)
		if is_instance_valid(wheel): sound.global_position = wheel.global_position
		sound.finished.connect(sound.queue_free)
		if order == 0: sound.play()
		else: vehicle.get_tree().create_timer(randf_range(.09, .16)).timeout.connect(sound.play)
