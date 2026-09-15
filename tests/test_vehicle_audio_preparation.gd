extends SceneTree
const ENGINE := preload("res://audio/VehicleEngineSound.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_usec()
	var original := ENGINE.get_layer_streams("bike_urban", "bike_urban")
	print("AUDIO_PREPARATION cold_bike_us=", Time.get_ticks_usec() - started)
	var original_data: PackedByteArray = original[0].data.duplicate()
	await ENGINE.prepare_catalog(self)
	var layers_before := ENGINE._layer_sets.size()
	var peak := 0
	for spec in VehicleCatalog.get_all_specs():
		var family := ENGINE.family_for_vehicle(spec.id)
		var cached: Array = ENGINE._layer_sets[ENGINE._cache_key(spec.id, family)]
		started = Time.get_ticks_usec()
		ENGINE.prewarm(spec.id)
		peak = maxi(peak, Time.get_ticks_usec() - started)
		var reused := ENGINE.get_layer_streams(family, spec.id)
		assert(not reused.is_empty())
		for i in cached.size(): assert(cached[i] == reused[i], "Warm playback reuses the prepared stream")
	assert(ENGINE._layer_sets.size() == layers_before)
	assert(ENGINE.get_layer_streams("bike_urban", "bike_urban")[0].data == original_data, "Preparation preserves the existing waveform")
	assert(ENGINE.get_road_stream() != null)
	print("AUDIO_PREPARATION PASS vehicles=", VehicleCatalog.get_all_specs().size(), " warm_peak_us=", peak)
	quit(0)
