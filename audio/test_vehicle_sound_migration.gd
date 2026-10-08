extends SceneTree
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CRASH := preload("res://audio/VehicleCrashAudio.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for pair in [["police_cruiser", "police"], ["route_city", "bus"],
		["porto_rosso", "rosso_v12"], ["port_forklift", "electric"],
		["monaliza", "street"]]:
		_check(PROFILE.family(pair[0]) == pair[1], "V1 engine family for " + pair[0])
	for index in 7:
		_check(ResourceLoader.exists("res://audio/acoustic/engine_electric_%d.wav" % index),
			"electric inverter bank %d is imported" % index)
	for effect in ["road", "air_brake", "turbo_shift_0", "turbo_shift_1", "turbo_shift_2",
		"sport_blowoff_0", "sport_blowoff_1", "sport_blowoff_2"]:
		_check(ResourceLoader.exists("res://audio/vehicle_fx/%s.wav" % effect),
			"V1 vehicle effect imported: " + effect)
	var scene := Node3D.new()
	root.add_child(scene)
	var car := VEHICLE.new()
	car.archetype = "nimbus_minivan"
	scene.add_child(car)
	car.set_physics_process(false)
	var tires: Node = car.effects.tire_effects
	tires._update_skid_audio(true, 8.0, 6.0)
	_check(is_instance_valid(tires.skid_audio) and tires.skid_audio.playing,
		"V1 skid WAV starts on a sliding V2 vehicle")
	if is_instance_valid(tires.skid_audio):
		_check(tires.skid_audio.stream.loop_end == 22050, "skid loop excludes V1 guard samples")
	tires._update_skid_audio(false, 0.0, 0.0)
	_check(not tires.skid_audio.playing, "skid WAV stops when grip returns")
	CRASH.play(car, null, car.global_position, 200.0)
	# Contact voices now live in the shared bounded pool, not beside the car.
	var pool = scene.get_node_or_null("ContactAudio")
	var crash_playing := false
	if pool != null:
		for voice in pool.voices:
			if voice.playing and voice.stream is AudioStreamWAV:
				crash_playing = true
	_check(crash_playing, "recorded V1 crash take plays in V2")
	var second_car := VEHICLE.new()
	second_car.archetype = "nimbus_minivan"
	scene.add_child(second_car)
	second_car.set_physics_process(false)
	var before: int = pool.played_count if pool != null else 0
	CRASH.play(car, second_car, car.global_position, 200.0)
	_check(pool != null and pool.played_count == before,
		"same-source collision is suppressed during source cooldown")
	# The pool clock uses physics ticks. Let the source and rejected contact
	# release naturally; resetting the old crash_audio_ms metadata does nothing.
	var release_frames := ceili(maxf(CRASH.SOURCE_COOLDOWN, CRASH.CONTACT_RELEASE)
		* Engine.physics_ticks_per_second) + 1
	for frame in release_frames: await physics_frame
	CRASH.play(car, second_car, car.global_position, 200.0)
	_check(pool != null and pool.played_count == before + 1,
		"new collision plays after source cooldown and contact release")
	var metal_contact := false
	if pool != null:
		for voice in pool.voices:
			if voice.playing and voice.stream != null and "metal_" in voice.stream.resource_path:
				metal_contact = true
	_check(metal_contact, "vehicle-to-vehicle collision uses V1 metal take")
	CRASH.play(car, second_car, car.global_position, 200.0)
	_check(pool != null and pool.played_count == before + 1,
		"repeated collision does not stack contact voices")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("VEHICLE_SOUND_MIGRATION: PASS checks=", checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("VEHICLE_SOUND_MIGRATION failures: ", failures)
		quit(1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
