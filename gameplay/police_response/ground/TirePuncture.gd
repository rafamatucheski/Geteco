extends Node
## Vehicle condition without a frame loop: the existing handling consumes it.
static var _pop_stream: AudioStreamWAV
const NODE_NAME := "PoliceTirePuncture"
var vehicle: CharacterBody3D
var count := 0
var original: Dictionary = {}
var wheel_scales: Array[Vector3] = []

static func puncture(car: CharacterBody3D, tires := 2) -> bool:
	if not is_instance_valid(car) or car.health <= 0 or car.archetype == "army_tank": return false
	var condition: Node = car.get_node_or_null(NODE_NAME)
	if condition == null:
		condition = load("res://gameplay/police_response/ground/TirePuncture.gd").new()
		condition.name = NODE_NAME
		condition.vehicle = car
		car.add_child(condition)
	return condition.apply(tires)

func apply(tires: int) -> bool:
	var next := clampi(tires, 0, 4)
	if next <= count: return false
	if original.is_empty():
		original = {"speed": vehicle.max_forward_speed, "drive_acceleration": vehicle.drive_acceleration}
		if vehicle.handling != null:
			for key in ["max_speed", "acceleration", "braking", "turn_speed", "drift_factor"]:
				original[key] = vehicle.handling.get(key)
		for wheel in vehicle.wheels: wheel_scales.append(wheel.scale)
	_play_puncture()
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
	for index in mini(count, vehicle.wheels.size()):
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

func _play_puncture() -> void:
	if _pop_stream == null:
		var rate := 22050
		var samples := PackedByteArray()
		samples.resize(int(rate * .42) * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7319
		for index in samples.size() / 2:
			var t := float(index) / rate
			var pop := sin(TAU * 105.0 * t) * exp(-t * 65.0)
			var hiss := rng.randf_range(-1.0, 1.0) * exp(-t * 12.0)
			samples.encode_s16(index * 2, int(clampf(pop * .55 + hiss * .65, -1.0, 1.0) * 32767))
		_pop_stream = AudioStreamWAV.new()
		_pop_stream.format = AudioStreamWAV.FORMAT_16_BITS
		_pop_stream.mix_rate = rate
		_pop_stream.data = samples
	var sound := AudioStreamPlayer3D.new()
	sound.name = "TirePunctureSound"
	sound.stream = _pop_stream
	sound.bus = "Vehicles" if AudioServer.get_bus_index("Vehicles") >= 0 else "Master"
	sound.volume_db = -3.0
	sound.max_distance = 45.0
	sound.unit_size = 8.0
	vehicle.add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
