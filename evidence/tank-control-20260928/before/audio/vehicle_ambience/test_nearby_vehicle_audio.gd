extends SceneTree

const MIXER := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")

var failures: Array[String] = []


class FakeDriving extends Node:
	var occupied := false
	var car: CharacterBody3D


class FakeDispatch extends Node:
	var units: Array = []


class FakeWorld extends Node3D:
	var driving: Node
	var dispatch: Node


class FakeUnit extends RefCounted:
	var vehicle: CharacterBody3D
	var finished := false


class FakeServiceMixer extends Node:
	var _entries: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var world := FakeWorld.new()
	var driving := FakeDriving.new()
	var dispatch := FakeDispatch.new()
	world.driving = driving
	world.dispatch = dispatch
	root.add_child(world)
	world.add_child(driving)
	world.add_child(dispatch)
	var listener := Node3D.new()
	world.add_child(listener)

	var mixer := MIXER.new()
	world.add_child(mixer)
	_check(mixer.configure(world, listener), "mixer configures against production-shaped contracts")
	var cars: Array[CharacterBody3D] = []
	for index in 8:
		var car := VEHICLE.new()
		car.archetype = "nimbus_minivan" if index % 2 == 0 else "vertice_midengine"
		world.add_child(car)
		car.traffic = true
		car.speed = 1.0 + index
		car.position = Vector3(index * 4.5 + 2.0, 0.0, 0.0)
		cars.append(car)
	var service_car := VEHICLE.new()
	service_car.archetype = "police_cruiser"
	world.add_child(service_car)
	service_car.controlled = true
	service_car.external_input = true
	service_car.position = Vector3(1.0, 0.0, 3.0)
	service_car.remove_from_group("drivable")
	var service_unit := FakeUnit.new()
	service_unit.vehicle = service_car
	dispatch.units.append(service_unit)
	await _frames(18)
	var first: Dictionary = mixer.snapshot()
	print("NearbyVehicleAudio initial snapshot: ", first)
	_check(first.audible == 6, "six-nearest audible ceiling")
	_check(first.playing_voices > 0 and first.playing_voices <= 12, "voice ceiling is active")
	_check(first.voice_limit == 12 and is_equal_approx(first.range, 45.0), "published voice and range budget")
	_check(service_car.get_instance_id() in first.audible_ids, "dispatch vehicle is discovered outside drivable group")

	driving.occupied = true
	driving.car = cars[0]
	await _frames(8)
	var occupied: Dictionary = mixer.snapshot()
	_check(cars[0].get_instance_id() not in occupied.audible_ids, "occupied vehicle never overlaps foreground engine")

	var service := FakeServiceMixer.new()
	world.add_child(service)
	service.add_to_group("service_vehicle_engine_mixer")
	service._entries[service_car.get_instance_id()] = true
	await _frames(8)
	var delegated: Dictionary = mixer.snapshot()
	_check(service_car.get_instance_id() not in delegated.audible_ids, "registered service engine is not duplicated")

	cars[2].position = Vector3(60.0, 0.0, 0.0)
	cars[3].engine_disabled = true
	await _frames(25)
	var filtered: Dictionary = mixer.snapshot()
	_check(cars[2].get_instance_id() not in filtered.audible_ids, "out-of-range vehicle is released")
	_check(cars[3].get_instance_id() not in filtered.audible_ids, "disabled engine is released")

	var removed_id := cars[4].get_instance_id()
	cars[4].queue_free()
	await _frames(4)
	_check(removed_id not in mixer.snapshot().audible_ids, "removed vehicle is released")
	mixer.shutdown()
	_check(mixer.snapshot().audible == 0 and mixer.snapshot().playing_voices == 0, "scene shutdown frees every voice")
	await _frames(8)
	world.queue_free()
	await _frames(8)
	if failures.is_empty():
		print("NearbyVehicleAudio contract: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NearbyVehicleAudio contract failures: ", failures.size())
		quit(1)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
