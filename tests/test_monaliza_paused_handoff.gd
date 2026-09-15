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
 var manager = world.get_node("PersonalCarManager")
 var car = manager.car
 interiors._on_exterior_destination_requested(world.get_node("District/Garage/Entrance"), player, &"", null, &"", garage, garage.spawn_point)
 manager._grant()
 while manager.delivery_in_progress: await process_frame
 check(paused, "Dialogue keeps gameplay paused at handoff")
 print("CAR sprite rotation=",car.sprite.global_rotation," model=",car.body_model.rotation," heading=",car.global_rotation)
 check(absf(car.sprite.global_rotation) < 0.001, "Reward sprite stays upright while paused")
 check(absf(wrapf(car.body_model.rotation.y + car.global_rotation + PI/2, -PI, PI)) < 0.001, "Model faces the garage gate before physics resumes")
 await create_timer(0.2,true).timeout
 if DisplayServer.get_name() != "headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("D:/geteco/monaliza-handoff-orientation.png")
 print("MONALIZA ORIENTATION failures=", failures)
 quit(1 if failures else 0)
