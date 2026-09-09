extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func observe_steps(actor: Node, frames: int) -> int:
	var count := 0
	var previous: int = actor._step_variation_index
	for i in frames:
		await physics_frame
		await process_frame
		var current: int = actor._step_variation_index
		if current != previous: count += 1
		previous = current
	return count

func check_surface_stream(actor: Node, expected: String) -> void:
	var variation: int = actor._step_variation_index
	actor._play_footstep(false)
	var voice: AudioStreamPlayer2D = actor._footstep_voices[variation % 2]
	check(voice.stream == ProceduralAudio.get_footstep_stream(expected, variation), "Player selects actual audio: " + expected)

func run() -> void:
	root.get_node("CityAudioManager").set_process(false)
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
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
	world.weather.set_weather(0)
	world.weather.set_interior_mode(false)
	actor.global_position = world.get_node("District").to_global(Vector2(580, 800))
	check_surface_stream(actor, "grass")
	world.weather.set_weather(1)
	check_surface_stream(actor, "grass_wet")
	actor.global_position = world.get_node("District").to_global(Vector2(655, 800))
	check_surface_stream(actor, "wet")
	actor.global_position = room.global_position
	check_surface_stream(actor, "tile")
	actor.global_position = world.get_node("District").to_global(Vector2(655, 800))
	check_surface_stream(actor, "wet")
	world.weather.set_weather(0)
	check_surface_stream(actor, "concrete")
	# Exercise the real physics/input path in an empty area, with a real static wall.
	actor.global_position = Vector2(50000, 50000)
	actor.velocity = Vector2.ZERO
	actor.set_dialogue_active(false)
	actor.set_physics_process(true)
	Input.action_press("ui_right")
	var start: Vector2 = actor.global_position
	var walking := await observe_steps(actor, 120)
	check(walking >= 2 and actor.global_position.distance_to(start) > 100.0, "Walking moves and emits steps")
	Input.action_press("sprint")
	start = actor.global_position
	var running := await observe_steps(actor, 120)
	check(running > walking and actor.global_position.distance_to(start) > 250.0, "Running increases movement and step cadence")
	Input.action_release("sprint")
	Input.action_release("ui_right")
	await observe_steps(actor, 20)
	check(await observe_steps(actor, 90) == 0, "Idle emits no footsteps")
	var wall := StaticBody2D.new()
	wall.collision_layer = actor.collision_mask
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(40, 400)
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = actor.global_position + Vector2(65, 0)
	Input.action_press("ui_right")
	await observe_steps(actor, 60)
	start = actor.global_position
	var blocked_steps := await observe_steps(actor, 120)
	check(actor.global_position.distance_to(start) < 0.1, "Real collision stops player at wall")
	check(blocked_steps == 0, "Holding direction against wall emits no steps")
	Input.action_release("ui_right")
	wall.queue_free()
	actor.set_dialogue_active(true)
	Input.action_press("ui_right")
	check(await observe_steps(actor, 90) == 0, "Dialogue blocks movement footsteps")
	Input.action_release("ui_right")
	actor.set_dialogue_active(false)
	actor.set_physics_process(false)
	# Rapid dialogue/interior toggles must settle on the latest target, without
	# changing the SFX bus (weapons, engines and voices share it).
	var sfx := AudioServer.get_bus_index(&"SFX")
	var sfx_before := AudioServer.get_bus_volume_db(sfx)
	soundscape.set_process(false)
	for i in 24:
		actor.set_dialogue_active(i % 2 == 0)
		soundscape._update_zones()
		weather.set_conditions(1.0, i % 3 == 0)
		weather._process(0.03)
		soundscape._process(0.03)
		check(weather.focus_gain >= 0.5 and weather.focus_gain <= 1.0, "Rain focus remains bounded")
	actor.set_dialogue_active(false)
	soundscape._update_zones()
	weather.set_conditions(1.0, false)
	weather._process(4.0)
	soundscape._process(2.0)
	check(is_equal_approx(weather.focus_gain, 1.0) and is_equal_approx(soundscape.focus_gain, 1.0), "Rapid dialogue toggles restore both mixers")
	check(is_equal_approx(weather.shelter_mix, 0.0), "Rapid shelter toggles restore outdoor rain")
	check(is_equal_approx(AudioServer.get_bus_volume_db(sfx), sfx_before), "Dialogue mix preserves shared SFX volume")
	print("MOVEMENT walking=%d running=%d wall=%d" % [walking, running, blocked_steps])
	world.queue_free()
	await create_timer(0.3).timeout
	print("FOOTSTEP MOVEMENT AND MIX: %d failures" % failures)
	quit(1 if failures else 0)
