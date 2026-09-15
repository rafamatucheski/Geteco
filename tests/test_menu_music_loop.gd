extends SceneTree
## Regression: compressed WAV byte length must not truncate the musical loop.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var audio = load("res://ui/MenuAudio.gd").get_music_stream()
	assert(audio.get_length() > 60.0, "Complete arrangement is imported")
	assert(audio.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	assert(audio.loop_end == roundi(audio.get_length() * audio.mix_rate), "Loop uses decoded frames")
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var player: AudioStreamPlayer = menu.get_node("MenuMusicPlayer")
	assert(player.playing and player.stream == audio)
	assert(player.bus == load("res://ui/MenuAudio.gd").get_music_bus_name())
	player.play(audio.get_length() - 0.2)
	await create_timer(0.7).timeout
	assert(player.playing, "Music continues across the loop seam")
	assert(player.get_playback_position() < 1.5, "Music wraps to the beginning")
	menu._stop_bg_music()
	assert(not player.playing)
	menu.queue_free()
	await process_frame
	print("PASS menu music: full arrangement, decoded loop bounds, menu playback, seam, stop")
	quit()
