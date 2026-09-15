extends SceneTree

const ENGINE = preload("res://audio/VehicleEngineSound.gd")
const CRASH = preload("res://audio/VehicleCrashAudio.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var hashes := []
	for id in ["bike_cruiser", "bike_sport", "bike_urban"]:
		check(ENGINE.family_for_vehicle(id) == id, id + " selects motorcycle engine")
		var layers := ENGINE.get_layer_streams(id, id)
		check(layers.size() == 3, id + " has idle, mid and high RPM")
		hashes.append(hash(layers[0].data))
	check(hashes[0] != hashes[1] and hashes[0] != hashes[2] and hashes[1] != hashes[2], "Three distinct exhaust waveforms")
	check(ENGINE._profile("bike_cruiser").cyl == 2 and ENGINE._profile("bike_cruiser").redline < ENGINE._profile("bike_sport").redline, "Cruiser is a low-rev twin")
	var world := Node2D.new()
	root.add_child(world)
	var bike := Node2D.new()
	var car := Node2D.new()
	world.add_child(bike)
	world.add_child(car)
	bike.add_to_group("motorcycle")
	for speed in [60.0, 180.0, 400.0]:
		for reverse in [false, true]:
			bike.set_meta("crash_audio_ms", -999999)
			car.set_meta("crash_audio_ms", -999999)
			CRASH.play(car if reverse else bike, bike if reverse else car, Vector2.ZERO, speed)
			var sound_player := world.get_child(world.get_child_count() - 1) as AudioStreamPlayer2D
			check(sound_player != null and sound_player.stream in CRASH.SAMPLES.motorcycle, "Bike impact uses glass-free motorcycle sample at speed %s, reversed=%s" % [speed, reverse])
			sound_player.free()
	world.free()
	print("MOTORCYCLE_AUDIO failures=", failures)
	quit(1 if failures else 0)
