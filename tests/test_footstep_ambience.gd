extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	root.get_node("CityAudioManager").set_process(false)
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 20: await process_frame
	var actor: Node2D = world.get_node("Player")
	actor.set_physics_process(false)
	var resolver = load("res://audio/footsteps/FootstepSurfaceResolver.gd")
	actor.global_position = world.get_node("District").to_global(Vector2(580, 800))
	check(resolver.resolve(actor, false) == "grass", "Actual district garden")
	check(resolver.resolve(actor, true) == "grass_wet", "Wet garden retains grass texture")
	actor.global_position = world.get_node("District").to_global(Vector2(655, 800))
	check(resolver.resolve(actor, false) == "concrete", "Paving overrides garden")
	var room = world.get_node("Interiors").clinic_interior
	actor.global_position = room.global_position
	check(resolver.resolve(actor, true) == "tile", "Actual clinic stays dry")
	var soundscape = world.get_node("HarborSoundscape")
	var weather = world.weather.weather_audio
	weather.set_process(false)
	weather.set_conditions(1.0, false)
	weather.set_dialogue_focus(false)
	weather._process(4.0)
	var before: float = weather.layers[0].volume_db
	actor.is_in_dialogue = true
	soundscape._update_zones()
	weather._process(1.0)
	check(weather.layers[0].volume_db < before - 5.9, "Dialogue lowers rain by 6 dB")
	check(soundscape.dialogue_focused, "Real dialogue state reaches soundscape")
	actor.is_in_dialogue = false
	soundscape._update_zones()
	weather._process(1.0)
	check(absf(weather.layers[0].volume_db - before) < 0.01, "Rain restores after dialogue")
	for material in load("res://audio/footsteps/FootstepAudioBank.gd").MATERIALS:
		for v in 4:
			var wav: AudioStreamWAV = ProceduralAudio.get_footstep_stream(material, v)
			check(wav != null and wav.data.size() > 0, "Valid footstep " + material)
	for i in 30: actor._play_footstep(i % 2 == 0)
	check(actor._footstep_voices.size() == 2, "Bounded footstep voices")
	for voice in actor._footstep_voices: check(voice.bus == &"SFX", "Footsteps respect SFX")
	world.queue_free()
	await create_timer(0.3).timeout
	print("FOOTSTEP AMBIENCE: %d failures" % failures)
	quit(1 if failures else 0)
