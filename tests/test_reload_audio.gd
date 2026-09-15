extends SceneTree
const BANK := preload("res://audio/reload/ReloadAudioBank.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func press_r() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.physical_keycode = KEY_R
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var city := root.get_node_or_null("CityAudioManager")
	if city:
		city.set_process(false)
		for child in city.get_children():
			if child is AudioStreamPlayer: child.stop()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player._respawn_grace_active = true
	await process_frame
	var capture := "record" in OS.get_cmdline_user_args()
	var recorder := AudioEffectRecord.new()
	var bus := AudioServer.get_bus_index("SFX")
	var slot := AudioServer.get_bus_effect_count(bus)
	if capture:
		AudioServer.set_bus_mute(bus,false)
		AudioServer.set_bus_volume_db(bus,0)
		AudioServer.add_bus_effect(bus,recorder)
		recorder.set_recording_active(true)
		await create_timer(0.2).timeout
	var heard_streams: Array[AudioStream] = []
	for id in BANK.WEAPONS:
		var stream := BANK.sound(id) as AudioStreamRandomizer
		check(stream != null and stream.streams_count == 3,id+" has three cached reload variants")
		check(stream.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS,id+" avoids repeated take")
		check(not heard_streams.has(stream),id+" has its own mechanism sound")
		heard_streams.append(stream)
		var longest := 0.0
		for i in 3:
			var sample := stream.get_stream(i) as AudioStreamWAV
			check(sample != null and sample.get_length()>0.3 and sample.loop_mode == AudioStreamWAV.LOOP_DISABLED,id+" valid one-shot sample")
			longest = maxf(longest,sample.get_length())
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		var size := int(WeaponCatalog.get_weapon(id).magazine_size)
		player.weapon_ammo[id] = {"clip":0,"reserve":size}
		press_r()
		var selected: AudioStream = player._reload_audio.stream
		check(selected in [stream.get_stream(0),stream.get_stream(1),stream.get_stream(2)],id+" selects its own recorded take")
		check(player.weapon_ammo[id] == {"clip":0,"reserve":size},id+" ammo stays unchanged during reload")
		check(player._reload_audio.playing and player._reload_audio.bus == &"SFX",id+" R plays matching sound on SFX")
		check(is_equal_approx(player._reload_duration,preload("res://guns/combat/WeaponReload.gd").duration(id)) and is_equal_approx(player._reload_audio.pitch_scale, 1.0) and selected.get_length() <= player._reload_duration,id+" original take plays unpitched within shared reload duration")
		press_r()
		check(player._reload_audio.stream == selected,id+" repeated R does not restart sound")
		await create_timer(player._reload_duration*0.5).timeout
		check(player.is_reloading() and player.get_reload_progress()>0.35 and player.get_reload_progress()<0.7,id+" animation follows audio position halfway through")
		player._shoot_towards(player.global_position+Vector2(400,0))
		check(player.weapon_ammo[id] == {"clip":0,"reserve":size},id+" shooting blocked while loading")
		await player.reload_finished
		check(player.weapon_ammo[id] == {"clip":size,"reserve":0} and not player.is_reloading(),id+" sound end commits ammo and unlocks firing")
		if capture: await create_timer(0.2).timeout
		press_r()
		check(not player._reload_audio.playing,id+" full magazine is silent")
		player.weapon_ammo[id] = {"clip":0,"reserve":0}
		press_r()
		check(not player._reload_audio.playing,id+" empty reserve is silent")
		if not capture:
			player.weapon_ammo[id] = {"clip":0,"reserve":size}
			player._shoot_towards(player.global_position+Vector2(400,0))
			check(player.weapon_ammo[id] == {"clip":0,"reserve":size} and player.is_reloading(),id+" automatic reload waits before firing")
			check(player._reload_audio.playing and player._reload_audio.stream != selected,id+" automatic reload uses a different take")
			if player._flamethrower_audio: player._flamethrower_audio.stop()
		player.equip_weapon("fists")
		check(not player._reload_audio.playing and not player.is_reloading(),id+" switching weapons cancels old reload")
		if not capture: check(player.weapon_ammo[id] == {"clip":0,"reserve":size},id+" cancellation preserves all ammo")
	check(BANK.sound("fists") == null and BANK.sound("knife") == null,"melee weapons have no reload sound")
	player.active_weapon_id = "pistol"
	player.weapon_ammo.pistol = {"clip":0,"reserve":12}
	press_r()
	var voice_count := 0
	for node in player.get_children():
		if node.name == "ReloadAudio": voice_count += 1
	check(voice_count == 1,"all reloads share one voice, with no sound-node accumulation")
	player.hide()
	check(not player._reload_audio.playing,"boarding or hiding Dante stops reload sound")
	if capture:
		await create_timer(0.2).timeout
		recorder.set_recording_active(false)
		check(recorder.get_recording().save_to_wav("D:/geteco/artifacts/reload-sync-0910/reload-preview.wav") == OK,"real mixer preview saved")
		AudioServer.remove_bus_effect(bus,slot)
	print("RELOAD_AUDIO failures=",failures)
	world.queue_free()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)
