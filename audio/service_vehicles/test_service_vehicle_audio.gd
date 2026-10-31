extends SceneTree
## Teste de contrato preparado; rode só depois de coordenar a execução do Godot.
const MIXER = preload("res://audio/service_vehicles/ServiceVehicleAudio.gd")
class TestWorld extends Node3D:
	var driving: Node
class TestDriving extends Node:
	var occupied := false
	var car: CharacterBody3D
class TestVehicle extends "res://scripts/Vehicle.gd":
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _voices(mixer: Node) -> int:
	var count := 0
	for slot in mixer._slots:
		for player in slot.players:
			if player.playing: count += 1
	return count

func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.driving = TestDriving.new()
	world.add_child(world.driving)
	var listener := Node3D.new()
	world.add_child(listener)
	var mixer := MIXER.new()
	world.add_child(mixer)
	_check(mixer.configure(world, listener), "configure")
	var cars: Array[CharacterBody3D] = []
	for index in 33:
		var car := TestVehicle.new()
		car.archetype = "station_wagon"
		car.controlled = true
		car.external_input = true
		world.add_child(car)
		car.position.x = index * 0.5
		cars.append(car)
		_check(mixer.register_vehicle(car, "mortician") == (index < 32), "registration ceiling")
	_check(mixer.register_vehicle(cars[0], "mortician"), "idempotent registration")
	_check(not mixer.register_vehicle(cars[0], "unknown"), "reject invalid service")
	mixer._process(0.1)
	_check(mixer._slots.size() == 6 and _voices(mixer) <= 12, "voice ceiling")
	_check(_voices(mixer) > 0, "NPC engine audible")
	cars[0].controlled = true
	cars[0].external_input = false
	world.driving.occupied = true
	world.driving.car = cars[0]
	mixer._process(0.1)
	for slot in mixer._slots:
		_check(slot.id != cars[0].get_instance_id(), "player engine excluded")
	mixer.set_enabled(false)
	_check(_voices(mixer) == 0 and not mixer.is_processing(), "global suspension")
	mixer.set_enabled(true)
	for car in cars:
		mixer.set_vehicle_active(car, false)
	mixer._process(0.1)
	_check(_voices(mixer) == 0, "inactive vehicles silent")
	mixer.set_vehicle_active(cars[1], true)
	cars[1].speed = 5.0
	mixer._process(0.1)
	_check(_voices(mixer) > 0, "resume")
	_check(mixer._entries[cars[1].get_instance_id()].acceleration > 0, "acceleration tracked")
	cars[1].engine_disabled = true
	mixer._process(0.1)
	_check(_voices(mixer) == 0, "disabled engine silent")
	cars[1].engine_disabled = false
	cars[1].hide()
	mixer._process(0.1)
	_check(_voices(mixer) == 0, "hidden dispatch vehicle silent")
	cars[1].show()
	cars[1].health = 0
	mixer._process(0.1)
	_check(_voices(mixer) == 0, "wreck silent")
	var removed_id := cars[1].get_instance_id()
	cars[1].free()
	_check(not mixer._entries.has(removed_id), "tree exit unregisters")
	# Bipe de ré: só serviço pesado andando para trás, separado do orçamento de motor.
	var truck := TestVehicle.new()
	truck.archetype = "american_dump_truck"
	truck.controlled = true
	truck.external_input = true
	world.add_child(truck)
	truck.position = Vector3(2, 0, 2)
	_check(mixer.register_vehicle(truck, "fire"), "heavy service vehicle registers")
	truck.speed = 3.0
	mixer._process(0.1)
	_check(mixer._beepers.is_empty(), "no reverse beep going forward")
	truck.speed = -3.0
	mixer._process(0.1)
	var beeper: AudioStreamPlayer3D = mixer._beepers.get(truck.get_instance_id())
	_check(beeper != null and beeper.playing and beeper.stream is AudioStreamWAV, "reverse beep plays while backing up")
	_check(_voices(mixer) <= 12, "beep stays outside the engine voice ceiling")
	truck.speed = 3.0
	mixer._process(0.1)
	_check(mixer._beepers.is_empty(), "reverse beep stops going forward")
	truck.speed = -3.0
	mixer._process(0.1)
	mixer.set_enabled(false)
	_check(mixer._beepers.is_empty(), "suspension releases the reverse beep")
	mixer.set_enabled(true)
	mixer.shutdown()
	mixer.shutdown()
	_check(mixer._entries.is_empty() and mixer._banks.is_empty(), "resources released")
	_check(mixer.get_child_count() == 0, "emitters released")
	world.free()
	print("ServiceVehicleAudio contract failures: ", failures)
	quit(1 if failures else 0)
