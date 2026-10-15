extends SceneTree

## Camadas do Firefly no motor do jogador (`WorldAudio`): estouro/assobio do turbo, compressor
## do muscle, bipe de ré dos pesados e a lista de alívio com as tomadas novas. Usa o mixer
## real com o mesmo fixture dos outros testes de áudio de veículo.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []

class Driving extends Node:
	var occupied := true
	var car: CharacterBody3D

class AudioWorld extends Node3D:
	var driving: Node
	var player: CharacterBody3D
	var session: Node

class WaterFixture extends Node3D:
	func clear_trail() -> void: pass

class Foreground extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		set_process(false)
		radio = AudioStreamPlayer.new()
		add_child(radio)
		for index in 7:
			var voice := AudioStreamPlayer.new()
			add_child(voice)
			layers.append(voice)
		road_audio = AudioStreamPlayer.new()
		shift_audio = AudioStreamPlayer.new()
		air_brake_audio = AudioStreamPlayer.new()
		for voice in [road_audio, shift_audio, air_brake_audio]: add_child(voice)
		water_steps = WaterFixture.new()
		add_child(water_steps)
	func _update_ambience(_delta: float) -> void: pass
	func _update_radio(_delta: float) -> void: pass

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func _mixer(archetype: String) -> Array:
	var world := AudioWorld.new()
	root.add_child(world)
	var car := VEHICLE.new()
	car.archetype = archetype
	world.add_child(car)
	car.place(Vector3(0, .04, 0), 0)
	car.set_physics_process(false)
	car.controlled = true
	world.player = CharacterBody3D.new()
	world.add_child(world.player)
	world.driving = Driving.new()
	world.driving.car = car
	world.add_child(world.driving)
	var foreground := Foreground.new()
	foreground.world = world
	world.add_child(foreground)
	return [world, car, foreground]

func run() -> void:
	# Coupe turbo: ao tirar o pé em giro e pressão altos entra estouro, trepidação ou assobio descendo.
	var coupe := _mixer("sport_coupe")
	var car: CharacterBody3D = coupe[1]
	var mixer: Node = coupe[2]
	car.speed = car.max_forward_speed * 0.8
	car.throttle_input = 1.0
	for tick in 20: mixer._process(.05)
	var extras := 0
	for attempt in 40:
		mixer.extra_cooldown = 0.0
		mixer.extra_audio.stop()
		mixer.engine_last_throttle = 1.0
		mixer.engine_rpm = 0.9
		mixer.engine_turbo_pressure = 0.9
		car.throttle_input = 0.0
		mixer._process(.05)
		if mixer.extra_audio.playing and str(mixer.extra_audio.stream.resource_path).begins_with("res://audio/vehicle_fx/"): extras += 1
		car.throttle_input = 1.0
		mixer._process(.05)
	check(extras >= 20, "coupe turbo solta flutter/assobio/estouro ao aliviar (%d de 40 tentativas)" % extras)
	check(mixer._blowoff_sounds().size() >= 3 and not mixer._blowoff_sounds().has(mixer.SPORT_BLOWOFF_SOUNDS[0]), "alívio do turbo usa só as tomadas novas (%d)" % mixer._blowoff_sounds().size())
	check(mixer.reverse_audio != null and not mixer.reverse_audio.playing, "coupe em marcha à frente não faz bipe de ré")
	car.speed = -4.0
	mixer._process(.05)
	check(not mixer.reverse_audio.playing, "coupe de passeio de ré não faz bipe")
	car.engine_disabled = true
	mixer._process(.05)
	check(not mixer.extra_audio.playing and not mixer.blower_audio.playing and not mixer.reverse_audio.playing, "motor desligado silencia as camadas novas")
	coupe[0].free()
	# Muscle: o compressor ronca em giro alto e some quando o motor para.
	var muscle := _mixer("sport_estate")
	var muscle_car: CharacterBody3D = muscle[1]
	var muscle_mixer: Node = muscle[2]
	muscle_car.speed = muscle_car.max_forward_speed * 0.7
	muscle_car.throttle_input = 1.0
	for tick in 20: muscle_mixer._process(.05)
	check(muscle_mixer.family == "muscle", "sport_estate usa o banco muscle (%s)" % muscle_mixer.family)
	check(muscle_mixer.blower_audio.playing and muscle_mixer.blower_audio.stream != null, "muscle em giro alto toca o compressor")
	var loud: float = muscle_mixer.blower_audio.volume_db
	check(loud < -8.0 and loud > -45.0, "compressor fica abaixo do motor (%.1f dB)" % loud)
	muscle_car.engine_disabled = true
	muscle_mixer._process(.05)
	check(not muscle_mixer.blower_audio.playing, "compressor para com o motor desligado")
	muscle[0].free()
	# Caminhão: bipe de ré só andando para trás.
	var truck := _mixer("american_dump_truck")
	var truck_car: CharacterBody3D = truck[1]
	var truck_mixer: Node = truck[2]
	truck_car.speed = 3.0
	for tick in 5: truck_mixer._process(.05)
	check(truck_mixer.family == "truck" and not truck_mixer.reverse_audio.playing, "caminhão para a frente não faz bipe")
	truck_car.speed = -3.0
	truck_mixer._process(.05)
	check(truck_mixer.reverse_audio.playing, "caminhão de ré toca o bipe")
	truck_car.speed = 3.0
	truck_mixer._process(.05)
	check(not truck_mixer.reverse_audio.playing, "bipe de ré para ao seguir em frente")
	truck[0].free()
	await process_frame
	print("FIREFLY_ENGINE_LAYERS extras_do_turbo=", extras, " compressor_db=", snappedf(loud, 0.1), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
