extends SceneTree
var failures := 0
func _initialize() -> void:
 run.call_deferred()
func check(ok: bool, label: String) -> void:
 print(("PASS " if ok else "FAIL ") + label)
 if not ok: failures += 1
func run() -> void:
 create_timer(90).timeout.connect(func(): quit(2))
 var saves = root.get_node("SaveManager")
 saves.set("_save_dir", OS.get_temp_dir().path_join("garage_audio_%d" % Time.get_ticks_usec()) + "/")
 saves.set("_save_directory_ready", false)
 saves.clear_pending_save()
 for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete"]:
  root.get_node("CampaignState").set_campaign_flag(flag, true)
 change_scene_to_file("res://world/harbor/HarborGame.tscn")
 await scene_changed
 while not current_scene.gameplay_ready: await process_frame
 var world = current_scene
 var interiors = world.get_node("Interiors")
 var garage = interiors.garage_interior
 var player = world.get_node("Player")
 var sound = world.get_node("HarborSoundscape")
 var weather = world.weather.weather_audio
 interiors._on_exterior_destination_requested(world.get_node("District/Garage/Entrance"), player, &"", null, &"", garage, garage.spawn_point)
 await create_timer(3).timeout
 check(sound._room == garage, "Real garage entry detected")
 for kind in sound.beds:
  if kind != "workshop": check(not sound.beds[kind].playing, "Exterior bed stopped: " + kind)
 check(sound.beds.workshop.playing and sound.beds.workshop.volume_db <= -32, "Quiet workshop bed")
 check(not sound.quarter.sources.indoor_radio.playing, "Indoor radio silent")
 check(weather.interior_silence and AudioServer.is_bus_mute(AudioServer.get_bus_index(weather.bus_name)), "Rain bus muted")
 weather.play_thunder()
 check(not weather.thunder.playing, "Thunder blocked")
 garage.jager_npc._open_dialogue()
 await create_timer(1).timeout
 check(sound.focus_gain <= 0.36, "Maciota dialogue ducks workshop")
 garage.jager_npc._close_dialogue()
 player.global_position = Vector2(1700, 1130)
 sound._update_zones()
 # Existing 0.7 s exponential release reaches the stop threshold after 4.9 s.
 await create_timer(5.5).timeout
 check(not weather.interior_silence, "Weather restored outside")
 check(sound.beds.terminal.playing and not sound.beds.workshop.playing, "Exterior returns and workshop stops")
 print("GARAGE AUDIO failures=", failures)
 quit(1 if failures else 0)
