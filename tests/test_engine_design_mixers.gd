extends SceneTree
## Integração do adaptador com instâncias reais de veículo e nós reais de reprodução.
## O movimento do veículo é segurado por esta fixture; a direção renderizada tem o próprio runner.
const BANKS := preload("res://audio/EngineDesignBanks.gd")
const LEGACY_BANKS := preload("res://audio/EngineBankCache.gd")
const CATALOG := preload("res://audio/FleetEngineDesign.gd")
const NEARBY := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const SERVICE := preload("res://audio/service_vehicles/ServiceVehicleAudio.gd")
var checks := 0
var failures: Array[String] = []

class StillVehicle extends "res://scripts/Vehicle.gd":
	func _physics_process(_delta: float) -> void: pass

class Driving extends Node:
	var occupied := false
	var car: CharacterBody3D

class AudioWorld extends Node3D:
	var driving: Node
	var player: CharacterBody3D
	var session: Node
	var dispatch: Node

class WaterFixture extends Node3D:
	func clear_trail() -> void: pass

class Foreground extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		set_process(false)
		radio = AudioStreamPlayer.new()
		add_child(radio)
		for index in 7:
			var layer := AudioStreamPlayer.new()
			add_child(layer)
			layers.append(layer)
		road_audio = AudioStreamPlayer.new()
		shift_audio = AudioStreamPlayer.new()
		air_brake_audio = AudioStreamPlayer.new()
		for channel in [road_audio, shift_audio, air_brake_audio]: add_child(channel)
		water_steps = WaterFixture.new()
		add_child(water_steps)
	func _update_ambience(_delta: float) -> void: pass
	func _update_radio(_delta: float) -> void: pass

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func(): push_error("ENGINE_DESIGN_MIXERS timeout"); quit(2))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func design_voice(slot: Dictionary) -> Node3D:
	return slot.get("design_voice") as Node3D

func slot_motors(slots: Array) -> int:
	var count := 0
	for slot in slots:
		var voice := design_voice(slot)
		if is_instance_valid(voice): count += int(voice.snapshot().motor_voices)
	return count

func legacy_motors(slots: Array) -> int:
	var count := 0
	for slot in slots:
		for player in slot.players:
			if player.playing: count += 1
	return count

func has_active_id(slots: Array, id: int) -> bool:
	for slot in slots:
		if slot.id != id: continue
		var voice := design_voice(slot)
		if is_instance_valid(voice) and int(voice.snapshot().motor_voices) > 0: return true
	return false

func update_all(foreground: Node, nearby: Node, service: Node, count := 20) -> void:
	for tick in count:
		service._process(.1)
		nearby._process(.1)
		foreground._process(.1)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not BANKS.enabled(): quit(2); return
	await LEGACY_BANKS.prewarm(self)
	await BANKS.prewarm(self)
	var world := AudioWorld.new()
	root.add_child(world)
	world.player = CharacterBody3D.new()
	world.add_child(world.player)
	world.driving = Driving.new()
	world.add_child(world.driving)
	var foreground := Foreground.new()
	foreground.world = world
	world.add_child(foreground)
	var nearby := NEARBY.new()
	world.add_child(nearby)
	check(nearby.configure(world, world.player), "nearby adapter configures against live world/listener")
	nearby.set_process(false)
	var service := SERVICE.new()
	world.add_child(service)
	check(service.configure(world, world.player), "service adapter configures against live world/listener")
	service.set_process(false)
	var cars: Array[CharacterBody3D] = []
	var ids := ["police_cruiser", "police_suv", "police_transport", "medic_box", "rescue_pumper", "station_wagon", "police_cruiser", "medic_box"]
	for index in ids.size():
		var car := StillVehicle.new()
		car.archetype = ids[index]
		world.add_child(car)
		car.position = Vector3(2.0+index*2.0, .1, 0)
		car.traffic = true
		car.speed = 10.0
		car.horizontal_velocity = Vector3(0, 0, -10)
		cars.append(car)
	for tick in 30: nearby._process(.1)
	check(nearby._slots.size() == 6 and nearby.snapshot().audible == 6, "eight nearby candidates keep six audible slots")
	check(slot_motors(nearby._slots) > 0 and slot_motors(nearby._slots) <= 24, "nearby uses designed banks within twenty-four motor voices")
	check(legacy_motors(nearby._slots) == 0, "nearby does not double new audio with legacy layers")
	for slot in nearby._slots:
		var voice := design_voice(slot)
		check(is_instance_valid(voice), "nearby slot has design adapter")
		if is_instance_valid(voice):
			var state: Dictionary = voice.snapshot()
			check(not state.foreground and not state.spool_playing and not state.release_playing, "nearby keeps spatial sound without foreground turbo FX")
	var roles := ["police", "police", "police", "medic", "fire", "mortician", "police", "medic"]
	for index in cars.size(): check(service.register_vehicle(cars[index], roles[index]), "real service registration " + str(index))
	update_all(foreground, nearby, service)
	check(service._slots.size() == 6 and slot_motors(service._slots) > 0 and slot_motors(service._slots) <= 24, "eight registered services retain six designed audible slots")
	check(legacy_motors(service._slots) == 0, "service does not double design and legacy audio")
	check(slot_motors(nearby._slots) == 0, "service ownership releases duplicate nearby playback")
	var occupied := cars[0]
	world.driving.car = occupied
	world.driving.occupied = true
	occupied.controlled = true
	occupied.external_input = false
	occupied.traffic = false
	occupied.throttle_input = .7
	update_all(foreground, nearby, service)
	check(is_instance_valid(foreground.design_voice), "foreground lazily creates authored voice")
	if is_instance_valid(foreground.design_voice):
		check(foreground.design_voice.snapshot().profile == CATALOG.profile(occupied.archetype) and foreground.design_voice.snapshot().motor_voices > 0, "driver uses this vehicle's designed powertrain")
	check(foreground.layers.all(func(layer): return not layer.playing), "driver authored sound does not overlap seven legacy bands")
	check(not has_active_id(service._slots, occupied.get_instance_id()) and not has_active_id(nearby._slots, occupied.get_instance_id()), "driver takeover removes the same car from both spatial owners")
	occupied.engine_disabled = true
	update_all(foreground, nearby, service, 2)
	check(foreground.design_voice.snapshot().motor_voices == 0, "disabled engine silences foreground adapter")
	occupied.engine_disabled = false
	update_all(foreground, nearby, service, 3)
	check(foreground.design_voice.snapshot().motor_voices > 0, "re-enabled engine resumes foreground adapter")
	world.driving.occupied = false
	occupied.controlled = false
	occupied.speed = 0.0
	update_all(foreground, nearby, service)
	check(foreground.design_voice.snapshot().motor_voices == 0, "unoccupied parked car releases foreground playback")
	world.driving.occupied = true
	occupied.controlled = true
	occupied.throttle_input = 0.0
	update_all(foreground, nearby, service)
	check(foreground.design_voice.snapshot().motor_voices > 0, "reentry recovers driver idle")
	world.driving.occupied = false
	occupied.controlled = false
	occupied.traffic = true
	occupied.speed = 8.0
	service.unregister_vehicle(occupied)
	update_all(foreground, nearby, service)
	check(has_active_id(nearby._slots, occupied.get_instance_id()) and not has_active_id(service._slots, occupied.get_instance_id()), "service release restores a single nearby owner")
	occupied.engine_disabled = true
	update_all(foreground, nearby, service)
	check(not has_active_id(nearby._slots, occupied.get_instance_id()), "disabled traffic engine releases its audible slot")
	# Dedicated desert controller retains ownership while adopting the same bank.
	var desert := StillVehicle.new()
	desert.archetype = "supra_a80"
	world.add_child(desert)
	desert.controlled = true
	world.driving.car = desert
	world.driving.occupied = true
	var sound: Node = desert.get_node_or_null("DesertCarAudio")
	check(sound != null, "real Supra keeps its drivetrain-owned audio adapter")
	if sound != null:
		sound.set_process(false)
		sound.drivetrain.rpm = 4000.0
		sound.drivetrain.throttle = .6
		for tick in 20: sound._process(.1)
		foreground._process(.1)
		check(is_instance_valid(sound._design_voice) and sound._design_voice.snapshot().profile == "jz2_i6_turbo", "desert adapter binds Supra's authored six-cylinder turbo")
		check(sound._layers.all(func(layer): return not layer.playing) and not sound._shift.playing, "desert design adapter stops duplicated legacy engine and blowoff")
		check(foreground.design_voice.snapshot().motor_voices == 0 and not nearby._eligible(desert), "desert engine is not also mixed by foreground or nearby")
		# Exercita um NPC registrado, não um motorista ocupado já excluído pela
		# regra de posse do player de serviço. Uma câmera próxima liga o caminho espacial
		# normal do DesertCarAudio sem forçar o estado de alcance do adaptador.
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(0, 10, 0)
		camera.make_current()
		world.driving.occupied = false
		desert.external_input = true
		desert.speed = 8.0
		check(service.register_vehicle(desert, "police"), "Supra can be registered as a service vehicle")
		check(not service._eligible(desert, service._entries[desert.get_instance_id()]), "service registration preserves dedicated desert engine ownership")
		for tick in 20:
			service._process(.1)
			sound._process(.1)
		check(not has_active_id(service._slots, desert.get_instance_id()), "registered NPC Supra is not also mixed by service audio")
		check(sound._design_voice.snapshot().motor_voices > 0 and not sound._design_voice.snapshot().foreground, "registered NPC Supra keeps its own spatial engine playing")
		desert.engine_disabled = true
		sound._process(.1)
		check(sound._design_voice.snapshot().motor_voices == 0, "desert engine disable stops authored voice")
	nearby.shutdown()
	service.shutdown()
	check(nearby._slots.is_empty() and service._slots.is_empty(), "spatial owners free bounded slots on shutdown")
	world.free()
	await process_frame
	await create_timer(.1).timeout
	print("ENGINE_DESIGN_MIXERS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
