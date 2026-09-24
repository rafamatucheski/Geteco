extends SceneTree
## Run with the V1 project root to export its current procedural vehicle Foley.
const ENGINE := preload("res://audio/VehicleEngineSound.gd")

func _initialize() -> void:
	var output_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
	if output_dir.is_empty():
		push_error("Provide --output-dir=... inside the V2 audio folder")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var sounds := {"road.wav": ENGINE.get_road_stream(), "air_brake.wav": ENGINE.get_air_brake_stream()}
	for index in 3:
		sounds["turbo_shift_%d.wav" % index] = ENGINE.get_turbo_shift_stream(index)
		sounds["sport_blowoff_%d.wav" % index] = ENGINE.get_sport_blowoff_stream(index)
	for name in sounds:
		var sound := sounds[name] as AudioStreamWAV
		if sound == null or sound.save_to_wav(output_dir.path_join(name)) != OK:
			push_error("Could not export " + name)
			quit(1)
			return
	print("V1_VEHICLE_FX_EXPORTED: ", sounds.size())
	quit(0)
