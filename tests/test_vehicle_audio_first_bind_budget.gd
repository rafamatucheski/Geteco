extends SceneTree

const ENGINE := preload("res://audio/VehicleEngineSound.gd")
const FRAME_BUDGET_USEC := 16670

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _new_voice(parent: Node2D) -> AudioStreamPlayer2D:
	var voice := AudioStreamPlayer2D.new()
	voice.bus = &"SFX"
	voice.max_distance = 600.0
	voice.attenuation = 1.8
	parent.add_child(voice)
	return voice

func _has_audible_engine_voice(engine, base: AudioStreamPlayer2D) -> bool:
	if base.playing and base.volume_db > -60.0:
		return true
	for value in engine._layer_players:
		var player := value as AudioStreamPlayer2D
		if is_instance_valid(player) and player.playing and player.volume_db > -60.0:
			return true
	return false

func _wait_for_preparation(limit_msec := 10000) -> int:
	var started := Time.get_ticks_msec()
	while ENGINE.poll_preparation() > 0 and Time.get_ticks_msec() - started < limit_msec:
		await process_frame
	return Time.get_ticks_msec() - started

func _stop_and_release_streams(parent: Node) -> void:
	for value in parent.find_children("*", "AudioStreamPlayer2D", true, false):
		var player := value as AudioStreamPlayer2D
		player.stop()
		player.stream = null

func _run() -> void:
	var object_baseline := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var street_root := Node2D.new()
	street_root.name = "StreetAudioProbe"
	root.add_child(street_root)
	var street_voice := _new_voice(street_root)
	var street_engine = ENGINE.new()

	var started := Time.get_ticks_usec()
	street_engine.bind(street_voice, "runtime_traffic_alias")
	var first_bind_usec := Time.get_ticks_usec() - started
	check(first_bind_usec < FRAME_BUDGET_USEC,
		"first runtime bind must stay inside 16.67 ms, got %.3f ms" % (first_bind_usec / 1000.0))
	check(street_voice.stream != null, "first bind must be audible immediately")
	var street_fallback := street_voice.stream
	street_engine.update(street_voice, 120.0, 400.0, 0.7, 1.0 / 60.0, "runtime_traffic_alias")
	check(_has_audible_engine_voice(street_engine, street_voice), "fallback engine must play while preparation runs")
	check(is_instance_valid(street_engine._road_player), "moving vehicle must retain a road-loop voice")
	check(street_engine._road_player.playing, "road-loop fallback must be audible")
	check(street_engine._road_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"road-loop fallback must remain looped")

	var twin_root := Node2D.new()
	twin_root.name = "TwinAudioProbe"
	root.add_child(twin_root)
	var twin_voice := _new_voice(twin_root)
	var twin_engine = ENGINE.new()
	started = Time.get_ticks_usec()
	twin_engine.bind(twin_voice, "runtime_traffic_alias")
	var pending_warm_bind_usec := Time.get_ticks_usec() - started
	twin_engine.update(twin_voice, 120.0, 400.0, 0.5, 1.0 / 60.0, "runtime_traffic_alias")
	check(twin_voice != street_voice, "playback voices must remain per vehicle")
	check(twin_voice.stream == street_voice.stream, "immutable fallback stream must be shared")
	check(twin_engine._road_player != street_engine._road_player, "road playback state must remain per vehicle")
	check(twin_engine._road_player.stream == street_engine._road_player.stream,
		"immutable road stream must be shared")

	var preparation_msec := await _wait_for_preparation()
	check(ENGINE.poll_preparation() == 0, "background audio preparation must finish without an abandoned job")
	street_engine.update(street_voice, 150.0, 400.0, 0.8, 1.0 / 60.0, "runtime_traffic_alias")
	twin_engine.update(twin_voice, 150.0, 400.0, 0.6, 1.0 / 60.0, "runtime_traffic_alias")
	var final_layers := ENGINE.get_layer_streams("street", "runtime_traffic_alias")
	check(final_layers.size() >= 3, "street family must upgrade from fallback to final layered engine")
	check(street_voice.stream == final_layers[0] and twin_voice.stream == final_layers[0],
		"both vehicles must converge on the same final immutable layer")
	check(street_voice.stream != street_fallback, "final engine must replace the temporary fallback")
	check(street_engine._layer_players.size() == final_layers.size() - 1,
		"all final engine layers must remain functional")
	check(_has_audible_engine_voice(street_engine, street_voice), "final layered engine must remain audible")
	check(street_engine._road_player.stream == ENGINE.get_road_stream(),
		"road voice must upgrade to the prepared shared loop")

	var hot_root := Node2D.new()
	hot_root.name = "HotAudioProbe"
	root.add_child(hot_root)
	var hot_voice := _new_voice(hot_root)
	var hot_engine = ENGINE.new()
	started = Time.get_ticks_usec()
	hot_engine.bind(hot_voice, "runtime_traffic_alias")
	var hot_bind_usec := Time.get_ticks_usec() - started
	check(hot_bind_usec < FRAME_BUDGET_USEC,
		"prepared bind must stay inside 16.67 ms, got %.3f ms" % (hot_bind_usec / 1000.0))
	check(hot_voice.stream == final_layers[0], "prepared bind must reuse the final shared stream")

	var truck_root := Node2D.new()
	truck_root.name = "TruckAudioProbe"
	root.add_child(truck_root)
	var truck_voice := _new_voice(truck_root)
	var truck_engine = ENGINE.new()
	started = Time.get_ticks_usec()
	truck_engine.bind(truck_voice, "cargo_flatbed_truck")
	var truck_first_bind_usec := Time.get_ticks_usec() - started
	check(truck_first_bind_usec < FRAME_BUDGET_USEC,
		"another cold family must also stay inside 16.67 ms, got %.3f ms" % (truck_first_bind_usec / 1000.0))
	check(truck_voice.stream != street_fallback,
		"families must retain distinct fallback timbres while final streams prepare")
	await _wait_for_preparation()
	truck_engine.update(truck_voice, 90.0, 300.0, 0.8, 1.0 / 60.0, "cargo_flatbed_truck")
	var truck_layers := ENGINE.get_layer_streams("truck", "cargo_flatbed_truck")
	check(truck_layers.size() >= 3, "truck must retain its final layered engine")
	check(truck_layers[0] != final_layers[0], "street and truck final timbres must remain distinct")

	var player_refs: Array[WeakRef] = [weakref(street_voice), weakref(twin_voice), weakref(hot_voice), weakref(truck_voice)]
	for vehicle_root in [street_root, twin_root, hot_root, truck_root]:
		_stop_and_release_streams(vehicle_root)
	# Give AudioServer a mix boundary to release AudioStreamPlaybackWAV before
	# the owning nodes disappear; otherwise a short headless test reports false
	# playback leaks even though the scene nodes were freed.
	for i in 3:
		await process_frame
	street_root.free()
	twin_root.free()
	hot_root.free()
	truck_root.free()
	await process_frame
	for reference in player_refs:
		check(reference.get_ref() == null, "per-vehicle playback voice must be released with its vehicle")
	check(ENGINE.poll_preparation() == 0, "test teardown must leave no background preparation")
	var object_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))

	print("VEHICLE_AUDIO_FIRST_BIND first_ms=%.3f pending_warm_ms=%.3f hot_ms=%.3f truck_first_ms=%.3f prepare_ms=%d objects_before=%d objects_after=%d failures=%s" % [
		first_bind_usec / 1000.0, pending_warm_bind_usec / 1000.0, hot_bind_usec / 1000.0,
		truck_first_bind_usec / 1000.0, preparation_msec, object_baseline, object_after, failures])
	quit(0 if failures.is_empty() else 1)
