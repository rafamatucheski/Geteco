extends SceneTree
const EngineSound = preload("res://audio/VehicleEngineSound.gd")
class FakePlayer extends Node:
	var money := 123
	var health := 100
	var is_dead := false
	var is_arrested := false
	func serialize() -> Dictionary: return {"money": money, "health": health}
class FakeVehicle extends Node2D:
	var has_nitro := true
	var is_nitro_active := true
	var nitro_amount := 100.0
	var nitro_max := 100.0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var player := FakePlayer.new()
	root.add_child(player)
	player.add_to_group("player")
	var sm = root.get_node("SaveManager")
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	var old_dir: String = sm._save_dir
	sm._save_dir = OS.get_temp_dir().path_join("geteco_save_gate_%s" % Time.get_ticks_usec()) + "/"
	sm._save_directory_ready = false
	var path: String = sm.get_slot_path("test")
	var original := JSON.stringify({"save_version": 1, "player": {"money": 789}, "wanted": {"current_stars": 5, "crime_points": 900}, "summary": {"current_stars": 5}})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	wanted.current_stars = 3
	for slot in ["test", "quicksave", "autosave"]:
		var result: Dictionary = sm.save_game(slot)
		check(not result.success and result.get("reason") == "wanted", "gate " + slot)
	check(not sm.request_autosave("test"), "checkpoint blocked")
	check(FileAccess.get_file_as_string(path) == original, "previous save unchanged")
	check(not FileAccess.file_exists(sm.get_slot_path("quicksave")), "no quicksave created")
	var loaded: Dictionary = sm.load_game("test")
	check(loaded.success and loaded.data.wanted.current_stars == 0, "legacy pursuit cleared in memory")
	check(loaded.data.player.money == 789, "legacy progress preserved")
	check(FileAccess.get_file_as_string(path) == original, "legacy disk unchanged")
	sm.clear_pending_save()
	wanted.reset_crime()
	var clean: Dictionary = sm.save_game("test")
	check(clean.success, "save allowed after pursuit")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(sm._save_dir)
	sm._save_dir = old_dir
	sm._save_directory_ready = false
	# Cobre as familias que o pedido nomeou (caminhao, onibus, SUV, esportivo)
	# alem das de emergencia: cada uma tem que resolver para o proprio timbre.
	var expected := {"route_city": "bus", "boxrunner": "truck", "rescue_pumper": "fire_diesel", "medic_box": "ambulance", "winter_suv_heavy": "suv", "sport_coupe": "sport", "cobra_v8": "muscle", "sedan_classic": "street", "courier_van": "diesel"}
	var fingerprints: Array[int] = []
	for id in expected:
		var family: String = EngineSound.family_for_vehicle(id)
		check(family == expected[id], "family " + id)
		var stream: AudioStreamWAV = EngineSound.get_stream(family, id)
		check(stream == EngineSound.get_stream(family, id), "cached " + id)
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loop " + id)
		check(not fingerprints.has(hash(stream.data)), "distinct PCM " + id)
		fingerprints.append(hash(stream.data))
		var max_delta := 0
		for i in range(1, stream.data.size() / 2):
			var sample := stream.data.decode_s16(i * 2)
			check(absi(sample) < 32767, "no clipping " + id)
			max_delta = maxi(max_delta, absi(sample - stream.data.decode_s16((i - 1) * 2)))
		# A emenda real está em loop_end, não no fim do buffer: depois de loop_end
		# existem amostras de guarda que só alimentam a interpolação do resampler
		# (sem elas ele lia o padding de zeros e estalava a cada volta do laço).
		var frames := stream.data.size() / 2
		check(frames > stream.loop_end, "guard samples after loop " + id)
		var seam_delta := absi(stream.data.decode_s16(0) - stream.data.decode_s16((stream.loop_end - 1) * 2))
		check(seam_delta <= max_delta, "loop seam " + id)
		# A guarda tem que reproduzir o começo do laço, senão a interpolação da
		# emenda continua produzindo um degrau artificial.
		check(stream.data.decode_s16(stream.loop_end * 2) == stream.data.decode_s16(0), "guard continues loop " + id)
	var upgrades := VehicleUpgradeManager.new()
	upgrades.active_customization["neon_equipped"] = false
	upgrades.active_customization["turbo_equipped"] = false
	upgrades.active_customization["nitro_equipped"] = true
	upgrades.unlocked_upgrades["nitro_stage"] = 3
	var vehicle := FakeVehicle.new()
	upgrades.apply_upgrades_to_vehicle(vehicle)
	check(not vehicle.has_nitro and not vehicle.is_nitro_active and vehicle.nitro_amount == 0 and vehicle.nitro_max == 0, "legacy NOS removed")
	upgrades.unlock_next_zone_upgrades(2)
	check(upgrades.unlocked_upgrades.nitro_stage == 0 and not upgrades.active_customization.nitro_equipped, "zone cannot unlock NOS")
	vehicle.free()
	upgrades.free()
	var sound := AudioStreamPlayer2D.new()
	root.add_child(sound)
	var response = EngineSound.new()
	response.update(sound, 120, 340, 1, 0.1, "route_city")
	check(sound.stream == EngineSound.get_stream("bus", "route_city"), "controller selects bus stream")
	sound.queue_free()
	player.queue_free()
	await process_frame
	print("SAVE_GATE_ENGINE_FAMILIES failures=", failures)
	quit(0 if failures.is_empty() else 1)


