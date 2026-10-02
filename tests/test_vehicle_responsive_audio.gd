extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const CRASH := preload("res://audio/VehicleCrashAudio.gd")
const SURFACE := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
var failures := 0
var checks := 0

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

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func playback_refs(node: Node) -> Array[WeakRef]:
	var result: Array[WeakRef] = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current.has_method("has_stream_playback") and current.has_stream_playback():
			var playback: RefCounted = current.get_stream_playback()
			result.append(weakref(playback))
		pending.append_array(current.get_children())
	return result

func run() -> void:
	check(PROFILE.drive_load(8, -1, false) == 0, "reverse button brakes forward motion without engine surge")
	check(PROFILE.drive_load(-8, 1, false) == 0, "forward button brakes reverse motion")
	check(PROFILE.drive_load(0, -1, false) == 1, "reverse engages from rest")
	check(PROFILE.drive_load(8, 1, true) == 0, "braking overrides acceleration audio")
	check(is_equal_approx(PROFILE.drive_load(8, .35, false), .35), "analog throttle remains proportional")
	check(PROFILE.loaded_rpm(.6, .12, 1, .3) > PROFILE.loaded_rpm(.6, .12, 0, .3), "lifting throttle changes RPM at the same wheel speed")
	check(PROFILE.loaded_rpm(.6, .12, 0, .3) > .4, "coasting retains drivetrain RPM")
	var world := AudioWorld.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.name = "AudioTestGround"
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, .2, 20)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -.1
	world.add_child(ground)
	ground.name = "Land"
	check(SURFACE._surface_kind(ground, Vector3(106.25, 0, 112.5)) == "grass", "shared land collider preserves authored harbor lawn")
	ground.name = "HarborEarthRoad"
	check(SURFACE._surface_kind(ground, Vector3.ZERO) == "dirt", "earth road is not classified as asphalt")
	ground.name = "AudioTestGround"
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	world.add_child(car)
	car.place(Vector3(0, .04, 0), 0)
	car.set_physics_process(false)
	car.controlled = true
	car.speed = 8
	car.horizontal_velocity = Vector3(0, 0, -8)
	world.player = CharacterBody3D.new()
	world.add_child(world.player)
	world.driving = Driving.new()
	world.driving.car = car
	world.add_child(world.driving)
	var foreground := Foreground.new()
	foreground.world = world
	world.add_child(foreground)
	car.throttle_input = 1
	for tick in 30: foreground._process(.05)
	var accelerating_rpm: float = foreground.engine_rpm
	check(foreground.engine_load > .95, "real foreground mixer responds to held throttle")
	car.throttle_input = 0
	for tick in 30: foreground._process(.05)
	check(foreground.engine_rpm < accelerating_rpm and foreground.engine_load < .01, "real foreground mixer unloads on button release")
	car.throttle_input = -1
	car.brake_input = true
	for tick in 10: foreground._process(.05)
	check(foreground.engine_load < .01, "real foreground mixer does not rev while braking")
	car.brake_input = false
	car.throttle_input = 0
	car.engine_disabled = true
	foreground._process(.05)
	check(foreground.layers.all(func(voice): return not voice.playing), "disabled engine stops every foreground band")
	car.engine_disabled = false
	var tires = car.effects.tire_effects
	await physics_frame
	await physics_frame
	for kind in ["hard", "grass", "dirt", "snow", "water"]:
		ground.set_meta("vehicle_surface", kind)
		for tick in 20: tires.physics_tick(.05, true)
		var mixer = tires.road_mixer
		var expected: String = "wet" if kind == "water" else kind
		check(is_instance_valid(mixer) and mixer.voices[expected].playing, "real wheel rays activate " + expected)
		check(mixer.voices[expected].volume_linear > .02, "audible rolling gain for " + expected)
		for other in mixer.voices:
			if other != expected: check(not mixer.voices[other].playing, "old surface fades out: " + other)
		car.brake_input = true
		tires.physics_tick(.05, true)
		check(tires.skid_audio.playing == (kind == "hard"), "rubber squeal only on hard ground")
		car.brake_input = false
	# Airborne tires, stopped car, exit and disabled presentation must go silent.
	car.position.y = 5
	for tick in 20: tires.physics_tick(.05, true)
	for voice in tires.road_mixer.voices.values(): check(not voice.playing, "no rolling sound in air")
	car.position.y = .04
	car.horizontal_velocity = Vector3.ZERO
	for tick in 20: tires.physics_tick(.05, true)
	for voice in tires.road_mixer.voices.values(): check(not voice.playing, "no rolling sound at rest")
	car.horizontal_velocity = Vector3(0, 0, -8)
	tires.physics_tick(.05, true)
	car.controlled = false
	tires.physics_tick(.05, true)
	for voice in tires.road_mixer.voices.values(): check(not voice.playing, "exit stops foreground rolling sound")
	car.controlled = true
	tires.physics_tick(.05, true)
	tires.physics_tick(.05, false)
	for voice in tires.road_mixer.voices.values(): check(not voice.playing, "inactive presentation stops loops")
	tires.physics_tick(.05, true)
	tires.road_mixer._process(.016)
	for voice in tires.road_mixer.voices.values(): check(not voice.playing, "suspended vehicle stops loops without another physics tick")
	for material in ["metal", "wood", "glass"]:
		ground.set_meta("impact_material", material)
		check(CRASH.contact_kind(ground, 200, false) == material, "impact material: " + material)
		var pool = CRASH.pool(car)
		pool.contacts.clear()
		pool.sources.clear()
		for voice in pool.voices: voice.stop()
		var before: int = pool.played_count
		CRASH.play(car, ground, Vector3.ZERO, 200)
		CRASH.play(car, ground, Vector3.ZERO, 200)
		check(pool.played_count == before + 1, "sustained contact does not spam impacts")
		check(pool.voices.any(func(voice): return voice.playing and voice.unit_size == 32), "driver impact audible and uses a real stream")
	var remaining := playback_refs(world)
	world.free()
	# stop() marks playbacks for deletion in the real mixer; the server's
	# following update releases them. Check completion rather than assuming
	# a SceneTreeTimer covers enough wall time after a slow fixture frame.
	var drain_began := Time.get_ticks_usec()
	while remaining.any(func(ref: WeakRef): return ref.get_ref() != null) and Time.get_ticks_usec() - drain_began < 2000000:
		await process_frame
		OS.delay_usec(1000)
	check(remaining.all(func(ref: WeakRef): return ref.get_ref() == null), "real mixer releases stopped playbacks before fixture exit")
	for i in 2: await process_frame
	print("AUDIO_FIXTURE_DRAIN wall_ms=", float(Time.get_ticks_usec() - drain_began) / 1000.0, " observed_playbacks=", remaining.size())
	print("RESPONSIVE_VEHICLE_AUDIO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
