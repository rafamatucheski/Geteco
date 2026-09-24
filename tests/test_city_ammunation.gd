extends SceneTree
func _initialize(): run.call_deferred()
func run():
 root.size=Vector2i(1280,720)
 root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
 root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete",true)
 var world=load("res://world/harbor/HarborGame.tscn").instantiate()
 root.add_child(world)
 current_scene=world
 while not world.gameplay_ready: await process_frame
 for i in 2: await process_frame
 var manager=world.get_node("Interiors")
 var room=manager.ammunation_interior
 var actor=world.get_node("Player")
 var door=world.get_node("District/NorthFrontage2/AmmunationEntrance")
 assert(room.inline_mode and room.global_position.distance_to(world.get_node("District/NorthFrontage2/AmmunationBranchFacade").global_position)<1)
 actor.global_position=room.spawn_point.global_position
 for i in 5: await process_frame
 assert(room.get_camera_rect().has_point(actor.global_position))
 actor.visible=true
 actor.set_physics_process(false)
 actor.position=room.to_global(room.merchant_point)
 room.open_catalog()
 assert(room.active and actor.is_in_dialogue)
 actor.money=3000
 actor.weapon_inventory.erase("shotgun")
 room.selection=room.stock.find("shotgun")
 room.change_selection(0)
 assert(room.gun.get_child_count()>0)
 room.purchase()
 assert(actor.money==1200 and actor.weapon_inventory.get("shotgun",false))
 room.purchase()
 assert(actor.money==1200)
 room.selection=room.stock.find("magnum")
 actor.weapon_inventory.erase("magnum")
 actor.money=0
 room.change_selection(0)
 assert(room.buy.disabled)
 room.purchase()
 assert(not actor.weapon_inventory.get("magnum",false))
 for layer in world.find_children("","CanvasLayer",true,false):
  if layer!=room.catalog: layer.hide()
 for i in 5: await process_frame
 await RenderingServer.frame_post_draw
 var artifact_dir=OS.get_temp_dir().path_join("geteco-ammunation-cutaway-0922")
 DirAccess.make_dir_recursive_absolute(artifact_dir)
 if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png(artifact_dir.path_join("city-catalog.png"))
 room.close_catalog()
 assert(not actor.is_in_dialogue)
 var camera=Camera2D.new()
 world.add_child(camera)
 camera.position=room.global_position
 camera.zoom=Vector2(1.3,1.3)
 camera.make_current()
 for layer in world.find_children("","CanvasLayer",true,false): layer.hide()
 for i in 5: await process_frame
 await RenderingServer.frame_post_draw
 if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png(artifact_dir.path_join("city-interior.png"))
 actor.global_position=door.to_global(Vector2(0,85))
 for i in 5: await process_frame
 assert(not room.contains_point(actor.global_position) and room.exit_door==null)
 print("AMMUNATION PASS inline entry preview purchase duplicate funds close exit")
 world.queue_free()
 await process_frame
 quit()
