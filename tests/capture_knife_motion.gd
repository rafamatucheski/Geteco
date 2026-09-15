extends SceneTree
func _init(): call_deferred("run")
func run():
 var scene := Node2D.new()
 root.add_child(scene)
 current_scene = scene
 var player = load("res://characters/Player.gd").new()
 var camera := Camera2D.new()
 camera.name = "Camera"
 player.add_child(camera)
 scene.add_child(player)
 player.set_physics_process(false)
 player.weapon_inventory.knife = true
 player.equip_weapon("knife")
 player.viewport_3d.size = Vector2i(256, 256)
 var atlas := Image.create(768, 768, false, Image.FORMAT_RGBA8)
 atlas.fill(Color("273039"))
 for side in 3:
  player.model_root.rotation.y = [-0.65, 1.57, 3.14][side]
  for variant in 3:
   for frame in 45: player.combat_pose.update(player, 1.0/60, false, false, 0)
   player.combat_pose.knife_variant = variant - 1
   player.combat_pose.on_attack("knife")
   for frame in 8: player.combat_pose.update(player, 1.0/60, false, false, 0)
   player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
   for frame in 3: await process_frame
   await RenderingServer.frame_post_draw
   atlas.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0,0,256,256), Vector2i(variant,side)*256)
 atlas.save_png("D:/geteco/artifacts/knife-0913/motions.png")
 scene.queue_free()
 await process_frame
 quit()
