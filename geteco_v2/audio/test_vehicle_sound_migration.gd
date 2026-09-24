extends SceneTree
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CRASH := preload("res://audio/VehicleCrashAudio.gd")
var failures: Array[String] = []

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
	var crash_playing := false
	for child in scene.get_children():
		if child is AudioStreamPlayer3D and child.playing and child.stream is AudioStreamWAV:
			crash_playing = true
	_check(crash_playing, "recorded V1 crash take plays in V2")
	var second_car := VEHICLE.new()
	second_car.archetype = "nimbus_minivan"
	scene.add_child(second_car)
	second_car.set_physics_process(false)
	car.set_meta("crash_audio_ms", -999999)
	CRASH.play(car, second_car, car.global_position, 200.0)
	var metal_contact := false
	for child in scene.get_children():
		if child is AudioStreamPlayer3D and child.stream != null and "metal_" in child.stream.resource_path:
			metal_contact = true
	_check(metal_contact, "vehicle-to-vehicle collision uses V1 metal take")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("VEHICLE_SOUND_MIGRATION: PASS")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("VEHICLE_SOUND_MIGRATION failures: ", failures)
		quit(1)

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
