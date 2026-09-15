extends SceneTree
var failures: Array[String] = []
var capture := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	create_timer(70).timeout.connect(func(): quit(2))
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]: state.set_campaign_flag(flag, true)
	root.get_node("SaveManager").clear_pending_save()
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for frame in 30: await process_frame
	var world: Node2D = current_scene
	var player: Node2D = world.get_node("Player")
	player.set_physics_process(false)
	var manager: Node = world.get_node("Interiors")
	var garage: Node2D = manager.garage_interior
	var door: Node2D = world.get_node("District/Garage/Entrance")
	var sound: Node = world.get_node("HarborSoundscape")
	world.weather.is_dark = false
	world.weather.is_dynamic_time = false
	player.global_position = door.global_position + Vector2(0, 50)
	sound._update_zones()
	sound._process(.05)
	check(sound.listener.is_current() and sound.listener.global_position == player.global_position, "Exterior hearing follows Dante, independently of camera framing")
	sound._play_detail("air", player.global_position)
	manager._on_exterior_destination_requested(door, player, &"", null, &"", garage, garage.spawn_point)
	check(sound._room == garage and sound.targets.workshop == 1.0, "Door entry changes audio context immediately before presentation polling")
	check(not sound.detail.playing, "The previous street sound stops at the room transition")
	check(sound.listener.global_position == player.global_position, "Audio listener crosses the door in the same transition")
	await create_timer(2.0).timeout
	check(sound.beds.workshop is AudioStreamPlayer2D and sound.beds.workshop.global_position == garage.diagnostic_area.global_position, "Workshop ambience comes from the actual tool bench")
	check(sound.beds.workshop.volume_db <= -12 and sound.beds.workshop.max_distance <= 320, "Workshop ambience remains local and restrained")
	check(sound.quarter.sources.indoor_radio.playing and not sound.quarter.sources.garage_radio.playing, "Only the interior radio plays while inside")
	player.global_position = garage.diagnostic_area.global_position + Vector2(0, 8)
	sound._process(.016)
	await record_room("workbench")
	var camera: Camera2D = root.get_camera_2d()
	var camera_before := camera.get_screen_center_position()
	player.global_position = garage.jager_npc.global_position + Vector2(12, 0)
	sound._process(.016)
	check(sound.listener.global_position == player.global_position and camera.get_screen_center_position() == camera_before, "A fixed interior camera does not pin the spatial listener to the room center")
	await record_room("office")
	sound._detail_clock = 0
	sound._update_zones()
	check(sound.detail.global_position == garage.diagnostic_area.global_position and sound.detail.global_position.distance_to(sound.quarter.sources.indoor_radio.global_position) > 10, "Metal details come from the tools, not the radio")
	check(sound.detail.get_meta("base_db") == -13.0, "Metal details do not use the loud bus-brake gain")
	player.is_in_dialogue = true
	sound._update_zones()
	sound._process(.3)
	check(sound.focus_gain <= .36, "Dialogue still reduces workshop and radio audio")
	player.is_in_dialogue = false
	garage._run_diagnostic()
	var diagnostic_audio: AudioStreamPlayer
	for child in garage.get_children():
		if child is AudioStreamPlayer: diagnostic_audio = child
	check(diagnostic_audio != null and diagnostic_audio.bus == &"SFX", "Diagnostic feedback respects the Effects volume control")
	garage.diagnostic_dialog.hide()
	garage.modal_closed.emit()
	check(garage.mission_board.audio_player.bus == &"SFX", "Chalkboard feedback also respects the Effects volume control")
	player.global_position = garage.spawn_point.global_position
	manager._on_exit_door_requested(garage.exit_door, player, &"", null, &"", &"harbor/District/Garage/Entrance")
	check(sound._room == null and sound.targets.workshop == 0.0 and not sound.detail.playing, "Exit immediately clears the room and stops interior details")
	await create_timer(2.0).timeout
	check(not sound.beds.workshop.playing and not sound.quarter.sources.indoor_radio.playing, "Interior decoders stop after the exit fade")
	var car: Node2D = world.get_node("PlayerCar")
	car.set_physics_process(false)
	car.is_driven_by_player = true
	car.global_position = door.global_position + Vector2(100, 70)
	player.hide()
	sound._process(.016)
	check(sound.listener.global_position == car.global_position, "Exterior vehicle hearing follows the driven car")
	car.is_driven_by_player = false
	player.show()
	sound._process(.016)
	check(sound.listener.global_position == player.global_position, "Leaving the car restores hearing to Dante")
	var city: Node = root.get_node("CityAudioManager")
	city._process(.1)
	check(not city.distant_siren_player.playing and not city.radio_chatter_player.playing, "Global fake sirens and chatter do not layer over Harbor audio")
	print("GARAGE_AUDIO_CONTEXT failures=", failures)
	quit(0 if failures.is_empty() else 1)

func record_room(label: String) -> void:
	if not capture: return
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	var slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, record)
	record.set_recording_active(true)
	await create_timer(3.0).timeout
	record.set_recording_active(false)
	var audio: AudioStreamWAV = record.get_recording()
	AudioServer.remove_bus_effect(0, slot)
	var peak := 0.0
	var energy := 0.0
	for index in audio.data.size() / 2:
		var sample := float(audio.data.decode_s16(index * 2)) / 32768.0
		peak = maxf(peak, absf(sample))
		energy += sample * sample
	var rms := sqrt(energy / maxf(1, audio.data.size() / 2))
	check(peak < .98 and rms > .00005, label + " output has an audible signal without clipping")
	check(audio.save_to_wav("D:/geteco/artifacts/life-refinement-0911/garage-audio-" + label + ".wav") == OK, label + " mixer capture saved")
	print("GARAGE_AUDIO_CAPTURE ", label, " driver=", AudioServer.get_driver_name(), " rms_db=", linear_to_db(rms), " peak_db=", linear_to_db(peak))
