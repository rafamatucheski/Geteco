extends SceneTree
## Body impacts remain audible and independent inside the shared contact budget.
const AUDIO := preload("res://audio/VehicleCrashAudio.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func reset_pool(pool) -> void:
	for voice in pool.voices: voice.stop()
	pool.contacts.clear()
	pool.sources.clear()

func run() -> void:
	await AUDIO.prewarm(self)
	var retained := AUDIO._streams.duplicate()
	for family in ["body_hit", "body_land"]:
		for take in 3:
			var stream: Variant = retained.get("res://audio/body_impacts/%s_%d.wav" % [family, take])
			check(stream is AudioStreamWAV and stream.get_length() > 0.25 and stream.get_length() <= 0.55,
				"short body clip retained before collisions: %s %d" % [family, take])
			if stream is AudioStreamWAV:
				check(not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
					"positional one-shot body clip: %s %d" % [family, take])
	var buses := AudioServer.get_bus_count()
	var world := Node3D.new()
	root.add_child(world)
	var context := Node3D.new()
	world.add_child(context)
	var first := Node3D.new()
	var second := Node3D.new()
	world.add_child(first)
	world.add_child(second)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 25.3, 25.3)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	check(not AUDIO.play_body_impact(context, first, Vector3.ZERO, NAN), "invalid impact speed ignored")
	check(not AUDIO.play_body_impact(context, first, Vector3(INF, 0, 0), 12), "invalid impact position ignored")
	check(not AUDIO.play_body_impact(context, first, Vector3.ZERO, 0.2), "soft settling remains silent")
	check(not AUDIO.play_body_impact(context, first, Vector3(500, 0, 0), 12), "remote body impact culled")
	check(not world.has_meta(AUDIO.META), "rejected impacts do not allocate a pool")
	check(AUDIO.play_body_impact(context, first, Vector3.ZERO, 3), "low speed body hit is heard")
	var pool = AUDIO.pool(context)
	var soft_volume: float = pool.voices[0].volume_db
	check(AUDIO.play_body_impact(context, second, Vector3.ZERO, 18), "second body may hit in the same frame")
	check(pool.voices[1].volume_db > soft_volume + 3, "fast hit has a stronger attack")
	check(not AUDIO.play_body_impact(context, first, Vector3.ZERO, 18), "same body does not repeat its hit")
	reset_pool(pool)
	check(AUDIO.play_body_impact(context, first, Vector3.ZERO, 5, true), "first ground impact is heard")
	check(AUDIO.play_body_impact(context, second, Vector3.ZERO, 5, true), "simultaneous body landings are independent")
	check(pool.voices[0].volume_db > -8.0, "ground hit uses audible landing gain at real fall speed")
	check(pool.voices[0].stream.resource_path.contains("body_land_"), "landing has its own dry body sound")
	check(not AUDIO.play_body_impact(context, first, Vector3(1, 0, 0), 5, true), "moving contact cannot evade body cooldown")
	reset_pool(pool)
	check(AUDIO.play_body_impact(context, first, Vector3.ZERO, 12), "initial vehicle contact plays")
	for tick in 8: await physics_frame
	check(AUDIO.play_body_impact(context, first, Vector3.ZERO, 4, true), "first landing is separate from initial vehicle hit")
	check(not pool.is_processing() and not pool.is_physics_processing(), "body audio has no per-frame loop")
	reset_pool(pool)
	var before: int = pool.played_count
	for index in 30:
		var body := Node3D.new()
		world.add_child(body)
		AUDIO.play_body_impact(context, body, Vector3.ZERO, 18)
	check(pool.played_count - before == AUDIO.MAX_VOICES and pool.dropped_count > 0, "body crowd respects voice budget")
	check(pool.get_child_count() == AUDIO.MAX_VOICES, "body audio reuses the original bounded pool")
	check(AUDIO._streams == retained, "first body contacts do not load extra resources")
	world.free()
	await process_frame
	check(AudioServer.get_bus_count() == buses, "body pool releases its mixer bus on unload")
	print("BODY_IMPACT_AUDIO checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
