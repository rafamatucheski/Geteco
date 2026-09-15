extends SceneTree
func _initialize():
 run.call_deferred()
func run():
 create_timer(120).timeout.connect(func(): quit(2))
 var label = "baseline"
 for arg in OS.get_cmdline_user_args(): label = arg
 var output = "D:/geteco/artifacts/weapon-range/"
 DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveManager")._save_dir = output + "saves/"
 root.get_node("SaveManager").clear_pending_save()
 root.get_node("CampaignState").reset_campaign()
 for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
  root.get_node("CampaignState").set_campaign_flag(StringName(flag), true)
 DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
 root.size = Vector2i(1280,720)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps = 0
 seed(911)
 var world = load("res://world/harbor/HarborGame.tscn").instantiate()
 root.add_child(world)
 current_scene = world
 for i in 180: await process_frame
 world.weather.time_of_day = 0.45
 world.weather.set_weather(0)
 world.weather.set_process(false)
 var player = world.get_node("Player")
 player.global_position = Vector2(700,475)
 var camera = Camera2D.new()
 camera.position = player.position
 camera.zoom = Vector2.ONE * 1.8
 world.add_child(camera)
 camera.make_current()
 for i in 120: await process_frame
 var samples = []
 var started = Time.get_ticks_usec()
 var last = started
 var next_shot = 0.0
 while Time.get_ticks_usec() - started < 30000000:
  var elapsed = (Time.get_ticks_usec()-started)/1000000.0
  if elapsed >= next_shot:
   next_shot += 0.11
   var b = load("res://guns/Bullet.tscn").instantiate()
   b.position = player.position + Vector2(0,-25)
   b.direction = Vector2.UP
   b.owner_body = player
   b.speed = 960
   b.damage = 8
   if b.has_method("configure_range"): b.configure_range(WeaponCatalog.get_weapon("smg"))
   world.add_child(b)
  await process_frame
  var now = Time.get_ticks_usec()
  samples.append((now-last)/1000.0)
  last = now
 var sorted = samples.duplicate()
 sorted.sort()
 var result = {"gpu":RenderingServer.get_video_adapter_name(),"frames":samples.size(),"fps":samples.size()/((last-started)/1000000.0),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":samples.filter(func(x): return x>33.3).size(),"over66":samples.filter(func(x): return x>66.7).size(),"samples":samples}
 FileAccess.open(output+label+".json",FileAccess.WRITE).store_string(JSON.stringify(result))
 result.erase("samples")
 print(result)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+label+".png")
 quit()
