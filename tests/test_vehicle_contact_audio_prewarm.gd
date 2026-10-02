extends SceneTree
const AUDIO := preload("res://audio/VehicleCrashAudio.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	# Let autoload initialization and the first monitor sample finish before
	# comparing the node count across an asynchronous warmup.
	await process_frame
	await process_frame
	var api := AUDIO.new()
	if not api.has_method("prewarm"):
		check(false,"contact banks must be retained under the loading curtain")
		api.free()
		quit(1)
		return
	api.free()
	AUDIO._streams.clear()
	AUDIO._last_take["metal"] = 2
	var history := AUDIO._last_take.duplicate()
	var buses := AudioServer.get_bus_count()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	seed(10203)
	var expected := randi()
	seed(10203)
	await AUDIO.prewarm(self)
	check(randi() == expected,"prewarm preserves global RNG")
	check(AUDIO._last_take == history,"prewarm does not select or play a crash take")
	check(AudioServer.get_bus_count() == buses,"prewarm does not create a mixer bus")
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	check(nodes_after == nodes,"prewarm does not spawn contact voices or world nodes (%d -> %d)" % [nodes,nodes_after])
	# Inspect actual authored assets rather than only the warmup manifest.
	var paths: Array[String] = []
	for file in DirAccess.get_files_at("res://audio/vehicle_crashes"):
		if file.ends_with(".wav"): paths.append("res://audio/vehicle_crashes/"+file)
	for file in DirAccess.get_files_at("res://assets/gameplay/audio"):
		if file.ends_with(".wav") and (file.begins_with("impact_flesh_") or file.begins_with("impact_glass_") or file.begins_with("impact_wood_")):
			paths.append("res://assets/gameplay/audio/"+file)
	check(paths.size() == 29,"all twenty vehicle clips and nine material clips are covered")
	for path in paths:
		var stream: Variant = AUDIO._streams.get(path)
		check(stream is AudioStream and stream.get_length() > 0,"retained imported contact stream: "+path)
		if stream is AudioStreamWAV: check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,"contact clip remains one shot: "+path)
	var identity := AUDIO._streams.duplicate()
	await AUDIO.prewarm(self)
	check(identity == AUDIO._streams,"repeat warmup retains identical resources")
	var world := Node3D.new()
	root.add_child(world)
	var context := Node3D.new()
	world.add_child(context)
	var pool = AUDIO.pool(context)
	for kind in ["bumper","heavy","metal","motorcycle","solid","glass","wood","flesh"]:
		pool.contacts.clear()
		pool.sources.clear()
		for voice in pool.voices: voice.stop()
		var before: int = pool.played_count
		check(AUDIO.play_contact(context,null,Vector3.ZERO,8.0,kind,kind),"real first contact plays after warmup: "+kind)
		check(pool.played_count == before+1 and pool.voices.any(func(voice): return voice.playing and voice.stream in identity.values()),"contact uses a retained resource: "+kind)
	check(identity == AUDIO._streams,"first contacts do not add or replace bank resources")
	world.free()
	await process_frame
	check(AudioServer.get_bus_count() == buses,"contact pool releases its mixer bus")
	print("CONTACT_AUDIO_PREWARM checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
