extends SceneTree
const BANK := preload("res://world/harbor/HarborAudioBank.gd")
const OPENING := preload("res://cutscenes/opening/OpeningCutscene.tscn")
var failures: Array[String] = []
var completed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	for kind in ["logo", "water", "terminal", "workshop", "air", "gull", "metal"]:
		var stream := BANK.sound(kind)
		check(stream == BANK.sound(kind), "Cached audio: " + kind)
		var bytes := stream.data
		var peak := 0
		var energy := 0.0
		for i in range(0, bytes.size(), 2):
			var sample := bytes.decode_s16(i)
			peak = maxi(peak, absi(sample))
			energy += float(sample) * sample
		check(peak > 500 and peak < 32767 and energy > 0.0, "Non-silent, unclipped PCM: " + kind)
		check(absi(bytes.decode_s16(0)) < 50 and absi(bytes.decode_s16(bytes.size() - 2)) < 50, "Soft audio boundaries: " + kind)
	var opening := OPENING.instantiate()
	opening.show_studio_intro = true
	opening.finished.connect(func(_destination): completed += 1)
	root.add_child(opening)
	paused = true
	check(opening._shot_index == -1 and is_instance_valid(opening._studio_card), "RCM before CGI")
	await create_timer(1.8).timeout
	check(opening._studio_elapsed < 2.8 and opening._shot_index == -1, "RCM breve antes da narrativa")
	await create_timer(1.3).timeout
	check(opening._shot_index == 0 and not is_instance_valid(opening._studio_card), "Natural fade into first CGI frame")
	var start := Time.get_ticks_msec()
	while completed == 0 and Time.get_ticks_msec() - start < 74000:
		await process_frame
	check(completed == 1, "Whole opening finishes naturally once while paused")
	opening.queue_free()
	await process_frame
	# Skip from the studio card also retains exactly-once destination behavior.
	opening = OPENING.instantiate()
	opening.show_studio_intro = true
	opening.skipped.connect(func(_destination): completed += 1)
	root.add_child(opening)
	await create_timer(1.0).timeout
	opening.skip()
	opening.skip()
	await create_timer(0.35).timeout
	check(completed == 2, "Skip studio card exactly once")
	opening.queue_free()
	paused = false
	await process_frame
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 15: await process_frame
	var soundscape = world.get_node("HarborSoundscape")
	check(not paused, "Seen intro does not replay on resume")
	check(soundscape.get_child_count() == 7 and soundscape.quarter.sources.size() == 7, "Bounded audio voices and authored quarter")
	world.get_node("Player").global_position = Vector2(1700, 1130)
	await create_timer(2.0).timeout
	check(soundscape.weights.terminal > 0.8 and soundscape.weights.water < 0.01, "Terminal bed local")
	world.get_node("Player").global_position = Vector2(3500, 1700)
	await create_timer(2.0).timeout
	check(soundscape.weights.water > 0.8 and soundscape.weights.terminal < 0.01, "Port crossfade")
	var garage = world.get_node("Interiors").garage_interior
	world.get_node("Player").global_position = garage.get_camera_rect().get_center()
	await create_timer(2.5).timeout
	check(soundscape.weights.workshop > 0.8 and soundscape.weights.water < 0.01, "Garage replaces exterior sound")
	check(not soundscape.beds.water.playing, "Distant water stops decoding after fade")
	world.get_node("Player").global_position = Vector2(1700, 1130)
	world.weather.is_dark = true
	world.weather.time_of_day = 0.85
	world.weather.is_dynamic_time = false
	await create_timer(2.5).timeout
	check(soundscape.weights.terminal <= 0.51 and soundscape.weights.workshop < 0.01, "Night is quieter and leaving garage restores exterior")
	for bed in soundscape.beds.values():
		check(bed.bus == &"SFX", "Environment follows SFX settings")
	check(soundscape.get_child_count() == 7 and soundscape.quarter.sources.size() == 7, "No per-frame audio allocations")
	world.queue_free()
	await process_frame
	print("HARBOR_PRESENTATION_AUDIO: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
