extends SceneTree
const TANK := preload("res://audio/tank/TankAudio.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const NEARBY := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const SERVICE := preload("res://audio/service_vehicles/ServiceVehicleAudio.gd")
var failures := 0
var checks := 0

class Driving extends Node:
	var occupied := false
	var car: CharacterBody3D

class World extends Node3D:
	var driving: Node
	var player: CharacterBody3D
	var session: Node
	var dispatch: Node

class TankVehicle extends "res://scripts/Vehicle.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

class WaterFixture extends Node3D:
	func clear_trail() -> void: pass

class Foreground extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		set_process(false)
		for index in 7:
			var player := AudioStreamPlayer.new()
			add_child(player)
			layers.append(player)
		road_audio = AudioStreamPlayer.new()
		shift_audio = AudioStreamPlayer.new()
		air_brake_audio = AudioStreamPlayer.new()
		for player in [road_audio, shift_audio, air_brake_audio]: add_child(player)
		water_steps = WaterFixture.new()
		add_child(water_steps)
	func _update_ambience(_delta: float) -> void: pass
	func _update_radio(_delta: float) -> void: pass

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func _pcm_ok(stream: AudioStreamWAV, looped: bool) -> bool:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo: return false
	var peak := 0.0
	var power := 0.0
	var samples := stream.data.size() / 2
	for index in samples:
		var sample := float(stream.data.decode_s16(index * 2)) / 32768.0
		peak = maxf(peak, absf(sample))
		power += sample * sample
	return peak < 0.96 and sqrt(power / samples) > 0.04 and stream.get_length() >= 2.0 \
		and stream.loop_mode == (AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED) \
		and (not looped or stream.loop_end == samples)

func _run() -> void:
	_check(PROFILE.bank_family("army_tank") == "tank", "fleet tank selects its own family")
	_check(PROFILE.bank_family("police_cruiser") == "police" and PROFILE.bank_family("route_city") == "bus", "normal service families remain intact")
	var bank := TANK.engine_bank()
	_check(bank.size() == 7, "seven authored diesel bands available")
	var signatures: Array[int] = []
	for index in bank.size():
		_check(_pcm_ok(bank[index], true), "diesel %d is audible, nonclipped, looping PCM" % index)
		signatures.append(hash(bank[index].data))
	_check(signatures.size() == 7 and signatures.count(signatures[0]) == 1 and signatures.count(signatures[6]) == 1,
		"idle and high RPM contain different authored samples")
	_check(bank[0] == TANK.engine_bank()[0] and TANK.fire_stream() == TANK.fire_stream(), "engine and cannon reuse cached resources")
	_check(_pcm_ok(TANK.start_stream(), false) and _pcm_ok(TANK.tracks_stream(), true), "finite starter and seamless track loop are valid")
	_check(_pcm_ok(TANK.fire_stream(), false) and _pcm_ok(TANK.impact_stream(), false), "cannon boom and impact are finite nonclipped samples")
	_check(hash(TANK.fire_stream().data) != hash(TANK.impact_stream().data), "muzzle blast and impact have distinct waveforms")
	_check(is_zero_approx(TANK.tracks_gain(0.0)) and TANK.tracks_pitch(8.0) > TANK.tracks_pitch(2.0), "tracks stop at rest and cadence follows speed")
	_check(is_equal_approx(TANK.tracks_gain(-5.0), TANK.tracks_gain(5.0)), "reverse uses physical track speed")
	var world := World.new()
	root.add_child(world)
	world.driving = Driving.new()
	world.player = CharacterBody3D.new()
	world.add_child(world.driving)
	world.add_child(world.player)
	var car := TankVehicle.new()
	car.archetype = "army_tank"
	car.max_forward_speed = 13.0
	car.controlled = true
	world.add_child(car)
	var foreground := Foreground.new()
	foreground.world = world
	world.add_child(foreground)
	world.driving.occupied = true
	world.driving.car = car
	foreground._process(0.1)
	_check(foreground.family == "tank" and foreground.layers[0].stream == bank[0], "foreground uses authored tank bank")
	_check(foreground.shift_audio.stream == TANK.start_stream() and foreground.shift_audio.playing, "first parked entry plays finite diesel startup")
	car.throttle_input = 1.0
	foreground._process(0.4)
	_check(not foreground.road_audio.playing and not foreground.air_brake_audio.playing, "stationary revving has no tracks or generic truck air brake")
	car.speed = 7.0
	foreground._process(0.2)
	var moving_pitch: float = foreground.road_audio.pitch_scale
	_check(foreground.road_audio.stream == TANK.tracks_stream() and foreground.road_audio.playing, "driving mixes actual tracks instead of road tire hiss")
	car.speed = -7.0
	foreground._process(0.1)
	_check(is_equal_approx(moving_pitch, foreground.road_audio.pitch_scale), "foreground reverse preserves track cadence")
	world.driving.occupied = false
	foreground._process(0.1)
	_check(_foreground_voices(foreground) == 0, "leaving tank immediately releases foreground voices")
	world.driving.occupied = true
	foreground._process(0.1)
	_check(not foreground.shift_audio.playing, "reentry does not restart an already running engine")
	car.engine_disabled = true
	foreground._process(0.1)
	_check(_foreground_voices(foreground) == 0, "disabled tank silences foreground engine and tracks")
	car.engine_disabled = false
	var normal := TankVehicle.new()
	normal.archetype = "police_cruiser"
	normal.speed = 7.0
	world.add_child(normal)
	world.driving.car = normal
	foreground._process(0.1)
	_check(foreground.family == "police" and foreground.road_audio.stream != TANK.tracks_stream(), "switching to normal car restores its engine and tire loop")
	world.driving.occupied = false
	foreground._process(0.1)
	foreground.free()
	car.external_input = true
	car.add_to_group("drivable")
	car.speed = 5.0
	var nearby := NEARBY.new()
	world.add_child(nearby)
	_check(nearby.configure(world, world.player), "nearby mixer configures")
	nearby.set_process(false)
	nearby._process(0.2)
	_check(nearby._states[car.get_instance_id()].family == "tank", "unregistered NPC tank does not fall back to truck or street")
	_check(nearby.snapshot().playing_voices == 2 and nearby.snapshot().voice_limit == 12, "NPC diesel and tracks fit existing two-voice budget")
	var slot: Dictionary = nearby._slots[0]
	_check(slot.players[1].stream == TANK.tracks_stream(), "nearby second voice is independent track sample")
	car.speed = 0.0
	car.throttle_input = 1.0
	nearby._process(0.1)
	_check(slot.players[0].playing and not slot.players[1].playing, "NPC stationary diesel remains while tracks stop")
	car.position.x = 100.0
	nearby._process(0.5)
	_check(nearby.snapshot().playing_voices == 0, "out-of-range tank releases bounded nearby voices")
	nearby.shutdown()
	nearby.free()
	car.position = Vector3.ZERO
	car.speed = 6.0
	var service := SERVICE.new()
	world.add_child(service)
	_check(service.configure(world, world.player) and service.register_vehicle(car, "police"), "dispatch tank registers through production service adapter")
	service.set_process(false)
	service._process(0.1)
	_check(service._entries[car.get_instance_id()].family == "tank" and _service_voices(service) == 2,
		"registered police tank uses diesel and tracks in two voices")
	_check(service._slots[0].players[1].stream == TANK.tracks_stream(), "service adapter preserves authored tracks")
	paused = true
	_check(not service.can_process() and not service._slots[0].players[0].can_process(), "tree pause suspends mixer and inherited emitter processing")
	paused = false
	car.engine_disabled = true
	service._process(0.1)
	_check(_service_voices(service) == 0, "disabled dispatch tank releases both voices")
	service.shutdown()
	_check(service.get_child_count() == 0, "shutdown frees service emitters")
	world.free()
	print("TANK_AUDIO checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _foreground_voices(audio: Node) -> int:
	var count := 0
	for player in audio.layers + [audio.road_audio, audio.shift_audio, audio.air_brake_audio]:
		if player.playing: count += 1
	return count

func _service_voices(audio: Node) -> int:
	var count := 0
	for slot in audio._slots:
		for player in slot.players:
			if player.playing: count += 1
	return count
